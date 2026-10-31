import Foundation
import Testing
@testable import PalmierPro

@Suite("Plan editing")
@MainActor
struct PlanEditingTests {
    private let undoManager = UndoManager()

    private func editor(clips: [Clip] = [], hasAudio: Bool = false) -> EditorViewModel {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(id: "v1", clips: clips), Fixtures.audioTrack(id: "a1")])
        editor.undo.attach(undoManager)
        let asset = MediaAsset(id: "cat", url: URL(fileURLWithPath: "/tmp/cat.mov"), type: .video, name: "cat", duration: 20)
        asset.hasAudio = hasAudio
        editor.mediaAssets.append(asset)
        return editor
    }

    private func plan(_ targets: [Double]) -> EditPlan {
        EditPlan(brief: "trip", style: nil, trackId: "v1", sections: targets.enumerated().map {
            PlanSection(id: "s\($0.offset)", title: "S\($0.offset)", targetSeconds: $0.element, hint: "")
        })
    }

    private func member(_ id: String, _ section: String, start: Int, duration: Int) -> Clip {
        var clip = Fixtures.clip(id: id, start: start, duration: duration)
        clip.planSectionId = section
        return clip
    }

    private func undoActions() -> Int {
        var count = 0
        while undoManager.canUndo { undoManager.undo(); count += 1 }
        return count
    }

    @Test func placingAMomentInsertsItTrimmedAtTheSectionEndInOneUndoStep() throws {
        let editor = editor(clips: [member("hook", "s0", start: 0, duration: 60)], hasAudio: true)
        editor.setPlan(plan([2, 10]), actionName: "Make Plan")
        undoManager.removeAllActions()

        let ids = try editor.placeMoment(PlanMoment(assetId: "cat", start: 4, end: 7, note: "jump"), in: "s0").get()

        let placed = try #require(editor.clipFor(id: ids[0]))
        #expect(ids.count == 2)
        #expect(placed.startFrame == 60)
        #expect(placed.trimStartFrame == 120)
        #expect(placed.durationFrames == 90)
        #expect(ids.allSatisfy { editor.clipFor(id: $0)?.planSectionId == "s0" })
        #expect(undoActions() == 1)
        #expect(editor.clipFor(id: ids[0]) == nil)
    }

    @Test func droppingSeveralClipsPlacesThemInOrderAsOneUndoStep() throws {
        let editor = editor()
        editor.setPlan(plan([5]), actionName: "Make Plan")
        undoManager.removeAllActions()

        let ids = try editor.placeMoments([PlanMoment(assetId: "cat", start: 0, end: 1, note: ""), PlanMoment(assetId: "cat", start: 5, end: 7, note: "")], in: "s0").get()

        #expect(ids.compactMap { editor.clipFor(id: $0)?.startFrame } == [0, 30])
        #expect(undoActions() == 1)
    }

    @Test func oneInvalidMomentRefusesTheWholeDrop() {
        let editor = editor()
        editor.setPlan(plan([5]), actionName: "Make Plan")
        undoManager.removeAllActions()

        let result = editor.placeMoments([PlanMoment(assetId: "cat", start: 0, end: 1, note: ""), PlanMoment(assetId: "cat", start: 5, end: 99, note: "")], in: "s0")

        #expect(result == .failure(.invalidRange))
        #expect(editor.timeline.tracks[0].clips.isEmpty)
        #expect(!undoManager.canUndo)
    }

    @Test func placingIntoAnEarlierSectionRipplesLaterOnes() throws {
        let editor = editor(clips: [member("hook", "s0", start: 0, duration: 60), member("food", "s1", start: 60, duration: 90)])
        editor.setPlan(plan([2, 3]), actionName: "Make Plan")

        _ = try editor.placeMoment(PlanMoment(assetId: "cat", start: 0, end: 1, note: ""), in: "s0").get()

        #expect(editor.clipFor(id: "food")?.startFrame == 90)
    }

    @Test(arguments: [(4.0, 4.0), (5.0, 21.0), (Double.nan, 3.0), (-1.0, 2.0)])
    func invalidRangesAreRefusedWithoutUndo(start: Double, end: Double) {
        let editor = editor()
        editor.setPlan(plan([5]), actionName: "Make Plan")
        undoManager.removeAllActions()

        let result = editor.placeMoment(PlanMoment(assetId: "cat", start: start, end: end, note: ""), in: "s0")

        #expect(result == .failure(.invalidRange))
        #expect(!undoManager.canUndo)
    }

    @Test func unknownSectionsAndAssetsAreRefused() {
        let editor = editor()
        #expect(editor.placeMoment(PlanMoment(assetId: "cat", start: 0, end: 1, note: ""), in: "s0") == .failure(.noPlan))
        editor.setPlan(plan([5]), actionName: "Make Plan")
        #expect(editor.placeMoment(PlanMoment(assetId: "cat", start: 0, end: 1, note: ""), in: "nope") == .failure(.unknownSection))
        #expect(editor.placeMoment(PlanMoment(assetId: "dog", start: 0, end: 1, note: ""), in: "s0") == .failure(.unknownAsset))
    }

    @Test func deletingASectionKeepsItsClips() {
        let editor = editor(clips: [member("hook", "s0", start: 0, duration: 60)])
        editor.setPlan(plan([2, 10]), actionName: "Make Plan")

        editor.deletePlanSection("s0")

        #expect(editor.timeline.plan?.sections.map(\.id) == ["s1"])
        #expect(editor.clipFor(id: "hook")?.startFrame == 0)
        #expect(editor.clipFor(id: "hook")?.planSectionId == nil)
    }

    @Test func sectionEditsValidateBeforeChanging() {
        let editor = editor()
        editor.setPlan(plan([5, 5]), actionName: "Make Plan")
        undoManager.removeAllActions()

        #expect(editor.editPlan([.setTarget("s0", seconds: 0.5)], actionName: "Set Length") == .invalidTarget)
        #expect(editor.editPlan([.rename("s0", to: "  ")], actionName: "Rename") == .invalidTitle)
        #expect(editor.editPlan([.move("s0", by: -1)], actionName: "Move") == .invalidMove)
        #expect(editor.editPlan([.rename("s0", to: "S0")], actionName: "Rename") == nil)
        #expect(!undoManager.canUndo)

        editor.movePlanSection("s0", by: 1)
        editor.setPlanSectionTarget("s0", seconds: 30)
        #expect(editor.timeline.plan?.sections.map(\.id) == ["s1", "s0"])
        #expect(editor.timeline.plan?.sections.last?.targetSeconds == 30)
    }

    @Test func replanningRetagsPlacedClipsByPosition() {
        let editor = editor(clips: [member("a", "old", start: 0, duration: 60), member("b", "old", start: 60, duration: 300)])

        editor.setPlan(plan([3, 20]), actionName: "Make Plan")

        #expect(editor.clipFor(id: "a")?.planSectionId == "s0")
        #expect(editor.clipFor(id: "b")?.planSectionId == "s1")
    }

    @Test func addingMusicAfterPlanningOnAnEmptyTimelineStillLetsMomentsIn() throws {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.audioTrack(id: "a1")])
        editor.undo.attach(undoManager)
        let cat = MediaAsset(id: "cat", url: URL(fileURLWithPath: "/tmp/cat.mov"), type: .video, name: "cat", duration: 20)
        cat.hasAudio = false
        let song = MediaAsset(id: "song", url: URL(fileURLWithPath: "/tmp/song.m4a"), type: .audio, name: "song", duration: 30)
        editor.mediaAssets += [cat, song]
        var p = plan([5])
        p.trackId = ""
        editor.setPlan(p, actionName: "Make Plan")
        editor.addClips(assets: [song], trackIndex: try #require(editor.timeline.tracks.firstIndex { $0.id == "a1" }), startFrame: 0)
        undoManager.removeAllActions()

        let ids = try editor.placeMoment(PlanMoment(assetId: "cat", start: 0, end: 2, note: ""), in: "s0").get()

        let trackId = try #require(editor.timeline.plan?.trackId)
        #expect(editor.timeline.tracks.first { $0.id == trackId }?.clips.map(\.id) == ids)
        #expect(PlanLayout.progress(try #require(editor.timeline.plan), in: editor.timeline).first?.actualSeconds == 2)
        #expect(undoActions() == 1)
        #expect(editor.timeline.tracks.map(\.id) == ["a1"])
    }

    @Test func removingThePlanClearsMembershipAndUndoRestoresIt() {
        let editor = editor(clips: [member("hook", "s0", start: 0, duration: 60)])
        editor.setPlan(plan([2]), actionName: "Make Plan")
        undoManager.removeAllActions()

        editor.setPlan(nil, actionName: "Remove Plan")
        #expect(editor.timeline.plan == nil)
        #expect(editor.clipFor(id: "hook")?.planSectionId == nil)

        undoManager.undo()
        #expect(editor.timeline.plan?.sections.map(\.id) == ["s0"])
        #expect(editor.clipFor(id: "hook")?.planSectionId == "s0")
    }
}
