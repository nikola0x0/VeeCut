import Foundation
import MCP
import Testing
@testable import PalmierPro

@Suite("MCP — follow_object", .serialized)
@MainActor
struct MCPFollowObjectTests {
    private let undoManager = UndoManager()

    private func makeHarness(extraVideo: Bool = false) -> (ToolHarness, TrackedMask) {
        var text = Fixtures.clip(id: "text", mediaRef: "", mediaType: .text, start: 0, duration: 30)
        text.transform = Transform(topLeft: (0.1, 0.1), width: 0.2, height: 0.1)
        text.textContent = "Cat"
        var tracks = [Fixtures.videoTrack(clips: [text]), Fixtures.videoTrack(clips: [Fixtures.clip(id: "video", start: 0, duration: 30)])]
        if extraVideo { tracks.append(Fixtures.videoTrack(clips: [Fixtures.clip(id: "video-2", start: 0, duration: 30)])) }
        let harness = ToolHarness(timeline: Fixtures.timeline(tracks: tracks))
        harness.editor.undo.attach(undoManager)
        return (harness, Fixtures.movingTrackedMask(in: harness.editor))
    }

    private func withClient(_ harness: ToolHarness, _ body: (Client) async throws -> Void) async throws {
        let server = Server(name: "follow-test", version: "1.0.0", capabilities: .init(tools: .init(listChanged: false)))
        await MCPService.registerTools(on: server, executor: harness.executor)
        let transports = await InMemoryTransport.createConnectedPair()
        let client = Client(name: "follow-test", version: "1.0.0")
        try await server.start(transport: transports.server)
        defer { harness.editor.releaseTrackedMasks() }
        do {
            _ = try await client.connect(transport: transports.client)
            try await body(client)
        } catch {
            await server.stop()
            await client.disconnect()
            throw error
        }
        await server.stop()
        await client.disconnect()
    }

    @Test func toolDiscoveryListsFollowObjectWithPlacements() async throws {
        let (harness, _) = makeHarness()
        try await withClient(harness) { client in
            let (tools, _) = try await client.listTools()
            let schema = String(describing: try #require(tools.first { $0.name == "follow_object" }?.inputSchema))
            for name in ["clipId", "maskId", "subjectClipId", "keepOffset", "above", "below", "center"] {
                #expect(schema.contains(name), "schema should mention \(name)")
            }
        }
    }

    @Test func placesTextAboveTheMovingObjectAndUndoesInOneStep() async throws {
        let (harness, mask) = makeHarness()
        try await withClient(harness) { client in
            let result = try await client.callTool(name: "follow_object", arguments: [
                "clipId": .string("text"), "maskId": .string(mask.id), "placement": .string("above"),
            ])
            #expect(result.isError != true)
            let receipt = try json(result.content)
            #expect(receipt["subjectClipId"] as? String == "video")
            #expect(receipt["followsFromFrame"] as? Int == 0)
            #expect(receipt["followsThroughFrame"] as? Int == 29)

            let timelineClip = try clipJSON(try await client.callTool(name: "get_timeline").content, id: "text")
            let position = try #require((timelineClip["keyframes"] as? [String: Any])?["position"] as? [[Any]])
            #expect(position.count >= 2)
            #expect(position.allSatisfy { $0.last as? String == "linear" })

            let text = try #require(harness.editor.clipFor(id: "text"))
            let video = try #require(harness.editor.clipFor(id: "video"))
            for frame in [0, 15, 29] {
                let box = try #require(harness.editor.subjectBox(of: mask.id, in: video, at: frame))
                let topLeft = text.topLeftAt(frame: frame)
                #expect(abs(topLeft.x + 0.1 - box.midX) < 0.005)
                #expect(abs(topLeft.y + 0.1 + EditorViewModel.followGap - box.minY) < 0.005)
            }

            _ = try await client.callTool(name: "undo")
            #expect(harness.editor.clipFor(id: "text")?.positionTrack == nil)
        }
    }

    @Test func refusesUnknownMasksBadPlacementsAndAmbiguousFootage() async throws {
        let (harness, mask) = makeHarness(extraVideo: true)
        try await withClient(harness) { client in
            let unknown = try await client.callTool(name: "follow_object", arguments: ["clipId": .string("text"), "maskId": .string("nope")])
            #expect(unknown.isError == true)
            #expect(try text(unknown.content).contains("track_object"))

            let badPlacement = try await client.callTool(name: "follow_object", arguments: [
                "clipId": .string("text"), "maskId": .string(mask.id), "subjectClipId": .string("video"), "placement": .string("left"),
            ])
            #expect(badPlacement.isError == true)

            let ambiguous = try await client.callTool(name: "follow_object", arguments: ["clipId": .string("text"), "maskId": .string(mask.id)])
            #expect(ambiguous.isError == true)
            #expect(try text(ambiguous.content).contains("subjectClipId"))

            #expect(harness.editor.clipFor(id: "text")?.positionTrack == nil)
            #expect(!undoManager.canUndo)
        }
    }

    @Test func acceptsTheShortSubjectClipIdGetTimelineShows() async throws {
        let videoId = UUID().uuidString
        var text = Fixtures.clip(id: "text", mediaRef: "", mediaType: .text, start: 0, duration: 30)
        text.transform = Transform(topLeft: (0.1, 0.1), width: 0.2, height: 0.1)
        let harness = ToolHarness(timeline: Fixtures.timeline(tracks: [
            Fixtures.videoTrack(clips: [text]), Fixtures.videoTrack(clips: [Fixtures.clip(id: videoId, start: 0, duration: 30)]),
        ]))
        harness.editor.undo.attach(undoManager)
        let mask = Fixtures.movingTrackedMask(in: harness.editor)
        try await withClient(harness) { client in
            let result = try await client.callTool(name: "follow_object", arguments: [
                "clipId": .string("text"), "maskId": .string(mask.id), "subjectClipId": .string(String(videoId.prefix(8))),
            ])
            #expect(result.isError != true)
            #expect(harness.editor.clipFor(id: "text")?.subjectFollow?.clipId == videoId)
        }
    }

    private func json(_ content: [Tool.Content]) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text(content).utf8)) as? [String: Any])
    }

    private func clipJSON(_ content: [Tool.Content], id: String) throws -> [String: Any] {
        let tracks = try json(content)["tracks"] as? [[String: Any]] ?? []
        return try #require(tracks.flatMap { $0["clips"] as? [[String: Any]] ?? [] }.first { $0["id"] as? String == id })
    }

    private func text(_ content: [Tool.Content]) throws -> String {
        for item in content {
            if case .text(let text, _, _) = item { return text }
        }
        throw CocoaError(.coderReadCorrupt)
    }
}
