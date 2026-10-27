import CoreGraphics
import Testing
@testable import PalmierPro

@Test func aShortStrokeIsATapAtItsStart() {
    #expect(SubjectMark.classify([CGPoint(x: 10, y: 10), CGPoint(x: 12, y: 13)]) == .point(CGPoint(x: 10, y: 10)))
}

@Test func aStrokeWhoseEndsMeetIsALoop() {
    let circle = (0...24).map { i -> CGPoint in
        let angle = CGFloat(i) / 24 * 2 * .pi
        return CGPoint(x: 100 + 50 * cos(angle), y: 100 + 50 * sin(angle))
    }
    guard case .loop(let points) = SubjectMark.classify(circle) else { Issue.record("expected a loop"); return }
    #expect(points == circle)
}

@Test func anOpenStrokeIsAScribbleResampledToEvenlySpacedPoints() {
    let line = (0...100).map { CGPoint(x: CGFloat($0), y: 50) }
    guard case .scribble(let points) = SubjectMark.classify(line) else { Issue.record("expected a scribble"); return }
    #expect(points.count == SubjectMark.maxScribblePoints)
    #expect(points.first == CGPoint(x: 0, y: 50))
    #expect(points.last == CGPoint(x: 100, y: 50))
    let gaps = zip(points, points.dropFirst()).map { $1.x - $0.x }
    #expect(gaps.allSatisfy { abs($0 - 100.0 / 7) < 1e-9 })
}

@Test func aFlatLoopIsTreatedAsAScribble() {
    let flat = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 2), CGPoint(x: 5, y: 1)]
    guard case .scribble = SubjectMark.classify(flat) else { Issue.record("expected a scribble"); return }
}

@Test func anEmptyStrokeMeansNothing() {
    #expect(SubjectMark.classify([]) == nil)
}
