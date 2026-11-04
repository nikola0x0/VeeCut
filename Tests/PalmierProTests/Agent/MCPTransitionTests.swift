import Foundation
import MCP
import Testing
@testable import PalmierPro

@Suite("MCP — transitions", .serialized)
@MainActor
struct MCPTransitionTests {
    private let undoManager = UndoManager()
    /// Four 2 s clips back to back at 30 fps: cuts at 0, 60, 120, 180; the song's drop at 4 s (frame 120).
    private let clips = (0..<4).map { Fixtures.clip(id: "c\($0)", mediaRef: "m\($0)", start: $0 * 60, duration: 60) }

    private func withClient(project: URL? = nil, _ body: (ToolHarness, Client) async throws -> Void) async throws {
        var timeline = Fixtures.timeline(tracks: [
            Fixtures.videoTrack(id: "plan", clips: clips),
            Fixtures.audioTrack(clips: [Fixtures.clip(id: "song", mediaRef: "song", mediaType: .audio, start: 0, duration: 240)]),
        ])
        timeline.plan = EditPlan(brief: "reel", style: .reel, trackId: "plan", sections: [], music: PlanMusic(assetId: "song", beatSeconds: 0.5, drop: 4))
        let harness = ToolHarness(timeline: timeline)
        harness.editor.projectURL = project
        harness.editor.undo.attach(undoManager)
        let server = Server(name: "transition-test", version: "1.0.0", capabilities: .init(tools: .init(listChanged: false)))
        await MCPService.registerTools(on: server, executor: harness.executor)
        let transports = await InMemoryTransport.createConnectedPair()
        let client = Client(name: "transition-test", version: "1.0.0")
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

    private func clip(_ harness: ToolHarness, _ id: String) -> Clip? { harness.editor.clipFor(id: id) }

    @Test func zoomPunchesEveryOtherCutAfterTwoSecondsAndUndoesInOneStep() async throws {
        try await withClient { harness, client in
            let (tools, _) = try await client.listTools()
            #expect(tools.contains { $0.name == "add_transitions" })

            let result = try await client.callTool(name: "add_transitions", arguments: [
                "transition": .string("zoom_punch"), "fromSeconds": .double(2), "every": .int(2),
            ])

            #expect(result.isError != true)
            let receipt = try json(result.content)
            #expect((receipt["applied"] as? [[String: Any]])?.compactMap { $0["frame"] as? Int } == [60, 180])
            #expect(clip(harness, "c1")?.scaleTrack != nil)
            #expect(clip(harness, "c2")?.scaleTrack == nil)
            #expect(clip(harness, "c3")?.scaleTrack != nil)

            _ = try await client.callTool(name: "undo")
            #expect(clip(harness, "c1")?.scaleTrack == nil && clip(harness, "c3")?.scaleTrack == nil)
        }
    }

    @Test func atTheDropUsesTheCutOnTheSongsDrop() async throws {
        try await withClient { harness, client in
            let result = try await client.callTool(name: "add_transitions", arguments: [
                "transition": .string("dip_to_black"), "at": .string("drop"),
            ])
            #expect(result.isError != true)
            #expect(clip(harness, "c1")?.fadeOutFrames == 8)
            #expect(clip(harness, "c2")?.fadeInFrames == 8)
            #expect(clip(harness, "c3")?.fadeInFrames == 0)
        }
    }

    @Test func aFlashPutsAFadingWhiteClipOnANewTopTrack() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("transitions-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await withClient(project: root.appendingPathComponent("Flash.veecut", isDirectory: true)) { harness, client in
            let result = try await client.callTool(name: "add_transitions", arguments: [
                "transition": .string("flash"), "at": .string("drop"),
            ])
            #expect(result.isError != true)
            let top = harness.editor.timeline.tracks[0]
            #expect(top.clips.map(\.startFrame) == [120])
            #expect(top.clips.first?.opacityTrack?.keyframes.map(\.value) == [1, 0])
            #expect(harness.editor.mediaAssets.filter { $0.name == EditorViewModel.flashMatteName }.count == 1)

            _ = try await client.callTool(name: "undo")
            #expect(harness.editor.timeline.tracks.count == 2)
        }
    }

    @Test func whenEveryCutIsSkippedItSaysWhyAndChangesNothing() async throws {
        try await withClient { harness, client in
            for id in ["c1", "c2", "c3"] {
                harness.editor.commitClipProperty(clipId: id) { $0.scaleTrack = KeyframeTrack(keyframes: [Keyframe(frame: 0, value: AnimPair(a: 1, b: 1))]) }
            }
            let before = harness.editor.timeline
            let result = try await client.callTool(name: "add_transitions", arguments: [
                "transition": .string("zoom_punch"), "fromSeconds": .double(1),
            ])
            #expect(result.isError == true)
            #expect(try text(result.content).contains("hasKeyframes"))
            #expect(harness.editor.timeline == before)
        }
    }

    @Test(arguments: [
        (["transition": "sparkle"], "unknown transition"),
        (["transition": "flash", "every": "0"], "every must be at least 1"),
        (["transition": "flash", "trackIndex": "1"], "audio track"),
        (["transition": "flash", "fromSeconds": "30"], "no cuts in range"),
    ] as [([String: String], String)])
    func refusesWithoutChanging(args: [String: String], reason: String) async throws {
        try await withClient { harness, client in
            var arguments: [String: Value] = [:]
            for (key, value) in args { arguments[key] = Int(value).map { .int($0) } ?? .string(value) }
            let before = harness.editor.timeline
            let result = try await client.callTool(name: "add_transitions", arguments: arguments)
            #expect(result.isError == true, "\(reason)")
            #expect(harness.editor.timeline == before)
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
