import AVFoundation

/// Passive keeps the coach silent with tips behind a badge; Active speaks and shows tips as they come.
enum CoachMode: String, Sendable {
    case passive, active

    private static let defaultsKey = "coachMode"

    @MainActor static var saved: CoachMode {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(CoachMode.init(rawValue:)) ?? .passive
    }

    @MainActor static func save(_ mode: CoachMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: defaultsKey)
    }
}

@MainActor
protocol CoachSpeaking: AnyObject {
    func speak(_ text: String)
    func stop()
}

/// Speaks coach lines with the system voice; a new line cuts off the previous one.
@MainActor
final class CoachVoice: CoachSpeaking {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        stop()
        synthesizer.speak(AVSpeechUtterance(string: text))
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }
}
