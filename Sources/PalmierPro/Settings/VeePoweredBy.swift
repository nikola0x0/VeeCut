import SwiftUI

/// Vee joined to the model providers it can run on; a provider lights up once its key is saved.
struct VeePoweredBy: View {
    @State private var credentials = AgentCredentialSnapshot()

    private static let providers: [AgentProvider] = [.meta, .anthropic, .openAI]

    var body: some View {
        let connected = Self.providers.map { !credentials[$0].isEmpty }
        HStack(spacing: 0) {
            VStack(spacing: AppTheme.Spacing.xs) {
                VeeIllustration(name: .hello, height: AppTheme.Settings.poweredByVeeHeight)
                    .frame(width: AppTheme.Settings.poweredByVeeHeight)
                Text(L10n.string("Vee is powered by"))
                    .font(.custom(AppTheme.Brand.wordmarkFontName, size: AppTheme.FontSize.mdLg).weight(AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                    .fixedSize()
            }
            links(connected)
            VStack(spacing: AppTheme.Spacing.smMd) {
                ForEach(Array(Self.providers.enumerated()), id: \.element) { index, provider in
                    badge(provider, connected: connected[index])
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.lg)
        .task { credentials = await AgentCredentialSnapshot.loadFromKeychain() }
        .onReceive(NotificationCenter.default.publisher(for: .agentAPIKeyChanged)) { _ in
            Task { credentials = await AgentCredentialSnapshot.loadFromKeychain() }
        }
    }

    /// Lines from Vee to each badge: solid accent when connected, dashed when the key is missing.
    private func links(_ connected: [Bool]) -> some View {
        let rows = CGFloat(Self.providers.count)
        let height = rows * AppTheme.Settings.poweredByBadgeHeight + (rows - 1) * AppTheme.Spacing.smMd
        return Canvas { context, size in
            let origin = CGPoint(x: 0, y: size.height / 2)
            for index in Self.providers.indices {
                let y = AppTheme.Settings.poweredByBadgeHeight / 2 + CGFloat(index) * (AppTheme.Settings.poweredByBadgeHeight + AppTheme.Spacing.smMd)
                var path = Path()
                path.move(to: origin)
                path.addCurve(to: CGPoint(x: size.width, y: y),
                              control1: CGPoint(x: size.width / 2, y: origin.y),
                              control2: CGPoint(x: size.width / 2, y: y))
                let style = connected[index]
                    ? StrokeStyle(lineWidth: AppTheme.BorderWidth.medium, lineCap: .round)
                    : StrokeStyle(lineWidth: AppTheme.BorderWidth.thin, lineCap: .round, dash: AppTheme.Settings.poweredByDash)
                context.stroke(path, with: .color(connected[index] ? AppTheme.Accent.primary : AppTheme.Text.mutedColor), style: style)
            }
        }
        .frame(width: AppTheme.Settings.poweredByLinkWidth, height: height)
        .accessibilityHidden(true)
    }

    private func badge(_ provider: AgentProvider, connected: Bool) -> some View {
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
            Text(connected ? L10n.string("Connected") : L10n.string("Add key below"))
                .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(connected ? AppTheme.Accent.primary : AppTheme.Text.tertiaryColor)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .frame(width: AppTheme.Settings.poweredByBadgeWidth, height: AppTheme.Settings.poweredByBadgeHeight)
        .veeField(focused: connected)
        .opacity(connected ? AppTheme.Opacity.opaque : AppTheme.Opacity.high)
        .accessibilityElement(children: .combine)
    }

    private static func logoKey(_ provider: AgentProvider) -> String {
        switch provider {
        case .meta: "meta"
        case .anthropic: "anthropic"
        case .openAI: "openai"
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
