import Foundation
import MCP
import Testing
@testable import PalmierPro

@Suite("MCP — smooth skin", .serialized)
@MainActor
struct MCPSmoothSkinTests {
    private let clip = Fixtures.clip(id: "clip", mediaRef: "media-1", start: 0, duration: 30)
    private let undoManager = UndoManager()

    private func withClient(_ body: (ToolHarness, TrackedMask, TrackedMask, Client) async throws -> Void) async throws {
        let harness = ToolHarness(timeline: Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [clip])]))
        harness.editor.undo.attach(undoManager)
        let person = Fixtures.trackedMask(in: harness.editor, label: "Nikola", presentAt: [0.5])
        let face = Fixtures.trackedMask(in: harness.editor, label: "Nikola’s face", presentAt: [0.5], face: FaceLink(personMaskId: person.id))
        let server = Server(name: "smooth-skin-test", version: "1.0.0", capabilities: .init(tools: .init(listChanged: false)))
        await MCPService.registerTools(on: server, executor: harness.executor)
        let transports = await InMemoryTransport.createConnectedPair()
        let client = Client(name: "smooth-skin-test", version: "1.0.0")
        try await server.start(transport: transports.server)
        defer { harness.editor.releaseTrackedMasks() }
        do {
            _ = try await client.connect(transport: transports.client)
            try await body(harness, person, face, client)
        } catch {
            await server.stop()
            await client.disconnect()
            throw error
        }
        await server.stop()
        await client.disconnect()
    }

    @Test func retouchesThePersonsFaceReadsBackAndUndoes() async throws {
        try await withClient { harness, person, face, client in
            let (tools, _) = try await client.listTools()
            #expect(tools.contains { $0.name == "smooth_skin" })

            let result = try await client.callTool(name: "smooth_skin", arguments: [
                "clipId": .string(clip.id), "maskId": .string(person.id), "smoothing": .double(0.4),
            ])
            #expect(result.isError != true)
            let receipt = try json(result.content)
            #expect(receipt["faceMaskId"] as? String == face.id)
            #expect(receipt["foundNewFace"] as? Bool == false)

            let timeline = try json(try await client.callTool(name: "get_timeline").content)
            let clipJSON = try #require((timeline["tracks"] as? [[String: Any]])?.flatMap { $0["clips"] as? [[String: Any]] ?? [] }.first)
            let regions = try #require(clipJSON["regions"] as? [[String: Any]])
            #expect(regions.count == 1)
            #expect(regions.first?["maskId"] as? String == face.id)
            let effect = try #require((regions.first?["effects"] as? [[String: Any]])?.first)
            #expect(effect["type"] as? String == "retouch.smoothSkin")
            #expect((effect["params"] as? [String: Any])?["amount"] as? Double == 0.4)
            #expect((effect["params"] as? [String: Any])?["blemishes"] as? Double == 1)

            _ = try await client.callTool(name: "undo")
            #expect(harness.editor.clipFor(id: clip.id)?.effectRegions == nil)
        }
    }

    @Test(arguments: [
        (["maskId": .string("unknown")], "maskId"),
        (["smoothing": .double(1.5)], "smoothing"),
        (["blemishes": .string("lots")], "blemishes"),
        (["clipId": .string("missing")], "Clip not found"),
    ] as [([String: Value], String)])
    func invalidRequestsAreRefusedWithoutChanges(overrides: [String: Value], message: String) async throws {
        try await withClient { harness, _, _, client in
            var arguments: [String: Value] = ["clipId": .string(clip.id)]
            arguments.merge(overrides) { $1 }
            let result = try await client.callTool(name: "smooth_skin", arguments: arguments)
            #expect(result.isError == true)
            #expect(try text(result.content).contains(message))
            #expect(harness.editor.clipFor(id: clip.id)?.effectRegions == nil)
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
