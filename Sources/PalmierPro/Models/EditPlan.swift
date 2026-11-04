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
    /// How fast the cuts come, from the song part this section sits on; nil without a song.
    var pace: MusicEnergy? = nil

    /// The length a section starts with when added by hand.
    static let newSectionSeconds = 10.0
}

/// The song a plan was cut to: its tempo and where the drop lands, in song seconds from the start.
struct PlanMusic: Codable, Sendable, Equatable {
    var assetId: String
    var beatSeconds: Double
    var drop: Double?
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
    var music: PlanMusic? = nil
}

extension PlanMoment {
    static let minimumSeconds = 1.0

    /// Finite, at least a second long, and inside the source.
    func isUsable(withinDuration duration: Double) -> Bool {
        start.isFinite && end.isFinite && start >= 0 && end <= duration && end - start >= Self.minimumSeconds
    }
}
