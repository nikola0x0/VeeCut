import Foundation
import Testing
@testable import PalmierPro

@MainActor
final class RecordingSpeaker: CoachSpeaking {
    private(set) var spoken: [String] = []
    private(set) var stops = 0
    func speak(_ text: String) { spoken.append(text) }
    func stop() { stops += 1 }
}

@Suite("Coach mode")
@MainActor
struct CoachModeTests {
    private func editor(mode: CoachMode) -> (EditorViewModel, RecordingSpeaker) {
        let editor = EditorViewModel()
        var clip = Fixtures.clip(id: "a", start: 0, duration: 900)
        clip.planSectionId = "s0"
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(id: "v1", clips: [clip])])
        editor.timeline.plan = EditPlan(brief: "", style: nil, trackId: "v1", sections: [PlanSection(id: "s0", title: "Food", targetSeconds: 5, hint: "")])
        let speaker = RecordingSpeaker()
        editor.coachVoice = speaker
        editor.coachMode = mode
        return (editor, speaker)
    }

    @Test func activeModeSpeaksNewNudgesOnce() {
        let (editor, speaker) = editor(mode: .active)

        editor.refreshCoachNudges()
        editor.refreshCoachNudges()

        #expect(speaker.spoken.count == 1)
        #expect(speaker.spoken.first?.contains("Food") == true)
    }

    @Test func passiveModeNeverSpeaks() {
        let (editor, speaker) = editor(mode: .passive)

        editor.refreshCoachNudges()
        editor.showCoachIfNeeded()

        #expect(editor.coachNudges.count == 1)
        #expect(speaker.spoken.isEmpty)
    }

    @Test func aSpokenRequestGetsATextOnlyReplyWhileVeeIsQuiet() {
        let (editor, speaker) = editor(mode: .passive)
        editor.coachAwaitingReply = true

        editor.coachReplyFinished("Done. Her skin is smoother.")

        #expect(speaker.spoken.isEmpty)
        #expect(!editor.coachAwaitingReply)
    }

    @Test func switchingToPassiveStopsSpeech() {
        let (editor, speaker) = editor(mode: .active)

        editor.coachMode = .passive

        #expect(speaker.stops == 1)
    }

    @Test func activeModeAsksTheOpeningQuestionAloud() {
        let (editor, speaker) = editor(mode: .active)
        editor.timeline.plan = nil
        editor.timelines = [editor.timeline]
        editor.activeTimelineId = editor.timeline.id
        editor.mediaAssets.append(MediaAsset(id: "cat", url: URL(fileURLWithPath: "/tmp/cat.mov"), type: .video, name: "cat", duration: 4))

        editor.showCoachIfNeeded()
        editor.showCoachIfNeeded()

        #expect(speaker.spoken.count == 1)
        #expect(speaker.spoken.first?.hasSuffix("What are we making today?") == true)
    }
}
