import Foundation
import Testing
@testable import PalmierPro

@MainActor
private func makeEditor(_ tracks: [Track]) -> EditorViewModel {
    let editor = EditorViewModel()
    editor.timeline = Fixtures.timeline(tracks: tracks)
    return editor
}

@Suite("EditorViewModel — track display label")
@MainActor
struct TrackDisplayLabelTests {

    @Test func labelsVisualTracksTopToBottomThenAudio() {
        let editor = makeEditor([
            Fixtures.videoTrack(),
            Fixtures.videoTrack(),
            Fixtures.audioTrack(),
        ])
        #expect(editor.timelineTrackDisplayLabel(at: 0) == "V2")
        #expect(editor.timelineTrackDisplayLabel(at: 1) == "V1")
        #expect(editor.timelineTrackDisplayLabel(at: 2) == "A1")
    }

    @Test func nameSurvivesComputedDesignationReorder() throws {
        let editor = makeEditor([
            Fixtures.videoTrack(),
            Fixtures.videoTrack(),
        ])
        let trackId = editor.timeline.tracks[0].id

        #expect(try editor.setTrackName(id: trackId, to: "  B-roll  "))
        #expect(editor.timelineTrackDisplayLabel(at: 0) == "V2")
        #expect(editor.timeline.tracks[0].name == "B-roll")

        editor.reorderTrackLive(id: trackId, to: 1)
        #expect(editor.timelineTrackDisplayLabel(at: 1) == "V2")
        #expect(editor.timeline.tracks[1].name == "B-roll")
        #expect(throws: TrackNameValidationError.self) { try editor.setTrackName(id: trackId, to: "Bad\nName") }
        #expect(editor.timeline.tracks[1].name == "B-roll")
    }

    @Test func aDraggedTrackKeepsItsLabel() {
        let editor = makeEditor([Fixtures.videoTrack(id: "top"), Fixtures.videoTrack(id: "bottom"), Fixtures.audioTrack(id: "a1"), Fixtures.audioTrack(id: "a2")])
        editor.reorderTrackLive(id: "top", to: 1)
        editor.reorderTrackLive(id: "a2", to: 2)
        #expect(editor.timeline.tracks.map(\.id) == ["bottom", "top", "a2", "a1"])
        #expect(editor.timeline.tracks.indices.map(editor.timelineTrackDisplayLabel(at:)) == ["V1", "V2", "A2", "A1"])
    }

    @Test func aNewTrackTakesTheSmallestFreeNumber() {
        let editor = makeEditor([Fixtures.videoTrack(id: "v2"), Fixtures.videoTrack(id: "v1")])
        editor.reorderTrackLive(id: "v2", to: 1)
        _ = editor.insertTrack(at: 0, type: .video)
        #expect(editor.timelineTrackDisplayLabel(at: 0) == "V3")

        editor.timeline.tracks.removeAll { $0.id == "v1" }
        _ = editor.insertTrack(at: 0, type: .video)
        #expect(Set(editor.timeline.tracks.indices.map(editor.timelineTrackDisplayLabel(at:))) == ["V1", "V2", "V3"])
    }

    @Test func aMovedTracksLabelSurvivesSaveAndReopen() throws {
        let editor = makeEditor([Fixtures.videoTrack(id: "top"), Fixtures.videoTrack(id: "bottom")])
        editor.reorderTrackLive(id: "top", to: 1)
        let reopened = makeEditor(try JSONDecoder().decode([Track].self, from: JSONEncoder().encode(editor.timeline.tracks)))
        #expect(reopened.timeline.tracks.indices.map(reopened.timelineTrackDisplayLabel(at:)) == ["V1", "V2"])
    }

    @Test func outOfRangeIndexReturnsEmpty() {
        let editor = makeEditor([Fixtures.videoTrack()])
        #expect(editor.timelineTrackDisplayLabel(at: 5) == "")
    }

    @Test func visualTrackAfterAudioDoesNotTrap() {
        // Invariant-violating order (visual below audio) — must not crash on the empty range.
        var text = Fixtures.videoTrack()
        text.type = .text
        let editor = makeEditor([
            Fixtures.videoTrack(),
            Fixtures.audioTrack(),
            text,
        ])
        #expect(editor.timelineTrackDisplayLabel(at: 2) == "T1")
    }
}
