import Foundation

/// Something Vee offers to do; each kind runs one existing editor operation.
struct VeeAction: Equatable, Identifiable {
    enum Kind: Equatable {
        case applyNudge(CoachNudge)
        case dismissNudge(CoachNudge)
        case dismissFailure
        case keepAllSuggestions
        case hideSuggestions
        case smoothSkin(clipId: String)
        case addCaptions(clipId: String)
        case cutPauses(clipId: String)
        case snapToBeat(sectionId: String)
    }

    let kind: Kind
    let title: String

    var id: String {
        switch kind {
        case .applyNudge(let nudge): "apply:\(nudge.id)"
        case .dismissNudge(let nudge): "dismiss:\(nudge.id)"
        case .dismissFailure: "dismissFailure"
        case .keepAllSuggestions: "keepAllSuggestions"
        case .hideSuggestions: "hideSuggestions"
        case .smoothSkin(let clipId): "smoothSkin:\(clipId)"
        case .addCaptions(let clipId): "addCaptions:\(clipId)"
        case .cutPauses(let clipId): "cutPauses:\(clipId)"
        case .snapToBeat(let sectionId): "snapToBeat:\(sectionId)"
        }
    }
}

/// The one thing Vee says right now, shown as a subtitle over the preview.
struct VeeLine: Equatable {
    let id: String
    let text: String
    let pose: VeeIllustration.Name
    let actions: [VeeAction]
}

extension CoachNudge {
    @MainActor func message(in plan: EditPlan) -> String {
        let title = sectionId.flatMap { id in plan.sections.first { $0.id == id }?.title } ?? ""
        switch kind {
        case .sectionOver(_, let extra):
            return L10n.string("\(title) is \(Int(extra.rounded())) s over. Trim its longest shots?")
        case .offBeatCuts(_, let cuts):
            return L10n.string("\(cuts.count) cuts in \(title) are just off the beat. Snap them?")
        case .emptySection(_, let moments):
            return L10n.string("\(title) is empty. You have \(moments.count) moments that fit.")
        case .hookCandidate(_, let moment):
            return moment.note.isEmpty
                ? L10n.string("Open with your strongest shot?")
                : L10n.string("Open with \u{201C}\(moment.note)\u{201D} as your hook?")
        case .fitToMusic(let seconds):
            let planned = plan.sections.reduce(0) { $0 + $1.targetSeconds }
            return L10n.string("The song is \(Self.clock(seconds)) but the plan is \(Self.clock(planned)). Fit the sections to it?")
        }
    }

    @MainActor var actionTitle: String {
        switch kind {
        case .sectionOver: L10n.string("Trim")
        case .offBeatCuts: L10n.string("Snap")
        case .emptySection: L10n.string("Add One")
        case .hookCandidate: L10n.string("Use It")
        case .fitToMusic: L10n.string("Fit")
        }
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
