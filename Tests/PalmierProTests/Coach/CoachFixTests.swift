import Foundation
import Testing
@testable import PalmierPro

@Suite("Coach fixes")
@MainActor
struct CoachFixTests {
    private let undoManager = UndoManager()

    private func member(_ id: String, _ section: String, start: Int, duration: Int, trimEnd: Int = 300) -> Clip {
        var clip = Fixtures.clip(id: id, start: start, duration: duration, trimEnd: trimEnd)
        clip.planSectionId = section
        return clip
    }

    private func editor(_ clips: [Clip], targets: [Double] = [5]) -> EditorViewModel {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(id: "v1", clips: clips), Fixtures.audioTrack(id: "a1")])
        editor.timeline.plan = EditPlan(brief: "", style: nil, trackId: "v1", sections: targets.enumerated().map {
            PlanSection(id: "s\($0.offset)", title: "S\($0.offset)", targetSeconds: $0.element, hint: "")
        })
        editor.undo.attach(undoManager)
        return editor
    }

    private func undoActions() -> Int {
        var count = 0
        while undoManager.canUndo { undoManager.undo(); count += 1 }
        return count
    }

    @Test func trimmingASectionReachesItsTargetInOneUndoStep() {
        let editor = editor([member("a", "s0", start: 0, duration: 150), member("b", "s0", start: 150, duration: 210)])

        editor.trimSectionToTarget("s0")

        #expect(editor.clipFor(id: "a")?.durationFrames == 120)
        #expect(editor.clipFor(id: "b")?.durationFrames == 30)
        #expect(editor.clipFor(id: "b")?.startFrame == 120)
        #expect(undoActions() == 1)
        #expect(editor.clipFor(id: "b")?.durationFrames == 210)
    }

    @Test func trimmingNeverTakesAClipBelowOneSecond() {
        let editor = editor([member("a", "s0", start: 0, duration: 40), member("b", "s0", start: 40, duration: 40)], targets: [1])

        editor.trimSectionToTarget("s0")

        #expect(editor.clipFor(id: "a")?.durationFrames == 30)
        #expect(editor.clipFor(id: "b")?.durationFrames == 30)
    }

    @Test func snappingMovesCutsOntoBeatsInOneUndoStep() {
        let editor = editor([member("a", "s0", start: 0, duration: 33), member("b", "s0", start: 33, duration: 30), member("c", "s0", start: 63, duration: 30)])

        editor.snapCutsToBeats(in: "s0", beatFrames: [30, 66])

        #expect(editor.clipFor(id: "b")?.startFrame == 30)
        #expect(editor.clipFor(id: "c")?.startFrame == 66)
        #expect(undoActions() == 1)
    }

    @Test func fittingThePlanToTheSongScalesEverySection() {
        let editor = editor([], targets: [60, 120])

        editor.apply(CoachNudge(id: "fit:90", kind: .fitToMusic(seconds: 90)))

        #expect(editor.timeline.plan?.sections.map(\.targetSeconds) == [30, 60])
    }

    @Test func dismissedNudgeNeverReturnsAndAddsNoUndo() {
        let editor = editor([member("a", "s0", start: 0, duration: 900)])
        editor.refreshCoachNudges()
        let nudge = try? #require(editor.coachNudges.first)

        if let nudge { editor.dismiss(nudge) }
        editor.refreshCoachNudges()

        #expect(editor.coachNudges.isEmpty)
        #expect(!undoManager.canUndo)
    }

    @Test func noNudgesWhilePlayingOrDragging() {
        let editor = editor([member("a", "s0", start: 0, duration: 900)])
        editor.isPlaying = true
        editor.refreshCoachNudges()
        #expect(editor.coachNudges.isEmpty)

        editor.isPlaying = false
        editor.dragBefore["a"] = editor.clipFor(id: "a")
        editor.refreshCoachNudges()
        #expect(editor.coachNudges.isEmpty)

        editor.dragBefore = [:]
        editor.refreshCoachNudges()
        #expect(editor.coachNudges.map(\.id) == ["over:s0"])
    }

    @Test func droppingMusicPlacesItFromTheStartOnAFreeAudioTrack() throws {
        let editor = editor([member("a", "s0", start: 0, duration: 90)])
        let song = MediaAsset(id: "song", url: URL(fileURLWithPath: "/tmp/song.m4a"), type: .audio, name: "song", duration: 10)
        editor.mediaAssets.append(song)

        let clipId = try editor.addMusic(song).get()

        let loc = try #require(editor.findClip(id: clipId))
        #expect(editor.timeline.tracks[loc.trackIndex].type == .audio)
        #expect(editor.clipFor(id: clipId)?.startFrame == 0)
        #expect(editor.musicSeconds == 10)
        #expect(undoActions() == 1)
        let video = MediaAsset(id: "cat", url: URL(fileURLWithPath: "/tmp/cat.mov"), type: .video, name: "cat", duration: 4)
        #expect(editor.addMusic(video) == .failure(.notAudio))
    }
}
