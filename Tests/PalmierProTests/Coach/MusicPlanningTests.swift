import Foundation
import Testing
@testable import PalmierPro

@Suite("Planning to music")
@MainActor
struct MusicPlanningTests {
    @Test func theSongOnTheTimelineIsThePlanningSong() {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(id: "v1")])
        #expect(editor.planningSong == nil)

        let song = MediaAsset(id: "song", url: URL(fileURLWithPath: "/tmp/song.m4a"), type: .audio, name: "song", duration: 30)
        editor.mediaAssets.append(song)
        editor.timeline.tracks.append(Fixtures.audioTrack(id: "a1", clips: [Fixtures.clip(id: "m", mediaRef: "song", mediaType: .audio, start: 0, duration: 900)]))

        #expect(editor.planningSong?.id == "song")
    }

    /// Calm 0–8 s, rising 8–16 s, peak 16–32 s with the drop at 16 s.
    private var song: MusicMap {
        MusicMap(duration: 32, beatSeconds: 0.5, barSeconds: 2, parts: [
            .init(start: 0, end: 8, energy: .calm, bars: 4),
            .init(start: 8, end: 16, energy: .rising, bars: 4),
            .init(start: 16, end: 32, energy: .peak, bars: 8),
        ], drop: 16)
    }

    private func note(_ id: String) -> FootageNote {
        FootageNote(assetId: id, fileKey: "k", durationSeconds: 20, hasSpeech: false, labels: [], summary: nil, moments: [])
    }

    @Test func musicSectionsKeepTheSongsTimingWhateverTheModelReturns() throws {
        let raw = try JSONDecoder().decode(RawPlan.self, from: Data(#"""
        {"sections":[{"title":"Morning","targetSeconds":40,"hint":"slow","suggestions":[{"assetId":"a","start":1,"end":5,"note":"sunrise"}]},
                     {"title":"Build","targetSeconds":3,"hint":"","suggestions":[]}]}
        """#.utf8))

        let plan = try CoachPlanner.validated(raw, notes: [note("a")], trackId: "v1", brief: "trip", style: .reel, music: .init(map: song, assetId: "song"))

        #expect(plan.sections.map(\.targetSeconds) == [8, 8, 16])
        #expect(plan.sections.map(\.pace) == [.calm, .rising, .peak])
        #expect(plan.sections.prefix(2).map(\.title) == ["Morning", "Build"])
        #expect(!plan.sections[2].title.isEmpty)
        #expect(plan.sections[0].suggestions.count == 1)
        #expect(plan.music == PlanMusic(assetId: "song", beatSeconds: 0.5, drop: 16))
    }

    @Test func theRequestCarriesTheSongsParts() async throws {
        let model = RecordingCoachModel(replies: [#"{"sections":[]}"#])

        _ = try await CoachPlanner.plan(brief: "trip", style: nil, notes: [note("a")], placed: [], music: song, client: model)

        let text = try #require(await model.requests.first?.parts.compactMap { if case .text(let t) = $0 { t } else { nil } }.first)
        #expect(text.contains(#""energy":"peak""#))
        #expect(text.contains(#""drop":16"#))
    }

    @Test func droppingASongFromTheMediaPanelMakesItThePlanningSong() {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(id: "v1")])
        editor.mediaAssets.append(MediaAsset(id: "song", url: URL(fileURLWithPath: "/tmp/song.m4a"), type: .audio, name: "song", duration: 30))
        editor.mediaAssets.append(MediaAsset(id: "cat", url: URL(fileURLWithPath: "/tmp/cat.mov"), type: .video, name: "cat", duration: 30))

        #expect(!editor.addMusic(fromDragStrings: [MediaTab.assetDragScheme + "cat"]))
        #expect(editor.addMusic(fromDragStrings: [MediaTab.assetDragScheme + "song"]))
        #expect(editor.planningSong?.id == "song")
    }

    @Test func theFirstCutLineNamesTheDrop() throws {
        let editor = EditorViewModel()
        let video = MediaAsset(id: "cat", url: URL(fileURLWithPath: "/tmp/cat.mov"), type: .video, name: "cat", duration: 30)
        video.hasAudio = false
        editor.mediaAssets = [video, MediaAsset(id: "song", url: URL(fileURLWithPath: "/tmp/song.m4a"), type: .audio, name: "song", duration: 30)]
        editor.timeline = Fixtures.timeline(tracks: [
            Fixtures.videoTrack(id: "v1"),
            Fixtures.audioTrack(id: "a1", clips: [Fixtures.clip(id: "m", mediaRef: "song", mediaType: .audio, start: 0, duration: 900)]),
        ])
        var section = PlanSection(id: "s0", title: "Peak", targetSeconds: 4, hint: "", suggestions: [PlanMoment(assetId: "cat", start: 0, end: 4, note: "")])
        section.pace = .peak
        editor.timeline.plan = EditPlan(brief: "", style: nil, trackId: "v1", sections: [section], music: PlanMusic(assetId: "song", beatSeconds: 0.5, drop: 24))
        editor.showsSuggestedTimeline = true

        let line = try #require(editor.veeLine)
        #expect(line.text.contains("0:24"))
    }

    @Test func keepingSuggestionsLeavesTheSongWhereItIs() {
        let editor = EditorViewModel()
        let video = MediaAsset(id: "cat", url: URL(fileURLWithPath: "/tmp/cat.mov"), type: .video, name: "cat", duration: 30)
        video.hasAudio = true
        editor.mediaAssets = [video, MediaAsset(id: "song", url: URL(fileURLWithPath: "/tmp/song.m4a"), type: .audio, name: "song", duration: 30)]
        editor.timeline = Fixtures.timeline(tracks: [
            Fixtures.videoTrack(id: "v1"),
            Fixtures.audioTrack(id: "a1", clips: [Fixtures.clip(id: "m", mediaRef: "song", mediaType: .audio, start: 0, duration: 900)]),
        ])
        var section = PlanSection(id: "s0", title: "Peak", targetSeconds: 4, hint: "", suggestions: [PlanMoment(assetId: "cat", start: 0, end: 4, note: "")])
        section.pace = .peak
        editor.timeline.plan = EditPlan(brief: "", style: nil, trackId: "v1", sections: [section], music: PlanMusic(assetId: "song", beatSeconds: 0.5, drop: nil))

        editor.keepAllSuggestions()

        let song = editor.clipFor(id: "m")
        #expect(song?.startFrame == 0)
        #expect(editor.findClip(id: "m").map { editor.timeline.tracks[$0.trackIndex].id } == "a1")
        let linkedAudio = editor.timeline.tracks.filter { $0.id != "a1" && $0.type == .audio }.flatMap(\.clips)
        #expect(!linkedAudio.isEmpty)
        #expect(editor.timeline.tracks.first { $0.id == "v1" }?.clips.isEmpty == false)
    }

    @Test func keptClipsPlayTheirOwnSoundUnderTheSong() {
        let editor = EditorViewModel()
        let video = MediaAsset(id: "cat", url: URL(fileURLWithPath: "/tmp/cat.mov"), type: .video, name: "cat", duration: 30)
        video.hasAudio = true
        editor.mediaAssets = [video, MediaAsset(id: "song", url: URL(fileURLWithPath: "/tmp/song.m4a"), type: .audio, name: "song", duration: 30)]
        editor.timeline = Fixtures.timeline(tracks: [
            Fixtures.videoTrack(id: "v1"),
            Fixtures.audioTrack(id: "a1", clips: [Fixtures.clip(id: "m", mediaRef: "song", mediaType: .audio, start: 0, duration: 900)]),
        ])
        let section = PlanSection(id: "s0", title: "Peak", targetSeconds: 4, hint: "", suggestions: [PlanMoment(assetId: "cat", start: 0, end: 4, note: "")])
        editor.timeline.plan = EditPlan(brief: "", style: nil, trackId: "v1", sections: [section], music: PlanMusic(assetId: "song", beatSeconds: 0.5, drop: nil))

        editor.keepAllSuggestions()

        let clipSound = editor.timeline.tracks.flatMap(\.clips).filter { $0.mediaRef == "cat" && $0.mediaType == .audio }
        #expect(!clipSound.isEmpty)
        #expect(clipSound.allSatisfy { abs(VolumeScale.dbFromLinear($0.volume) - EditorViewModel.musicEditClipSoundDb) < 0.01 })
        #expect(editor.clipFor(id: "m")?.volume == 1)
    }

    @Test func aMusicPlanTrimsTheSongToItsLength() {
        let editor = EditorViewModel()
        editor.mediaAssets = [MediaAsset(id: "song", url: URL(fileURLWithPath: "/tmp/song.m4a"), type: .audio, name: "song", duration: 30)]
        editor.timeline = Fixtures.timeline(tracks: [
            Fixtures.videoTrack(id: "v1"),
            Fixtures.audioTrack(id: "a1", clips: [Fixtures.clip(id: "m", mediaRef: "song", mediaType: .audio, start: 0, duration: 900)]),
        ])
        let section = PlanSection(id: "s0", title: "Calm", targetSeconds: 16, hint: "", suggestions: [])

        editor.setPlan(EditPlan(brief: "", style: nil, trackId: "v1", sections: [section], music: PlanMusic(assetId: "song", beatSeconds: 0.5, drop: nil)), actionName: "Make Plan")

        #expect(editor.clipFor(id: "m")?.durationFrames == 480)
        #expect(editor.clipFor(id: "m")?.trimEndFrame == 420)
    }

    @Test func aMultiItemDragUsesItsFirstSong() {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(id: "v1")])
        editor.mediaAssets.append(MediaAsset(id: "cat", url: URL(fileURLWithPath: "/tmp/cat.mov"), type: .video, name: "cat", duration: 30))
        editor.mediaAssets.append(MediaAsset(id: "song", url: URL(fileURLWithPath: "/tmp/song.m4a"), type: .audio, name: "song", duration: 30))

        #expect(editor.addMusic(fromDragStrings: [MediaTab.assetDragScheme + "cat\n" + MediaTab.assetDragScheme + "song"]))
        #expect(editor.planningSong?.id == "song")
    }
}
