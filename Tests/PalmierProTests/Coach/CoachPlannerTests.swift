import Foundation
import Testing
@testable import PalmierPro

actor RecordingCoachModel: CoachModel {
    private(set) var requests: [(schemaName: String, parts: [MetaInputPart])] = []
    private var replies: [String]
    private let bySchema: [String: String]

    init(replies: [String]) {
        self.replies = replies
        bySchema = [:]
    }

    /// Answers each request by its schema name ("footage", "ideas" or "plan"), however the calls interleave.
    init(bySchema: [String: String]) {
        replies = []
        self.bySchema = bySchema
    }

    func structuredResponse(model: String, instructions: String, parts: [MetaInputPart], schemaName: String, schemaJSON: Data) async throws -> String {
        requests.append((schemaName, parts))
        if let reply = bySchema[schemaName] { return reply }
        return replies.isEmpty ? #"{"clips":[]}"# : replies.removeFirst()
    }

    func count(_ schemaName: String) -> Int { requests.filter { $0.schemaName == schemaName }.count }
}

@Suite("Coach planner")
struct CoachPlannerTests {
    private static func note(_ id: String, duration: Double = 20) -> FootageNote {
        FootageNote(assetId: id, fileKey: "k", durationSeconds: duration, hasSpeech: false, labels: ["food"], summary: nil,
                    moments: [PlanMoment(assetId: id, start: 1, end: 3, note: "food")])
    }

    private static func raw(_ json: String) throws -> RawPlan {
        try JSONDecoder().decode(RawPlan.self, from: Data(json.utf8))
    }

    @MainActor @Test func validationDropsUnknownAssetsAndOutOfRangeMoments() throws {
        let raw = try Self.raw("""
        {"sections":[
          {"title":"Hook","targetSeconds":8,"hint":"Best shot","suggestions":[
            {"assetId":"a","start":2,"end":6,"note":"keep"},
            {"assetId":"ghost","start":0,"end":3,"note":"unknown"},
            {"assetId":"a","start":18,"end":25,"note":"past the end"},
            {"assetId":"a","start":4,"end":4.5,"note":"too short"}]},
          {"title":"Broken","targetSeconds":0,"hint":"","suggestions":[]}]}
        """)

        let plan = try CoachPlanner.validated(raw, notes: [Self.note("a")], trackId: "v1", brief: "trip", style: .reel)

        #expect(plan.sections.map(\.title) == ["Hook"])
        #expect(plan.sections[0].suggestions == [PlanMoment(assetId: "a", start: 2, end: 6, note: "keep")])
        #expect(plan.trackId == "v1")
        #expect(plan.style == .reel)
    }

    @MainActor @Test func anEmptyPlanIsAFailure() throws {
        let raw = try Self.raw(#"{"sections":[{"title":"X","targetSeconds":-1,"hint":"","suggestions":[]}]}"#)
        #expect(throws: CoachFailure.emptyPlan) {
            try CoachPlanner.validated(raw, notes: [Self.note("a")], trackId: "v1", brief: "", style: nil)
        }
    }

    @MainActor
    @Test(arguments: PlanStyle.allCases)
    func templatesSplitTheTotalByStyle(style: PlanStyle) {
        let plan = PlanTemplates.plan(style, totalSeconds: 180, trackId: "v1")
        #expect(abs(plan.sections.reduce(0) { $0 + $1.targetSeconds } - 180) <= 0.5)
        #expect(plan.style == style)
        #expect(plan.sections.allSatisfy { $0.suggestions.isEmpty && !$0.title.isEmpty })
    }

    @Test func readerRequestCarriesSheetsAndIds() async throws {
        let url = try await FixtureVideo.write(scenes: [.init(rgb: (200, 0, 0), seconds: 2), .init(rgb: (0, 0, 200), seconds: 2)])
        defer { try? FileManager.default.removeItem(at: url) }
        let model = RecordingCoachModel(replies: [#"""
        {"clips":[{"assetId":"a","summary":"A red room turns blue","moments":[{"start":0.5,"end":2,"note":"red"},{"start":3,"end":9,"note":"past the end"}]},
                  {"assetId":"ghost","summary":"x","moments":[]}]}
        """#])

        let read = try await FootageReader.read([Self.note("a", duration: 4), Self.note("b", duration: 4)], urls: ["a": url, "b": url], client: model)

        let requests = await model.requests
        #expect(requests.count == 1)
        let texts = requests[0].parts.compactMap { if case .text(let t) = $0 { t } else { nil } }
        let images = requests[0].parts.filter { if case .jpeg = $0 { true } else { false } }
        #expect(texts.contains { $0.contains("assetId=a duration=4") })
        #expect(texts.contains { $0.contains("assetId=b duration=4") })
        #expect(images.count == 2)
        let a = try #require(read.first { $0.assetId == "a" })
        #expect(a.summary == "A red room turns blue")
        #expect(a.moments == [PlanMoment(assetId: "a", start: 0.5, end: 2, note: "red")])
        let b = try #require(read.first { $0.assetId == "b" })
        #expect(b.summary == "")
        #expect(b.moments == Self.note("b").moments)
    }

    @Test func aClipTheReaderSeesTalkingToCameraIsMarkedTalking() async throws {
        let url = try await FixtureVideo.write(scenes: [.init(rgb: (200, 0, 0), seconds: 2)])
        defer { try? FileManager.default.removeItem(at: url) }
        let model = RecordingCoachModel(replies: [#"""
        {"clips":[{"assetId":"a","summary":"Me in a café","talksToCamera":true,"moments":[]},
                  {"assetId":"b","summary":"A street","talksToCamera":false,"moments":[]}]}
        """#])

        let read = try await FootageReader.read([Self.note("a", duration: 2), Self.note("b", duration: 2)], urls: ["a": url, "b": url], client: model)

        #expect(read.first { $0.assetId == "a" }?.wantsTranscript == true)
        #expect(read.first { $0.assetId == "b" }?.wantsTranscript == false)
    }

    @Test func readerBatchesEightClipsPerRequest() async throws {
        let url = try await FixtureVideo.write(scenes: [.init(rgb: (0, 200, 0), seconds: 2)])
        defer { try? FileManager.default.removeItem(at: url) }
        let notes = (0..<9).map { Self.note("c\($0)", duration: 2) }
        let model = RecordingCoachModel(replies: [])

        let read = try await FootageReader.read(notes, urls: Dictionary(uniqueKeysWithValues: notes.map { ($0.assetId, url) }), client: model)

        #expect(await model.requests.count == 2)
        #expect(read.count == 9)
        #expect(read.allSatisfy { $0.summary == "" })
    }
}

/// Opt in with VEECUT_LIVE_MUSE=1 and MODEL_API_KEY. Plans from two notes with Muse Spark.
@Suite("Live — Muse Spark planning", .enabled(if: ProcessInfo.processInfo.environment["VEECUT_LIVE_MUSE"] == "1"))
struct LiveCoachPlannerTests {
    @MainActor @Test func liveMuseSparkPlansFromNotes() async throws {
        let key = try #require(ProcessInfo.processInfo.environment["MODEL_API_KEY"])
        let notes = [
            FootageNote(assetId: "cafe", fileKey: "k", durationSeconds: 40, hasSpeech: false, labels: ["coffee or café"], summary: "Latte art in a wooden café",
                        moments: [PlanMoment(assetId: "cafe", start: 3, end: 9, note: "pouring latte")]),
            FootageNote(assetId: "night", fileKey: "k", durationSeconds: 60, hasSpeech: true, labels: ["street at night"], summary: "Walking a lantern street at night",
                        moments: [PlanMoment(assetId: "night", start: 10, end: 18, note: "lanterns overhead")]),
        ]
        let thinking = ThinkingRecorder()
        let raw = try await CoachPlanner.plan(brief: "a cozy 1 minute Dalat vlog", style: .travelVlog, notes: notes, placed: [], client: MetaModelClient(apiKey: key)) { delta in
            await thinking.add(delta)
        }
        let plan = try CoachPlanner.validated(raw, notes: notes, trackId: "v1", brief: "", style: .travelVlog)
        #expect(!plan.sections.isEmpty)
        #expect(await !thinking.text.isEmpty)
    }

    @Test func liveMuseSparkRecommendsIdeasFromNotes() async throws {
        let key = try #require(ProcessInfo.processInfo.environment["MODEL_API_KEY"])
        let notes = [
            FootageNote(assetId: "cafe", fileKey: "k", durationSeconds: 40, hasSpeech: false, labels: ["coffee or café"], summary: "Latte art in a wooden café in Dalat", moments: []),
            FootageNote(assetId: "night", fileKey: "k", durationSeconds: 60, hasSpeech: true, labels: ["street at night"], summary: "Walking a lantern-lit night market", moments: []),
        ]
        let recommendation = try await CoachRecommender.recommend(notes, client: MetaModelClient(apiKey: key))
        #expect(!recommendation.summary.isEmpty)
        #expect(!recommendation.ideas.isEmpty)
    }
}

actor ThinkingRecorder {
    private(set) var text = ""
    func add(_ delta: String) { text += delta }
}
