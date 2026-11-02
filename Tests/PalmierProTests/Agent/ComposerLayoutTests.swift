import AppKit
import SwiftUI
import Testing
@testable import PalmierPro

@MainActor
@Test func theComposerFitsTheNarrowestChatPanel() throws {
    let longestModel = try #require(AgentModel.allCases.max { $0.displayName.count < $1.displayName.count })
    let efforts = longestModel.supportedReasoningEfforts.map { L10n.string(key: $0.labelKey) }
    let composer = AgentInputBox(draft: .constant(""), mentions: .constant([]), isSending: false, canSend: true, onSend: {}, onCancel: {}) {
        Menu {} label: { ChipLabel(title: longestModel.displayName) { ProviderLogo(iconKey: "openai", size: AppTheme.IconSize.xs) } }.chipMenu()
        Menu {} label: { ChipLabel(title: efforts[0], sizedFor: efforts) { EffortMeter(level: 0, of: efforts.count) } }.chipMenu()
    }
    .environment(EditorViewModel())
    .fixedSize(horizontal: true, vertical: false)

    let needed = NSHostingView(rootView: composer).fittingSize.width + 2 * AppTheme.Spacing.mdLg

    #expect(needed <= Layout.agentPanelMin)
}
