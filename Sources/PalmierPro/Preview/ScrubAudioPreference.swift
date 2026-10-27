import Foundation

/// Whether dragging the playhead plays audio. Off by default; frame stepping always clicks.
@MainActor
enum ScrubAudioPreference {
    private static let defaultsKey = "scrubAudioEnabled"
    // Cached so the per-drag seek path never touches UserDefaults.
    private(set) static var isEnabled = UserDefaults.standard.bool(forKey: defaultsKey)

    static func toggle() {
        isEnabled.toggle()
        UserDefaults.standard.set(isEnabled, forKey: defaultsKey)
    }
}
