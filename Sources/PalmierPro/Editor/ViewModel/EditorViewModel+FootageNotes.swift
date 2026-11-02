import Foundation

/// Keeps `footageNotes` current: video assets without a note for their current file get scanned on device.
extension EditorViewModel {
    func scanFootage() {
        guard footageScanTask == nil else {
            footageScanPending = true
            return
        }
        let assets = mediaAssets.filter { $0.type == .video && !$0.isGenerating && $0.duration > 0 }
            .map { (id: $0.id, url: $0.url, duration: $0.duration, hasAudio: $0.hasAudio) }
        guard !assets.isEmpty else { return }
        let notes = footageNotes
        let labelsAvailable = VisualModelLoader.shared.isReady
        let searchIndex = searchIndex
        let withAudio = Set(assets.filter(\.hasAudio).map(\.id))
        footageScanTask = Task { [weak self] in
            let inputs = await Self.scanInputs(assets.map { ($0.id, $0.url, $0.duration) })
            let pending = FootageScanner.inputsNeedingScan(inputs, notes: notes, labelsAvailable: labelsAvailable)
            let ids = Set(pending.map(\.assetId))
            let scanned = pending.isEmpty ? [] : await FootageScanner.scan(
                pending,
                search: { label in await searchIndex.search(query: label, limit: 500, within: ids) },
                speech: { input in withAudio.contains(input.assetId) ? await Self.hasSpeech(input) : false }
            )
            guard let self else { return }
            footageScanTask = nil
            if !Task.isCancelled { mergeFootageNotes(scanned) }
            if footageScanPending {
                footageScanPending = false
                scanFootage()
            }
        }
    }

    func savedFootageNotes() -> [FootageNote]? {
        let ids = Set(mediaAssets.map(\.id))
        let notes = footageNotes.values.filter { ids.contains($0.assetId) }.sorted { $0.assetId < $1.assetId }
        return notes.isEmpty ? nil : notes
    }

    /// A rescan of the same file keeps what Muse Spark already read.
    private func mergeFootageNotes(_ scanned: [FootageNote]) {
        let ids = Set(mediaAssets.map(\.id))
        for var note in scanned where ids.contains(note.assetId) {
            if let existing = footageNotes[note.assetId], existing.fileKey == note.fileKey, existing.summary != nil {
                note.summary = existing.summary
                note.moments = existing.moments
            }
            footageNotes[note.assetId] = note
        }
        showCoachIfNeeded()
        readFootageInBackground()
    }

    /// With a Meta key, Muse Spark reads every unread clip once, then recommends what to make; without one, nothing runs.
    func readFootageInBackground() {
        guard footageReadTask == nil else {
            footageReadPending = true
            return
        }
        footageReadTask = Task { [weak self] in
            await self?.readUnreadFootage()
            guard let self, !Task.isCancelled else { return }
            footageReadTask = nil
            if footageReadPending {
                footageReadPending = false
                readFootageInBackground()
            } else {
                recommendFromFootage()
            }
            resumeFootageReadWaiters()
        }
    }

    /// Stores read notes whose file hasn't changed since the scan.
    func storeReadNotes(_ notes: [FootageNote], countsAsRead: Bool = true) {
        defer { if !notes.isEmpty { onProjectCheckpointRequired?() } }
        for note in notes where footageNotes[note.assetId].map({ $0.fileKey == note.fileKey }) ?? mediaAssets.contains(where: { $0.id == note.assetId }) {
            footageNotes[note.assetId] = note
        }
        guard countsAsRead, var progress = footageReadProgress else { return }
        progress.done = min(progress.total, progress.done + notes.count)
        progress.recent = Array((progress.recent + notes.map(\.summary).compactMap { $0 }.filter { !$0.isEmpty }).suffix(3))
        footageReadProgress = progress
    }

    private var coachVideoIds: [String] {
        mediaAssets.filter { $0.type == .video && !$0.isGenerating }.map(\.id)
    }

    private func readUnreadFootage() async {
        let ids = coachVideoIds
        var unread = ids.compactMap { footageNotes[$0] }.filter { $0.summary == nil }
        guard !unread.isEmpty, let model = try? await coachModelProvider() else { return }
        let urls = Dictionary(mediaAssets.map { ($0.id, $0.url) }) { first, _ in first }
        footageReadProgress = FootageReadProgress(done: 0, total: unread.count, recent: [])
        for index in unread.indices where unread[index].wantsTranscript && unread[index].transcript == nil {
            guard !Task.isCancelled, let url = urls[unread[index].assetId] else { continue }
            do {
                let lines = try await footageTranscriptSource(url)
                guard !Task.isCancelled else { return }
                unread[index].transcript = Self.transcriptText(lines)
                storeReadNotes([unread[index]], countsAsRead: false)
            } catch {
                Log.editor.notice("footage transcript skipped asset=\(unread[index].assetId) error=\(String(describing: error))")
            }
        }
        defer { footageReadProgress = nil }
        do {
            _ = try await FootageReader.read(unread, urls: urls, client: model) { [weak self] batch in
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self?.storeReadNotes(batch)
                }
            }
        } catch {
            Log.editor.error("footage read failed clips=\(unread.count) error=\(String(describing: error))")
        }
    }

    nonisolated static let transcriptCharacterLimit = 800

    /// "[1.5] words [4.0] more words", cut at a line boundary near the limit.
    nonisolated static func transcriptText(_ lines: [(start: Double, text: String)]) -> String? {
        var text = ""
        for line in lines {
            let words = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !words.isEmpty else { continue }
            let entry = "[\(String(format: "%.1f", line.start))] \(words)"
            guard text.count + entry.count <= transcriptCharacterLimit else { break }
            text += text.isEmpty ? entry : " " + entry
        }
        return text.isEmpty ? nil : text
    }

    private func recommendFromFootage() {
        guard footageRecommendTask == nil else { return }
        let notes = coachVideoIds.compactMap { footageNotes[$0] }.filter { $0.summary != nil }
        guard !notes.isEmpty, footageRecommendation?.assetIds != notes.map(\.assetId).sorted() else { return }
        footageRecommendTask = Task { [weak self] in
            var recommended = false
            defer {
                self?.footageRecommendTask = nil
                // Clips read while this ran make it stale; the asset-id guard stops a repeat once it matches.
                if recommended, self?.footageReadTask == nil { self?.recommendFromFootage() }
            }
            guard let model = try? await self?.coachModelProvider() else { return }
            do {
                let recommendation = try await CoachRecommender.recommend(notes, client: model)
                guard let self, !Task.isCancelled else { return }
                footageRecommendation = recommendation
                recommended = true
                onProjectCheckpointRequired?()
                showCoachIfNeeded()
            } catch {
                Log.editor.error("footage recommendation failed clips=\(notes.count) error=\(String(describing: error))")
            }
        }
    }

    @concurrent
    nonisolated static func scanInputs(_ assets: [(id: String, url: URL, duration: Double)]) async -> [ScanInput] {
        assets.compactMap { asset in
            EmbeddingStore.key(for: asset.url).map { ScanInput(assetId: asset.id, url: asset.url, fileKey: $0, durationSeconds: asset.duration) }
        }
    }

    private nonisolated static func hasSpeech(_ input: ScanInput) async -> Bool {
        guard let analysis = try? await VoiceActivity.analysis(for: input.url, mediaRef: input.assetId) else { return false }
        return analysis.segments.contains { $0.end - $0.start >= 1 }
    }
}
