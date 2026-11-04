import Testing
@testable import PalmierPro

@MainActor
struct PlanSectionSnapTests {
    @Test func aPlansSectionEdgesAreSnapPoints() {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(id: "v1")])
        editor.timeline.plan = EditPlan(brief: "", style: nil, trackId: "v1", sections: [
            PlanSection(id: "s0", title: "Build", targetSeconds: 16, hint: ""),
            PlanSection(id: "s1", title: "Drop", targetSeconds: 16, hint: ""),
        ])
        #expect(editor.planSectionSnapFrames() == [0, 480, 960])
    }

    @Test func noPlanMeansNoSectionSnapPoints() {
        let editor = EditorViewModel()
        #expect(editor.planSectionSnapFrames().isEmpty)
    }

    @Test func aDraggedClipSnapsToASectionEdge() {
        let targets = SnapEngine.collectTargets(tracks: [], sectionFrames: [480])
        #expect(targets.map(\.kind) == [.section])
        var state = SnapEngine.SnapState()
        let snap = SnapEngine.findSnap(position: 476, targets: targets, state: &state, baseThreshold: 8, pixelsPerFrame: 2)
        #expect(snap?.frame == 480)
    }
}
