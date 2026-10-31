import SwiftUI

/// Shows the plan bar when the timeline has a plan; reading the plan here keeps the timeline pane from observing timeline edits.
struct PlanBarHost: View {
    @Environment(EditorViewModel.self) private var editor

    var body: some View {
        if let plan = editor.timeline.plan {
            PlanBar(plan: plan)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(AppTheme.Border.primaryColor)
                        .frame(height: AppTheme.BorderWidth.thin)
                }
        }
    }
}

/// The plan as colored section bands drawn on the timeline's own time scale, right above the clips they cover.
struct PlanBar: View {
    @Environment(EditorViewModel.self) private var editor
    let plan: EditPlan

    var body: some View {
        let progress = PlanLayout.progress(plan, in: editor.timeline)
        let bands = PlanLayout.bands(plan, in: editor.timeline, progress: progress)
        let viewport = editor.timelineViewport
        let zoom = editor.zoomScale
        HStack(spacing: 0) {
            HStack(spacing: AppTheme.Spacing.xs) {
                menu
                PlanTipsButton()
                Spacer(minLength: 0)
                MusicSlot()
            }
            .padding(.trailing, AppTheme.Spacing.xs)
            .padding(.leading, AppTheme.Spacing.sm)
            .frame(width: viewport.headerWidth)
            ScrolledWithTimeline(viewport: viewport) {
                ZStack(alignment: .leading) {
                    ForEach(Array(plan.sections.enumerated()), id: \.element.id) { index, section in
                        let band = bands[index]
                        let slotWidth = Double(band.slot.count) * zoom
                        PlanBand(
                            section: section, progress: progress[index], index: index, count: plan.sections.count,
                            placedFraction: band.slot.isEmpty ? 0 : Double(band.placed?.count ?? 0) / Double(band.slot.count)
                        )
                        .frame(width: max(slotWidth, AppTheme.Coach.minimumBandWidth))
                        .offset(x: Double(band.slot.lowerBound) * zoom)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .padding(.vertical, AppTheme.Spacing.xxs)
        .frame(height: AppTheme.Coach.barHeight)
    }

    private var menu: some View {
        Menu {
            Button(L10n.string("Re-plan…")) { editor.askForPlan() }
            Button(L10n.string("Add Section")) { editor.addPlanSection(after: plan.sections.last?.id) }
            Divider()
            Toggle(L10n.string("Active Coach"), isOn: Binding(
                get: { editor.coachMode == .active },
                set: { editor.setCoachMode($0 ? .active : .passive) }
            ))
            Divider()
            Button(L10n.string("Remove Plan"), role: .destructive) { editor.setPlan(nil, actionName: "Remove Plan") }
        } label: {
            Image(systemName: "sparkles")
                .frame(width: AppTheme.IconSize.sm, height: AppTheme.IconSize.sm)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.string("Plan"))
    }
}

private struct PlanBand: View {
    @Environment(EditorViewModel.self) private var editor
    let section: PlanSection
    let progress: SectionProgress
    let index: Int
    let count: Int
    /// The share of the band covered by placed clips; the rest is the section's missing time.
    let placedFraction: Double
    @State private var showsDetails = false
    @State private var isDropTargeted = false

    private var color: Color { AppTheme.Coach.bandColors[index % AppTheme.Coach.bandColors.count] }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(color.opacity(AppTheme.Opacity.moderate))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                            .strokeBorder(color, style: StrokeStyle(lineWidth: AppTheme.BorderWidth.thin, dash: [AppTheme.Spacing.xs, AppTheme.Spacing.xxs]))
                    )
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(color)
                    .frame(width: geometry.size.width * placedFraction)
                Text(verbatim: label)
                    .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Tint.inkColor)
                    .lineLimit(1)
                    .padding(.horizontal, AppTheme.Spacing.sm)
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .strokeBorder(AppTheme.Accent.primary, lineWidth: isDropTargeted ? AppTheme.BorderWidth.thick : 0)
            }
        }
        .contentShape(Rectangle())
        .help(section.hint)
        .onTapGesture { showsDetails = true }
        .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
            PlanSectionPopover(sectionId: section.id)
                .environment(editor)
        }
        .contextMenu {
            Button(L10n.string("Rename…")) { showsDetails = true }
            Button(L10n.string("Set Length…")) { showsDetails = true }
            Divider()
            Button(L10n.string("Move Left")) { editor.movePlanSection(section.id, by: -1) }
                .disabled(index == 0)
            Button(L10n.string("Move Right")) { editor.movePlanSection(section.id, by: 1) }
                .disabled(index == count - 1)
            Button(L10n.string("Add Section After")) { editor.addPlanSection(after: section.id) }
            Divider()
            Button(L10n.string("Delete Section"), role: .destructive) { editor.deletePlanSection(section.id) }
        }
        .dropDestination(for: String.self) { items, _ in
            let moments = items.flatMap { $0.split(separator: "\n").map(String.init) }.compactMap(moment(fromDragString:))
            guard !moments.isEmpty else { return false }
            return editor.placeMomentsReportingFailure(moments, in: section.id)
        } isTargeted: { isDropTargeted = $0 }
    }

    private var label: String {
        let title = section.title
        if progress.isFilled { return "\(title) ✓" }
        return "\(title)  \(Int(progress.actualSeconds.rounded()))/\(Int(progress.targetSeconds.rounded())) s"
    }

    /// A Media-panel drag: a whole clip, or a search moment carrying its source range.
    private func moment(fromDragString line: String) -> PlanMoment? {
        guard let id = MediaTab.assetId(fromDragString: line),
              let asset = editor.mediaAssets.first(where: { $0.id == id }) else { return nil }
        let range = MediaTab.assetSegment(fromDragString: line) ?? 0...asset.duration
        return PlanMoment(assetId: id, start: range.lowerBound, end: min(range.upperBound, asset.duration), note: "")
    }
}

/// "2 tips" in Passive mode opens the current tip; in Active mode the tip shows on its own.
private struct PlanTipsButton: View {
    @Environment(EditorViewModel.self) private var editor
    @State private var isPresented = false
    @State private var shownNudgeId: String?

    var body: some View {
        let count = editor.coachNudges.count
        Button {
            isPresented = true
        } label: {
            Text(count == 0 ? L10n.string("Plan") : L10n.string("\(count) tips"))
                .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(count == 0 ? AppTheme.Text.secondaryColor : AppTheme.Accent.primary)
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            NudgeCard().environment(editor)
        }
        .onChange(of: editor.coachNudges.first?.id) { _, id in
            guard let id else {
                isPresented = false
                return
            }
            if editor.coachMode == .active, id != shownNudgeId {
                shownNudgeId = id
                isPresented = true
            }
        }
    }
}

/// Drop a song here: it goes on the timeline from the start and its beats feed the coach.
private struct MusicSlot: View {
    @Environment(EditorViewModel.self) private var editor
    @State private var isTargeted = false

    var body: some View {
        let seconds = editor.musicSeconds
        Label {
            Text(seconds.map { String(format: "%d:%02d", Int($0.rounded()) / 60, Int($0.rounded()) % 60) } ?? L10n.string("Music"))
        } icon: {
            Image(systemName: "music.note")
        }
        .font(.system(size: AppTheme.FontSize.xs))
        .foregroundStyle(seconds == nil ? AppTheme.Text.tertiaryColor : AppTheme.Text.secondaryColor)
        .padding(.horizontal, AppTheme.Spacing.xs)
        .padding(.vertical, AppTheme.Spacing.xxs)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                .strokeBorder(isTargeted ? AppTheme.Accent.primary : AppTheme.Border.subtleColor,
                              style: StrokeStyle(lineWidth: AppTheme.BorderWidth.thin, dash: seconds == nil ? [AppTheme.Spacing.xs] : []))
        )
        .help(L10n.string("Drop a song here. It starts at the beginning and its beats guide the cuts."))
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(MediaTab.assetId(fromDragString:)),
                  let asset = editor.mediaAssets.first(where: { $0.id == id }) else { return false }
            if case .failure = editor.addMusic(asset) {
                editor.mediaPanelToast = MediaPanelToast(message: L10n.string("Drop a song or other audio here."))
                return false
            }
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

/// Follows the timeline's horizontal scroll; only this view observes the scroll position.
private struct ScrolledWithTimeline<Content: View>: View {
    let viewport: TimelineViewport
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(x: -viewport.scrollX)
    }
}
