import Foundation
import Testing
@testable import PalmierPro

/// Suspends inside the gated call ("plan" by default) until the test releases a reply; other calls answer at once.
actor GatedCoachModel: CoachModel {
    private let gated: String
    private var called: CheckedContinuation<Void, Never>?
    private var reply: CheckedContinuation<String, Never>?
    private var wasCalled = false

    init(gating schemaName: String = "plan") { gated = schemaName }

    func structuredResponse(model: String, instructions: String, parts: [MetaInputPart], schemaName: String, schemaJSON: Data) async throws -> String {
        if schemaName != gated {
            switch schemaName {
            case "footage": return #"{"clips":[]}"#
            case "ideas": return #"{"summary":"","ideas":[]}"#
            default: return CoachSessionTests.planReply
            }
        }
        wasCalled = true
        called?.resume()
        called = nil
        return await withCheckedContinuation { reply = $0 }
    }

    func waitForCall() async {
        guard !wasCalled else { return }
        await withCheckedContinuation { called = $0 }
    }

    func release(_ text: String) {
        reply?.resume(returning: text)
        reply = nil
    }
}

@Suite("Coach session")
@MainActor
struct CoachSessionTests {
    nonisolated static let planReply = #"{"sections":[{"title":"Hook","targetSeconds":5,"hint":"Best shot","suggestions":[{"assetId":"cat","start":0,"end":1.5,"note":"cat"}]}]}"#
    private let undoManager = UndoManager()

    private func editor(assets: [(String, ClipType)] = [("cat", .video)], model: (any CoachModel)? = nil) -> EditorViewModel {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(id: "v1"), Fixtures.audioTrack(id: "a1")])
        editor.timelines = [editor.timeline]
        editor.activeTimelineId = editor.timeline.id
        editor.undo.attach(undoManager)
        for (id, type) in assets {
            editor.mediaAssets.append(MediaAsset(id: id, url: URL(fileURLWithPath: "/tmp/\(id).mov"), type: type, name: id, duration: 4))
        }
        editor.coachModelProvider = { () throws(MetaModelError) -> any CoachModel in
            guard let model else { throw .missingAPIKey }
            return model
        }
        return editor
    }

    private func readNote(_ id: String, url: URL) -> FootageNote {
        FootageNote(assetId: id, fileKey: EmbeddingStore.key(for: url) ?? "", durationSeconds: 4, hasSpeech: false, labels: ["animal"], summary: "a cat", moments: [])
    }

    @Test func coachAsksOnlyWhenThereIsVideoAndNoPlan() {
        let empty = editor(assets: [])
        empty.showCoachIfNeeded()
        #expect(empty.coach == .hidden)

        let audioOnly = editor(assets: [("song", .audio), ("photo", .image)])
        audioOnly.showCoachIfNeeded()
        #expect(audioOnly.coach == .hidden)

        let video = editor()
        video.showCoachIfNeeded()
        guard case .asking(let overview) = video.coach else { Issue.record("expected the coach to ask"); return }
        #expect(overview.hasPrefix("1 clips"))

        video.setPlan(PlanTemplates.plan(.reel, trackId: "v1"), actionName: "Make Plan")
        video.showCoachIfNeeded()
        #expect(video.coach == .hidden)
    }

    @Test func submittingABriefReadsUnreadNotesOnceThenPlans() async throws {
        let url = try await FixtureVideo.write(scenes: [.init(rgb: (200, 0, 0), seconds: 4)])
        defer { try? FileManager.default.removeItem(at: url) }
        let model = RecordingCoachModel(bySchema: [
            "footage": #"{"clips":[{"assetId":"cat","summary":"a cat","moments":[]}]}"#,
            "ideas": #"{"summary":"A cat","ideas":[]}"#,
            "plan": Self.planReply,
        ])
        let editor = editor(assets: [], model: model)
        editor.mediaAssets.append(MediaAsset(id: "cat", url: url, type: .video, name: "cat", duration: 4))

        editor.submitBrief("a cat vlog", style: nil)
        await editor.coachTask?.value

        #expect(await model.count("footage") == 1)
        #expect(await model.count("plan") == 1)
        #expect(editor.footageNotes["cat"]?.summary == "a cat")
        #expect(editor.timeline.plan?.sections.map(\.title) == ["Hook"])
        #expect(editor.timeline.plan?.brief == "a cat vlog")
        #expect(editor.coach == .hidden)

        editor.askForPlan()
        editor.submitBrief("shorter", style: .reel)
        await editor.coachTask?.value
        #expect(await model.count("footage") == 1)
        #expect(await model.count("plan") == 2)
    }

    @Test func withoutAKeyTheStyleTemplateIsApplied() async {
        let editor = editor()

        editor.submitBrief("anything", style: .reel)
        await editor.coachTask?.value

        #expect(editor.timeline.plan?.sections.count == 3)
        #expect(editor.timeline.plan?.style == .reel)
        #expect(editor.coach == .hidden)
    }

    @Test func cancellingLeavesNoPlanAndNoUndo() async throws {
        let url = try await FixtureVideo.write(scenes: [.init(rgb: (0, 200, 0), seconds: 4)])
        defer { try? FileManager.default.removeItem(at: url) }
        let model = GatedCoachModel()
        let editor = editor(assets: [], model: model)
        editor.mediaAssets.append(MediaAsset(id: "cat", url: url, type: .video, name: "cat", duration: 4))
        editor.footageNotes["cat"] = readNote("cat", url: url)

        editor.submitBrief("trip", style: nil)
        await model.waitForCall()
        #expect(editor.coach == .planning)
        editor.cancelCoach()
        await model.release(Self.planReply)
        await editor.coachTask?.value

        #expect(editor.timeline.plan == nil)
        #expect(!undoManager.canUndo)
        guard case .asking = editor.coach else { Issue.record("expected the coach to ask again"); return }
    }

    @Test func aTimelineClosedDuringPlanningGetsNoPlan() async throws {
        let url = try await FixtureVideo.write(scenes: [.init(rgb: (0, 0, 200), seconds: 4)])
        defer { try? FileManager.default.removeItem(at: url) }
        let model = GatedCoachModel()
        let editor = editor(assets: [], model: model)
        editor.mediaAssets.append(MediaAsset(id: "cat", url: url, type: .video, name: "cat", duration: 4))
        editor.footageNotes["cat"] = readNote("cat", url: url)
        let original = editor.activeTimelineId

        editor.submitBrief("trip", style: nil)
        await model.waitForCall()
        editor.createTimeline()
        editor.deleteTimeline(original)
        await model.release(Self.planReply)
        await editor.coachTask?.value

        #expect(editor.timelines.allSatisfy { $0.plan == nil })
    }

    @Test func dismissedCoachStaysHiddenForThatTimeline() {
        let editor = editor()
        editor.showCoachIfNeeded()
        let first = editor.activeTimelineId

        editor.dismissCoach()
        editor.showCoachIfNeeded()
        #expect(editor.coach == .hidden)

        editor.createTimeline()
        guard case .asking = editor.coach else { Issue.record("expected the coach on the new timeline"); return }

        editor.activateTimeline(first)
        #expect(editor.coach == .hidden)
        editor.askForPlan()
        guard case .asking = editor.coach else { Issue.record("expected the coach when asked"); return }
    }

    @Test func cancellingWhileFootageIsStillBeingReadReturnsAtOnce() async throws {
        let url = try await FixtureVideo.write(scenes: [.init(rgb: (10, 200, 60), seconds: 4)])
        defer { try? FileManager.default.removeItem(at: url) }
        let model = GatedCoachModel(gating: "footage")
        let editor = editor(assets: [], model: model)
        editor.mediaAssets.append(MediaAsset(id: "cat", url: url, type: .video, name: "cat", duration: 4))

        let planning = editor.submitBrief("trip", style: nil)
        await model.waitForCall()
        editor.cancelCoach()
        let result = await planning.value

        #expect(result == .failure(.cancelled))
        #expect(editor.timeline.plan == nil)
        await model.release(#"{"clips":[]}"#)
        await editor.footageReadTask?.value
    }

    @Test func aPlanTheAgentStartedCanBeCancelledFromTheCard() async throws {
        let url = try await FixtureVideo.write(scenes: [.init(rgb: (60, 10, 200), seconds: 4)])
        defer { try? FileManager.default.removeItem(at: url) }
        let model = GatedCoachModel()
        let editor = editor(assets: [], model: model)
        editor.mediaAssets.append(MediaAsset(id: "cat", url: url, type: .video, name: "cat", duration: 4))
        editor.footageNotes["cat"] = readNote("cat", url: url)
        let executor = ToolExecutor(editor: editor, exportQueue: ExportQueue())

        let call = Task { await executor.execute(name: "make_plan", args: ["brief": "trip"]) }
        await model.waitForCall()
        #expect(editor.coachTask != nil)
        editor.cancelCoach()
        await model.release(Self.planReply)
        let result = await call.value

        #expect(result.isError)
        #expect(editor.timeline.plan == nil)
        #expect(editor.coach != .planning)
    }

    @Test func closingTheProjectStopsBackgroundReading() async throws {
        let url = try await FixtureVideo.write(scenes: [.init(rgb: (200, 200, 0), seconds: 4)])
        defer { try? FileManager.default.removeItem(at: url) }
        let model = GatedCoachModel(gating: "footage")
        let editor = editor(assets: [], model: model)
        editor.mediaAssets.append(MediaAsset(id: "cat", url: url, type: .video, name: "cat", duration: 4))
        var note = readNote("cat", url: url)
        note.summary = nil
        editor.footageNotes["cat"] = note

        editor.readFootageInBackground()
        let reading = try #require(editor.footageReadTask)
        await model.waitForCall()
        editor.tearDownCoach()
        await model.release(#"{"clips":[{"assetId":"cat","summary":"late","moments":[]}]}"#)
        await reading.value

        #expect(editor.footageNotes["cat"]?.summary == nil)
        #expect(editor.footageRecommendTask == nil)
    }

    @Test func readingFootageAsksForTheProjectToBeSaved() async throws {
        let url = try await FixtureVideo.write(scenes: [.init(rgb: (0, 90, 90), seconds: 4)])
        defer { try? FileManager.default.removeItem(at: url) }
        let model = RecordingCoachModel(bySchema: ["footage": #"{"clips":[{"assetId":"cat","summary":"a cat","moments":[]}]}"#, "ideas": #"{"summary":"Cats","ideas":[]}"#])
        let editor = editor(assets: [], model: model)
        editor.mediaAssets.append(MediaAsset(id: "cat", url: url, type: .video, name: "cat", duration: 4))
        var note = readNote("cat", url: url)
        note.summary = nil
        editor.footageNotes["cat"] = note
        var checkpoints = 0
        editor.onProjectCheckpointRequired = { checkpoints += 1 }

        editor.readFootageInBackground()
        await editor.footageReadTask?.value
        await editor.footageRecommendTask?.value

        #expect(checkpoints >= 2)
    }
}
