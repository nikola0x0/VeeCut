import AppKit
import SwiftUI

/// Centers the coach card near the top of the editor window, like Spotlight.
struct CoachOverlay: View {
    @Environment(EditorViewModel.self) private var editor

    var body: some View {
        GeometryReader { geometry in
            if editor.showsCoachCard {
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
                    .overlay(Capsule().strokeBorder(AppTheme.Accent.primary, lineWidth: AppTheme.BorderWidth.focus))
                    .shadow(AppTheme.Shadow.md)
                    .padding(.top, AppTheme.Spacing.xl)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: AppTheme.Anim.transition), value: editor.showsCoachCard)
        .animation(.easeOut(duration: AppTheme.Anim.transition), value: editor.coachListening)
    }
}

/// Vee's question, ideas and reading/planning progress.
struct CoachCard: View {
    @Environment(EditorViewModel.self) private var editor
    @State private var brief = ""
    @FocusState private var briefFocused: Bool
    @State private var songHasDrop = false

    private var pose: VeeIllustration.Name {
        VeePose.pose(coach: editor.coach, isReading: editor.footageReadProgress != nil, isListening: editor.coachListening)
    }

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
            HStack(alignment: .center, spacing: AppTheme.Spacing.lg) {
                VeeIllustration(name: pose, height: AppTheme.Coach.statusPoseHeight)
                planningStatus
            }
        case .failed(let failure):
            HStack(alignment: .center, spacing: AppTheme.Spacing.lg) {
                VeeIllustration(name: pose, height: AppTheme.Coach.statusPoseHeight)
                failed(failure)
            }
        }
    }

    private var planningStatus: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            if let reading = editor.footageReadProgress {
                progress(Self.readingMessage(reading), value: Self.readingValue(reading))
                readingTicker(reading)
            } else {
                progress(L10n.string("Planning the edit…"), value: nil)
                let labels = Set(editor.footageNotes.values.flatMap(\.labels))
                let hasSong = editor.planningSong != nil
                SwiftUI.TimelineView(.periodic(from: .now, by: AppTheme.Coach.quipInterval)) { context in
                    let tick = Int(context.date.timeIntervalSinceReferenceDate / AppTheme.Coach.quipInterval)
                    Text(VeeQuips.line(tick: tick, labels: labels, hasSong: hasSong, hasDrop: songHasDrop))
                        .font(.custom(AppTheme.Brand.wordmarkFontName, size: AppTheme.FontSize.lg).weight(AppTheme.FontWeight.medium))
                        .foregroundStyle(AppTheme.Text.secondaryColor)
                        .id(tick)
                        .transition(.opacity)
                        .animation(.easeOut(duration: AppTheme.Anim.transition), value: tick)
                }
                .task(id: editor.planningSong?.id) {
                    songHasDrop = false
                    guard let song = editor.planningSong else { return }
                    songHasDrop = await editor.musicMap(for: song)?.drop != nil
                }
            }
        }
    }

    private func asking(_ overview: String) -> some View {
        let recommendation = editor.footageRecommendation
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack(alignment: .center, spacing: AppTheme.Spacing.lg) {
                VeeIllustration(name: pose, height: AppTheme.Coach.cardPoseHeight)
                Text(editor.coachQuestion(overview: overview))
                    .font(.custom(AppTheme.Brand.wordmarkFontName, size: AppTheme.FontSize.title1).weight(AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reading = editor.footageReadProgress {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(Self.readingMessage(reading))
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.secondaryColor)
                    progressBar(Self.readingValue(reading))
                }
                readingTicker(reading)
            }
            if let ideas = recommendation?.ideas, !ideas.isEmpty {
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    ForEach(ideas, id: \.self) { idea in
                        ideaButton(idea)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            SongSlot()
            HStack(spacing: AppTheme.Spacing.sm) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "text.cursor")
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                    TextField(L10n.string("Or tell me your own idea: what, how long, what feeling"), text: $brief)
                        .textFieldStyle(.plain)
                        .font(.system(size: AppTheme.FontSize.xl))
                        .focused($briefFocused)
                        .onSubmit { submit(style: nil) }
                }
                .padding(AppTheme.Spacing.md)
                .veeField(focused: briefFocused)
                Button {
                    editor.toggleCoachListening()
                } label: {
                    Label(editor.coachListening ? L10n.string("Stop") : L10n.string("Say It"),
                          systemImage: editor.coachListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.semibold))
                        .padding(.horizontal, AppTheme.Spacing.xs)
                        .frame(minHeight: AppTheme.IconSize.lgXl)
                }
                .buttonStyle(.capsule(.prominent, size: .regular))
            }
            HStack(spacing: AppTheme.Spacing.sm) {
                Text(L10n.string("Or start from a template:"))
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                ForEach(PlanStyle.allCases, id: \.self) { style in
                    Button(style.displayName) { submit(style: style) }
                        .buttonStyle(.capsule(.secondary, size: .small))
                }
                Spacer(minLength: 0)
                Button(L10n.string("Not Now")) { editor.dismissCoach() }
                    .buttonStyle(.capsule(.secondary, size: .small))
            }
            Text(L10n.string("I\u{2019}ll lay out a first cut. Nothing goes in until you keep it."))
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
        }
    }

    private func ideaButton(_ idea: PlanIdea) -> some View {
        IdeaRow(idea: idea) { editor.startIdea(idea) }
    }

    /// Clips come back in batches, so the count only moves once the first batch is read.
    private static func readingMessage(_ reading: FootageReadProgress) -> String {
        reading.done == 0 ? L10n.string("Watching your footage\u{2026}") : L10n.string("Reading your footage… \(reading.done) of \(reading.total) clips")
    }

    private static func readingValue(_ reading: FootageReadProgress) -> Double? {
        reading.done == 0 ? nil : reading.fraction
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
                .buttonStyle(.capsule(.prominent, size: .small))
            Button(L10n.string("Close")) { editor.dismissCoach() }
                .buttonStyle(.capsule(.secondary, size: .small))
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
            reportPlacementFailure(failure)
            return false
        }
    }

    func reportPlacementFailure(_ failure: PlanPlacementFailure) {
        mediaPanelToast = MediaPanelToast(message: failure.message)
        NSSound.beep()
    }
}

/// One recommended video as a card: title, pitch and its style and length; highlights on hover.
private struct IdeaRow: View {
    let idea: PlanIdea
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text(verbatim: idea.title)
                    .font(.system(size: AppTheme.FontSize.lg, weight: AppTheme.FontWeight.bold))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: idea.pitch)
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(format)
                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Accent.primary)
            }
            .padding(AppTheme.Spacing.mdLg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(isHovered ? AppTheme.Tint.lilacColor : AppTheme.Background.surfaceColor, in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.lg).strokeBorder(isHovered ? AppTheme.Accent.primary : AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.thin))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var format: String {
        let seconds = Int(idea.targetSeconds.rounded())
        return seconds < 90
            ? L10n.string("\(idea.style.displayName), \(seconds) seconds")
            : L10n.string("\(idea.style.displayName), about \(Int((Double(seconds) / 60).rounded())) minutes")
    }
}

/// Pick a song before planning and Vee cuts to it: sections follow its parts and the best shot lands on the drop.
/// A menu rather than a drop target: the card floats above AppKit panels, which take every drag under it.
private struct SongSlot: View {
    @Environment(EditorViewModel.self) private var editor
    @State private var map: MusicMap?
    @State private var isListening = false

    var body: some View {
        let song = editor.planningSong
        let songs = editor.mediaAssets.filter { $0.type == .audio && !$0.isGenerating }
        Menu {
            if songs.isEmpty {
                Text(L10n.string("Import a song into the Media panel first."))
            } else {
                ForEach(songs, id: \.id) { candidate in
                    Button {
                        _ = editor.addMusic(candidate)
                    } label: {
                        Text(verbatim: candidate.name)
                    }
                    .disabled(candidate.id == song?.id)
                }
            }
        } label: {
            SongSlotLabel(songName: song?.name, detail: detail)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .task(id: song?.id) {
            map = nil
            guard let song else { return }
            isListening = true
            map = await editor.musicMap(for: song)
            isListening = false
        }
    }

    private var detail: String {
        if isListening { return L10n.string("Listening to the song\u{2026}") }
        guard let map else { return L10n.string("I couldn\u{2019}t find a steady beat, so I\u{2019}ll plan without it.") }
        let length = Self.clock(map.duration)
        if let drop = map.drop {
            return L10n.string("\(length), \(map.parts.count) parts. The drop hits at \(Self.clock(drop)).")
        }
        return L10n.string("\(length), \(map.parts.count) parts. I\u{2019}ll cut to its beat.")
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct SongSlotLabel: View {
    let songName: String?
    let detail: String
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            PhosphorImage(.music)
                .frame(width: AppTheme.IconSize.sm, height: AppTheme.IconSize.sm)
                .foregroundStyle(songName == nil ? AppTheme.Text.tertiaryColor : AppTheme.Accent.primary)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                if let songName {
                    Text(verbatim: songName)
                        .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.semibold))
                        .foregroundStyle(AppTheme.Text.primaryColor)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.secondaryColor)
                } else {
                    Text(L10n.string("Got a song? Pick it here and I\u{2019}ll cut to its beat."))
                        .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.medium))
                        .foregroundStyle(AppTheme.Text.primaryColor)
                    Text(L10n.string("Or drag it onto the timeline."))
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: AppTheme.Coach.songSlotHeight)
        .background(isHovered ? AppTheme.Tint.lilacColor : AppTheme.Background.baseColor, in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .strokeBorder(AppTheme.Border.primaryColor,
                              style: StrokeStyle(lineWidth: AppTheme.BorderWidth.thin, dash: songName == nil ? [AppTheme.Spacing.xs, AppTheme.Spacing.xxs] : []))
        )
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        .onHover { isHovered = $0 }
    }
}
