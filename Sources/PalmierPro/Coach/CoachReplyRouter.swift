import Foundation

enum CoachReply: Equatable, Sendable {
    case accept, decline, request(String)
}

/// A spoken reply is a yes or no to the current tip only when that is all it says; anything else is a request.
enum CoachReplyRouter {
    static let acceptPhrases: Set<String> = ["yes", "yeah", "yep", "ok", "okay", "sure", "do it", "có", "ừ", "được"]
    static let declinePhrases: Set<String> = ["no", "nope", "skip", "not now", "không", "bỏ qua"]

    static func route(_ text: String) -> CoachReply {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let phrase = trimmed.lowercased()
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if acceptPhrases.contains(phrase) { return .accept }
        if declinePhrases.contains(phrase) { return .decline }
        return .request(trimmed)
    }
}
