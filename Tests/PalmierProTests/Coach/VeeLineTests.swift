import Foundation
import Testing
@testable import PalmierPro

@Suite("Vee's line")
@MainActor
struct VeeLineTests {
    private let undoManager = UndoManager()

    private func overTargetEditor() -> EditorViewModel {
        let editor = EditorViewModel()
        var clip = Fixtures.clip(id: "a", start: 0, duration: 900, trimEnd: 300)
        clip.planSectionId = "s0"
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(id: "v1", clips: [clip])])
        editor.timeline.plan = EditPlan(brief: "", style: nil, trackId: "v1", sections: [
            PlanSection(id: "s0", title: "S0", targetSeconds: 5, hint: ""),
        ])
        editor.undo.attach(undoManager)
        editor.refreshCoachNudges()
        return editor
    }

    @Test func aTipBecomesVeesLineWithItsFix() throws {
        let editor = overTargetEditor()
        let nudge = try #require(editor.coachNudges.first)

        let line = try #require(editor.veeLine)

        #expect(line.actions.map(\.kind) == [.applyNudge(nudge), .dismissNudge(nudge)])
        #expect(line.pose == .avatar)
    }

    @Test func performingTheFixAppliesItInOneUndoStep() throws {
        let editor = overTargetEditor()
        let fix = try #require(editor.veeLine?.actions.first)

        editor.perform(fix)

        #expect(editor.clipFor(id: "a")?.durationFrames == 150)
        var steps = 0
        while undoManager.canUndo { undoManager.undo(); steps += 1 }
        #expect(steps == 1)
    }

    @Test func noLineWhilePlayingOrDragging() {
        let editor = overTargetEditor()
        editor.isPlaying = true
        #expect(editor.veeLine == nil)

        editor.isPlaying = false
        editor.dragBefore["a"] = editor.clipFor(id: "a")
        #expect(editor.veeLine == nil)

        editor.dragBefore = [:]
        editor.refreshCoachNudges()
        #expect(editor.veeLine != nil)
    }

    @Test func noLineWhileTheCardIsOpen() {
        let editor = overTargetEditor()
        editor.coach = .asking(overview: "")
        #expect(editor.veeLine == nil)
    }

    @Test func aToolFailureIsVeesLineUntilDismissed() throws {
        let editor = overTargetEditor()
        editor.subjectTrackingFailure = .notFound

        let line = try #require(editor.veeLine)
        #expect(line.pose == .oops)
        #expect(line.text == L10n.string("No subject found there. Try scribbling right on it."))
        #expect(line.actions.map(\.kind) == [.dismissFailure])

        editor.perform(try #require(line.actions.first))

        #expect(editor.subjectTrackingFailure == nil)
        #expect(editor.veeLine?.pose == .avatar)
    }
}
