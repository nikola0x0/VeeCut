import Foundation

/// On-device footage reading: scene labels from the visual search index plus speech presence.
enum FootageScanner {
    static let vocabulary = [
        "food", "coffee or café", "street at night", "city street", "landscape or nature", "animal",
        "person talking to the camera", "group of friends", "beach or water", "inside a car or vehicle",
        "sunset or sunrise", "market or shop",
    ]
    static let talkingLabel = "person talking to the camera"
    static let scoreFloor: Float = 0.12
    static let maximumMoments = 6

    @concurrent
    static func scan(
        _ assets: [ScanInput],
        search: @Sendable (String) async -> [VisualSearch.Hit],
        speech: @Sendable (ScanInput) async -> Bool
    ) async -> [FootageNote] {
        let ids = Set(assets.map(\.assetId))
        var hitsByAsset: [String: [(label: String, hit: VisualSearch.Hit)]] = [:]
        for label in vocabulary {
            guard !Task.isCancelled else { return [] }
            for hit in await search(label) where ids.contains(hit.assetID) && hit.score >= scoreFloor {
                hitsByAsset[hit.assetID, default: []].append((label, hit))
            }
        }
        var notes: [FootageNote] = []
        for asset in assets {
            guard !Task.isCancelled else { return [] }
            let ranked = (hitsByAsset[asset.assetId] ?? []).sorted { $0.hit.score > $1.hit.score }
            var labels: [String] = []
            var shots: Set<Double> = []
            var moments: [PlanMoment] = []
            for (label, hit) in ranked {
                if !labels.contains(label) { labels.append(label) }
                guard moments.count < maximumMoments, shots.insert(hit.shotStart).inserted else { continue }
                moments.append(PlanMoment(assetId: asset.assetId, start: hit.shotStart, end: hit.shotEnd, note: label))
            }
            notes.append(FootageNote(
                assetId: asset.assetId, fileKey: asset.fileKey, durationSeconds: asset.durationSeconds,
                hasSpeech: await speech(asset), labels: labels, summary: nil, moments: moments
            ))
        }
        return notes
    }

    /// Assets without a current note; a label-less note is retried once labels can be read.
    static func inputsNeedingScan(_ inputs: [ScanInput], notes: [String: FootageNote], labelsAvailable: Bool) -> [ScanInput] {
        inputs.filter { input in
            guard let note = notes[input.assetId], note.fileKey == input.fileKey else { return true }
            return labelsAvailable && note.labels.isEmpty
        }
    }

    /// "42 clips — cafés, animals and night streets · 9 with talking".
    @MainActor
    static func overview(_ notes: [FootageNote]) -> String {
        let count = notes.count
        let talking = notes.filter(\.hasSpeech).count
        var counts: [String: Int] = [:]
        for note in notes { for label in Set(note.labels) { counts[label, default: 0] += 1 } }
        let top = vocabulary.filter { counts[$0] != nil }
            .enumerated()
            .sorted { (counts[$0.element]!, -$0.offset) > (counts[$1.element]!, -$1.offset) }
            .prefix(4)
            .map { displayName($0.element) }
        let base: String
        if top.isEmpty {
            let minutes = Int((notes.reduce(0) { $0 + $1.durationSeconds } / 60).rounded())
            base = L10n.string("\(count) clips, \(minutes) min")
        } else {
            base = L10n.string("\(count) clips — \(top.formatted(.list(type: .and)))")
        }
        return talking > 0 ? L10n.string("\(base) · \(talking) with talking") : base
    }

    @MainActor
    private static func displayName(_ label: String) -> String {
        switch label {
        case "food": L10n.string("food")
        case "coffee or café": L10n.string("cafés")
        case "street at night": L10n.string("night streets")
        case "city street": L10n.string("city streets")
        case "landscape or nature": L10n.string("landscapes")
        case "animal": L10n.string("animals")
        case "person talking to the camera": L10n.string("talking to camera")
        case "group of friends": L10n.string("friends")
        case "beach or water": L10n.string("water")
        case "inside a car or vehicle": L10n.string("on the road")
        case "sunset or sunrise": L10n.string("sunsets")
        case "market or shop": L10n.string("markets")
        default: label
        }
    }
}
