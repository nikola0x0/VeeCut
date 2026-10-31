import SwiftUI

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

/// The current coaching tip with its one-click fix; one tip at a time.
struct NudgeCard: View {
    @Environment(EditorViewModel.self) private var editor

    var body: some View {
        if let plan = editor.timeline.plan, let nudge = editor.coachNudges.first {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "sparkles").foregroundStyle(AppTheme.Accent.canvasAI)
                    Text(nudge.message(in: plan))
                        .font(.system(size: AppTheme.FontSize.md))
                        .foregroundStyle(AppTheme.Text.primaryColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: AppTheme.Spacing.sm) {
                    if editor.coachNudges.count > 1 {
                        Text(L10n.string("\(editor.coachNudges.count - 1) more"))
                            .font(.system(size: AppTheme.FontSize.xs))
                            .foregroundStyle(AppTheme.Text.tertiaryColor)
                    }
                    Spacer(minLength: 0)
                    Button(L10n.string("Not Now")) { editor.dismiss(nudge) }
                        .controlSize(.small)
                    Button(nudge.actionTitle) { editor.apply(nudge) }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(AppTheme.Spacing.lg)
            .frame(width: AppTheme.Coach.nudgeWidth, alignment: .leading)
        }
    }
}
