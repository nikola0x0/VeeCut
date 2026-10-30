import Foundation
import Testing
@testable import PalmierPro

@Suite("AgentService - object mentions")
@MainActor
struct ObjectMentionTests {
    private func editorWithObject(named name: String = "Sky") -> (EditorViewModel, TrackedMask) {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [Fixtures.clip(id: "clip", start: 0, duration: 30)])])
        let mask = Fixtures.trackedMask(in: editor, label: name, presentAt: [0])
        editor.selectCanvasObject(clipId: "clip", maskId: mask.id)
        return (editor, mask)
    }

    @Test func taggingAnObjectOpensChatFocusesItAndInsertsOneToken() throws {
        let (editor, object) = editorWithObject(named: "Blue Sky")
        editor.agentPanelVisible = false

        editor.agentService.attachMention(forObject: object.id, clipId: "clip")
        editor.agentService.attachMention(forObject: object.id, clipId: "clip")

        let mention = try #require(editor.agentService.mentions.first)
        #expect(editor.agentService.mentions.count == 1)
        #expect(editor.agentService.draft == "@Blue-Sky ")
        #expect(mention.object == AgentObjectMention(maskId: object.id, clipId: "clip"))
        #expect(editor.agentPanelVisible)
        #expect(editor.agentService.inputFocusRequested)
    }

    @Test func objectsWithTheSameNameGetDistinctTokens() {
        let (editor, first) = editorWithObject()
        let second = Fixtures.trackedMask(in: editor, label: "Sky", presentAt: [0])

        editor.agentService.attachMention(forObject: first.id, clipId: "clip")
        editor.agentService.attachMention(forObject: second.id, clipId: "clip")

        #expect(editor.agentService.draft == "@Sky @Sky#\(second.id.prefix(6)) ")
    }

    @Test func taggingAnUnknownObjectChangesNothing() {
        let (editor, _) = editorWithObject()
        editor.agentService.attachMention(forObject: "missing", clipId: "clip")
        #expect(editor.agentService.mentions.isEmpty)
        #expect(editor.agentService.draft.isEmpty)
    }

    @Test func theAgentReceivesTheObjectsIds() throws {
        let (editor, object) = editorWithObject()
        editor.agentService.attachMention(forObject: object.id, clipId: "clip")

        let entry = try #require(AgentMentionContext.mentionEntries(editor.agentService.mentions, editor: editor).first)
        #expect(entry["kind"] as? String == "object")
        #expect(entry["maskId"] as? String == object.id)
        #expect(entry["clipId"] as? String == "clip")
        #expect(entry["name"] as? String == "Sky")
        #expect(AgentMentionContext.hint(editor.agentService.mentions, editor: editor).contains("region"))
    }

    @Test func atListsTheShelfsObjectsBeforeMedia() {
        let (editor, object) = editorWithObject()
        editor.importMediaAsset(MediaAsset(id: "sky-photo", url: URL(fileURLWithPath: "/tmp/sky.jpg"), type: .image, name: "Sky Photo", duration: 5))

        let all = MentionCandidate.candidates(query: "sky", tab: .all, editor: editor).map(\.id)
        #expect(all == [object.id, "sky-photo"])
        #expect(MentionCandidate.candidates(query: "", tab: .objects, editor: editor).map(\.id) == [object.id])
        #expect(MentionCandidate.candidates(query: "", tab: .image, editor: editor).map(\.id) == ["sky-photo"])
    }
}
