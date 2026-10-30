import SwiftUI

enum MentionTab: CaseIterable, Hashable {
    case all, objects, video, image, audio

    var localizedLabel: String {
        switch self {
        case .all: L10n.key("All")
        case .objects: L10n.key("Objects")
        case .video: L10n.key("Video")
        case .image: L10n.key("Image")
        case .audio: L10n.key("Audio")
        }
    }

    var clipType: ClipType? {
        switch self {
        case .all, .objects: nil
        case .video: .video
        case .image: .image
        case .audio: .audio
        }
    }

    var localizedEmptyLabel: String {
        switch self {
        case .all: L10n.key("No media")
        case .objects: L10n.key("No objects on this clip")
        case .video: L10n.key("No video clips")
        case .image: L10n.key("No images")
        case .audio: L10n.key("No audio")
        }
    }
}

/// Something `@` can reference: an object picked on the shelf's clip, or a media asset.
@MainActor
enum MentionCandidate {
    case object(TrackedMask, clipId: String)
    case media(MediaAsset)

    static let limit = 50

    var id: String {
        switch self {
        case .object(let mask, _): mask.id
        case .media(let asset): asset.id
        }
    }

    var displayName: String {
        switch self {
        case .object(let mask, _): AgentMention.makeDisplayName(from: mask.label)
        case .media(let asset): asset.mentionDisplayName
        }
    }

    /// The shelf clip's objects first, then media, filtered by tab and a case-insensitive name match.
    @MainActor
    static func candidates(query: String, tab: MentionTab, editor: EditorViewModel) -> [MentionCandidate] {
        var all: [MentionCandidate] = []
        if tab == .all || tab == .objects, let clipId = editor.shelfClipId {
            all += editor.canvasObjects(clipId: clipId).map { .object($0, clipId: clipId) }
        }
        if tab != .objects {
            let assets = tab.clipType.map { type in editor.mediaAssets.filter { $0.type == type } } ?? editor.mediaAssets
            all += assets.map(MentionCandidate.media)
        }
        let q = query.lowercased()
        let matched = q.isEmpty ? all : all.filter { $0.displayName.lowercased().contains(q) }
        return Array(matched.prefix(limit))
    }
}

/// Pure render. State lives on `AgentInputBox` so keyboard nav follows the focused TextEditor.
struct MentionPopover: View {
    let query: String
    let candidates: [MentionCandidate]
    @Binding var highlightedIndex: Int
    @Binding var tab: MentionTab
    let scrollTick: Int
    let onPick: (MentionCandidate) -> Void

    @State private var visibleIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabStrip
            Rectangle().fill(AppTheme.Border.subtleColor).frame(height: 0.5)
            contentArea
                .frame(height: 280)
        }
        .frame(width: 260)
        .glassEffect(.clear, in: .rect(cornerRadius: AppTheme.Radius.md))
    }

    @ViewBuilder
    private var contentArea: some View {
        if candidates.isEmpty {
            Text(query.isEmpty
                ? L10n.string(key: tab.localizedEmptyLabel)
                : L10n.string("No matches for \"\(query)\""))
                .font(.system(size: AppTheme.FontSize.xs))
                .foregroundStyle(AppTheme.Text.mutedColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(AppTheme.Spacing.md)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                            mentionRow(candidate, isHighlighted: index == highlightedIndex)
                                .contentShape(Rectangle())
                                .onTapGesture { onPick(candidate) }
                                .onHover { hovering in if hovering { highlightedIndex = index } }
                                .id(candidate.id)
                                .onScrollVisibilityChange(threshold: 0.95) { visible in
                                    if visible {
                                        visibleIDs.insert(candidate.id)
                                    } else {
                                        visibleIDs.remove(candidate.id)
                                    }
                                }
                        }
                    }
                }
                .onChange(of: scrollTick) { _, _ in
                    scrollHighlightIntoViewIfNeeded(proxy: proxy)
                }
                .onChange(of: candidates.map(\.id)) { _, ids in
                    visibleIDs.formIntersection(ids)
                }
            }
        }
    }

    private func scrollHighlightIntoViewIfNeeded(proxy: ScrollViewProxy) {
        guard candidates.indices.contains(highlightedIndex) else { return }
        let targetID = candidates[highlightedIndex].id
        if visibleIDs.contains(targetID) { return }

        let visibleIndices = visibleIDs.compactMap { id in
            candidates.firstIndex { $0.id == id }
        }
        let anchor: UnitPoint = (visibleIndices.max().map { highlightedIndex > $0 } ?? false)
            ? .bottom
            : .top

        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(targetID, anchor: anchor)
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 0) {
            ForEach(MentionTab.allCases, id: \.self) { t in
                Text(L10n.string(key: t.localizedLabel))
                    .font(.system(size: AppTheme.FontSize.xs, weight: t == tab ? .semibold : .regular))
                    .foregroundStyle(t == tab ? AppTheme.Text.primaryColor : AppTheme.Text.tertiaryColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        t == tab
                            ? AppTheme.Accent.primary.opacity(0.18)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { tab = t }
            }
        }
        .padding(AppTheme.Spacing.xs)
    }

    private func mentionRow(_ candidate: MentionCandidate, isHighlighted: Bool) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Group {
                switch candidate {
                case .media(let asset):
                    if let thumb = asset.thumbnail {
                        Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        placeholder(systemImage: asset.type.sfSymbolName)
                    }
                case .object:
                    ZStack {
                        Rectangle().fill(AppTheme.ObjectKind.fill)
                        Image(systemName: "person.crop.rectangle")
                            .font(.system(size: AppTheme.FontSize.xs))
                            .foregroundStyle(AppTheme.Tint.inkColor)
                    }
                }
            }
            .frame(width: 28, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: candidate.displayName)
                    .font(.system(size: AppTheme.FontSize.xs, weight: .medium))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                    .lineLimit(1)
                Text(verbatim: subtitle(candidate))
                    .font(.system(size: AppTheme.FontSize.xxs))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }
            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, 4)
        .background(isHighlighted ? AppTheme.Accent.primary.opacity(0.15) : .clear)
    }

    private func placeholder(systemImage: String) -> some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: systemImage)
                .font(.system(size: AppTheme.FontSize.xs))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
        }
    }

    private func subtitle(_ candidate: MentionCandidate) -> String {
        switch candidate {
        case .media(let asset): asset.type.localizedTrackLabel
        case .object: L10n.string("Tracked object")
        }
    }
}
