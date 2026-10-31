import Foundation

/// A time range in a source clip, in source seconds.
struct PlanMoment: Codable, Sendable, Equatable, Hashable {
    var assetId: String
    var start: Double
    var end: Double
    var note: String
}

struct PlanSection: Codable, Sendable, Equatable, Identifiable {
    var id = UUID().uuidString
    var title: String
    var targetSeconds: Double
    var hint: String
    var suggestions: [PlanMoment] = []
}

enum PlanStyle: String, Codable, CaseIterable, Sendable {
    case travelVlog, reel, cinematicRecap, talkingHead
}

struct EditPlan: Codable, Sendable, Equatable {
    var brief: String
    var style: PlanStyle?
    var trackId: String
    var sections: [PlanSection]
    var dismissedNudges: Set<String> = []
}

extension PlanMoment {
    static let minimumSeconds = 1.0

    /// Finite, at least a second long, and inside the source.
    func isUsable(withinDuration duration: Double) -> Bool {
        start.isFinite && end.isFinite && start >= 0 && end <= duration && end - start >= Self.minimumSeconds
    }
}
