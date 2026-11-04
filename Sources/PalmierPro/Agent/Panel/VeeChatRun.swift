import Foundation

/// Groups the chat into runs: everything Vee says between two of the user's messages shares one avatar.
extension AgentMessage {
    /// Tool results travel as user messages but render inside Vee's run, so only text counts as the user speaking.
    var showsInChat: Bool {
        role != .user || blocks.contains { if case .text = $0 { true } else { false } }
    }

    static func startsVeeRun(_ messages: [AgentMessage], at index: Int) -> Bool {
        guard messages.indices.contains(index), messages[index].role == .assistant else { return false }
        let previous = messages[..<index].last(where: \.showsInChat)
        return previous?.role != .assistant
    }

    /// Vee is replying but hasn't said anything yet in this run.
    static func veeIsTypingNewRun(_ messages: [AgentMessage]) -> Bool {
        messages.last(where: \.showsInChat)?.role == .user
    }
}
