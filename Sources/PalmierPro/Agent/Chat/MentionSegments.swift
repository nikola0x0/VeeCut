import Foundation

enum MentionSegment: Equatable {
    case text(String)
    case mention(AgentMention)
}

/// Splits a chat draft into plain text and registered `@DisplayName` tokens, and joins it back losslessly.
enum MentionSegments {
    static func split(_ text: String, mentions: [AgentMention]) -> [MentionSegment] {
        let candidates = mentions.sorted { $0.displayName.count > $1.displayName.count }
        var segments: [MentionSegment] = []
        var plain = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "@", index == text.startIndex || !continuesToken(text[text.index(before: index)]),
               let (mention, end) = token(in: text, after: index, candidates: candidates) {
                if !plain.isEmpty { segments.append(.text(plain)) }
                plain = ""
                segments.append(.mention(mention))
                index = end
            } else {
                plain.append(text[index])
                index = text.index(after: index)
            }
        }
        if !plain.isEmpty { segments.append(.text(plain)) }
        return segments
    }

    static func serialize(_ segments: [MentionSegment]) -> String {
        segments.map { segment in
            switch segment {
            case .text(let text): text
            case .mention(let mention): "@\(mention.displayName)"
            }
        }.joined()
    }

    private static func token(
        in text: String,
        after at: String.Index,
        candidates: [AgentMention]
    ) -> (AgentMention, String.Index)? {
        let rest = text[text.index(after: at)...]
        for mention in candidates where !mention.displayName.isEmpty && rest.hasPrefix(mention.displayName) {
            let end = rest.index(rest.startIndex, offsetBy: mention.displayName.count)
            if end == text.endIndex || !continuesToken(text[end]) { return (mention, end) }
        }
        return nil
    }

    /// Display names collapse spaces to "-" and disambiguate with "#", so those continue a token.
    private static func continuesToken(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-" || character == "#" || character == "_"
    }
}
