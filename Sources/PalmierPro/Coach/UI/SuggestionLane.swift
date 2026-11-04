import SwiftUI

/// The suggested timeline: faded ghost clips on the timeline's scale, kept one at a time or all at once.
struct SuggestionLane: View {
    @Environment(EditorViewModel.self) private var editor
    let plan: EditPlan
    let ghosts: [GhostClip]

    var body: some View {
        let viewport = editor.timelineViewport
        let zoom = editor.zoomScale
        HStack(spacing: 0) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Button(L10n.string("Keep All")) { editor.keepAllSuggestions() }
                    .buttonStyle(.capsule(.prominent, size: .small))
                    .help(L10n.string("Put every suggested clip on the timeline as one undo step"))
                Button(L10n.string("Hide")) { editor.showsSuggestedTimeline = false }
                    .buttonStyle(.capsule(.secondary, size: .small))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            .frame(width: viewport.headerWidth)
            ScrolledWithTimeline(viewport: viewport) {
                ZStack(alignment: .leading) {
                    ForEach(ghosts) { ghost in
                        GhostClipView(ghost: ghost, color: color(for: ghost), url: editor.mediaAssets.first { $0.id == ghost.moment.assetId }?.url)
                            .frame(width: Double(ghost.durationFrames) * zoom)
                            .offset(x: Double(ghost.startFrame) * zoom)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .padding(.vertical, AppTheme.Spacing.xxs)
        .frame(height: AppTheme.Coach.laneHeight)
    }

    private func color(for ghost: GhostClip) -> Color {
        let index = plan.sections.firstIndex { $0.id == ghost.sectionId } ?? 0
        return AppTheme.Coach.bandColors[index % AppTheme.Coach.bandColors.count]
    }
}

private struct GhostClipView: View {
    @Environment(EditorViewModel.self) private var editor
    let ghost: GhostClip
    let color: Color
    let url: URL?
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MomentThumbnail(url: url, time: ghost.moment.start, contentMode: .fill)
                .opacity(isHovered ? AppTheme.Opacity.prominent : AppTheme.Opacity.medium)
            if !ghost.moment.note.isEmpty {
                Text(verbatim: ghost.moment.note)
                    .font(.system(size: AppTheme.FontSize.xxs, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.MediaOverlay.primaryColor)
                    .lineLimit(1)
                    .padding(.horizontal, AppTheme.Spacing.xs)
                    .padding(.bottom, AppTheme.Spacing.xxs)
            }
            if isHovered {
                Text(L10n.string("Keep"))
                    .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Tint.inkColor)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.xxs)
                    .background(Capsule().fill(AppTheme.Tint.lilacColor))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(color).frame(height: AppTheme.Coach.ghostEdgeHeight)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                .strokeBorder(color, style: StrokeStyle(lineWidth: AppTheme.BorderWidth.thin, dash: [AppTheme.Spacing.xs, AppTheme.Spacing.xxs]))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { editor.keepSuggestion(ghost) }
        .help(ghost.moment.note)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("Keep suggestion"))
        .accessibilityAddTraits(.isButton)
    }
}
