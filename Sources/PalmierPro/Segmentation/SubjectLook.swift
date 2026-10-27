import Foundation

/// One look's effects: for a subject and the clip's background, or for the whole clip.
struct LookPlan: Equatable, Sendable {
    var subject: [Effect] = []
    var background: [Effect] = []
    /// Whole-clip grade, for clips without a subject.
    var frame: [Effect] = []

    var isEmpty: Bool { subject.isEmpty && background.isEmpty && frame.isEmpty }
}

/// One-click looks for the tracked subject, its background, both, or the whole clip.
enum SubjectLook: CaseIterable {
    case popSubject
    case darkenBackground
    case blurBackground
    case vlogPop
    case cinematic
    case moody

    enum Placement { case subject, background, both }

    var placement: Placement {
        switch self {
        case .popSubject: .subject
        case .darkenBackground, .blurBackground: .background
        case .vlogPop, .cinematic, .moody: .both
        }
    }

    /// The look split around a subject, or as one whole-clip grade when there is none.
    func plan(hasSubject: Bool) -> LookPlan {
        guard !hasSubject, placement == .both else { return plan }
        switch self {
        case .vlogPop:
            return LookPlan(frame: [
                .make("color.exposure", ["ev": 0.15]), .make("color.contrast", ["amount": 1.06]),
                .make("color.temperature", ["temperature": 7000, "tint": 0]), .make("color.vibrance", ["amount": 0.35]),
            ])
        case .cinematic:
            return LookPlan(frame: [
                .make("color.contrast", ["amount": 1.1]),
                .make("color.highlightsShadows", ["highlights": -0.2, "shadows": 0.1]),
                .make("color.temperature", ["temperature": 5800, "tint": 0]),
                .make("color.saturation", ["amount": 0.85]),
                .make("stylize.grain", ["amount": 0.12, "size": 1.5]),
                .make("stylize.vignette", ["amount": -0.3, "midpoint": 0.5, "roundness": 0, "feather": 0.6]),
            ])
        case .moody:
            return LookPlan(frame: [
                .make("color.exposure", ["ev": -0.3]), .make("color.contrast", ["amount": 1.12]),
                .make("color.temperature", ["temperature": 5500, "tint": 0]),
                .make("color.saturation", ["amount": 0.6]),
                .make("stylize.vignette", ["amount": -0.45, "midpoint": 0.45, "roundness": 0, "feather": 0.6]),
            ])
        case .popSubject, .darkenBackground, .blurBackground:
            return plan
        }
    }

    var titleKey: String {
        switch self {
        case .popSubject: L10n.key("Pop Subject")
        case .darkenBackground: L10n.key("Darken Background")
        case .blurBackground: L10n.key("Blur Background")
        case .vlogPop: L10n.key("Vlog Pop")
        case .cinematic: L10n.key("Cinematic")
        case .moody: L10n.key("Moody")
        }
    }

    var plan: LookPlan {
        switch self {
        case .popSubject:
            LookPlan(subject: [
                .make("color.exposure", ["ev": 0.3]), .make("color.contrast", ["amount": 1.08]),
                .make("color.vibrance", ["amount": 0.3]),
            ])
        case .darkenBackground:
            LookPlan(background: [.make("color.exposure", ["ev": -1.2]), .make("color.saturation", ["amount": 0.7])])
        case .blurBackground:
            LookPlan(background: [.make(Effect.gaussianBlurType, [Effect.gaussianBlurRadiusKey: 14])])
        case .vlogPop:
            LookPlan(
                subject: [
                    .make("color.exposure", ["ev": 0.25]), .make("color.contrast", ["amount": 1.06]),
                    .make("color.vibrance", ["amount": 0.35]),
                ],
                background: [
                    .make("color.temperature", ["temperature": 7200, "tint": 0]),
                    .make("color.vibrance", ["amount": 0.25]),
                    .make(Effect.gaussianBlurType, [Effect.gaussianBlurRadiusKey: 5]),
                ]
            )
        case .cinematic:
            LookPlan(
                subject: [
                    .make("color.contrast", ["amount": 1.1]),
                    .make("color.highlightsShadows", ["highlights": -0.15, "shadows": 0.15]),
                    .make("stylize.grain", ["amount": 0.12, "size": 1.5]),
                ],
                background: [
                    .make("color.exposure", ["ev": -0.4]),
                    .make("color.temperature", ["temperature": 5600, "tint": 0]),
                    .make("color.saturation", ["amount": 0.8]),
                    .make("stylize.grain", ["amount": 0.12, "size": 1.5]),
                    .make("stylize.vignette", ["amount": -0.35, "midpoint": 0.5, "roundness": 0, "feather": 0.6]),
                ]
            )
        case .moody:
            LookPlan(
                subject: [.make("color.contrast", ["amount": 1.12]), .make("color.saturation", ["amount": 0.85])],
                background: [
                    .make("color.exposure", ["ev": -0.8]),
                    .make("color.temperature", ["temperature": 5400, "tint": 0]),
                    .make("color.saturation", ["amount": 0.55]),
                    .make("stylize.vignette", ["amount": -0.5, "midpoint": 0.45, "roundness": 0, "feather": 0.6]),
                ]
            )
        }
    }
}
