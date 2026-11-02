import CoreGraphics
import Testing
@testable import PalmierPro

struct VeeLinePlacementTests {
    private let container = CGSize(width: 1000, height: 600)
    private let bubble = CGSize(width: 400, height: 80)

    @Test func theDefaultSitsAtTheBottomCenter() {
        let center = VeeLinePlacement.center(for: VeeLinePlacement.defaultPosition, bubble: bubble, in: container)
        #expect(center == CGPoint(x: 500, y: 600 - 40 - VeeLinePlacement.margin))
    }

    @Test(arguments: [CGPoint(x: -1, y: -1), CGPoint(x: 2, y: 2), CGPoint(x: 0, y: 0.5)])
    func theBubbleNeverLeavesThePreview(position: CGPoint) {
        let center = VeeLinePlacement.center(for: position, bubble: bubble, in: container)
        #expect(center.x - bubble.width / 2 >= VeeLinePlacement.margin)
        #expect(center.x + bubble.width / 2 <= container.width - VeeLinePlacement.margin)
        #expect(center.y - bubble.height / 2 >= VeeLinePlacement.margin)
        #expect(center.y + bubble.height / 2 <= container.height - VeeLinePlacement.margin)
    }

    @Test func aDroppedBubbleStaysWhereItWasDropped() {
        let dropped = CGPoint(x: 300, y: 120)
        let position = VeeLinePlacement.position(for: dropped, bubble: bubble, in: container)
        #expect(VeeLinePlacement.center(for: position, bubble: bubble, in: container) == dropped)
    }

    @Test func aBubbleWiderThanThePreviewStaysCentered() {
        let center = VeeLinePlacement.center(for: CGPoint(x: 0, y: 0.5), bubble: CGSize(width: 1200, height: 80), in: container)
        #expect(center.x == 500)
    }

    @Test(arguments: [
        (CGPoint(x: 0.1, y: 0.45), CGPoint(x: 0, y: 0.5)),
        (CGPoint(x: 0.6, y: 0.9), CGPoint(x: 0.5, y: 1)),
        (CGPoint(x: 0.95, y: 0.05), CGPoint(x: 1, y: 0)),
        (CGPoint(x: 0.3, y: 0.2), CGPoint(x: 0.5, y: 0)),
        (CGPoint(x: 0.5, y: 0.5), VeeLinePlacement.defaultPosition),
    ])
    func aDroppedBubbleSnapsToTheNearestBorderSpot(dropped: CGPoint, snapped: CGPoint) {
        #expect(VeeLinePlacement.snapped(dropped) == snapped)
    }
}
