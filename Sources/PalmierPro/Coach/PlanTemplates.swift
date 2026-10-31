import Foundation

/// Starter plans per style, used without an API key or when the user picks a style with no brief.
@MainActor
enum PlanTemplates {
    static let defaultTotalSeconds = 180.0

    static func plan(_ style: PlanStyle, totalSeconds: Double = defaultTotalSeconds, trackId: String) -> EditPlan {
        let sections = shares(style).map { title, hint, share in
            PlanSection(title: title, targetSeconds: (totalSeconds * share).rounded(), hint: hint)
        }
        return EditPlan(brief: "", style: style, trackId: trackId, sections: sections)
    }

    private static func shares(_ style: PlanStyle) -> [(String, String, Double)] {
        switch style {
        case .travelVlog: [
            (L10n.string("Hook"), L10n.string("Your strongest shot"), 0.08),
            (L10n.string("Arrival"), L10n.string("Wide shots that set the place"), 0.17),
            (L10n.string("Explore"), L10n.string("What you saw and did"), 0.45),
            (L10n.string("Highlight"), L10n.string("The best moment of the trip"), 0.22),
            (L10n.string("Outro"), L10n.string("A calm closing shot"), 0.08),
        ]
        case .reel: [
            (L10n.string("Hook"), L10n.string("Grab attention in the first second"), 0.15),
            (L10n.string("Build"), L10n.string("Quick cuts that raise the energy"), 0.55),
            (L10n.string("Payoff"), L10n.string("The moment it was all for"), 0.30),
        ]
        case .cinematicRecap: [
            (L10n.string("Opening"), L10n.string("A slow, wide establishing shot"), 0.15),
            (L10n.string("Journey"), L10n.string("Moments in the order they happened"), 0.60),
            (L10n.string("Closing"), L10n.string("Let the last shot breathe"), 0.25),
        ]
        case .talkingHead: [
            (L10n.string("Hook"), L10n.string("The line that makes them stay"), 0.10),
            (L10n.string("Point 1"), L10n.string("Your first point"), 0.30),
            (L10n.string("Point 2"), L10n.string("Your second point"), 0.30),
            (L10n.string("Point 3"), L10n.string("Your third point"), 0.20),
            (L10n.string("Wrap"), L10n.string("Sum up and sign off"), 0.10),
        ]
        }
    }
}
