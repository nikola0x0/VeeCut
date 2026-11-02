import AppKit
import SwiftUI
import Testing
@testable import PalmierPro

@MainActor
private final class HeaderPosition {
    var minX: CGFloat = .nan
}

@MainActor
@Test func contentWiderThanTheTimelineKeepsTheHeaderOnScreen() {
    let position = HeaderPosition()
    let row = HStack(spacing: 0) {
        Color.clear
            .frame(width: 100)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { position.minX = $0 }
        ScrolledWithTimeline(viewport: TimelineViewport()) {
            Color.red.frame(width: 5000)
        }
        .clipped()
    }
    let host = NSHostingView(rootView: row.frame(width: 800, height: 20))
    host.frame = CGRect(x: 0, y: 0, width: 800, height: 20)
    host.layoutSubtreeIfNeeded()

    #expect(position.minX == 0)
}
