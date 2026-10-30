import CoreGraphics
import Testing
@testable import PalmierPro

@Test func theBrushCoversTheStrokeGrownByItsRadius() {
    let stroke = [CGPoint(x: 10, y: 20), CGPoint(x: 60, y: 40), CGPoint(x: 110, y: 30)]
    #expect(BrushMark.covered(stroke, radius: 8) == CGRect(x: 2, y: 12, width: 116, height: 36))
}

@Test func aDabCoversTheBrushTip() {
    #expect(BrushMark.covered([CGPoint(x: 50, y: 50)], radius: 10) == CGRect(x: 40, y: 40, width: 20, height: 20))
    #expect(BrushMark.hintPoints([CGPoint(x: 50, y: 50)]) == [CGPoint(x: 50, y: 50)])
}

@Test func aLongStrokeGivesAtMostTenHintsFromEndToEnd() {
    let stroke = (0...200).map { CGPoint(x: CGFloat($0), y: 0) }
    let hints = BrushMark.hintPoints(stroke)
    #expect(hints.count == BrushMark.maxHintPoints)
    #expect(hints.first == CGPoint(x: 0, y: 0) && hints.last == CGPoint(x: 200, y: 0))
}

@Test func anEmptyStrokeCoversNothing() {
    #expect(BrushMark.covered([], radius: 10) == nil)
    #expect(BrushMark.covered([CGPoint(x: 1, y: 1)], radius: .nan) == nil)
}
