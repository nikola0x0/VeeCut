import Foundation
import Testing
@testable import PalmierPro

/// End-to-end against Meta's Responses API with the in-app agent's real prompt and tools.
/// Opt in with VEECUT_LIVE_MUSE=1 and MODEL_API_KEY.
@Suite("Live — Muse Spark agent turn", .serialized, .enabled(if: ProcessInfo.processInfo.environment["VEECUT_LIVE_MUSE"] == "1"))
@MainActor
struct LiveMuseSparkAgentTests {
    @Test func callsAToolThenAnswersAfterTheToolResult() async throws {
        let key = ProcessInfo.processInfo.environment["MODEL_API_KEY"] ?? ""
        let client = BYOKClient(apiKey: key, settings: AgentRunSettings(model: .museSpark, reasoningEffort: .medium))
        let tools = ToolDefinitions.inAppAgent.map {
            AgentToolSchema(name: $0.name.rawValue, description: $0.description, inputSchema: $0.inputSchema)
        }
        let system = AgentInstructions.serverInstructions
        let context = AgentRequestContext(conversationID: UUID(), traceID: UUID(), spanID: UUID(),
                                          inputMessageID: UUID(), outputMessageID: UUID(), projectID: nil)
        let user = AgentRequestMessage(role: .user, content: [.content(.text(
            "Make the background darker behind the person in my vlog clip. Look at the timeline first."
        ))])

        var assistant: [AgentRequestBlock] = []
        var call: (id: String, name: String)?
        for try await event in client.stream(system: system, tools: tools, messages: [user], context: context) {
            switch event {
            case .reasoningComplete(let itemID, let summary, let encrypted):
                assistant.append(.content(.openAIReasoning(summary: summary, encryptedContent: encrypted, itemID: itemID, model: .museSpark)))
            case .toolUseComplete(let id, let name, let input):
                assistant.append(.content(.toolUse(id: id, name: name, inputJSON: input)))
                if call == nil { call = (id, name) }
            case .textDelta(let text):
                assistant.append(.content(.text(text)))
            default:
                break
            }
        }
        let first = try #require(call, "Muse Spark should call a tool")
        print("MUSE first tool: \(first.name)")

        let timeline = #"{"fps":30,"tracks":[{"id":"v1","type":"video","clips":[{"id":"clip-1","mediaRef":"m1","name":"vlog.mov","start":0,"duration":900}]}],"masks":[]}"#
        let followUp = [
            user,
            AgentRequestMessage(role: .assistant, content: assistant),
            AgentRequestMessage(role: .user, content: [.content(.toolResult(toolUseId: first.id, content: [.text(timeline)], isError: false))]),
        ]
        var secondCalls: [String] = []
        var text = ""
        for try await event in client.stream(system: system, tools: tools, messages: followUp, context: context) {
            if case .toolUseComplete(_, let name, let input) = event { secondCalls.append("\(name) \(input)") }
            if case .textDelta(let delta) = event { text += delta }
        }
        print("MUSE second turn tools: \(secondCalls) text: \(text.prefix(300))")
        #expect(!secondCalls.isEmpty || !text.isEmpty)
    }
}
