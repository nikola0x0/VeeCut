import AppKit
import SwiftUI

struct AgentPanelView: View {
    @Environment(EditorViewModel.self) var editor

    private static let starterPrompts: [AgentStarterPrompt] = [
        AgentStarterPrompt(
            id: "keep_best_takes",
            title: L10n.string("Keep the best takes"),
            systemImage: "scissors",
            prompt: "Tighten this edit. Keep the strongest takes, cut filler words and long silences, and leave a clean continuous cut."
        ),
        AgentStarterPrompt(
            id: "sync_multicam",
            title: L10n.string("Sync my multicam"),
            systemImage: "rectangle.on.rectangle.angled",
            prompt: "Set up my multicam. Group the matching camera angles with their audio, verify sync, and leave it ready to switch."
        ),
        AgentStarterPrompt(
            id: "cut_to_beat",
            title: L10n.string("Cut to the beat"),
            systemImage: "metronome",
            prompt: "Assemble my clips to the beat of a song. Detect the beats and cut or place clips so the edit hits the rhythm."
        ),
        AgentStarterPrompt(
            id: "add_captions",
            title: L10n.string("Add captions"),
            systemImage: "captions.bubble",
            prompt: "Add captions to this timeline. Transcribe the dialogue, phrase it for readability, and place text clips locked to the speech."
        ),
        AgentStarterPrompt(
            id: "make_vertical_shorts",
            title: L10n.string("Make vertical shorts"),
            systemImage: "rectangle.portrait",
            prompt: "Find the strongest moments in this video and turn each into a short-form vertical clip. Create multiple 9:16 timelines, reframe for vertical, and keep every clip tight and self-contained."
        ),
    ]

    private var service: AgentService { editor.agentService }

    private var canSend: Bool {
        !service.isStreaming &&
        service.canStream &&
        !service.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            floatingTabBar
            messageList
            footer
        }
    }

    private var floatingTabBar: some View {
        GlassEffectContainer {
            HStack(spacing: AppTheme.Spacing.xs) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            ForEach(service.openSessions) { session in
                                ChatTabView(
                                    session: session,
                                    isActive: session.id == service.currentSessionId,
                                    onSelect: { service.selectSession(session.id) },
                                    onClose: { service.closeTab(session.id) }
                                )
                                .id(session.id)
                            }
                        }
                    }
                    .onChange(of: service.currentSessionId) { _, new in
                        guard let new else { return }
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(new, anchor: .center) }
                    }
                }
                planButton
                newTabButton
                historyButton
                ViewSkillsButton()
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            .frame(maxWidth: .infinity)
            .frame(height: Layout.panelHeaderHeight)
            .glassEffect(.regular, in: .rect(cornerRadius: AppTheme.Radius.lg))
        }
        .padding(.horizontal, AppTheme.Spacing.mdLg)
    }

    private var planButton: some View {
        Button { editor.askForPlan() } label: {
            Image(systemName: "sparkles")
                .font(.system(size: AppTheme.FontSize.sm, weight: .medium))
                .foregroundStyle(AppTheme.Accent.primary)
                .frame(width: AppTheme.IconSize.smMd, height: AppTheme.IconSize.smMd)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!editor.hasCoachFootage)
        .help(editor.planTheEditHelp)
    }

    private var newTabButton: some View {
        Button { service.newChat() } label: {
            Image(systemName: "plus")
                .font(.system(size: AppTheme.FontSize.sm, weight: .medium))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
                .frame(width: AppTheme.IconSize.smMd, height: AppTheme.IconSize.smMd)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(L10n.string("New chat"))
    }

    @State private var showHistory = false
    @State private var isScrolledFromBottom = false

    private var historyButton: some View {
        Button { showHistory.toggle() } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: AppTheme.FontSize.sm, weight: .medium))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
                .frame(width: AppTheme.IconSize.smMd, height: AppTheme.IconSize.smMd)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(L10n.string("Chat history"))
        .popover(isPresented: $showHistory, arrowEdge: .top) {
            ChatHistoryList(
                sessions: service.sessions.sorted { $0.updatedAt > $1.updatedAt },
                currentId: service.currentSessionId,
                onSelect: { id in
                    service.selectSession(id)
                    showHistory = false
                },
                onDelete: { service.deleteSession($0) }
            )
        }
    }

    private var modelPicker: some View {
        let ready = service.availableModels.filter { service.hasKey(for: $0.provider) }
        let locked = service.availableModels.filter { !service.hasKey(for: $0.provider) }
        return Menu {
            ForEach(ready, id: \.self) { model in
                Button { service.model = model } label: {
                    menuOptionLabel(model.displayName, selected: model == service.model)
                }
            }
            if !locked.isEmpty {
                Section(L10n.string("Add a key in Settings to use")) {
                    ForEach(locked, id: \.self) { model in
                        Button {} label: { Text(verbatim: model.displayName) }
                            .disabled(true)
                    }
                }
            }
            Divider()
            Button(L10n.string("Manage Keys\u{2026}")) { SettingsWindowController.shared.show(tab: .agent) }
        } label: {
            ChipLabel(title: service.model.displayName) {
                switch service.model.provider {
                case .anthropic:
                    ExternalAgentLogo(agent: .claude, size: AppTheme.IconSize.xs)
                case .openAI:
                    ProviderLogo(iconKey: "openai", size: AppTheme.IconSize.xs)
                case .meta:
                    ProviderLogo(iconKey: "meta", size: AppTheme.IconSize.xs)
                }
            }
        }
        .chipMenu()
        .layoutPriority(1)
        .accessibilityLabel(L10n.string("Model"))
        .accessibilityValue(Text(verbatim: service.model.displayName))
        .help(L10n.string("Model"))
    }

    private var reasoningEffortPicker: some View {
        let efforts = service.model.supportedReasoningEfforts
        return Menu {
            ForEach(efforts, id: \.self) { effort in
                Button {
                    service.reasoningEffort = effort
                } label: {
                    menuOptionLabel(L10n.string(key: effort.labelKey), selected: effort == service.reasoningEffort)
                    if let note = Self.effortNote(effort) { Text(note) }
                }
            }
        } label: {
            ChipLabel(title: L10n.string(key: service.reasoningEffort.labelKey), sizedFor: efforts.map { L10n.string(key: $0.labelKey) }) {
                EffortMeter(level: efforts.firstIndex(of: service.reasoningEffort) ?? 0, of: efforts.count)
            }
        }
        .chipMenu()
        .accessibilityLabel(L10n.string("Thinking"))
        .accessibilityValue(L10n.string(key: service.reasoningEffort.labelKey))
        .help(L10n.string("How long Vee thinks before answering"))
    }

    private static func effortNote(_ effort: AgentReasoningEffort) -> String? {
        switch effort {
        case .none, .minimal, .low: L10n.string("Fastest replies")
        case .medium: L10n.string("Balanced")
        case .high, .xHigh, .max: L10n.string("Most careful, slower")
        }
    }

    @ViewBuilder
    private func menuOptionLabel(_ title: String, selected: Bool) -> some View {
        if selected {
            Label {
                Text(verbatim: title)
            } icon: {
                Image(systemName: "checkmark")
            }
        } else {
            Text(verbatim: title)
        }
    }

    private var toolResults: [String: ToolRunResult] {
        var out: [String: ToolRunResult] = [:]
        for msg in service.messages where msg.role == .user {
            for block in msg.blocks {
                if case let .toolResult(id, content, isError) = block {
                    out[id] = ToolRunResult(content: content, isError: isError)
                }
            }
        }
        return out
    }

    private var messageList: some View {
        Group {
            if !service.messages.contains(where: { $0.role != .system }) && !service.isStreaming {
                VStack(spacing: AppTheme.Spacing.smMd) {
                    emptyState
                    errorBanner
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, AppTheme.Spacing.lgXl)
            } else {
                scrollingMessages
            }
        }
    }

    private var scrollingMessages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    let results = toolResults
                    let messages = service.messages
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                        AgentMessageView(message: msg, toolResults: results, startsVeeRun: AgentMessage.startsVeeRun(messages, at: index))
                            .id(msg.id)
                    }
                    if service.isStreaming {
                        HStack(alignment: .center, spacing: AppTheme.ChatThread.avatarGap) {
                            if AgentMessage.veeIsTypingNewRun(messages) {
                                VeeChatAvatar()
                            } else {
                                Color.clear.frame(width: AppTheme.ChatThread.avatarSize, height: 1)
                            }
                            ThinkingDots()
                        }
                        .id("streaming-indicator")
                    }
                    errorBanner
                        .padding(.top, AppTheme.Spacing.sm)
                }
                .padding(.horizontal, AppTheme.Spacing.lgXl)
                .padding(.top, AppTheme.Spacing.mdLg)
                .padding(.bottom, AppTheme.Spacing.smMd)
                .frame(maxWidth: Layout.chatColumnMax)
                .frame(maxWidth: .infinity)
                .background(AgentOverlayScrollerStyle())
            }
            .scrollIndicators(.automatic)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .onScrollGeometryChange(for: Bool.self) { geo in
                let distance = geo.contentSize.height - geo.contentOffset.y - geo.containerSize.height
                return distance > 80
            } action: { _, newValue in
                withAnimation(.easeOut(duration: 0.15)) { isScrolledFromBottom = newValue }
            }
            .onChange(of: service.messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: service.isStreaming) { _, _ in scrollToBottom(proxy) }
            .overlay(alignment: .bottomTrailing) {
                if isScrolledFromBottom {
                    scrollToBottomButton(proxy: proxy)
                        .padding(.trailing, AppTheme.Spacing.mdLg)
                        .padding(.bottom, AppTheme.Spacing.mdLg)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
        }
    }

    private func scrollToBottomButton(proxy: ScrollViewProxy) -> some View {
        Button {
            scrollToBottom(proxy)
        } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: AppTheme.FontSize.smMd, weight: .semibold))
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .frame(width: AppTheme.IconSize.lgXl, height: AppTheme.IconSize.lgXl)
                .glassEffect(.regular, in: .circle)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(L10n.string("Scroll to latest"))
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let err = service.streamError {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                Text(verbatim: errorMessage(err))
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.leading)
                if let cta = errorCTA(for: err) {
                    Button(action: cta.action) {
                        Text(cta.title)
                            .font(.system(size: AppTheme.FontSize.xs, weight: .medium))
                    }
                    .buttonStyle(.capsule(.secondary))
                    .controlSize(.small)
                }
            }
        }
    }

    private struct ErrorCTA {
        let title: String
        let action: () -> Void
    }

    private func errorCTA(for error: AgentServiceError?) -> ErrorCTA? {
        guard let error else { return nil }
        switch error {
        case .unavailable:
            return ErrorCTA(title: L10n.string("Open Settings")) {
                SettingsWindowController.shared.show(tab: .agent)
            }
        case .refusal, .upstream:
            return nil
        }
    }

    private func errorMessage(_ error: AgentServiceError) -> String {
        switch error {
        case .upstream(let message):
            message
        case .unavailable(let model):
            model.provider.chatPresentation.unavailableMessage
        case .refusal:
            L10n.string("The selected model refused this request. Revise the prompt and try again.")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if service.canStream {
            VStack(spacing: AppTheme.Spacing.smMd) {
                VeeChatGreeting()
                VStack(spacing: AppTheme.Spacing.xs) {
                    ForEach(Self.starterPrompts) { starterPrompt in
                        AgentStarterPromptButton(starterPrompt: starterPrompt) {
                            Analytics.capture(.agentStarterPromptClicked, properties: [
                                "starter_prompt": starterPrompt.id,
                            ])
                            populatePrompt(starterPrompt.prompt)
                        }
                    }
                }
            }
        } else {
            missingKeyState
        }
    }

    private var missingKeyState: some View {
        Button(action: { SettingsWindowController.shared.show(tab: .agent) }) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "key")
                Text(service.model.provider.chatPresentation.addKeyTitle)
            }
            .font(.system(size: AppTheme.FontSize.mdLg, weight: .semibold))
        }
        .buttonStyle(.capsule(.prominent, size: .regular))
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if service.isStreaming {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("streaming-indicator", anchor: .bottom)
            }
        } else if let last = service.messages.last {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var footer: some View {
        @Bindable var service = editor.agentService
        return VStack(spacing: AppTheme.Spacing.sm) {
            if !service.canStream && !service.messages.isEmpty {
                missingKeyState
            }
            AgentInputBox(
                draft: $service.draft,
                mentions: $service.mentions,
                isSending: service.isStreaming,
                canSend: canSend,
                onSend: submit,
                onCancel: { service.cancel() }
            ) {
                modelPicker
                reasoningEffortPicker
            }
        }
        .padding(.horizontal, AppTheme.Spacing.mdLg)
        .padding(.bottom, AppTheme.Spacing.mdLg)
        .padding(.top, AppTheme.Spacing.xs)
        .frame(maxWidth: Layout.chatColumnMax)
        .frame(maxWidth: .infinity)
    }

    private func submit() {
        guard canSend else { return }
        service.send(text: service.draft, mentions: service.mentions)
        service.draft = ""
        service.mentions.removeAll()
    }

    private func populatePrompt(_ prompt: String) {
        service.draft = prompt
        service.mentions.removeAll()
    }
}

private struct AgentOverlayScrollerStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> AgentOverlayScrollerProbe {
        AgentOverlayScrollerProbe()
    }

    func updateNSView(_ nsView: AgentOverlayScrollerProbe, context: Context) {
        nsView.apply()
    }
}

private final class AgentOverlayScrollerProbe: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    func apply() {
        var ancestor = superview
        while let current = ancestor {
            if let scrollView = current as? NSScrollView {
                scrollView.scrollerStyle = .overlay
                scrollView.autohidesScrollers = true
                return
            }
            ancestor = current.superview
        }
    }
}

private struct AgentStarterPrompt: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let prompt: String
}

private struct AgentStarterPromptButton: View {
    let starterPrompt: AgentStarterPrompt
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: starterPrompt.systemImage)
                    .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .frame(width: AppTheme.IconSize.smMd, height: AppTheme.IconSize.smMd)
                Text(starterPrompt.title)
                    .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hoverHighlight(cornerRadius: AppTheme.Radius.lg)
            .glassEffect(.regular, in: .rect(cornerRadius: AppTheme.Radius.lg))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(L10n.string("Fill prompt"))
    }
}

private struct ChatTabView: View {
    let session: ChatSession
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Text(verbatim: displayTitle)
                .font(.system(
                    size: AppTheme.FontSize.xs,
                    weight: isActive ? AppTheme.FontWeight.semibold : AppTheme.FontWeight.medium
                ))
                .foregroundStyle(isActive ? AppTheme.Text.primaryColor : AppTheme.Text.secondaryColor)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .documentTabChrome(isActive: isActive, isCloseable: true, onClose: onClose)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var displayTitle: String {
        let t = session.title
        return t.count > 20 ? String(t.prefix(20)) + "…" : t
    }
}

@MainActor
private extension AgentProvider {
    var chatPresentation: (unavailableMessage: String, addKeyTitle: String) {
        switch self {
        case .anthropic:
            (
                L10n.string("Add an Anthropic API key in Settings to use this model."),
                L10n.string("Add Anthropic API Key")
            )
        case .openAI:
            (
                L10n.string("Add an OpenAI API key in Settings to use this model."),
                L10n.string("Add OpenAI API Key")
            )
        case .meta:
            (
                L10n.string("Add a Meta Model API key in Settings to use Muse Spark."),
                L10n.string("Add Meta Model API Key")
            )
        }
    }
}

/// Vee's hello in an empty chat; it hands planning to the card or the plan once either is on screen.
private struct VeeChatGreeting: View {
    @Environment(EditorViewModel.self) private var editor

    var body: some View {
        let hasPlan = editor.timeline.plan != nil
        let cardShown = editor.showsCoachCard
        VStack(spacing: AppTheme.Spacing.smMd) {
            VeeIllustration(name: .hello, height: AppTheme.Coach.statusPoseHeight)
            Text(hasPlan ? L10n.string("Your edit is on the timeline. Ask me for any change.")
                 : cardShown ? L10n.string("Hi, I\u{2019}m Vee. Pick an idea on my card, or ask me here.")
                 : L10n.string("Hi, I\u{2019}m Vee. What are we making today?"))
                .font(.custom(AppTheme.Brand.wordmarkFontName, size: AppTheme.FontSize.xl).weight(AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.Text.primaryColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !hasPlan && !cardShown {
                Button(L10n.string("Plan the Edit"), systemImage: "sparkles") { editor.askForPlan() }
                    .buttonStyle(.capsule(.prominent, size: .regular))
                    .disabled(!editor.hasCoachFootage)
                    .help(editor.planTheEditHelp)
                if !editor.hasCoachFootage {
                    Text(L10n.string("Import a video clip to plan your edit."))
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                        .multilineTextAlignment(.center)
                }
            }
            Text(hasPlan || cardShown ? L10n.string("Ask me to:") : L10n.string("Or ask me to:"))
                .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .multilineTextAlignment(.center)
                .padding(.top, AppTheme.Spacing.sm)
        }
    }
}

/// How hard the model thinks: signal bars filled up to the chosen level.
struct EffortMeter: View {
    let level: Int
    let of: Int

    var body: some View {
        Image(systemName: "cellularbars", variableValue: of <= 1 ? 1 : Double(level + 1) / Double(of))
            .accessibilityHidden(true)
    }
}
