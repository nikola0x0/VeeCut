import Testing
@testable import PalmierPro

@Test func packingPlacesClipsEndToEndInTheGivenOrder() {
    let clips = [Fixtures.clip(id: "b", start: 90, duration: 20), Fixtures.clip(id: "a", start: 10, duration: 30)]
    #expect(MagneticPacking.packed(clips).map { "\($0.id)@\($0.startFrame)" } == ["b@0", "a@20"])
}

@Test(arguments: [(0, 0), (14, 0), (16, 1), (59, 2), (500, 3)] as [(Int, Int)])
func dropsInsertBeforeTheFirstClipWhoseMiddleIsPastTheDrop(drop: Int, index: Int) {
    let clips = [0, 30, 60].map { Fixtures.clip(start: $0, duration: 30) }
    #expect(MagneticPacking.insertionIndex(dropFrame: drop, among: clips) == index)
}

@Suite("Magnetic timeline")
@MainActor
struct MagneticTimelineTests {
    private func editor(_ tracks: [Track]) -> EditorViewModel {
        let e = EditorViewModel()
        e.timeline = Fixtures.timeline(tracks: tracks)
        e.isMagneticTimeline = true
        return e
    }

    private func starts(_ e: EditorViewModel, track: Int) -> [String] {
        e.timeline.tracks[track].clips.sorted { $0.startFrame < $1.startFrame }.map { "\($0.id)@\($0.startFrame)" }
    }

    @Test func draggingOntoTheMainTrackInsertsAndRepacksWithoutCutting() {
        let e = editor([Fixtures.videoTrack(clips: [
            Fixtures.clip(id: "a", start: 0, duration: 30),
            Fixtures.clip(id: "b", start: 30, duration: 30),
            Fixtures.clip(id: "c", start: 60, duration: 30),
        ])])
        e.moveClips([(clipId: "c", toTrack: 0, toFrame: 10)], magnetic: true)
        #expect(starts(e, track: 0) == ["c@0", "a@30", "b@60"])
    }

    @Test func linkedAudioFollowsItsVideoOnTheMainTrack() {
        var a = Fixtures.clip(id: "a", start: 0, duration: 30)
        var b = Fixtures.clip(id: "b", start: 30, duration: 30)
        var bAudio = Fixtures.clip(id: "b-audio", mediaType: .audio, start: 30, duration: 30)
        a.linkGroupId = nil
        b.linkGroupId = "g"
        bAudio.linkGroupId = "g"
        let e = editor([Fixtures.videoTrack(clips: [a, b]), Fixtures.audioTrack(clips: [bAudio])])
        e.moveClips([(clipId: "b", toTrack: 0, toFrame: 0), (clipId: "b-audio", toTrack: 1, toFrame: 0)], magnetic: true)
        #expect(starts(e, track: 0) == ["b@0", "a@30"])
        #expect(starts(e, track: 1) == ["b-audio@0"])
    }

    @Test func droppingOnAClipOnAnotherTrackLiftsTheDropInsteadOfCutting() {
        let overlay = Fixtures.clip(id: "overlay", start: 0, duration: 60)
        let dragged = Fixtures.clip(id: "dragged", start: 0, duration: 30)
        let e = editor([Fixtures.videoTrack(clips: [overlay]), Fixtures.videoTrack(clips: [dragged])])
        e.moveClips([(clipId: "dragged", toTrack: 0, toFrame: 10)], magnetic: true)
        #expect(e.clipFor(id: "overlay")?.durationFrames == 60)
        #expect(e.clipFor(id: "overlay")?.startFrame == 0)
        let draggedTrack = e.findClip(id: "dragged")?.trackIndex
        let overlayTrack = e.findClip(id: "overlay")?.trackIndex
        #expect(draggedTrack != nil && draggedTrack != overlayTrack)
        #expect(e.clipFor(id: "dragged")?.startFrame == 10)
    }

    @Test func deletingFromTheMainTrackClosesTheGap() {
        let e = editor([Fixtures.videoTrack(clips: [
            Fixtures.clip(id: "a", start: 0, duration: 30),
            Fixtures.clip(id: "b", start: 30, duration: 30),
            Fixtures.clip(id: "c", start: 60, duration: 30),
        ])])
        e.selectedClipIds = ["b"]
        e.deleteSelectedClips()
        #expect(starts(e, track: 0) == ["a@0", "c@30"])
    }

    @Test func classicModeKeepsExactPlacementAndOverwrite() {
        let e = editor([Fixtures.videoTrack(clips: [
            Fixtures.clip(id: "a", start: 0, duration: 30),
            Fixtures.clip(id: "b", start: 60, duration: 30),
        ])])
        e.isMagneticTimeline = false
        e.selectedClipIds = ["a"]
        e.deleteSelectedClips()
        #expect(starts(e, track: 0) == ["b@60"])
    }
}
