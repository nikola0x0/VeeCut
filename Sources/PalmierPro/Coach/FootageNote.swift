import Foundation

/// What the coach knows about one asset; stale once `fileKey` no longer matches the file.
struct FootageNote: Codable, Sendable, Equatable {
    var assetId: String
    var fileKey: String
    var durationSeconds: Double
    var hasSpeech: Bool
    var labels: [String]
    var summary: String?
    var moments: [PlanMoment]
    /// What is said, as "[seconds] words" lines; only for clips with talking.
    var transcript: String? = nil

    var wantsTranscript: Bool { hasSpeech || labels.contains(FootageScanner.talkingLabel) }
}

struct ScanInput: Sendable {
    let assetId: String
    let url: URL
    let fileKey: String
    let durationSeconds: Double
}

struct FootageReadProgress: Equatable {
    var done: Int
    var total: Int
    /// The latest clip summaries, newest last.
    var recent: [String]

    var fraction: Double { total > 0 ? min(Double(done) / Double(total), 1) : 0 }
}
