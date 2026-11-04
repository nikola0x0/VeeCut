import Foundation
import Testing
@testable import PalmierPro

struct ProjectOpenPanelTests {
    @Test(arguments: [
        ("/Users/me/Documents/VeeCut/4 Nov.veecut", true),
        ("/Users/me/Documents/VeeCut/4 Nov.VEECUT", true),
        ("/Users/me/Documents/VeeCut", false),
        ("/Users/me/Movies/trip.mov", false),
    ])
    func onlyAVeeCutPackageCanBeOpened(path: String, opens: Bool) {
        #expect(ProjectOpenPanel.isProject(URL(fileURLWithPath: path, isDirectory: true)) == opens)
    }
}
