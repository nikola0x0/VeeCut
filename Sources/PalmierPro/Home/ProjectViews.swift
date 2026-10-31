import AppKit
import SwiftUI

/// The project to pick up: its last frame, its name, its plan as section bands and the coach's next tip.
struct LatestProjectCard: View {
    let entry: ProjectEntry
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        let summary = ProjectPlanSummaries.shared.summary(for: entry)
        Button { open(entry) } label: {
            VStack(alignment: .leading, spacing: 0) {
                ProjectThumbnail(entry: entry)
                    .aspectRatio(AppTheme.Home.latestThumbAspect, contentMode: .fit)
                    .overlay(alignment: .topTrailing) {
                        if let summary, summary.durationSeconds > 0 {
                            Text(verbatim: lengthLabel(summary))
                                .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.semibold))
                                .foregroundStyle(AppTheme.Tint.inkColor)
                                .padding(.horizontal, AppTheme.Spacing.sm)
                                .padding(.vertical, AppTheme.Spacing.xxs)
                                .background(Color.white, in: Capsule())
                                .padding(AppTheme.Spacing.mdLg)
                        }
                    }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.mdLg) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: entry.name)
                            .font(.custom(AppTheme.Brand.wordmarkFontName, size: AppTheme.Home.projectTitleSize).weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: AppTheme.Spacing.sm)
                        Text(ProjectDates.edited(entry.lastOpenedDate))
                            .font(.system(size: AppTheme.FontSize.sm))
                            .foregroundStyle(AppTheme.Text.tertiaryColor)
                    }
                    if let summary, !summary.sections.isEmpty {
                        PlanStrip(sections: summary.sections, labeled: true)
                            .frame(height: AppTheme.Home.planStripHeight)
                    }
                    if let summary, let plan = summary.plan, let nudge = summary.nextNudge {
                        Label {
                            Text(nudge.message(in: plan))
                                .font(.system(size: AppTheme.FontSize.sm))
                                .foregroundStyle(AppTheme.Text.primaryColor)
                        } icon: {
                            Image(systemName: "sparkles").foregroundStyle(AppTheme.Accent.primary)
                        }
                        .padding(AppTheme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.Background.baseColor, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                    }
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.Background.raisedColor)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .strokeBorder(isHovered ? AppTheme.Accent.primary.opacity(AppTheme.Opacity.medium) : AppTheme.Border.subtleColor,
                                  lineWidth: AppTheme.BorderWidth.thin)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!entry.isAccessible)
        .onHover { isHovered = $0 }
        .contextMenu { ProjectContextMenu(entry: entry, onDelete: onDelete) }
        .task(id: entry.lastOpenedDate) { await ProjectPlanSummaries.shared.load(entry) }
    }

    private func lengthLabel(_ summary: ProjectPlanSummary) -> String {
        let length = ProjectDates.clock(summary.durationSeconds)
        return summary.plannedSeconds > 0 ? L10n.string("\(length) of \(ProjectDates.clock(summary.plannedSeconds))") : length
    }
}

/// One project in the list: thumbnail, name, when it was last opened and a small plan strip.
struct ProjectRow: View {
    let entry: ProjectEntry
    let isSelecting: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            if isSelecting { onSelect() } else { open(entry) }
        } label: {
            HStack(spacing: AppTheme.Spacing.lg) {
                ProjectThumbnail(entry: entry)
                    .frame(width: AppTheme.Home.rowThumb.width, height: AppTheme.Home.rowThumb.height)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    Text(verbatim: entry.name)
                        .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.semibold))
                        .lineLimit(1)
                    Text(entry.isAccessible ? ProjectDates.edited(entry.lastOpenedDate) : L10n.string("File missing"))
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                }
                Spacer(minLength: AppTheme.Spacing.sm)
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: AppTheme.FontSize.xl))
                        .foregroundStyle(isSelected ? AppTheme.Accent.primary : AppTheme.Text.tertiaryColor)
                } else if let sections = ProjectPlanSummaries.shared.summary(for: entry)?.sections, !sections.isEmpty {
                    PlanStrip(sections: sections, labeled: false)
                        .frame(width: AppTheme.Home.miniPlanSize.width, height: AppTheme.Home.miniPlanSize.height)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(isHovered || isSelected ? AppTheme.Tint.lilacColor.opacity(AppTheme.Opacity.medium) : .clear,
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
            .contentShape(Rectangle())
            .opacity(entry.isAccessible ? 1 : AppTheme.Opacity.strong)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu { ProjectContextMenu(entry: entry, onDelete: onDelete) }
        .task(id: entry.lastOpenedDate) { await ProjectPlanSummaries.shared.load(entry) }
    }
}

/// A project's plan as section bands that fill left to right with what is placed.
struct PlanStrip: View {
    let sections: [ProjectPlanSummary.Section]
    let labeled: Bool

    var body: some View {
        GeometryReader { geometry in
            let total = sections.reduce(0) { $0 + max($1.targetSeconds, 1) }
            let gap = labeled ? AppTheme.Spacing.xxs : AppTheme.BorderWidth.medium
            let available = max(geometry.size.width - gap * CGFloat(max(sections.count - 1, 0)), 0)
            HStack(spacing: gap) {
                ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                    let color = AppTheme.Coach.bandColors[index % AppTheme.Coach.bandColors.count]
                    let fill = min(section.actualSeconds / max(section.targetSeconds, 1), 1)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: labeled ? AppTheme.Radius.sm : AppTheme.Radius.xs)
                            .fill(AppTheme.Text.primaryColor.opacity(AppTheme.Opacity.faint))
                        RoundedRectangle(cornerRadius: labeled ? AppTheme.Radius.sm : AppTheme.Radius.xs)
                            .fill(color)
                            .frame(width: available * max(section.targetSeconds, 1) / total * fill)
                        if labeled {
                            Text(verbatim: section.title)
                                .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.semibold))
                                .foregroundStyle(AppTheme.Tint.inkColor)
                                .lineLimit(1)
                                .padding(.horizontal, AppTheme.Spacing.sm)
                        }
                    }
                    .frame(width: available * max(section.targetSeconds, 1) / total)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("Plan: \(sections.filter { $0.actualSeconds >= $0.targetSeconds * 0.9 }.count) of \(sections.count) sections filled"))
    }
}

/// A project's saved last frame, loaded off the main thread.
struct ProjectThumbnail: View {
    let entry: ProjectEntry
    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack {
            AppTheme.Background.placeholderColor
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: entry.isAccessible ? "film" : "questionmark.folder")
                    .font(.system(size: AppTheme.FontSize.xl, weight: AppTheme.FontWeight.light))
                    .foregroundStyle(AppTheme.Text.mutedColor)
            }
        }
        .clipped()
        .task(id: entry.lastOpenedDate) { await load() }
    }

    private func load() async {
        let url = entry.url.appendingPathComponent(Project.thumbnailFilename, isDirectory: false)
        let image = await Task.detached(priority: .utility) { ImageEncoder.thumbnail(url: url, maxPixelSize: 640) }.value
        guard let image, !Task.isCancelled else { return }
        thumbnail = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

private struct ProjectContextMenu: View {
    let entry: ProjectEntry
    let onDelete: () -> Void

    var body: some View {
        if entry.isAccessible {
            Button(L10n.string("Open")) { open(entry) }
            Button(L10n.string("Reveal in Finder")) {
                NSWorkspace.shared.selectFile(entry.url.path, inFileViewerRootedAtPath: entry.url.deletingLastPathComponent().path)
            }
            Divider()
        }
        Button(L10n.string("Remove from Recents")) { ProjectRegistry.shared.remove(entry.url) }
        Button(L10n.string("Delete Project"), role: .destructive, action: onDelete)
    }
}

@MainActor
private func open(_ entry: ProjectEntry) {
    guard entry.isAccessible else { return }
    AppState.shared.openProject(at: entry.url)
}

@MainActor
enum ProjectDates {
    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static func edited(_ date: Date) -> String {
        L10n.string("Edited \(relative.localizedString(for: date, relativeTo: Date()))")
    }

    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
