import AppKit
import SwiftUI

/// Vee joined to the model providers it can run on, and the one place to manage their keys:
/// click a provider to paste its key (its link draws in), or click a connected one to remove it.
struct VeePoweredBy: View {
    @State private var credentials = AgentCredentialSnapshot()
    @State private var entering: AgentProvider?
    @State private var managing: AgentProvider?
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private static let providers: [AgentProvider] = [.meta, .anthropic, .openAI]

    /// The key to store from what was pasted; nil when it's blank.
    nonisolated static func keyToSave(_ draft: String) -> String? {
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    /// A saved key as its last four characters, so the full key is never on screen.
    nonisolated static func masked(_ key: String) -> String {
        String(repeating: "\u{2022}", count: 4) + (key.count > 4 ? String(key.suffix(4)) : "")
    }

    var body: some View {
        let connected = Self.providers.map { !credentials[$0].isEmpty }
        VStack(spacing: AppTheme.Spacing.md) {
            HStack(spacing: 0) {
                VStack(spacing: AppTheme.Spacing.xs) {
                    VeeIllustration(name: .poweredBy, height: AppTheme.Settings.poweredByVeeHeight)
                        .frame(width: AppTheme.Settings.poweredByVeeHeight)
                    Text(L10n.string("Vee is powered by"))
                        .font(.custom(AppTheme.Brand.wordmarkFontName, size: AppTheme.FontSize.mdLg).weight(AppTheme.FontWeight.semibold))
                        .foregroundStyle(AppTheme.Text.primaryColor)
                        .fixedSize()
                }
                links(connected)
                VStack(spacing: AppTheme.Spacing.smMd) {
                    ForEach(Array(Self.providers.enumerated()), id: \.element) { index, provider in
                        if entering == provider {
                            keyEntry(provider)
                        } else if managing == provider, connected[index] {
                            savedKey(provider)
                        } else {
                            badge(provider, connected: connected[index])
                        }
                    }
                }
            }
            Text(L10n.string("Keys stay in your Mac’s Keychain. The Meta key also runs SAM 3.1 tracking, Muse Image stickers and Muse Voice captions."))
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.lg)
        .task { credentials = await AgentCredentialSnapshot.loadFromKeychain() }
        .onReceive(NotificationCenter.default.publisher(for: .agentAPIKeyChanged)) { _ in
            Task { credentials = await AgentCredentialSnapshot.loadFromKeychain() }
        }
    }

    /// Lines from Vee to each badge: dashed while the key is missing, then a solid accent line draws in over it.
    private func links(_ connected: [Bool]) -> some View {
        let rows = CGFloat(Self.providers.count)
        let height = rows * AppTheme.Settings.poweredByBadgeHeight + (rows - 1) * AppTheme.Spacing.smMd
        return ZStack {
            ForEach(Array(Self.providers.indices), id: \.self) { index in
                let link = ProviderLink(row: index)
                link.stroke(AppTheme.Text.mutedColor, style: StrokeStyle(lineWidth: AppTheme.BorderWidth.thin, lineCap: .round, dash: AppTheme.Settings.poweredByDash))
                    .opacity(connected[index] ? 0 : 1)
                link.trim(from: 0, to: connected[index] ? 1 : 0)
                    .stroke(Self.brand(Self.providers[index]), style: StrokeStyle(lineWidth: AppTheme.BorderWidth.medium, lineCap: .round))
            }
        }
        .animation(.easeOut(duration: AppTheme.Anim.linkDraw), value: connected)
        .frame(width: AppTheme.Settings.poweredByLinkWidth, height: height)
        .accessibilityHidden(true)
    }

    private func badge(_ provider: AgentProvider, connected: Bool) -> some View {
        Button {
            if connected {
                managing = managing == provider ? nil : provider
            } else {
                draft = ""
                managing = nil
                entering = provider
                fieldFocused = true
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.smMd) {
                ProviderLogo(iconKey: Self.logoKey(provider), size: AppTheme.Settings.poweredByLogoSize)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: provider.displayName)
                        .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.semibold))
                        .foregroundStyle(AppTheme.Text.primaryColor)
                    Text(verbatim: Self.family(provider))
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                }
                Spacer(minLength: AppTheme.Spacing.sm)
                Text(connected ? L10n.string("Connected") : L10n.string("Connect"))
                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(connected ? Self.brand(provider) : AppTheme.Text.secondaryColor)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(width: AppTheme.Settings.poweredByBadgeWidth, height: AppTheme.Settings.poweredByBadgeHeight)
            .veeField(focused: connected, tint: Self.brand(provider))
            .opacity(connected ? AppTheme.Opacity.opaque : AppTheme.Opacity.high)
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        }
        .buttonStyle(.plain)
        .help(connected ? L10n.string("Show or remove the \(provider.displayName) key") : L10n.string("Paste a \(provider.displayName) API key to use \(Self.family(provider))"))
        .accessibilityElement(children: .combine)
    }

    private func keyEntry(_ provider: AgentProvider) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            ProviderLogo(iconKey: Self.logoKey(provider), size: AppTheme.Settings.poweredByLogoSize)
            SecureField(L10n.string("Paste API key"), text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: AppTheme.FontSize.sm))
                .focused($fieldFocused)
                .onSubmit { connect(provider) }
                .onExitCommand { entering = nil }
            if Self.keyToSave(draft) == nil {
                Button { NSWorkspace.shared.open(Self.consoleURL(provider), configuration: .init(), completionHandler: nil) } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.semibold))
                }
                .buttonStyle(.capsule(.secondary, size: .small))
                .help(L10n.string("Get a \(provider.displayName) API key"))
            }
            Button(L10n.string("Connect")) { connect(provider) }
                .buttonStyle(.capsule(.prominent, size: .small))
                .disabled(Self.keyToSave(draft) == nil)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .frame(width: AppTheme.Settings.poweredByBadgeWidth, height: AppTheme.Settings.poweredByBadgeHeight)
        .veeField(focused: true, tint: Self.brand(provider))
        .onChange(of: fieldFocused) { _, focused in
            if !focused, Self.keyToSave(draft) == nil { entering = nil }
        }
    }

    private func savedKey(_ provider: AgentProvider) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            ProviderLogo(iconKey: Self.logoKey(provider), size: AppTheme.Settings.poweredByLogoSize)
            Text(verbatim: Self.masked(credentials[provider]))
                .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                .foregroundStyle(AppTheme.Text.secondaryColor)
            Spacer(minLength: AppTheme.Spacing.sm)
            Button(L10n.string("Remove")) {
                managing = nil
                Task { await provider.setAPIKey(nil) }
            }
            .buttonStyle(.capsule(.secondary, size: .small))
            Button(L10n.string("Done")) { managing = nil }
                .buttonStyle(.capsule(.tinted, size: .small))
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .frame(width: AppTheme.Settings.poweredByBadgeWidth, height: AppTheme.Settings.poweredByBadgeHeight)
        .veeField(focused: true, tint: Self.brand(provider))
    }

    private func connect(_ provider: AgentProvider) {
        guard let key = Self.keyToSave(draft) else { return }
        draft = ""
        entering = nil
        Task { await provider.setAPIKey(key) }
    }

    private static func logoKey(_ provider: AgentProvider) -> String {
        switch provider {
        case .meta: "meta"
        case .anthropic: "anthropic"
        case .openAI: "openai"
        }
    }

    private static func brand(_ provider: AgentProvider) -> Color {
        switch provider {
        case .meta: AppTheme.Settings.metaBrand
        case .anthropic: AppTheme.Settings.anthropicBrand
        case .openAI: AppTheme.Settings.openAIBrand
        }
    }

    private static func consoleURL(_ provider: AgentProvider) -> URL {
        switch provider {
        case .meta: URL(string: "https://dev.meta.ai/platform")!
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")!
        case .openAI: URL(string: "https://platform.openai.com/api-keys")!
        }
    }

    /// The model family each provider runs in VeeCut.
    private static func family(_ provider: AgentProvider) -> String {
        switch provider {
        case .meta: "Muse Spark"
        case .anthropic: "Claude"
        case .openAI: "GPT"
        }
    }
}

/// The curve from Vee to one badge row; trimming it draws the link in.
private struct ProviderLink: Shape {
    let row: Int

    func path(in rect: CGRect) -> Path {
        let rowHeight = AppTheme.Settings.poweredByBadgeHeight
        let y = rowHeight / 2 + CGFloat(row) * (rowHeight + AppTheme.Spacing.smMd)
        let origin = CGPoint(x: rect.minX, y: rect.midY)
        var path = Path()
        path.move(to: origin)
        path.addCurve(to: CGPoint(x: rect.maxX, y: y),
                      control1: CGPoint(x: rect.midX, y: origin.y),
                      control2: CGPoint(x: rect.midX, y: y))
        return path
    }
}
