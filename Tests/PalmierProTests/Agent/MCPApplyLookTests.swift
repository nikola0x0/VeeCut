import Foundation
import MCP
import Testing
@testable import PalmierPro

@Suite("MCP — apply look", .serialized)
@MainActor
struct MCPApplyLookTests {
    private let clip = Fixtures.clip(id: "clip", mediaRef: "media-1", start: 0, duration: 30)
    private let undoManager = UndoManager()

    private func withClient(_ body: (ToolHarness, TrackedMask, Client) async throws -> Void) async throws {
        let harness = ToolHarness(timeline: Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [clip])]))
        harness.editor.undo.attach(undoManager)
        let person = Fixtures.trackedMask(in: harness.editor, label: "man in black jacket", presentAt: [0.5])
        let server = Server(name: "apply-look-test", version: "1.0.0", capabilities: .init(tools: .init(listChanged: false)))
        await MCPService.registerTools(on: server, executor: harness.executor)
        let transports = await InMemoryTransport.createConnectedPair()
        let client = Client(name: "apply-look-test", version: "1.0.0")
        try await server.start(transport: transports.server)
        defer { harness.editor.releaseTrackedMasks() }
        do {
            _ = try await client.connect(transport: transports.client)
            try await body(harness, person, client)
        } catch {
            await server.stop()
            await client.disconnect()
            throw error
        }
        await server.stop()
        await client.disconnect()
    }

    private func regions(_ client: Client) async throws -> [[String: Any]] {
        let timeline = try json(try await client.callTool(name: "get_timeline").content)
        let clipJSON = try #require((timeline["tracks"] as? [[String: Any]])?.flatMap { $0["clips"] as? [[String: Any]] ?? [] }.first)
        return clipJSON["regions"] as? [[String: Any]] ?? []
    }

    @Test func popSubjectAndBlurBackgroundUseTheObjectBarsLooksAndUndo() async throws {
        try await withClient { harness, person, client in
            let (tools, _) = try await client.listTools()
            #expect(tools.contains { $0.name == "apply_look" })

            let pop = try await client.callTool(name: "apply_look", arguments: [
                "clipId": .string(clip.id), "look": .string("pop_subject"), "maskId": .string(person.id),
            ])
            #expect(pop.isError != true)
            #expect(try json(pop.content)["placement"] as? String == "subject")
            let blur = try await client.callTool(name: "apply_look", arguments: [
                "clipId": .string(clip.id), "look": .string("blur_background"), "maskId": .string(person.id),
            ])
            #expect(blur.isError != true)

            #expect(Set(try await regions(client).compactMap { $0["side"] as? String }) == ["inside", "outside"])
            let stored = try #require(harness.editor.clipFor(id: clip.id)?.effectRegions)
            let inside = try #require(stored.first { !$0.matte.invert })
            #expect(inside.effects.map(\.type) == SubjectLook.popSubject.plan(hasSubject: true).subject.map(\.type))
            #expect(!inside.effects.contains { $0.type == "color.saturation" })

            _ = try await client.callTool(name: "undo")
            #expect(harness.editor.clipFor(id: clip.id)?.effectRegions?.map(\.matte.invert) == [false])
            _ = try await client.callTool(name: "undo")
            #expect(harness.editor.clipFor(id: clip.id)?.effectRegions == nil)
        }
    }

    @Test func aBackgroundLookKeepsTheRequestedSubjectSharpToo() async throws {
        try await withClient { harness, person, client in
            _ = try await client.callTool(name: "apply_look", arguments: [
                "clipId": .string(clip.id), "look": .string("blur_background"), "maskId": .string(person.id),
            ])
            let second = Fixtures.trackedMask(in: harness.editor, label: "woman with yellow bag", presentAt: [0.5])

            let result = try await client.callTool(name: "apply_look", arguments: [
                "clipId": .string(clip.id), "look": .string("darken_background"), "maskId": .string(second.id),
            ])

            #expect(result.isError != true)
            let backgrounds = try #require(harness.editor.clipFor(id: clip.id)?.effectRegions).filter(\.matte.invert)
            #expect(backgrounds.count == 1)
            #expect(Set(backgrounds.first?.matte.maskIds ?? []) == [person.id, second.id])
            #expect(Set(try json(result.content)["keptSharp"] as? [String] ?? []) == [person.id, second.id])
        }
    }

    @Test func aWholeClipLookNeedsNoSubject() async throws {
        try await withClient { harness, _, client in
            let result = try await client.callTool(name: "apply_look", arguments: [
                "clipId": .string(clip.id), "look": .string("vlog_pop"),
            ])
            #expect(result.isError != true)
            #expect(try json(result.content)["placement"] as? String == "wholeClip")
            #expect(harness.editor.clipFor(id: clip.id)?.effects?.map(\.type) == SubjectLook.vlogPop.plan(hasSubject: false).frame.map(\.type))
        }
    }

    @Test(arguments: [
        (["look": "pop_subject"], "needs maskId"),
        (["look": "sparkle"], "unknown look"),
        (["look": "blur_background", "maskId": "nope"], "unknown maskId"),
    ] as [([String: String], String)])
    func refusesWithoutChanging(args: [String: String], reason: String) async throws {
        try await withClient { harness, _, client in
            var arguments: [String: Value] = ["clipId": .string(clip.id)]
            for (key, value) in args { arguments[key] = .string(value) }
            let result = try await client.callTool(name: "apply_look", arguments: arguments)
            #expect(result.isError == true, "\(reason)")
            #expect(harness.editor.clipFor(id: clip.id)?.effectRegions == nil)
            #expect(harness.editor.clipFor(id: clip.id)?.effects?.isEmpty ?? true)
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
