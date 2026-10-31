import AppKit
import SwiftUI

/// Centers the coach card near the top of the editor window, like Spotlight.
struct CoachOverlay: View {
    @Environment(EditorViewModel.self) private var editor

    var body: some View {
        GeometryReader { geometry in
            if editor.coach != .hidden {
                CoachCard()
                    .frame(maxWidth: .infinity)
                    .padding(.top, geometry.size.height * AppTheme.Coach.cardTopFraction)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .overlay(alignment: .top) {
            if editor.coachListening {
                Label(L10n.string("Listening…"), systemImage: "waveform")
                    .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                    .symbolEffect(.variableColor.iterative)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.sm)
                    .background(AppTheme.Background.raisedColor, in: Capsule())
                    .overlay(Capsule().strokeBorder(AppTheme.Accent.primary, lineWidth: AppTheme.BorderWidth.medium))
                    .shadow(AppTheme.Shadow.md)
                    .padding(.top, AppTheme.Spacing.xl)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: AppTheme.Anim.transition), value: editor.coach == .hidden)
        .animation(.easeOut(duration: AppTheme.Anim.transition), value: editor.coachListening)
    }
}

/// The coach's question, ideas and reading/planning progress.
struct CoachCard: View {
    @Environment(EditorViewModel.self) private var editor
    @State private var brief = ""

    var body: some View {
        content
            .padding(AppTheme.Spacing.xl)
            .frame(width: AppTheme.Coach.cardWidth, alignment: .leading)
            .background(AppTheme.Background.raisedColor, in: RoundedRectangle(cornerRadius: AppTheme.Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.xl).strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.thin))
            .shadow(AppTheme.Shadow.lg)
            .onExitCommand(perform: close)
    }

    private func close() {
        if editor.coach == .planning { editor.cancelCoach() } else { editor.dismissCoach() }
    }

    @ViewBuilder
    private var content: some View {
        switch editor.coach {
        case .hidden:
            EmptyView()
        case .asking(let overview):
            asking(overview)
        case .planning:
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                if let reading = editor.footageReadProgress {
                    progress(L10n.string("Reading your footage… \(reading.done) of \(reading.total) clips"), value: reading.fraction)
                    readingTicker(reading)
                } else {
                    progress(L10n.string("Planning the edit…"), value: nil)
                    if !editor.coachThinking.isEmpty {
                        Label {
                            Text(verbatim: editor.coachThinking)
                                .lineLimit(4)
                                .truncationMode(.head)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "brain")
                        }
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.secondaryColor)
                        .animation(.easeOut(duration: AppTheme.Anim.transition), value: editor.coachThinking)
                    }
                }
            }
        case .failed(let failure):
            failed(failure)
        }
    }

    private func asking(_ overview: String) -> some View {
        let recommendation = editor.footageRecommendation
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Label {
                Text(editor.coachQuestion(overview: overview))
                    .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.primaryColor)
            } icon: {
                Image(systemName: "sparkles").foregroundStyle(AppTheme.Accent.canvasAI)
            }
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "text.cursor")
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                TextField(L10n.string("Describe what you want: idea, vibe and length"), text: $brief)
                    .textFieldStyle(.plain)
                    .font(.system(size: AppTheme.FontSize.xl))
                    .onSubmit { submit(style: nil) }
            }
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Background.baseColor, in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.lg).strokeBorder(AppTheme.Border.primaryColor, lineWidth: AppTheme.BorderWidth.thin))
            if let reading = editor.footageReadProgress {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(L10n.string("Reading your footage… \(reading.done) of \(reading.total) clips"))
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.secondaryColor)
                    progressBar(reading.fraction)
                }
                readingTicker(reading)
            }
            if let ideas = recommendation?.ideas, !ideas.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    ForEach(ideas, id: \.self) { idea in
                        ideaButton(idea)
                    }
                }
            }
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(PlanStyle.allCases, id: \.self) { style in
                    Button(style.displayName) { submit(style: style) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Spacer(minLength: 0)
                Button(L10n.string("Not Now")) { editor.dismissCoach() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
    }

    private func ideaButton(_ idea: PlanIdea) -> some View {
        IdeaRow(idea: idea) { editor.startIdea(idea) }
    }

    private func readingTicker(_ reading: FootageReadProgress) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
            ForEach(Array(reading.recent.enumerated()), id: \.offset) { _, summary in
                Label {
                    Text(verbatim: summary).lineLimit(1)
                } icon: {
                    Image(systemName: "eye")
                }
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: AppTheme.Anim.transition), value: reading.recent)
    }

    private func progress(_ message: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.md) {
                Text(message)
                    .font(.system(size: AppTheme.FontSize.md))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Spacer(minLength: 0)
                Button(L10n.string("Cancel")) { editor.cancelCoach() }
                    .controlSize(.small)
            }
            progressBar(value)
        }
    }

    /// Fills left to right like the export progress; nil animates while there is nothing to count.
    @ViewBuilder
    private func progressBar(_ value: Double?) -> some View {
        Group {
            if let value {
                ProgressView(value: value)
            } else {
                ProgressView()
            }
        }
        .progressViewStyle(.linear)
        .tint(AppTheme.Accent.primary)
        .animation(.linear(duration: AppTheme.Anim.transition), value: value)
    }

    private func failed(_ failure: CoachFailure) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(AppTheme.Status.warningColor)
            Text(failure.message)
                .font(.system(size: AppTheme.FontSize.md))
                .foregroundStyle(AppTheme.Text.primaryColor)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(L10n.string("Try Again")) { editor.askForPlan() }
                .controlSize(.small)
            Button(L10n.string("Close")) { editor.dismissCoach() }
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
    }

    private func submit(style: PlanStyle?) {
        let text = brief.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            if let style { editor.startStarterPlan(style) }
        } else {
            editor.submitBrief(text, style: style)
        }
    }
}

extension PlanStyle {
    @MainActor var displayName: String {
        switch self {
        case .travelVlog: L10n.string("Travel Vlog")
        case .reel: L10n.string("Reel")
        case .cinematicRecap: L10n.string("Cinematic Recap")
        case .talkingHead: L10n.string("Talking Head")
        }
    }
}

extension CoachFailure {
    @MainActor var message: String {
        switch self {
        case .missingAPIKey: L10n.string("Add your Meta API key in Settings to plan with Muse Spark.")
        case .noFootage: L10n.string("Import video to plan an edit from.")
        case .emptyPlan: L10n.string("Muse Spark didn't return a usable plan. Try again with more detail.")
        case .cancelled: L10n.string("Planning was cancelled.")
        case .service(let detail): L10n.string("Planning failed: \(detail)")
        }
    }
}

extension PlanPlacementFailure {
    @MainActor var message: String {
        switch self {
        case .noPlan: L10n.string("This timeline has no plan.")
        case .unknownSection: L10n.string("That section no longer exists.")
        case .unknownAsset: L10n.string("Sections take video and images. Put music on an audio track.")
        case .invalidRange: L10n.string("That moment is outside the clip.")
        case .rippleBlocked: L10n.string("Inserting there would break a multicam group's sync.")
        }
    }
}

extension EditorViewModel {
    /// Places the moments and says why when nothing could be placed.
    @discardableResult
    func placeMomentsReportingFailure(_ moments: [PlanMoment], in sectionId: String) -> Bool {
        switch placeMoments(moments, in: sectionId) {
        case .success: return true
        case .failure(let failure):
            mediaPanelToast = MediaPanelToast(message: failure.message)
            NSSound.beep()
            return false
        }
    }
}

/// One recommended video: title and pitch, with its style and length; highlights on hover.
private struct IdeaRow: View {
    let idea: PlanIdea
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    Text(verbatim: idea.title)
                        .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.semibold))
                        .foregroundStyle(AppTheme.Text.primaryColor)
                    Text(verbatim: idea.pitch)
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.secondaryColor)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Text(L10n.string("\(idea.style.displayName) · \(Int(idea.targetSeconds.rounded())) s"))
                    .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Accent.primary)
            }
            .padding(AppTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? AppTheme.Tint.lilacColor : AppTheme.Background.surfaceColor, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.md).strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.thin))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
