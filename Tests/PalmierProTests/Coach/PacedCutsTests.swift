import Testing
@testable import PalmierPro

struct PacedCutsTests {
    private func moment(_ id: String, _ start: Double, _ end: Double) -> PlanMoment {
        PlanMoment(assetId: id, start: start, end: end, note: "")
    }

    @Test func peakCutsTakeTwoBeats() {
        #expect(PacedCuts.cutSeconds(for: .peak, beatSeconds: 0.5) == 1)
        #expect(PacedCuts.cutSeconds(for: .rising, beatSeconds: 0.5) == 2)
        #expect(PacedCuts.cutSeconds(for: .calm, beatSeconds: 0.5) == 4)
    }

    @Test func framedCutsEndOnTheFrameNearestTheirSongTime() {
        let cuts: [PlanMoment] = (0..<5).map { index in moment("a", Double(index) * 1.36, Double(index + 1) * 1.36) }
        func boundary(_ index: Int) -> Int { Int(((0.3 + Double(index) * 1.36) * 30).rounded()) }
        let expected: [Int] = (0..<5).map { index in boundary(index + 1) - boundary(index) }

        let framed = PacedCuts.framed(cuts, startSeconds: 0.3, fps: 30)

        #expect(framed.map { cut in Int((cut.end - cut.start) * 30) } == expected)
    }

    @Test func framedCutsSnapToTheSongsDetectedBeats() {
        let cuts: [PlanMoment] = (0..<4).map { index in moment("a", Double(index), Double(index + 1)) }

        let framed = PacedCuts.framed(cuts, startSeconds: 0, fps: 30, beatFrames: [0, 31, 59, 92, 120], snapWithin: 7)

        #expect(framed.map { cut in Int((cut.end - cut.start) * 30) } == [31, 28, 33, 28])
    }

    @Test func aBeatTooFarAwayLeavesTheCutOnTheGrid() {
        let cuts: [PlanMoment] = (0..<2).map { index in moment("a", Double(index), Double(index + 1)) }

        let framed = PacedCuts.framed(cuts, startSeconds: 0, fps: 30, beatFrames: [0, 45, 60], snapWithin: 7)

        #expect(framed.map { cut in Int((cut.end - cut.start) * 30) } == [30, 30])
    }

    @Test func cutsRoundRobinAcrossMoments() {
        let cuts = PacedCuts.moments(from: [moment("a", 0, 4), moment("b", 10, 14)], cutSeconds: 1, beatSeconds: 0.5, filling: 4)
        #expect(cuts == [moment("a", 0, 1), moment("b", 10, 11), moment("a", 1, 2), moment("b", 11, 12)])
    }

    @Test func momentsAreReusedUntilTheSectionIsFull() {
        let cuts = PacedCuts.moments(from: [moment("a", 0, 2)], cutSeconds: 1, beatSeconds: 0.5, filling: 4)
        #expect(cuts == [moment("a", 0, 1), moment("a", 1, 2), moment("a", 0, 1), moment("a", 1, 2)])
    }

    @Test func theLeftoverPartOfABeatGoesOnTheLastCut() {
        let cuts = PacedCuts.moments(from: [moment("a", 0, 10)], cutSeconds: 2, beatSeconds: 0.5, filling: 4.2)
        #expect(cuts.map(\.end).last.map { ($0 * 10).rounded() / 10 } == 4.2)
        #expect(cuts.reduce(0) { $0 + $1.end - $1.start } > 4.19)
    }

    @Test func theOpeningSectionTakesItsLeftoverUpFront() {
        let cuts = PacedCuts.moments(from: [moment("a", 0, 10)], cutSeconds: 2, beatSeconds: 0.5, filling: 4.2, leftoverFirst: true)
        #expect(abs(cuts[0].end - cuts[0].start - 2.2) < 1e-6)
        #expect(abs(cuts[1].end - cuts[1].start - 2) < 1e-6)
    }

    @Test func theLeftoverGoesOnTheNextCutWithRoomSoTheSectionStillFills() {
        let cuts = PacedCuts.moments(from: [moment("a", 0, 2), moment("b", 10, 13)], cutSeconds: 2, beatSeconds: 0.5, filling: 4.2, leftoverFirst: true)
        #expect(abs(cuts.reduce(0) { $0 + $1.end - $1.start } - 4.2) < 1e-6)
    }

    @Test func noUsableMomentMeansNoCuts() {
        #expect(PacedCuts.moments(from: [moment("a", 0, 0.3)], cutSeconds: 1, beatSeconds: 0.5, filling: 4).isEmpty)
    }

    @Test func aMomentShorterThanTheCutGivesWholeBeats() {
        let cuts = PacedCuts.moments(from: [moment("a", 0, 1.7)], cutSeconds: 4, beatSeconds: 0.5, filling: 4)
        #expect(cuts == [moment("a", 0, 1.5), moment("a", 0, 1.5), moment("a", 0, 1)])
    }
}
