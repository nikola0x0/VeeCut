import Foundation
import MCP
import Testing
@testable import PalmierPro

@Suite("MCP — add_sticker", .serialized)
@MainActor
struct MCPStickerTests {
    private let undoManager = UndoManager()

    private func makeHarness(package: URL) -> (ToolHarness, TrackedMask) {
        let harness = ToolHarness(timeline: Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [Fixtures.clip(id: "video", start: 0, duration: 60)])]))
        harness.editor.projectURL = package
        harness.editor.undo.attach(undoManager)
        harness.editor.stickerImageSource = { _ in try await StickerFixtures.staged() }
        return (harness, Fixtures.movingTrackedMask(in: harness.editor))
    }

    private func withClient(_ harness: ToolHarness, _ body: (Client) async throws -> Void) async throws {
        let server = Server(name: "sticker-test", version: "1.0.0", capabilities: .init(tools: .init(listChanged: false)))
        await MCPService.registerTools(on: server, executor: harness.executor)
        let transports = await InMemoryTransport.createConnectedPair()
        let client = Client(name: "sticker-test", version: "1.0.0")
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

    @Test func toolDiscoveryListsAddSticker() async throws {
        let (root, package) = try await StickerFixtures.makePackage()
        let (harness, _) = makeHarness(package: package)
        try await withClient(harness) { client in
            let (tools, _) = try await client.listTools()
            let schema = String(describing: try #require(tools.first { $0.name == "add_sticker" }?.inputSchema))
            for name in ["description", "maskId", "subjectClipId", "placement", "startFrame"] {
                #expect(schema.contains(name), "schema should mention \(name)")
            }
        }
        await StickerFixtures.remove(root)
    }

    @Test func stickerFollowsTheObjectAboveItAndUndoesWithItsMedia() async throws {
        let (root, package) = try await StickerFixtures.makePackage()
        let (harness, mask) = makeHarness(package: package)
        try await withClient(harness) { client in
            let result = try await client.callTool(name: "add_sticker", arguments: [
                "description": .string("golden crown"), "maskId": .string(mask.id), "placement": .string("above"),
            ])
            #expect(result.isError != true)
            let receipt = try json(result.content)
            #expect(receipt["follows"] as? Bool == true)
            #expect(receipt["subjectClipId"] as? String == "video")
            let mediaRef = try #require(receipt["mediaRef"] as? String)

            let media = try text(try await client.callTool(name: "get_media").content)
            #expect(media.contains(mediaRef))
            let timeline = try json(try await client.callTool(name: "get_timeline").content)
            let clips = (timeline["tracks"] as? [[String: Any]] ?? []).flatMap { $0["clips"] as? [[String: Any]] ?? [] }
            let sticker = try #require(clips.first { $0["mediaRef"] as? String == mediaRef })
            #expect((sticker["keyframes"] as? [String: Any])?["position"] != nil)

            let clip = try #require(harness.editor.timeline.tracks.flatMap(\.clips).first { $0.mediaType == .image })
            let video = try #require(harness.editor.clipFor(id: "video"))
            let box = try #require(harness.editor.subjectBox(of: mask.id, in: video, at: 10))
            #expect(clip.topLeftAt(frame: 10).y + clip.sizeAt(frame: 10).height <= box.minY + 0.0001)

            _ = try await client.callTool(name: "undo")
            #expect(harness.editor.clipFor(id: clip.id) == nil)
            #expect(!harness.editor.mediaAssets.contains { $0.id == clip.mediaRef })
            #expect(!(try text(try await client.callTool(name: "get_media").content)).contains(mediaRef))
        }
        await StickerFixtures.remove(root)
    }

    @Test func refusesFollowOptionsWithoutAnObjectAndUnknownObjects() async throws {
        let (root, package) = try await StickerFixtures.makePackage()
        let (harness, _) = makeHarness(package: package)
        try await withClient(harness) { client in
            let orphanPlacement = try await client.callTool(name: "add_sticker", arguments: [
                "description": .string("crown"), "placement": .string("above"),
            ])
            #expect(orphanPlacement.isError == true)
            let unknown = try await client.callTool(name: "add_sticker", arguments: [
                "description": .string("crown"), "maskId": .string("nope"),
            ])
            #expect(unknown.isError == true)
            #expect(try text(unknown.content).contains("track_object"))
            let empty = try await client.callTool(name: "add_sticker", arguments: ["description": .string("   ")])
            #expect(empty.isError == true)
            #expect(harness.editor.mediaAssets.isEmpty)
            #expect(!undoManager.canUndo)
        }
        await StickerFixtures.remove(root)
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
