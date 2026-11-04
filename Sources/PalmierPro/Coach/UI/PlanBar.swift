import SwiftUI

/// Shows the plan bar when the timeline has a plan; reading the plan here keeps the timeline pane from observing timeline edits.
struct PlanBarHost: View {
    @Environment(EditorViewModel.self) private var editor

    var body: some View {
        if let plan = editor.timeline.plan {
            VStack(spacing: 0) {
                PlanBar(plan: plan)
                if editor.showsSuggestedTimeline {
                    let ghosts = editor.suggestedGhosts
                    if !ghosts.isEmpty { SuggestionLane(plan: plan, ghosts: ghosts) }
                }
            }
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
                PlanTipsLabel()
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
                        PlanBand(
                            section: section, progress: progress[index], index: index, count: plan.sections.count,
                            placedFraction: band.slot.isEmpty ? 0 : Double(band.placed?.count ?? 0) / Double(band.slot.count),
                            slotWidth: Double(band.slot.count) * zoom,
                            beatSeconds: plan.music?.beatSeconds
                        )
                        .offset(x: Double(band.slot.lowerBound) * zoom)
                    }
                    if let last = plan.sections.last, let end = bands.last?.slot.upperBound {
                        AddSectionBand { _ = editor.addPlanSection(after: last.id) }
                            .frame(width: PlanSection.newSectionSeconds * Double(editor.timeline.fps) * zoom)
                            .offset(x: Double(end) * zoom)
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
            Toggle(L10n.string("Show Suggestions"), isOn: Binding(
                get: { editor.showsSuggestedTimeline },
                set: { editor.showsSuggestedTimeline = $0 }
            ))
            Divider()
            Toggle(L10n.string("Vee Speaks Aloud"), isOn: Binding(
                get: { editor.coachMode == .active },
                set: { editor.setCoachMode($0 ? .active : .passive) }
            ))
            Divider()
            Button(L10n.string("Remove Plan"), role: .destructive) { editor.setPlan(nil, actionName: "Remove Plan") }
        } label: {
            HStack(spacing: AppTheme.Spacing.xxs) {
                PhosphorImage(.list)
                    .frame(width: AppTheme.IconSize.xxs, height: AppTheme.IconSize.xxs)
                Text(L10n.string("Plan"))
                Image(systemName: "chevron.down")
                    .font(.system(size: AppTheme.FontSize.micro, weight: AppTheme.FontWeight.semibold))
            }
            .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.medium))
            .foregroundStyle(AppTheme.Text.secondaryColor)
            .planBarChip(border: AppTheme.Border.subtleColor)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.string("Edit the plan: add sections, re-plan, or remove it"))
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
    let slotWidth: Double
    let beatSeconds: Double?
    @State private var showsDetails = false
    @State private var isDropTargeted = false
    @State private var isHovered = false
    @State private var resizeFrames: Double?

    private var color: Color { AppTheme.Coach.bandColors[index % AppTheme.Coach.bandColors.count] }

    private var resizedSeconds: Double? {
        resizeFrames.map { PlanLayout.resizedSeconds(from: section.targetSeconds, dragFrames: $0, fps: editor.timeline.fps, beatSeconds: beatSeconds) }
    }

    private var displayWidth: Double {
        guard let seconds = resizedSeconds else { return slotWidth }
        return max(slotWidth + (seconds - section.targetSeconds) * Double(editor.timeline.fps) * editor.zoomScale, AppTheme.Coach.bandResizeHandleWidth * 2)
    }

    var body: some View {
        band
            .frame(width: displayWidth)
            .overlay(alignment: .trailing) { resizeHandle }
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: AppTheme.Coach.bandResizeHandleWidth)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in resizeFrames = value.translation.width / max(editor.zoomScale, 1e-6) }
                    .onEnded { _ in
                        if let seconds = resizedSeconds, seconds != section.targetSeconds {
                            editor.setPlanSectionTarget(section.id, seconds: seconds)
                        }
                        resizeFrames = nil
                    }
            )
            .help(L10n.string("Drag to change the section's length"))
    }

    private var band: some View {
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
                HStack(spacing: AppTheme.Spacing.xxs) {
                    Text(verbatim: label)
                        .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.medium))
                        .foregroundStyle(AppTheme.Tint.inkColor)
                        .lineLimit(1)
                    if isHovered || resizeFrames != nil {
                        Image(systemName: "pencil")
                            .font(.system(size: AppTheme.FontSize.xxs, weight: AppTheme.FontWeight.semibold))
                            .foregroundStyle(AppTheme.Tint.inkColor)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.sm)
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .strokeBorder(AppTheme.Accent.primary, lineWidth: isDropTargeted || isHovered || resizeFrames != nil ? AppTheme.BorderWidth.focus : 0)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .pointerStyle(.link)
        .help(L10n.string("\(section.title). Click to edit, drag the right edge to change its length, or drop clips here."))
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
        if let seconds = resizedSeconds { return "\(title)  \(Int(seconds.rounded())) s" }
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

/// Where the next section would go: a dashed band as long as a new section, added on click.
private struct AddSectionBand: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(L10n.string("Add Section"), systemImage: "plus")
                .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(isHovered ? AppTheme.Accent.primary : AppTheme.Text.tertiaryColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                        .fill(isHovered ? AppTheme.Accent.primary.opacity(AppTheme.Opacity.subtle) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                        .strokeBorder(isHovered ? AppTheme.Accent.primary : AppTheme.Border.subtleColor,
                                      style: StrokeStyle(lineWidth: AppTheme.BorderWidth.thin, dash: [AppTheme.Spacing.xs, AppTheme.Spacing.xxs]))
                )
                .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(L10n.string("Add a section after the last one"))
    }
}

/// How many tips are waiting; Vee says the first one over the preview.
private struct PlanTipsLabel: View {
    @Environment(EditorViewModel.self) private var editor

    var body: some View {
        let count = editor.coachNudges.count
        if count > 0 {
            Text(L10n.string("\(count) tips"))
                .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.Accent.primary)
                .lineLimit(1)
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
        .planBarChip(border: isTargeted ? AppTheme.Accent.primary : AppTheme.Border.subtleColor, dashed: seconds == nil)
        .help(L10n.string("Drop a song here. It starts at the beginning and its beats guide the cuts."))
        .dropDestination(for: String.self) { items, _ in
            editor.addMusic(fromDragStrings: items)
        } isTargeted: { isTargeted = $0 }
    }
}

/// Follows the timeline's horizontal scroll; only this view observes the scroll position.
struct ScrolledWithTimeline<Content: View>: View {
    let viewport: TimelineViewport
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .offset(x: -viewport.scrollX)
    }
}

private extension View {
    /// The plan bar's small outlined chips (the Plan menu and the music slot), sized to its 10 pt labels.
    func planBarChip(border: Color, dashed: Bool = false) -> some View {
        padding(.horizontal, AppTheme.Spacing.xs)
            .padding(.vertical, AppTheme.Spacing.xxs)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .strokeBorder(border, style: StrokeStyle(lineWidth: AppTheme.BorderWidth.thin, dash: dashed ? [AppTheme.Spacing.xs] : []))
            )
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
    }
}
