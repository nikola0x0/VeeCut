import Foundation
import Testing
@testable import PalmierPro

@MainActor
struct TourTests {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "TourTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    @Test func theTourShowsVeeAndItsChatBeforeTheLayout() {
        let editor = EditorViewModel()
        editor.tour.start(in: editor)
        #expect(editor.tour.steps.map(\.kind) == [
            .intro,
            .spotlight(.element(.veeButton)),
            .spotlight(.panel(.agent)),
            .spotlight(.element(.editorModeSwitch)),
            .spotlight(.panel(.media)),
            .spotlight(.panel(.preview)),
            .spotlight(.panel(.timeline)),
            .spotlight(.panel(.inspector)),
            .outro,
        ])
    }

    @Test func theTourStartsOnlyOnTheFirstProject() {
        withDefaults { defaults in
            let first = EditorViewModel()
            first.tour.startIfFirstRun(in: first, defaults: defaults)
            #expect(first.tour.stepIndex == 0)

            let second = EditorViewModel()
            second.tour.startIfFirstRun(in: second, defaults: defaults)
            #expect(second.tour.stepIndex == nil)
        }
    }
}

@MainActor
@Test func theCoachCardWaitsWhileTheTourRuns() {
    let editor = EditorViewModel()
    editor.coach = .asking(overview: "")
    editor.tour.start(in: editor)
    #expect(!editor.showsCoachCard)
    editor.tour.end()
    #expect(editor.showsCoachCard)
}

@MainActor
@Test func planningSaysToImportFootageUntilThereIsVideo() {
    let editor = EditorViewModel()
    editor.mediaAssets = [MediaAsset(id: "song", url: URL(fileURLWithPath: "/tmp/song.m4a"), type: .audio, name: "song", duration: 120)]
    #expect(editor.planTheEditHelp == "Import a video clip to plan your edit.")
    editor.mediaAssets.append(MediaAsset(id: "shot", url: URL(fileURLWithPath: "/tmp/shot.mov"), type: .video, name: "shot", duration: 3))
    #expect(editor.planTheEditHelp == "Plan the Edit")
}
