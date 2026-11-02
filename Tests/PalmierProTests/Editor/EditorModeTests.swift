import Foundation
import Testing
@testable import PalmierPro

struct EditorModeTests {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "EditorModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    @Test func simpleIsTheDefault() {
        withDefaults { #expect(EditorMode.saved(in: $0) == .simple) }
    }

    @Test func theModeIsRememberedAcrossLaunches() {
        withDefaults { defaults in
            EditorMode.pro.save(in: defaults)
            #expect(EditorMode.saved(in: defaults) == .pro)
            EditorMode.simple.save(in: defaults)
            #expect(EditorMode.saved(in: defaults) == .simple)
        }
    }
}
