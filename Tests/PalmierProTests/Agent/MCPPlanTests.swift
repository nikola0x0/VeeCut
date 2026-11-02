import Foundation
import MCP
import Testing
@testable import PalmierPro

@Suite("MCP — plan", .serialized)
@MainActor
struct MCPPlanTests {
    private let undoManager = UndoManager()

    private func plan() -> EditPlan {
        EditPlan(brief: "trip", style: nil, trackId: "v1", sections: [
            PlanSection(id: "s0", title: "Hook", targetSeconds: 5, hint: "Best shot",
                        suggestions: [PlanMoment(assetId: "cat", start: 1, end: 3, note: "cat jumps")]),
            PlanSection(id: "s1", title: "Food", targetSeconds: 20, hint: ""),
        ])
    }

    private func withClient(planned: Bool = true, assets: [MediaAsset]? = nil, _ body: (ToolHarness, Client) async throws -> Void) async throws {
        let harness = ToolHarness(timeline: Fixtures.timeline(tracks: [Fixtures.videoTrack(id: "v1"), Fixtures.audioTrack(id: "a1")]))
        harness.editor.undo.attach(undoManager)
        let cat = MediaAsset(id: "cat", url: URL(fileURLWithPath: "/tmp/cat.mov"), type: .video, name: "cat", duration: 20)
        cat.hasAudio = false
        harness.editor.mediaAssets = assets ?? [cat]
        harness.editor.coachModelProvider = { () throws(MetaModelError) -> any CoachModel in throw .missingAPIKey }
        if planned {
            harness.editor.setPlan(plan(), actionName: "Make Plan")
            undoManager.removeAllActions()
        }
        let server = Server(name: "plan-test", version: "1.0.0", capabilities: .init(tools: .init(listChanged: false)))
        await MCPService.registerTools(on: server, executor: harness.executor)
        let transports = await InMemoryTransport.createConnectedPair()
        let client = Client(name: "plan-test", version: "1.0.0")
        try await server.start(transport: transports.server)
        do {
            _ = try await client.connect(transport: transports.client)
            try await body(harness, client)
        } catch {
            await server.stop()
            await client.disconnect()
            throw error
        }
        await server.stop()
        await client.disconnect()
    }

    @Test func getPlanShowsPaceAndMusic() async throws {
        try await withClient { harness, client in
            var plan = harness.editor.timeline.plan!
            plan.sections[0].pace = .peak
            plan.music = PlanMusic(assetId: "song", beatSeconds: 0.5, drop: 16)
            harness.editor.timeline.plan = plan

            let read = try json(try await client.callTool(name: "get_plan").content)
            let readPlan = try #require(read["plan"] as? [String: Any])
            let sections = try #require(readPlan["sections"] as? [[String: Any]])
            #expect(sections[0]["pace"] as? String == "peak")
            #expect(sections[1]["pace"] is NSNull)
            let music = try #require(readPlan["music"] as? [String: Any])
            #expect(music["beatSeconds"] as? Double == 0.5)
            #expect(music["dropSeconds"] as? Double == 16)
        }
    }

    @Test func planToolsAreDiscoverable() async throws {
        try await withClient { _, client in
            let names = Set(try await client.listTools().tools.map(\.name))
            #expect(names.isSuperset(of: ["get_plan", "make_plan", "edit_plan", "add_to_section"]))
        }
    }

    @Test func addToSectionPlacesTheMomentAndGetPlanShowsProgress() async throws {
        try await withClient { harness, client in
            let before = try json(try await client.callTool(name: "get_plan").content)
            let sections = try #require((before["plan"] as? [String: Any])?["sections"] as? [[String: Any]])
            #expect(sections.map { $0["sectionId"] as? String } == ["s0", "s1"])
            #expect((sections[0]["suggestions"] as? [[String: Any]])?.first?["mediaRef"] as? String == "cat")
            let ghost = (before["suggestedTimeline"] as? [[String: Any]])?.first
            #expect(ghost?["sectionId"] as? String == "s0")
            #expect(ghost?["mediaRef"] as? String == "cat")
            #expect(ghost?["startFrame"] as? Int == 0)
            let hookTip = (before["tips"] as? [[String: Any]])?.first { $0["tipId"] as? String == "hook:s0" }
            #expect(hookTip?["kind"] as? String == "hookCandidate")
            #expect(hookTip?["mediaRef"] as? String == "cat")

            let result = try await client.callTool(name: "add_to_section", arguments: [
                "sectionId": .string("s0"), "mediaRef": .string("cat"), "startSeconds": .double(2), "endSeconds": .double(5),
            ])
            #expect(result.isError != true)

            let after = try json(try await client.callTool(name: "get_plan").content)
            #expect((after["tips"] as? [[String: Any]])?.contains { $0["tipId"] as? String == "hook:s0" } == false)
            let hook = try #require(((after["plan"] as? [String: Any])?["sections"] as? [[String: Any]])?.first)
            #expect(hook["actualSeconds"] as? Double == 3)
            #expect(hook["filled"] as? Bool == false)
            let clips = try #require(harness.editor.timeline.tracks.first { $0.id == "v1" }?.clips)
            #expect(clips.count == 1)
            #expect(clips.first?.planSectionId == "s0")
            #expect(clips.first?.trimStartFrame == 60)

            _ = try await client.callTool(name: "undo")
            #expect(harness.editor.timeline.tracks.first { $0.id == "v1" }?.clips.isEmpty == true)
        }
    }

    @Test func editPlanAppliesAllOperationsAsOneUndoStep() async throws {
        try await withClient { harness, client in
            let result = try await client.callTool(name: "edit_plan", arguments: ["operations": .array([
                .object(["op": .string("rename"), "sectionId": .string("s0"), "title": .string("Opening")]),
                .object(["op": .string("setTarget"), "sectionId": .string("s1"), "seconds": .double(30)]),
                .object(["op": .string("add"), "afterSectionId": .string("s0"), "title": .string("Night"), "seconds": .double(15)]),
                .object(["op": .string("move"), "sectionId": .string("s1"), "offset": .int(-2)]),
            ])])
            #expect(result.isError != true)
            let plan = try #require(harness.editor.timeline.plan)
            #expect(plan.sections.map(\.title) == ["Food", "Opening", "Night"])
            #expect(plan.sections[0].targetSeconds == 30)
            #expect(plan.sections[2].targetSeconds == 15)
            let receipt = try json(result.content)
            #expect((receipt["addedSectionIds"] as? [String])?.first == plan.sections[2].id)

            _ = try await client.callTool(name: "undo")
            #expect(harness.editor.timeline.plan == self.plan())
        }
    }

    @Test(arguments: [
        ("add_to_section", ["sectionId": .string("nope"), "mediaRef": .string("cat")], "sectionId"),
        ("add_to_section", ["sectionId": .string("s0"), "mediaRef": .string("cat"), "startSeconds": .double(5), "endSeconds": .double(40)], "range"),
        ("add_to_section", ["sectionId": .string("s0"), "mediaRef": .string("ghost")], "not found"),
        ("edit_plan", ["operations": .array([.object(["op": .string("explode"), "sectionId": .string("s0")])])], "op"),
        ("edit_plan", ["operations": .array([
            .object(["op": .string("rename"), "sectionId": .string("s0"), "title": .string("Opening")]),
            .object(["op": .string("setTarget"), "sectionId": .string("s1"), "seconds": .double(0)]),
        ])], "operations[1]"),
    ] as [(String, [String: Value], String)])
    func invalidRequestsAreRefusedWithoutChanges(tool: String, arguments: [String: Value], message: String) async throws {
        try await withClient { harness, client in
            let result = try await client.callTool(name: tool, arguments: arguments)
            #expect(result.isError == true)
            #expect(try text(result.content).contains(message))
            #expect(harness.editor.timeline.plan == plan())
            #expect(harness.editor.timeline.tracks.allSatisfy { $0.clips.isEmpty })
            #expect(!undoManager.canUndo)
        }
    }

    @Test func makePlanWithoutAKeyUsesTheTemplate() async throws {
        try await withClient(planned: false) { harness, client in
            harness.editor.footageRecommendation = FootageRecommendation(
                summary: "A café day with a cat",
                ideas: [PlanIdea(title: "Cat Reel", style: .reel, targetSeconds: 20, pitch: "The cat's best jumps")],
                assetIds: ["cat"]
            )
            let empty = try json(try await client.callTool(name: "get_plan").content)
            #expect(empty["plan"] is NSNull)
            #expect(empty["footageSummary"] as? String == "A café day with a cat")
            #expect((empty["ideas"] as? [[String: Any]])?.first?["style"] as? String == "reel")

            let result = try await client.callTool(name: "make_plan", arguments: ["brief": .string("a quick reel"), "style": .string("reel")])
            #expect(result.isError != true)
            #expect(try json(result.content)["source"] as? String == "template")
            #expect(harness.editor.timeline.plan?.sections.count == 3)
            #expect(harness.editor.timeline.plan?.brief == "a quick reel")

            _ = try await client.callTool(name: "undo")
            #expect(harness.editor.timeline.plan == nil)
        }
    }

    @Test func makePlanWithoutVideoSaysThereIsNothingToPlanFrom() async throws {
        try await withClient(planned: false, assets: []) { harness, client in
            let result = try await client.callTool(name: "make_plan", arguments: ["brief": .string("trip")])
            #expect(result.isError == true)
            #expect(try text(result.content).contains("no video"))
            #expect(harness.editor.timeline.plan == nil)
        }
    }

    private func json(_ content: [Tool.Content]) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text(content).utf8)) as? [String: Any])
    }

    private func text(_ content: [Tool.Content]) throws -> String {
        for item in content {
            if case .text(let text, _, _) = item { return text }
        }
        throw CocoaError(.coderReadCorrupt)
    }
}
