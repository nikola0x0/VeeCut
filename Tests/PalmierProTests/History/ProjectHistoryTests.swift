import Foundation
import Testing
@testable import PalmierPro

private func projectFile(clipId: String) -> ProjectFile {
    let timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [Fixtures.clip(id: clipId, start: 0, duration: 30)])])
    return ProjectFile(timelines: [timeline], activeTimelineId: timeline.id, openTimelineIds: [timeline.id])
}

private func clipIds(_ file: ProjectFile) -> [String] {
    file.timelines.flatMap(\.tracks).flatMap(\.clips).map(\.id)
}

@Suite("Project history")
@MainActor
struct ProjectHistoryTests {
    @Test func versionsKeepCommitOrderAndGetCompressed() async throws {
        let history = ProjectHistory()
        var live: Set<UUID> = []
        for name in ["Cut", "Trim", "Apply Look"] {
            let entry = UUID()
            live.insert(entry)
            history.record(actionName: name, entryId: entry, file: projectFile(clipId: name), liveEntryIds: live)
        }
        await history.encodingFinished()
        #expect(history.versions.map(\.actionName) == ["Cut", "Trim", "Apply Look"])
        #expect(history.versions.allSatisfy { $0.byteCount > 0 })
        #expect(clipIds(try await history.versions[1].projectFile()) == ["Trim"])
    }

    @Test func onlyTheNewestVersionsAreKept() async {
        let history = ProjectHistory()
        for index in 0..<(ProjectHistory.maxVersions + 5) {
            history.record(actionName: "Edit \(index)", entryId: nil, file: projectFile(clipId: "c"), liveEntryIds: [])
        }
        await history.encodingFinished()
        #expect(history.versions.count == ProjectHistory.maxVersions)
        #expect(history.versions.first?.actionName == "Edit 5")
    }

    @Test func versionsAndTheirMasksRoundTripThroughThePackage() async throws {
        let history = ProjectHistory()
        var file = projectFile(clipId: "clip")
        file.trackedMasks = [TrackedMask(id: "dog", mediaRef: "media-1", label: "Dog", sourceFPS: 30, sourceWidth: 64, sourceHeight: 48)]
        history.record(actionName: "Track Dog", entryId: nil, file: file, liveEntryIds: [])
        let files = try ProjectHistory.packageFiles(history.versions, maskFiles: ["dog": Data([1, 2, 3]), "unused": Data([9])])
        let byName = Dictionary(uniqueKeysWithValues: files.map { ($0.name, $0.data) })

        let read = ProjectHistory.read { byName[$0] }
        #expect(read.versions.map(\.actionName) == ["Track Dog"])
        #expect(read.maskFiles == ["dog": Data([1, 2, 3])])
        #expect(clipIds(try await read.versions[0].projectFile()) == ["clip"])
    }

    @Test func anUnreadableIndexMeansNoHistory() {
        #expect(ProjectHistory.read { _ in Data("not json".utf8) }.versions.isEmpty)
    }

    @Test func savedStepsReplayIntoUndoSoCommandZWorksAfterReopening() async throws {
        let undoManager = UndoManager()
        let editor = EditorViewModel()
        editor.applyProjectFile(projectFile(clipId: "c"))
        editor.undo.attach(undoManager)
        let files = ["a", "b", "c"].map { projectFile(clipId: $0) }
        let versions = ["", "Cut", "Trim"].map {
            ProjectHistory.Version(id: UUID(), entryId: nil, actionName: $0, date: .now, maskIds: [], content: .file(files[0]))
        }
        editor.projectHistory.load(versions)
        editor.replayHistory(versions, files: files)

        #expect(editor.undo.history.map(\.actionName) == ["Cut", "Trim"])
        undoManager.undo()
        #expect(clipIds(editor.projectFileSnapshot()) == ["b"])
        undoManager.undo()
        #expect(clipIds(editor.projectFileSnapshot()) == ["a"])
        undoManager.redo()
        #expect(clipIds(editor.projectFileSnapshot()) == ["b"])
        #expect(editor.projectHistoryForSave().map(\.actionName) == ["", "Cut"])
    }

    @Test func anUndoneEditIsNotSavedOnceANewEditReplacesIt() {
        let undoManager = UndoManager()
        let editor = EditorViewModel()
        editor.applyProjectFile(projectFile(clipId: "clip"))
        editor.undo.attach(undoManager)
        editor.loadProjectHistory([], maskFiles: [:])
        editor.commitClipProperties(clipIds: ["clip"], actionName: "Fade") { $0.opacity = 0.5 }
        undoManager.undo()
        editor.commitClipProperties(clipIds: ["clip"], actionName: "Dim") { $0.opacity = 0.2 }

        #expect(editor.projectHistoryForSave().map(\.actionName) == ["", "Dim"])
    }

}

@Test func historySurvivesWritingAndReadingTheProjectPackage() async throws {
    let package = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).palmier")
    defer { try? FileManager.default.removeItem(at: package) }
    let version = ProjectHistory.Version(id: UUID(), entryId: nil, actionName: "Trim", date: .now, maskIds: [],
                                         content: .encoded(try await ProjectHistory.encode(projectFile(clipId: "trimmed"))))
    let snapshot = ProjectPackageSnapshot(
        timeline: try JSONEncoder().encode(projectFile(clipId: "live")),
        chatSessionFiles: [],
        historyVersions: [version]
    )
    try VideoProject.writeProjectPackage(snapshot, to: package, sourceURL: nil)
    let contents = try VideoProject.readProjectPackage(at: package)
    #expect(contents.historyVersions.map(\.actionName) == ["Trim"])
    #expect(clipIds(try await contents.historyVersions[0].projectFile()) == ["trimmed"])
}
