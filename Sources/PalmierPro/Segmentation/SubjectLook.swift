import Foundation

/// One look's effects: for a subject and the clip's background, or for the whole clip.
struct LookPlan: Equatable, Sendable {
    var subject: [Effect] = []
    var background: [Effect] = []
    /// Whole-clip grade, for clips without a subject.
    var frame: [Effect] = []

    var isEmpty: Bool { subject.isEmpty && background.isEmpty && frame.isEmpty }
}

/// One-click presets for the tracked subject, its background, both, or the whole clip.
enum SubjectLook: CaseIterable {
    case popSubject
    case crispSubject
    case darkenBackground
    case blurBackground
    case colorPop
    case vlogPop
    case cinematic
    case moody
    case goldenHour
    case tealOrange
    case noir
    case vintageFilm
    case dreamy
    case crisp

    enum Placement { case subject, background, both }

    var placement: Placement {
        switch self {
        case .popSubject, .crispSubject: .subject
        case .darkenBackground, .blurBackground, .colorPop: .background
        case .vlogPop, .cinematic, .moody, .goldenHour, .tealOrange, .noir, .vintageFilm, .dreamy, .crisp: .both
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
        case .goldenHour:
            return LookPlan(frame: [
                .make("color.exposure", ["ev": 0.1]), .make("color.temperature", ["temperature": 7600, "tint": 5]),
                .make("color.vibrance", ["amount": 0.2]),
                .make("stylize.glow", ["intensity": 0.2, "radius": 30, "threshold": 0.6, "warmth": 0.5]),
            ])
        case .tealOrange:
            return LookPlan(frame: [
                .make("color.contrast", ["amount": 1.08]), .make("color.temperature", ["temperature": 5000, "tint": -8]),
                .make("color.highlightsShadows", ["highlights": -0.1, "shadows": 0.1]),
                .make("color.vibrance", ["amount": 0.25]),
            ])
        case .noir:
            return LookPlan(frame: [
                .make("color.saturation", ["amount": 0]), .make("color.contrast", ["amount": 1.25]),
                .make("stylize.grain", ["amount": 0.15, "size": 1.5]),
                .make("stylize.vignette", ["amount": -0.45, "midpoint": 0.45, "roundness": 0, "feather": 0.6]),
            ])
        case .vintageFilm:
            return LookPlan(frame: [
                .make("color.contrast", ["amount": 0.92]), .make("color.saturation", ["amount": 0.75]),
                .make("color.temperature", ["temperature": 6600, "tint": 6]),
                .make("color.highlightsShadows", ["highlights": -0.1, "shadows": 0.2]),
                .make("stylize.grain", ["amount": 0.25, "size": 2]),
                .make("stylize.vignette", ["amount": -0.25, "midpoint": 0.5, "roundness": 0, "feather": 0.7]),
            ])
        case .dreamy:
            return LookPlan(frame: [
                .make("color.exposure", ["ev": 0.15]), .make("color.contrast", ["amount": 0.92]),
                .make("color.saturation", ["amount": 0.9]),
                .make("stylize.glow", ["intensity": 0.35, "radius": 40, "threshold": 0.5, "warmth": 0.3]),
            ])
        case .crisp:
            return LookPlan(frame: [
                .make("detail.clarity", ["clarity": 0.3, "dehaze": 0.1]), .make("blur.sharpen", ["amount": 0.5]),
                .make("color.contrast", ["amount": 1.05]), .make("color.vibrance", ["amount": 0.2]),
            ])
        case .popSubject, .crispSubject, .darkenBackground, .blurBackground, .colorPop:
            return plan
        }
    }

    var titleKey: String {
        switch self {
        case .popSubject: L10n.key("Pop Subject")
        case .crispSubject: L10n.key("Crisp Subject")
        case .darkenBackground: L10n.key("Darken Background")
        case .blurBackground: L10n.key("Blur Background")
        case .colorPop: L10n.key("Color Pop")
        case .vlogPop: L10n.key("Vlog Pop")
        case .cinematic: L10n.key("Cinematic")
        case .moody: L10n.key("Moody")
        case .goldenHour: L10n.key("Golden Hour")
        case .tealOrange: L10n.key("Teal & Orange")
        case .noir: L10n.key("Noir")
        case .vintageFilm: L10n.key("Vintage Film")
        case .dreamy: L10n.key("Dreamy")
        case .crisp: L10n.key("Crisp")
        }
    }

    var plan: LookPlan {
        switch self {
        case .popSubject:
            LookPlan(subject: [
                .make("color.exposure", ["ev": 0.3]), .make("color.contrast", ["amount": 1.08]),
                .make("color.vibrance", ["amount": 0.3]),
            ])
        case .crispSubject:
            LookPlan(subject: [.make("detail.clarity", ["clarity": 0.35, "dehaze": 0]), .make("blur.sharpen", ["amount": 0.5])])
        case .darkenBackground:
            LookPlan(background: [.make("color.exposure", ["ev": -1.2]), .make("color.saturation", ["amount": 0.7])])
        case .colorPop:
            LookPlan(background: [.make("color.saturation", ["amount": 0])])
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
        case .goldenHour:
            LookPlan(
                subject: [.make("color.exposure", ["ev": 0.15]), .make("color.vibrance", ["amount": 0.25])],
                background: [
                    .make("color.temperature", ["temperature": 7800, "tint": 5]),
                    .make("stylize.glow", ["intensity": 0.25, "radius": 30, "threshold": 0.55, "warmth": 0.6]),
                ]
            )
        case .tealOrange:
            LookPlan(
                subject: [.make("color.temperature", ["temperature": 7000, "tint": 4]), .make("color.vibrance", ["amount": 0.2])],
                background: [
                    .make("color.temperature", ["temperature": 4600, "tint": -10]),
                    .make("color.contrast", ["amount": 1.1]),
                    .make("color.highlightsShadows", ["highlights": -0.15, "shadows": 0.05]),
                ]
            )
        case .noir:
            LookPlan(
                subject: [.make("color.saturation", ["amount": 0]), .make("color.contrast", ["amount": 1.2])],
                background: [
                    .make("color.saturation", ["amount": 0]), .make("color.exposure", ["ev": -0.5]),
                    .make("color.contrast", ["amount": 1.25]),
                    .make("stylize.vignette", ["amount": -0.5, "midpoint": 0.45, "roundness": 0, "feather": 0.6]),
                ]
            )
        case .vintageFilm:
            LookPlan(
                subject: [.make("color.saturation", ["amount": 0.85]), .make("stylize.grain", ["amount": 0.25, "size": 2])],
                background: [
                    .make("color.contrast", ["amount": 0.9]), .make("color.saturation", ["amount": 0.7]),
                    .make("color.temperature", ["temperature": 6600, "tint": 6]),
                    .make("stylize.grain", ["amount": 0.25, "size": 2]),
                    .make("stylize.vignette", ["amount": -0.3, "midpoint": 0.5, "roundness": 0, "feather": 0.7]),
                ]
            )
        case .dreamy:
            LookPlan(
                subject: [.make("color.exposure", ["ev": 0.15]), .make("detail.clarity", ["clarity": -0.2, "dehaze": 0])],
                background: [
                    .make("stylize.glow", ["intensity": 0.45, "radius": 45, "threshold": 0.45, "warmth": 0.3]),
                    .make(Effect.gaussianBlurType, [Effect.gaussianBlurRadiusKey: 3]),
                ]
            )
        case .crisp:
            LookPlan(
                subject: [.make("detail.clarity", ["clarity": 0.35, "dehaze": 0]), .make("blur.sharpen", ["amount": 0.5])],
                background: [.make("detail.clarity", ["clarity": 0.15, "dehaze": 0.1]), .make("color.vibrance", ["amount": 0.15])]
            )
        }
    }
}
