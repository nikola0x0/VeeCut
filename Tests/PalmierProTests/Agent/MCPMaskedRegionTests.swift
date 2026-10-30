import Foundation
import MCP
import Testing
@testable import PalmierPro

@Suite("MCP — masked regions", .serialized)
@MainActor
struct MCPMaskedRegionTests {
    private let clip = Fixtures.clip(id: "clip", mediaRef: "media-1", start: 0, duration: 30)
    private let otherClip = Fixtures.clip(id: "other", mediaRef: "media-2", start: 30, duration: 30)

    private let undoManager = UndoManager()

    private func makeHarness() -> (ToolHarness, TrackedMask) {
        let harness = ToolHarness(timeline: Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [clip, otherClip])]))
        harness.editor.undo.attach(undoManager)
        let mask = TrackedMask(mediaRef: "media-1", label: "person", sourceFPS: 30, sourceWidth: 64, sourceHeight: 48)
        harness.editor.registerTrackedMask(mask, frames: [:], file: Data())
        return (harness, mask)
    }

    private func withClient(_ harness: ToolHarness, _ body: (Client) async throws -> Void) async throws {
        let server = Server(name: "region-test", version: "1.0.0", capabilities: .init(tools: .init(listChanged: false)))
        await MCPService.registerTools(on: server, executor: harness.executor)
        let transports = await InMemoryTransport.createConnectedPair()
        let client = Client(name: "region-test", version: "1.0.0")
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

    @Test func toolDiscoveryExposesTrackObjectAndRegionParameters() async throws {
        let (harness, _) = makeHarness()
        try await withClient(harness) { client in
            let (tools, _) = try await client.listTools()
            #expect(tools.contains { $0.name == "track_object" })
            for name in ["apply_color", "apply_effect"] {
                let schema = try #require(tools.first { $0.name == name }?.inputSchema)
                #expect(String(describing: schema).contains("region"), "\(name) should accept region")
            }
        }
    }

    @Test func gradesOutsideRegionWithoutTouchingWholeFrameGradeAndUndoes() async throws {
        let (harness, mask) = makeHarness()
        try await withClient(harness) { client in
            _ = try await client.callTool(name: "apply_color", arguments: [
                "clipIds": .array([.string(clip.id)]), "contrast": .double(1.2),
            ])
            let result = try await client.callTool(name: "apply_color", arguments: [
                "clipIds": .array([.string(clip.id)]),
                "exposure": .double(-1),
                "region": .object(["maskId": .string(mask.id), "side": .string("outside"), "feather": .double(4)]),
            ])
            #expect(result.isError != true)

            let timelineClip = try clipJSON(try await client.callTool(name: "get_timeline").content, id: clip.id)
            let wholeFrame = try #require(timelineClip["color"] as? [String: Any])
            #expect(wholeFrame["contrast"] as? Double == 1.2)
            #expect(wholeFrame["exposure"] == nil)
            let region = try #require((timelineClip["regions"] as? [[String: Any]])?.first)
            #expect(region["maskId"] as? String == mask.id)
            #expect(region["side"] as? String == "outside")
            #expect(region["target"] as? String == "person")
            #expect(region["feather"] as? Double == 4)
            #expect((region["color"] as? [String: Any])?["exposure"] as? Double == -1)

            let stored = try #require(harness.editor.clipFor(id: clip.id)?.effectRegions?.first)
            #expect(stored.matte == EffectMatte(maskId: mask.id, invert: true, feather: 4))

            _ = try await client.callTool(name: "undo")
            #expect(harness.editor.clipFor(id: clip.id)?.effectRegions == nil)
            #expect(harness.editor.clipFor(id: clip.id)?.effects?.isEmpty == false)
        }
    }

    @Test func smoothSkinIsRefusedOutsideAFace() async throws {
        let (harness, mask) = makeHarness()
        try await withClient(harness) { client in
            let result = try await client.callTool(name: "apply_effect", arguments: [
                "clipIds": .array([.string(clip.id)]),
                "effects": .array([.object(["type": .string("retouch.smoothSkin")])]),
                "region": .object(["maskId": .string(mask.id), "side": .string("inside")]),
            ])
            #expect(result.isError == true)
            #expect(try text(result.content).contains("smooth_skin"))
            #expect(harness.editor.clipFor(id: clip.id)?.effectRegions == nil)
        }
    }

    @Test func insideAndOutsideRegionsKeepSeparateStacks() async throws {
        let (harness, mask) = makeHarness()
        try await withClient(harness) { client in
            for (side, ev) in [("inside", 0.5), ("outside", -1.0)] {
                _ = try await client.callTool(name: "apply_color", arguments: [
                    "clipIds": .array([.string(clip.id)]),
                    "exposure": .double(ev),
                    "region": .object(["maskId": .string(mask.id), "side": .string(side)]),
                ])
            }
            _ = try await client.callTool(name: "apply_effect", arguments: [
                "clipIds": .array([.string(clip.id)]),
                "effects": .array([.object(["type": .string("blur.gaussian")])]),
                "region": .object(["maskId": .string(mask.id), "side": .string("outside")]),
            ])

            let regions = try #require(harness.editor.clipFor(id: clip.id)?.effectRegions)
            #expect(regions.count == 2)
            let inside = try #require(regions.first { !$0.matte.invert })
            let outside = try #require(regions.first { $0.matte.invert })
            #expect(inside.effects.map(\.type) == ["color.exposure"])
            #expect(Set(outside.effects.map(\.type)) == ["color.exposure", "blur.gaussian"])
            #expect(harness.editor.clipFor(id: clip.id)?.effects == nil)
        }
    }

    @Test(arguments: [
        ("unknown-mask", "inside", 0.0, "unknown maskId"),
        (nil, "sideways", 0.0, "inside' or 'outside"),
        (nil, "inside", 80.0, "feather"),
    ] as [(String?, String, Double, String)])
    func invalidRegionsAreRefusedWithoutMutation(maskId: String?, side: String, feather: Double, message: String) async throws {
        let (harness, mask) = makeHarness()
        try await withClient(harness) { client in
            let result = try await client.callTool(name: "apply_color", arguments: [
                "clipIds": .array([.string(clip.id)]),
                "exposure": .double(1),
                "region": .object(["maskId": .string(maskId ?? mask.id), "side": .string(side), "feather": .double(feather)]),
            ])
            #expect(result.isError == true)
            #expect(try text(result.content).contains(message))
            #expect(harness.editor.clipFor(id: clip.id)?.effectRegions == nil)
            #expect(harness.editor.clipFor(id: clip.id)?.effects == nil)
        }
    }

    @Test func regionOnClipWithDifferentMediaIsRefused() async throws {
        let (harness, mask) = makeHarness()
        try await withClient(harness) { client in
            let result = try await client.callTool(name: "apply_effect", arguments: [
                "clipIds": .array([.string(clip.id), .string(otherClip.id)]),
                "effects": .array([.object(["type": .string("blur.gaussian")])]),
                "region": .object(["maskId": .string(mask.id)]),
            ])
            #expect(result.isError == true)
            #expect(harness.editor.clipFor(id: clip.id)?.effectRegions == nil)
        }
    }

    private func clipJSON(_ content: [Tool.Content], id: String) throws -> [String: Any] {
        let payload = try #require(JSONSerialization.jsonObject(with: Data(text(content).utf8)) as? [String: Any])
        let tracks = payload["tracks"] as? [[String: Any]] ?? []
        return try #require(tracks.flatMap { $0["clips"] as? [[String: Any]] ?? [] }.first { $0["id"] as? String == id })
    }

    private func text(_ content: [Tool.Content]) throws -> String {
        for item in content {
            if case .text(let text, _, _) = item { return text }
        }
        throw CocoaError(.coderReadCorrupt)
    }
}
