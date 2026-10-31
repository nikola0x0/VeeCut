import AppKit
import SwiftUI
import Testing
@testable import PalmierPro

@Suite("Editor window layout")
@MainActor
struct EditorWindowLayoutTests {
    @Test(arguments: [false, true])
    func theEditorWindowLaysOutWithoutAConstraintLoop(withPlan: Bool) {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(id: "v1", clips: [Fixtures.clip(start: 0, duration: 90)])])
        if withPlan {
            editor.timeline.plan = EditPlan(brief: "", style: nil, trackId: "v1", sections: [PlanSection(title: "Hook", targetSeconds: 5, hint: "")])
        }
        let root = EditorView()
            .padding([.horizontal, .bottom], Layout.panelGap / 2)
            .environment(editor)
            .ignoresSafeArea(.container, edges: .top)
        let host = NSHostingController(rootView: root.appLocalization())
        host.sizingOptions = .minSize
        host.safeAreaRegions = []
        let window = NSWindow(contentViewController: host)
        window.styleMask.insert(.fullSizeContentView)
        window.setContentSize(NSSize(width: 1400, height: 900))
        window.layoutIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(window.contentView != nil)
    }
}
