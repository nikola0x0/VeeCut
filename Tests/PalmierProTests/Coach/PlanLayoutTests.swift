import Foundation
import Testing
@testable import PalmierPro

struct PlanLayoutTests {
    private func plan(trackId: String, targets: [Double]) -> EditPlan {
        EditPlan(brief: "", style: nil, trackId: trackId, sections: targets.enumerated().map {
            PlanSection(id: "s\($0.offset)", title: "S\($0.offset)", targetSeconds: $0.element, hint: "")
        })
    }

    private func member(_ section: String, start: Int, duration: Int) -> Clip {
        var clip = Fixtures.clip(start: start, duration: duration)
        clip.planSectionId = section
        return clip
    }

    @Test func progressSumsMemberClipsOnThePlanTrack() {
        let track = Fixtures.videoTrack(clips: [member("s0", start: 0, duration: 90), member("s0", start: 90, duration: 150), member("s1", start: 240, duration: 30)])
        let progress = PlanLayout.progress(plan(trackId: track.id, targets: [8, 10]), in: Fixtures.timeline(tracks: [track]))

        #expect(progress.map(\.actualSeconds) == [8, 1])
        #expect(progress[0].frames == 0..<240)
        #expect(progress[0].isFilled)
        #expect(!progress[1].isFilled)
    }

    @Test func clipsOnOtherTracksDontCount() {
        let planTrack = Fixtures.videoTrack(clips: [])
        let other = Fixtures.videoTrack(clips: [member("s0", start: 0, duration: 90)])
        let progress = PlanLayout.progress(plan(trackId: planTrack.id, targets: [8]), in: Fixtures.timeline(tracks: [planTrack, other]))

        #expect(progress[0].actualSeconds == 0)
        #expect(progress[0].frames == nil)
    }

    @Test func emptySectionInsertsAfterThePreviousFilledSection() {
        let track = Fixtures.videoTrack(clips: [member("s0", start: 0, duration: 90), member("s2", start: 90, duration: 60)])
        let p = plan(trackId: track.id, targets: [3, 5, 5])

        #expect(PlanLayout.insertionFrame(for: "s1", plan: p, timeline: Fixtures.timeline(tracks: [track])) == 90)
        #expect(PlanLayout.insertionFrame(for: "s2", plan: p, timeline: Fixtures.timeline(tracks: [track])) == 150)
    }

    @Test func firstEmptySectionInsertsAtZero() {
        let track = Fixtures.videoTrack(clips: [member("s1", start: 0, duration: 90)])
        let p = plan(trackId: track.id, targets: [3, 5])

        #expect(PlanLayout.insertionFrame(for: "s0", plan: p, timeline: Fixtures.timeline(tracks: [track])) == 0)
        #expect(PlanLayout.insertionFrame(for: "missing", plan: p, timeline: Fixtures.timeline(tracks: [track])) == nil)
    }

    @Test func splittingAClipKeepsBothHalvesInTheSection() {
        let track = Fixtures.videoTrack(clips: [member("s0", start: 0, duration: 45), member("s0", start: 45, duration: 45)])
        let progress = PlanLayout.progress(plan(trackId: track.id, targets: [3]), in: Fixtures.timeline(tracks: [track]))

        #expect(progress[0].actualSeconds == 3)
        #expect(progress[0].frames == 0..<90)
    }

    @Test func positionMembershipFollowsCumulativeTargets() {
        let clips = [Fixtures.clip(id: "a", start: 0, duration: 270), Fixtures.clip(id: "b", start: 360, duration: 390), Fixtures.clip(id: "c", start: 1200, duration: 600)]
        let track = Fixtures.videoTrack(clips: clips)

        let membership = PlanLayout.membership(byPosition: plan(trackId: track.id, targets: [10, 20, 30]), timeline: Fixtures.timeline(tracks: [track]))

        #expect(membership == ["a": "s0", "b": "s1", "c": "s2"])
    }

    @Test func bandsSitOnTheirClipsAndShowTheRestOfTheTarget() {
        let track = Fixtures.videoTrack(clips: [member("s0", start: 0, duration: 60), member("s1", start: 60, duration: 300)])
        let bands = PlanLayout.bands(plan(trackId: track.id, targets: [5, 8]), in: Fixtures.timeline(tracks: [track]))

        #expect(bands.map(\.placed) == [0..<60, 60..<360])
        #expect(bands.map(\.slot) == [0..<60, 60..<360])
    }

    @Test func aShortSectionAtTheEndShowsItsMissingTimeAsASlot() {
        let track = Fixtures.videoTrack(clips: [member("s0", start: 0, duration: 60)])
        let bands = PlanLayout.bands(plan(trackId: track.id, targets: [5, 4]), in: Fixtures.timeline(tracks: [track]))

        #expect(bands[0].placed == 0..<60)
        #expect(bands[0].slot == 0..<150)
        #expect(bands[1].placed == nil)
        #expect(bands[1].slot == 150..<270)
    }

    @Test func anEmptySectionBetweenFilledOnesSitsWhereItsClipsWillGo() {
        let track = Fixtures.videoTrack(clips: [member("s0", start: 0, duration: 60), member("s2", start: 60, duration: 90)])
        let bands = PlanLayout.bands(plan(trackId: track.id, targets: [2, 4, 3]), in: Fixtures.timeline(tracks: [track]))

        #expect(bands[1].placed == nil)
        #expect(bands[1].slot == 60..<60)
        #expect(bands[2].slot == 60..<150)
    }
}
