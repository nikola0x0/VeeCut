import Foundation
import Testing
@testable import PalmierPro

@Suite("Vee's suggestions for the selected clip")
@MainActor
struct VeeSuggestionsTests {
    private func note(talking: Bool) -> FootageNote {
        FootageNote(assetId: "cat", fileKey: "k", durationSeconds: 10, hasSpeech: talking, labels: [], summary: nil, moments: [])
    }

    private let clip = Fixtures.clip(id: "a", mediaRef: "cat", start: 0, duration: 90)

    @Test func aTalkingClipGetsSkinCaptionsAndPauses() {
        #expect(VeeSuggestions.kinds(for: clip, note: note(talking: true), canCutPauses: true, offBeatSectionId: nil)
            == [.smoothSkin(clipId: "a"), .addCaptions(clipId: "a"), .cutPauses(clipId: "a")])
        #expect(VeeSuggestions.kinds(for: clip, note: note(talking: false), canCutPauses: true, offBeatSectionId: nil).isEmpty)
    }

    @Test func skinAlreadySmoothedIsNotOfferedAgain() {
        var smoothed = clip
        smoothed.effectRegions = [EffectRegion(matte: EffectMatte(maskId: "face"), effects: [Effect.make(EditorViewModel.smoothSkinEffect)])]

        #expect(VeeSuggestions.kinds(for: smoothed, note: note(talking: true), canCutPauses: false, offBeatSectionId: nil)
            == [.addCaptions(clipId: "a")])
    }

    @Test func pausesAreOnlyOfferedWhenTheClipHasItsAudio() {
        #expect(VeeSuggestions.kinds(for: clip, note: note(talking: true), canCutPauses: false, offBeatSectionId: nil)
            == [.smoothSkin(clipId: "a"), .addCaptions(clipId: "a")])
    }

    @Test func anOffBeatCutAddsSnap() {
        #expect(VeeSuggestions.kinds(for: clip, note: nil, canCutPauses: false, offBeatSectionId: "s0") == [.snapToBeat(sectionId: "s0")])
    }

    @Test func aSelectedTalkingClipBecomesVeesLine() {
        let editor = editor(clips: [clip])
        editor.selectedClipIds = ["a"]

        #expect(editor.veeLine?.actions.map(\.kind) == [.smoothSkin(clipId: "a"), .addCaptions(clipId: "a")])
    }

    @Test func aVideoClipWithItsLinkedAudioSelectedStillGetsSuggestions() {
        var video = clip
        video.linkGroupId = "g"
        var audio = Fixtures.clip(id: "a-audio", mediaRef: "cat", mediaType: .audio, start: 0, duration: 90)
        audio.linkGroupId = "g"
        let editor = editor(clips: [video])
        editor.timeline.tracks.append(Fixtures.audioTrack(id: "a1", clips: [audio]))
        editor.selectedClipIds = ["a", "a-audio"]

        #expect(editor.veeLine?.actions.map(\.kind).prefix(2) == [.smoothSkin(clipId: "a"), .addCaptions(clipId: "a")])
    }

    @Test func pausesAreOnlyOfferedWhereSpeechCanBeAnalyzed() {
        var video = clip
        video.linkGroupId = "g"
        var audio = Fixtures.clip(id: "a-audio", mediaRef: "cat", mediaType: .audio, start: 0, duration: 90)
        audio.linkGroupId = "g"
        let editor = editor(clips: [video])
        editor.timeline.tracks.append(Fixtures.audioTrack(id: "a1", clips: [audio]))
        editor.selectedClipIds = ["a", "a-audio"]

        let offersPauses = editor.veeLine?.actions.contains { $0.kind == .cutPauses(clipId: "a") } == true
        #expect(offersPauses == MLXRuntime.isAvailable)
    }

    @Test(arguments: [
        (["a", "b"], ClipType.video),
        (["a"], .text),
        (["a"], .audio),
        ([], .video),
    ])
    func onlyOneVideoClipGetsSuggestions(selected: [String], type: ClipType) {
        let editor = editor(clips: [
            Fixtures.clip(id: "a", mediaRef: "cat", mediaType: type, start: 0, duration: 90),
            Fixtures.clip(id: "b", mediaRef: "cat", start: 90, duration: 90),
        ])
        editor.selectedClipIds = Set(selected)

        #expect(editor.veeLine == nil)
    }

    @Test func captionsThatFailedSayWhyInsteadOfSilence() {
        let editor = editor(clips: [clip])
        let failed = EditorViewModel.CaptionGeneration(createdIds: [], failures: [.init(mediaRef: "cat", cause: .offline)])
        let silent = EditorViewModel.CaptionGeneration(createdIds: [], failures: [])
        let done = EditorViewModel.CaptionGeneration(createdIds: ["c1"], failures: [])

        #expect(editor.captionOutcomeMessage(failed) == editor.captionFailureNote(failed.failures))
        #expect(editor.captionOutcomeMessage(failed) != L10n.string("No speech detected."))
        #expect(editor.captionOutcomeMessage(silent) == L10n.string("No speech detected."))
        #expect(editor.captionOutcomeMessage(done) == nil)
    }

    private func editor(clips: [Clip]) -> EditorViewModel {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(id: "v1", clips: clips)])
        editor.footageNotes["cat"] = note(talking: true)
        return editor
    }
}
