import Foundation
import Testing
@testable import PalmierPro

@Suite("Footage recommendations")
@MainActor
struct FootageRecommendationTests {
    private static let readReply = #"{"clips":[{"assetId":"cat","summary":"A cat on a café windowsill","moments":[]}]}"#
    private static let ideasReply = #"""
    {"summary":"A cozy café day with a cat","ideas":[
      {"title":"Café Cat Vlog","style":"travelVlog","targetSeconds":120,"pitch":"A slow morning with the café cat"},
      {"title":"Cat Reel","style":"reel","targetSeconds":20,"pitch":"The cat's best jumps"},
      {"title":"Bad","style":"opera","targetSeconds":30,"pitch":"unknown style"},
      {"title":"Endless","style":"reel","targetSeconds":-5,"pitch":"bad length"}]}
    """#

    private func editor(url: URL, model: (any CoachModel)?) -> EditorViewModel {
        let editor = EditorViewModel()
        editor.mediaAssets.append(MediaAsset(id: "cat", url: url, type: .video, name: "cat", duration: 4))
        editor.coachModelProvider = { () throws(MetaModelError) -> any CoachModel in
            guard let model else { throw .missingAPIKey }
            return model
        }
        return editor
    }

    private func unreadNote(url: URL) -> FootageNote {
        FootageNote(assetId: "cat", fileKey: EmbeddingStore.key(for: url) ?? "", durationSeconds: 4, hasSpeech: false, labels: ["animal"], summary: nil, moments: [])
    }

    @Test func newFootageIsReadInTheBackgroundOnceThenRecommended() async throws {
        let url = try await FixtureVideo.write(scenes: [.init(rgb: (200, 120, 0), seconds: 4)])
        defer { try? FileManager.default.removeItem(at: url) }
        let model = RecordingCoachModel(bySchema: ["footage": Self.readReply, "ideas": Self.ideasReply])
        let editor = editor(url: url, model: model)
        editor.footageNotes["cat"] = unreadNote(url: url)

        editor.readFootageInBackground()
        await editor.footageReadTask?.value
        await editor.footageRecommendTask?.value

        #expect(editor.footageNotes["cat"]?.summary == "A cat on a café windowsill")
        let recommendation = try #require(editor.footageRecommendation)
        #expect(recommendation.summary == "A cozy café day with a cat")
        #expect(recommendation.ideas.map(\.title) == ["Café Cat Vlog", "Cat Reel"])
        #expect(recommendation.assetIds == ["cat"])

        editor.readFootageInBackground()
        await editor.footageReadTask?.value
        await editor.footageRecommendTask?.value
        #expect(await model.count("footage") == 1)
        #expect(await model.count("ideas") == 1)
    }

    @Test func withoutAKeyNothingIsReadOrRecommended() async throws {
        let url = try await FixtureVideo.write(scenes: [.init(rgb: (0, 120, 200), seconds: 4)])
        defer { try? FileManager.default.removeItem(at: url) }
        let editor = editor(url: url, model: nil)
        editor.footageNotes["cat"] = unreadNote(url: url)

        editor.readFootageInBackground()
        await editor.footageReadTask?.value
        await editor.footageRecommendTask?.value

        #expect(editor.footageNotes["cat"]?.summary == nil)
        #expect(editor.footageRecommendation == nil)
    }

    @Test func recommendationIsRedoneWhenTheFootageChanges() async throws {
        let url = try await FixtureVideo.write(scenes: [.init(rgb: (120, 0, 200), seconds: 4)])
        defer { try? FileManager.default.removeItem(at: url) }
        let model = RecordingCoachModel(bySchema: ["ideas": Self.ideasReply])
        let editor = editor(url: url, model: model)
        var note = unreadNote(url: url)
        note.summary = "A cat"
        editor.footageNotes["cat"] = note
        editor.footageRecommendation = FootageRecommendation(summary: "Old", ideas: [], assetIds: ["cat", "deleted"])

        editor.readFootageInBackground()
        await editor.footageReadTask?.value
        await editor.footageRecommendTask?.value

        #expect(await model.count("footage") == 0)
        #expect(await model.count("ideas") == 1)
        #expect(editor.footageRecommendation?.summary == "A cozy café day with a cat")
    }

    private static let bothReadReply = #"{"clips":[{"assetId":"cat","summary":"A cat","talksToCamera":false,"moments":[]},{"assetId":"dog","summary":"A dog","talksToCamera":false,"moments":[]}]}"#

    @Test func footageQueuedDuringAReadIsRecommendedOnceWithEveryClip() async throws {
        let url = try await FixtureVideo.write(scenes: [.init(rgb: (60, 160, 60), seconds: 4)])
        defer { try? FileManager.default.removeItem(at: url) }
        let model = HeldCoachModel(holding: "footage", bySchema: ["footage": Self.bothReadReply, "ideas": Self.ideasReply])
        let editor = editor(url: url, model: model)
        editor.footageNotes["cat"] = unreadNote(url: url)
        editor.readFootageInBackground()
        await model.waitUntilGated()

        editor.mediaAssets.append(MediaAsset(id: "dog", url: url, type: .video, name: "dog", duration: 4))
        var dog = unreadNote(url: url)
        dog.assetId = "dog"
        editor.footageNotes["dog"] = dog
        editor.readFootageInBackground()
        await model.open()
        while let task = editor.footageReadTask ?? editor.footageRecommendTask { await task.value }

        #expect(await model.count("ideas") == 1)
        #expect(editor.footageRecommendation?.assetIds == ["cat", "dog"])
    }

    @Test func aRecommendationOutdatedWhileItRanIsRedone() async throws {
        let url = try await FixtureVideo.write(scenes: [.init(rgb: (160, 60, 60), seconds: 4)])
        defer { try? FileManager.default.removeItem(at: url) }
        let model = HeldCoachModel(holding: "ideas", bySchema: ["ideas": Self.ideasReply])
        let editor = editor(url: url, model: model)
        var cat = unreadNote(url: url)
        cat.summary = "A cat"
        editor.footageNotes["cat"] = cat
        editor.readFootageInBackground()
        await model.waitUntilGated()

        editor.mediaAssets.append(MediaAsset(id: "dog", url: url, type: .video, name: "dog", duration: 4))
        var dog = cat
        dog.assetId = "dog"
        editor.footageNotes["dog"] = dog
        editor.readFootageInBackground()
        await model.open()
        while let task = editor.footageReadTask ?? editor.footageRecommendTask { await task.value }

        #expect(editor.footageRecommendation?.assetIds == ["cat", "dog"])
    }

    @Test func pickingAnIdeaPlansWithItsStyleAndBrief() async throws {
        let url = try await FixtureVideo.write(scenes: [.init(rgb: (0, 200, 120), seconds: 4)])
        defer { try? FileManager.default.removeItem(at: url) }
        let editor = editor(url: url, model: nil)
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(id: "v1")])
        editor.timelines = [editor.timeline]
        editor.activeTimelineId = editor.timeline.id

        editor.startIdea(PlanIdea(title: "Cat Reel", style: .reel, targetSeconds: 20, pitch: "The cat's best jumps"))
        await editor.coachTask?.value

        #expect(editor.timeline.plan?.style == .reel)
        #expect(editor.timeline.plan?.brief == "Cat Reel: The cat's best jumps (about 20 seconds)")
    }

    @Test func talkingClipsAreTranscribedBeforeReadingAndOthersAreNot() async throws {
        let url = try await FixtureVideo.write(scenes: [.init(rgb: (90, 90, 200), seconds: 4)])
        defer { try? FileManager.default.removeItem(at: url) }
        let model = RecordingCoachModel(bySchema: ["footage": Self.readReply, "ideas": Self.ideasReply])
        let editor = editor(url: url, model: model)
        editor.mediaAssets.append(MediaAsset(id: "street", url: url, type: .video, name: "street", duration: 4))
        var talking = unreadNote(url: url)
        talking.labels = ["person talking to the camera"]
        editor.footageNotes["cat"] = talking
        var quiet = unreadNote(url: url)
        quiet.assetId = "street"
        quiet.labels = ["city street"]
        editor.footageNotes["street"] = quiet
        let asked = TranscriptRequests()
        editor.footageTranscriptSource = { url in
            await asked.add(url)
            return [(start: 1.5, text: "This is the best coffee in Dalat")]
        }

        editor.readFootageInBackground()
        await editor.footageReadTask?.value

        #expect(await asked.count == 1)
        #expect(editor.footageNotes["cat"]?.transcript == "[1.5] This is the best coffee in Dalat")
        #expect(editor.footageNotes["street"]?.transcript == nil)
        let parts = await model.requests.first { $0.schemaName == "footage" }?.parts ?? []
        let texts: [String] = parts.compactMap { part in
            if case .text(let text) = part { return text }
            return nil
        }
        #expect(texts.contains { $0.contains("This is the best coffee in Dalat") })
    }
}

/// Holds the first request of one schema until opened, so a test can change state while it is in flight.
actor HeldCoachModel: CoachModel {
    private let gating: String
    private let bySchema: [String: String]
    private var counts: [String: Int] = [:]
    private var gated = false
    private var opened = false
    private var gatedWaiter: CheckedContinuation<Void, Never>?
    private var openWaiter: CheckedContinuation<Void, Never>?

    init(holding gating: String, bySchema: [String: String]) {
        self.gating = gating
        self.bySchema = bySchema
    }

    func structuredResponse(model: String, instructions: String, parts: [MetaInputPart], schemaName: String, schemaJSON: Data) async throws -> String {
        counts[schemaName, default: 0] += 1
        if schemaName == gating, counts[schemaName] == 1 {
            gated = true
            gatedWaiter?.resume()
            gatedWaiter = nil
            if !opened { await withCheckedContinuation { openWaiter = $0 } }
        }
        return bySchema[schemaName] ?? #"{"clips":[]}"#
    }

    func waitUntilGated() async {
        if !gated { await withCheckedContinuation { gatedWaiter = $0 } }
    }

    func open() {
        opened = true
        openWaiter?.resume()
        openWaiter = nil
    }

    func count(_ schemaName: String) -> Int { counts[schemaName, default: 0] }
}

actor TranscriptRequests {
    private(set) var count = 0
    func add(_ url: URL) { count += 1 }
}
