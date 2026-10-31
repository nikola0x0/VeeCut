import Foundation
import Testing
@testable import PalmierPro

struct CoachRulesTests {
    private func plan(_ targets: [Double], suggestions: [[PlanMoment]] = [], dismissed: Set<String> = []) -> EditPlan {
        EditPlan(brief: "", style: nil, trackId: "v1", sections: targets.enumerated().map { index, target in
            PlanSection(id: "s\(index)", title: "S\(index)", targetSeconds: target, hint: "",
                        suggestions: index < suggestions.count ? suggestions[index] : [])
        }, dismissedNudges: dismissed)
    }

    private func member(_ section: String, start: Int, duration: Int) -> Clip {
        var clip = Fixtures.clip(start: start, duration: duration)
        clip.planSectionId = section
        return clip
    }

    private func timeline(_ clips: [Clip]) -> Timeline {
        Fixtures.timeline(tracks: [Fixtures.videoTrack(id: "v1", clips: clips)])
    }

    private let moment = PlanMoment(assetId: "cat", start: 1, end: 3, note: "cat")

    @Test(arguments: [(391, true), (390, false), (345, false)])
    func aSectionOverItsTargetByMoreThanTheMarginIsFlagged(frames: Int, flagged: Bool) {
        let nudges = CoachRules.nudges(plan: plan([10]), timeline: timeline([member("s0", start: 0, duration: frames)]), beatFrames: [])
        #expect(nudges.contains { $0.id == "over:s0" } == flagged)
    }

    @Test func smallSectionsUseTheThreeSecondMargin() {
        let nudges = CoachRules.nudges(plan: plan([4]), timeline: timeline([member("s0", start: 0, duration: 7 * 30)]), beatFrames: [])
        #expect(nudges.isEmpty)
        let over = CoachRules.nudges(plan: plan([4]), timeline: timeline([member("s0", start: 0, duration: 7 * 30 + 1)]), beatFrames: [])
        guard case .sectionOver(let id, let extra)? = over.first?.kind else { Issue.record("expected sectionOver"); return }
        #expect(id == "s0")
        #expect(abs(extra - (3 + 1.0 / 30)) < 0.001)
    }

    @Test func cutsJustOffTheBeatAreFlaggedButNotOnOrFarFromIt() {
        let clips = [member("s0", start: 0, duration: 33), member("s0", start: 33, duration: 30), member("s0", start: 63, duration: 37), member("s0", start: 100, duration: 30)]
        let nudges = CoachRules.nudges(plan: plan([5]), timeline: timeline(clips), beatFrames: [30, 61, 80, 100])
        guard case .offBeatCuts(let id, let cuts)? = nudges.first?.kind else { Issue.record("expected offBeatCuts"); return }
        #expect(id == "s0")
        #expect(cuts == [33])
    }

    @Test func noBeatsMeansNoBeatNudge() {
        let clips = [member("s0", start: 0, duration: 33), member("s0", start: 33, duration: 30)]
        #expect(CoachRules.nudges(plan: plan([5]), timeline: timeline(clips), beatFrames: []).isEmpty)
    }

    @Test func anEmptyFirstSectionWithSuggestionsOffersAHookAndLaterOnesOfferMoments() {
        let nudges = CoachRules.nudges(plan: plan([5, 5, 5], suggestions: [[moment], [moment], []]), timeline: timeline([]), beatFrames: [])
        #expect(nudges.map(\.id) == ["empty:s1", "hook:s0"])
    }

    @Test func dismissedNudgesStayGoneAndPriorityOrderHolds() {
        let clips = [member("s0", start: 0, duration: 600), member("s0", start: 600, duration: 33)]
        let all = CoachRules.nudges(plan: plan([5, 5], suggestions: [[], [moment]]), timeline: timeline(clips), beatFrames: [603])
        #expect(all.map(\.id) == ["over:s0", "beats:s0", "empty:s1"])

        let remaining = CoachRules.nudges(plan: plan([5, 5], suggestions: [[], [moment]], dismissed: ["over:s0"]), timeline: timeline(clips), beatFrames: [603])
        #expect(remaining.map(\.id) == ["beats:s0", "empty:s1"])
    }

    @Test func aSongThatDoesNotMatchThePlanLengthOffersToFitIt() {
        let nudges = CoachRules.nudges(plan: plan([60, 60]), timeline: timeline([]), beatFrames: [], musicSeconds: 167)
        #expect(nudges.first == CoachNudge(id: "fit:167", kind: .fitToMusic(seconds: 167)))
        #expect(CoachRules.nudges(plan: plan([60, 60]), timeline: timeline([]), beatFrames: [], musicSeconds: 125).isEmpty)
    }
}
