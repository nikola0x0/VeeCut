import Foundation
import Testing
@testable import PalmierPro

struct CoachReplyRouterTests {
    @Test(arguments: ["yes", "Yeah!", "yep.", "OK", "okay", "Sure", "do it", "Có", "ừ", "được."])
    func acceptPhrases(_ text: String) {
        #expect(CoachReplyRouter.route(text) == .accept)
    }

    @Test(arguments: ["no", "Nope", "skip!", "not now", "Không", "bỏ qua"])
    func declinePhrases(_ text: String) {
        #expect(CoachReplyRouter.route(text) == .decline)
    }

    @Test func anythingElseIsARequest() {
        #expect(CoachReplyRouter.route("  yes and make the hook shorter ") == .request("yes and make the hook shorter"))
        #expect(CoachReplyRouter.route("a cozy 3 minute vlog") == .request("a cozy 3 minute vlog"))
    }
}

@Suite("Coach voice replies")
@MainActor
struct CoachUtteranceTests {
    private func editor(mode: CoachMode) -> EditorViewModel {
        let editor = EditorViewModel()
        var clip = Fixtures.clip(id: "a", start: 0, duration: 900, trimEnd: 300)
        clip.planSectionId = "s0"
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(id: "v1", clips: [clip])])
        editor.timelines = [editor.timeline]
        editor.activeTimelineId = editor.timeline.id
        editor.timeline.plan = EditPlan(brief: "", style: nil, trackId: "v1", sections: [PlanSection(id: "s0", title: "Food", targetSeconds: 5, hint: "")])
        editor.coachVoice = RecordingSpeaker()
        editor.coachMode = mode
        editor.coachModelProvider = { () throws(MetaModelError) -> any CoachModel in throw .missingAPIKey }
        return editor
    }

    @Test func holdToTalkIsIgnoredInPassiveMode() {
        let editor = editor(mode: .passive)
        editor.startCoachListening()
        #expect(!editor.coachListening)
    }

    @Test func sayingYesAppliesTheCurrentTip() {
        let editor = editor(mode: .active)
        editor.refreshCoachNudges()

        editor.handleCoachUtterance("Yes!")

        #expect(editor.clipFor(id: "a")?.durationFrames == 150)
    }

    @Test func sayingSkipDismissesTheCurrentTip() {
        let editor = editor(mode: .active)
        editor.refreshCoachNudges()

        editor.handleCoachUtterance("skip")

        #expect(editor.timeline.plan?.dismissedNudges == ["over:s0"])
        #expect(editor.clipFor(id: "a")?.durationFrames == 900)
    }

    @Test func answeringTheQuestionAloudPlansFromWhatWasSaid() async {
        let editor = editor(mode: .active)
        editor.timeline.plan = nil
        editor.mediaAssets.append(MediaAsset(id: "cat", url: URL(fileURLWithPath: "/tmp/cat.mov"), type: .video, name: "cat", duration: 4))
        editor.showCoachIfNeeded()

        editor.handleCoachUtterance("a quick cat reel")
        await editor.coachTask?.value

        #expect(editor.timeline.plan?.brief == "a quick cat reel")
    }
}
