import AppKit
import SwiftUI
import Testing
@testable import PalmierPro

@MainActor
@Test(arguments: [#selector(NSTextView.complete(_:)), #selector(NSResponder.cancelOperation(_:))])
func escapeCancelsTheMentionList(selector: Selector) {
    var received: [MentionTextView.Command] = []
    let view = MentionTextView(text: .constant("@ca"), mentions: [], isFocused: .constant(true),
                               onCommand: { received.append($0); return true }, onPaste: { false })

    _ = view.makeCoordinator().textView(NSTextView(), doCommandBy: selector)

    #expect(received == [.cancel])
}

@MainActor
private func composerTextHeight(_ text: String) -> CGFloat {
    let view = MentionTextView(text: .constant(text), mentions: [], isFocused: .constant(false),
                               onCommand: { _ in false }, onPaste: { false })
        .frame(width: 280)
    return NSHostingView(rootView: view).fittingSize.height
}

@MainActor
@Test func theComposerGrowsWithItsTextUpToItsLimit() {
    let short = composerTextHeight("hi")
    let fourLines = composerTextHeight("one\ntwo\nthree\nfour")
    let long = composerTextHeight(String(repeating: "a long line of words ", count: 80))

    #expect(fourLines > short)
    #expect(long == AppTheme.Composer.maxTextHeight)
}
