import Foundation

/// Simple shows the few tools most edits need; Pro is the full editor.
enum EditorMode: String, CaseIterable, Sendable {
    case simple, pro

    private static let defaultsKey = "editorMode"

    static func saved(in defaults: UserDefaults = .standard) -> EditorMode {
        defaults.string(forKey: defaultsKey).flatMap(EditorMode.init(rawValue:)) ?? .simple
    }

    func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
