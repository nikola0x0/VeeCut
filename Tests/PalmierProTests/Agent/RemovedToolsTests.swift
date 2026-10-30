import Testing
@testable import PalmierPro

@Suite("Removed Palmier backend tools")
@MainActor
struct RemovedToolsTests {
    nonisolated static let removedNames = ["list_models", "generate_video", "generate_image", "generate_audio", "upscale_media", "send_feedback"]

    @Test func toolListsOmitBackendTools() {
        let names = Set((ToolDefinitions.mcpServer + ToolDefinitions.inAppAgent).map(\.name.rawValue))
        #expect(names.isDisjoint(with: Self.removedNames))
    }

    @Test(arguments: removedNames)
    func executorRejectsBackendTool(_ name: String) async {
        let result = await ToolHarness().runRaw(name)
        #expect(result.isError)
        #expect(ToolHarness.textOf(result) == "Unknown tool: \(name)")
    }
}
