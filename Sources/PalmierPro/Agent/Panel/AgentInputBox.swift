import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AgentInputBox<LeadingTools: View>: View {
    @Environment(EditorViewModel.self) var editor
    @Binding var draft: String
    @Binding var mentions: [AgentMention]
    let isSending: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onCancel: () -> Void
    let leadingTools: LeadingTools

    init(
        draft: Binding<String>,
        mentions: Binding<[AgentMention]>,
        isSending: Bool,
        canSend: Bool,
        onSend: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        @ViewBuilder leadingTools: () -> LeadingTools
    ) {
        self._draft = draft
        self._mentions = mentions
        self.isSending = isSending
        self.canSend = canSend
        self.onSend = onSend
        self.onCancel = onCancel
        self.leadingTools = leadingTools()
    }

    @State private var focused = false
    @State private var mentionQuery: String? = nil
    @State private var highlightedMentionIndex: Int = 0
    @State private var mentionTab: MentionTab = .all
    @State private var mentionScrollTick: Int = 0
    @State private var isDropTargeted = false

    private var showMentionPicker: Bool { mentionQuery != nil }

    private var mentionCandidates: [MentionCandidate] {
        MentionCandidate.candidates(query: mentionQuery ?? "", tab: mentionTab, editor: editor)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showMentionPicker {
                MentionPopover(
                    query: mentionQuery ?? "",
                    candidates: mentionCandidates,
                    highlightedIndex: $highlightedMentionIndex,
                    tab: $mentionTab,
                    scrollTick: mentionScrollTick,
                    onPick: { candidate in pickMention(candidate) }
                )
                Rectangle()
                    .fill(AppTheme.Border.subtleColor)
                    .frame(height: AppTheme.BorderWidth.hairline)
                    .transition(.opacity)
            }
            textField
                .onChange(of: mentionTab) { _, _ in highlightedMentionIndex = 0 }
                .onChange(of: editor.agentService.inputFocusRequested, initial: true) { _, requested in
                    guard requested else { return }
                    focused = true
                    editor.agentService.inputFocusRequested = false
                }
            bottomBar
        }
        .veeField(focused: focused || isDropTargeted)
        .animation(.easeOut(duration: AppTheme.Anim.hover), value: showMentionPicker)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    private var textField: some View {
        ZStack(alignment: .topLeading) {
            MentionTextView(
                text: $draft,
                mentions: mentions,
                isFocused: $focused,
                onCommand: handleCommand,
                onPaste: handlePaste
            )
            .padding(.horizontal, AppTheme.Spacing.mdLg)
            .padding(.top, AppTheme.Spacing.smMd)
            .padding(.bottom, AppTheme.Spacing.xs)
            .clipped()
            .onChange(of: draft) { _, new in updateMentionQuery(from: new) }

            if draft.isEmpty {
                Text(L10n.string("Ask Vee, or type @ to reference media"))
                    .font(.body)
                    .foregroundStyle(AppTheme.Text.mutedColor)
                    .padding(.horizontal, AppTheme.Spacing.mdLg)
                    .padding(.top, AppTheme.Spacing.smMd)
                    .allowsHitTesting(false)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            leadingTools
            Spacer(minLength: 0)
            sendStopButton
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    private var sendStopButton: some View {
        Button(action: isSending ? onCancel : onSend) {
            Image(systemName: isSending ? "stop.fill" : "arrow.up")
                .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.bold))
                .frame(width: AppTheme.IconSize.sm, height: AppTheme.IconSize.sm)
        }
        .buttonStyle(.capsule(.prominent, size: .small))
        .disabled(!isSending && !canSend)
        .help(isSending ? L10n.string("Stop") : L10n.string("Send"))
        .contentTransition(.symbolEffect(.replace))
    }

    private func cycleMentionTab(reverse: Bool) {
        let tabs = MentionTab.allCases
        let step = reverse ? -1 : 1
        let current = tabs.firstIndex(of: mentionTab) ?? 0
        mentionTab = tabs[(current + step + tabs.count) % tabs.count]
        mentionScrollTick &+= 1
    }

    private func handleCommand(_ command: MentionTextView.Command) -> Bool {
        if showMentionPicker {
            let candidates = mentionCandidates
            switch command {
            case .moveUp:
                moveMentionHighlight(by: -1, within: candidates)
            case .moveDown:
                moveMentionHighlight(by: 1, within: candidates)
            case .submit, .newline:
                if candidates.indices.contains(highlightedMentionIndex) {
                    pickMention(candidates[highlightedMentionIndex])
                }
            case .tab:
                cycleMentionTab(reverse: false)
            case .backtab:
                cycleMentionTab(reverse: true)
            case .cancel:
                mentionQuery = nil
            }
            return true
        }
        guard command == .submit, canSend else { return false }
        onSend()
        return true
    }

    private func moveMentionHighlight(by delta: Int, within candidates: [MentionCandidate]) {
        guard !candidates.isEmpty else { return }
        let next = min(candidates.count - 1, max(0, highlightedMentionIndex + delta))
        guard next != highlightedMentionIndex else { return }
        highlightedMentionIndex = next
        mentionScrollTick &+= 1
    }

    private func updateMentionQuery(from text: String) {
        let newQuery: String? = {
            guard let lastAt = text.lastIndex(of: "@") else { return nil }
            let after = text[text.index(after: lastAt)...]
            if after.contains(where: { $0.isWhitespace || $0.isNewline }) { return nil }
            if lastAt > text.startIndex {
                let prev = text[text.index(before: lastAt)]
                if !prev.isWhitespace && !prev.isNewline { return nil }
            }
            return String(after)
        }()

        guard newQuery != mentionQuery else { return }
        mentionQuery = newQuery
        highlightedMentionIndex = 0
    }

    private func pickMention(_ candidate: MentionCandidate) {
        switch candidate {
        case .media(let asset):
            pickMention(asset)
        case .object(let mask, let clipId):
            if let lastAt = draft.lastIndex(of: "@") { draft = String(draft[..<lastAt]) }
            editor.agentService.attachMention(forObject: mask.id, clipId: clipId)
            mentionQuery = nil
            highlightedMentionIndex = 0
        }
    }

    private func pickMention(_ asset: MediaAsset) {
        let displayName = AgentService.disambiguatedMentionName(for: asset, existing: mentions)
        if let lastAt = draft.lastIndex(of: "@") {
            let prefix = draft[..<lastAt]
            draft = String(prefix) + "@\(displayName) "
        } else {
            draft += "@\(displayName) "
        }
        mentions.append(AgentMention(
            displayName: displayName,
            mediaRef: asset.id,
            type: asset.type
        ))
        mentionQuery = nil
        highlightedMentionIndex = 0
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            handled = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    if let asset = editor.addMediaAsset(from: url) {
                        editor.agentService.attachMention(for: asset)
                    }
                }
            }
        }
        return handled
    }

    /// Imports pasted files and images as mentions; returns false for plain text.
    private func handlePaste() -> Bool {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            urls.compactMap { editor.addMediaAsset(from: $0) }
                .forEach { editor.agentService.attachMention(for: $0) }
            return true
        }
        for (type, ext) in [(NSPasteboard.PasteboardType.png, "png"), (.tiff, "tiff")] {
            if let data = pb.data(forType: type) {
                Task { @MainActor in
                    guard let asset = await editor.importPastedImageData(data, fileExtension: ext) else { return }
                    editor.agentService.attachMention(for: asset)
                }
                return true
            }
        }
        return false
    }
}
