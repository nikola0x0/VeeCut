import Foundation

/// Server-sent events of a streamed `/responses` call, reduced to what the coach shows and keeps.
enum MetaResponseStream {
    enum Event: Equatable, Sendable {
        case thinking(String)
        case text(String)
        case failed(String)
    }

    static func event(fromLine line: String) -> Event? {
        guard line.hasPrefix("data:"),
              let object = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(5).utf8)) as? [String: Any],
              let type = object["type"] as? String else { return nil }
        switch type {
        case "response.reasoning_summary_text.delta":
            return (object["delta"] as? String).map(Event.thinking)
        case "response.output_text.delta":
            return (object["delta"] as? String).map(Event.text)
        case "response.failed", "error":
            let error = (object["response"] as? [String: Any])?["error"] as? [String: Any] ?? object["error"] as? [String: Any]
            return .failed(error?["message"] as? String ?? type)
        default:
            return nil
        }
    }
}
