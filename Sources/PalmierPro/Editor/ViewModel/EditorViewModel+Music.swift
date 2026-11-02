import Foundation

/// The song Vee plans to: the first music clip on the timeline, read into a music map once per song.
extension EditorViewModel {
    nonisolated static let musicSampleRate = 11_025.0

    var planningSong: MediaAsset? {
        musicClips.first.flatMap { clip in mediaAssetsById[clip.mediaRef] }
    }

    /// The first song in a Media-panel drag (one line per item) goes on the timeline from the start; no song is refused with a toast.
    @discardableResult
    func addMusic(fromDragStrings items: [String]) -> Bool {
        let assets = items.flatMap { $0.split(separator: "\n").map(String.init) }
            .compactMap(MediaTab.assetId(fromDragString:)).compactMap { mediaAssetsById[$0] }
        guard let song = assets.first(where: { $0.type == .audio }), case .success = addMusic(song) else {
            mediaPanelToast = MediaPanelToast(message: L10n.string("Drop a song or other audio here."))
            return false
        }
        return true
    }

    /// Beats come from the shared beat store; loudness is read off the main thread. Nil when the song has no usable beat.
    func musicMap(for song: MediaAsset) async -> MusicMap? {
        if let cached = musicMaps[song.id] { return cached }
        let analysis: BeatAnalysis
        if let known = mediaVisualCache.beats.analysis(for: song.id) {
            analysis = known
        } else {
            do {
                analysis = try await mediaVisualCache.beats.detect(for: song).value
            } catch {
                if !(error is CancellationError) { Log.editor.error("music beats failed asset=\(song.id) error=\(String(describing: error))") }
                return nil
            }
        }
        let map: MusicMap?
        do {
            map = try await Self.readMusicMap(url: song.url, analysis: analysis, duration: song.duration)
        } catch {
            if !(error is CancellationError) { Log.editor.error("music read failed asset=\(song.id) error=\(String(describing: error))") }
            return nil
        }
        guard !Task.isCancelled else { return nil }
        if let map { musicMaps[song.id] = map }
        return map
    }

    @concurrent
    private nonisolated static func readMusicMap(url: URL, analysis: BeatAnalysis, duration: Double) async throws -> MusicMap? {
        let samples = try await AudioTrackReader.readMonoFloats(from: url, sampleRate: musicSampleRate)
        try Task.checkCancellation()
        let loudness = MusicMap.beatLoudness(samples: samples, sampleRate: musicSampleRate, beats: analysis.beats)
        return MusicMap.make(analysis: analysis, beatLoudness: loudness, duration: duration)
    }
}
