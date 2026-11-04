import Foundation
import Testing
@testable import PalmierPro

struct VeeChatRunTests {
    private let user = AgentMessage(role: .user, blocks: [.text("Add transitions")])
    private let toolResult = AgentMessage(role: .user, blocks: [.toolResult(toolUseId: "t1", content: [], isError: false)])
    private let vee = AgentMessage(role: .assistant, blocks: [.text("On it.")])

    @Test func veesAvatarOpensEachRunOfReplies() {
        let messages = [user, vee, toolResult, vee, user, vee]
        #expect(messages.indices.map { AgentMessage.startsVeeRun(messages, at: $0) } == [false, true, false, false, false, true])
    }

    @Test func veeIsTypingAfterTheUsersMessageButNotMidRun() {
        #expect(AgentMessage.veeIsTypingNewRun([user]))
        #expect(!AgentMessage.veeIsTypingNewRun([user, vee, toolResult]))
        #expect(!AgentMessage.veeIsTypingNewRun([]))
    }
}
