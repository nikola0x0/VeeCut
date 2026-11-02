import Testing
@testable import PalmierPro

@MainActor
struct VeeQuipsTests {
    @Test func footageGetsItsOwnJoke() {
        let lines = VeeQuips.lines(labels: ["animal"])
        #expect(lines.contains(L10n.string("Giving the animal its close-up\u{2026}")))
        #expect(!VeeQuips.lines(labels: []).contains(L10n.string("Giving the animal its close-up\u{2026}")))
    }

    @Test(arguments: [0, 1, 7, 1_000])
    func everyTickHasALine(tick: Int) {
        #expect(!VeeQuips.line(tick: tick, labels: []).isEmpty)
    }

    @Test func linesTakeTurns() {
        #expect(VeeQuips.line(tick: 0, labels: []) != VeeQuips.line(tick: 1, labels: []))
    }

    @Test func theDropLineNeedsASongWithADrop() {
        let drop = L10n.string("Saving the best shot for the drop\u{2026}")
        #expect(!VeeQuips.lines(labels: [], hasSong: true).contains(drop))
        #expect(VeeQuips.lines(labels: [], hasSong: true, hasDrop: true).contains(drop))
    }

    @Test func aSongGetsItsOwnLine() {
        #expect(VeeQuips.lines(labels: [], hasSong: true).contains(L10n.string("Counting the beats in your song\u{2026}")))
        #expect(!VeeQuips.lines(labels: []).contains(L10n.string("Counting the beats in your song\u{2026}")))
    }
}
