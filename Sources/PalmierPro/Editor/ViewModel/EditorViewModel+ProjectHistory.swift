import Foundation

/// Edit history that outlives the session: a saved version after each action, replayed into the undo stack on open
/// so ⌘Z keeps stepping back past a restart.
extension EditorViewModel {
    /// Loads the saved versions and, once decoded, makes each one an undo step. `onReplayed` runs only if they were
    /// added, so the document can drop the edited mark the replay leaves.
    func loadProjectHistory(_ versions: [ProjectHistory.Version], maskFiles: [String: Data], onReplayed: (@MainActor () -> Void)? = nil) {
        projectHistory.load(versions)
        trackedMaskFiles.merge(maskFiles) { current, _ in current }
        projectHistory.recordBase(projectFileSnapshot())
        guard versions.count > 1 else { return }
        historyReplay = Task {
            var files: [ProjectFile] = []
            for version in versions {
                guard let file = try? await version.projectFile() else {
                    Log.project.error("history replay skipped: version \(version.id) unreadable")
                    return
                }
                files.append(file)
            }
            guard !Task.isCancelled, undo.history.isEmpty else { return }
            replayHistory(versions, files: files)
            onReplayed?()
        }
    }

    /// Registers one undo step per saved action, oldest first, each returning to the version before it.
    func replayHistory(_ versions: [ProjectHistory.Version], files: [ProjectFile]) {
        isReplayingHistory = true
        defer { isReplayingHistory = false }
        for index in versions.indices.dropFirst() {
            let actionName = versions[index].actionName
            undo.perform(actionName, date: versions[index].date) {
                registerReturn(to: files[index - 1], actionName: actionName)
            }
        }
        projectHistory.adopt(entryIds: undo.history.map(\.id))
    }

    func recordProjectVersion() {
        guard !isReplayingHistory, let entry = undo.history.last else { return }
        projectHistory.record(actionName: entry.actionName, entryId: entry.id, file: projectFileSnapshot(),
                              liveEntryIds: Set(undo.history.map(\.id)))
    }

    /// Versions for the package: only edits currently applied, so a reopened project undoes back through them.
    func projectHistoryForSave() -> [ProjectHistory.Version] {
        projectHistory.savedVersions(applied: undo.history.prefix(undo.historyPosition).map(\.id))
    }

    /// Undo goes back to `file`; redo comes back to the state it replaced.
    private func registerReturn(to file: ProjectFile, actionName: String) {
        undo.register(actionName, withTarget: self) { editor in
            let current = editor.projectFileSnapshot()
            editor.applyRestoredProjectFile(file)
            editor.registerReturn(to: current, actionName: actionName)
        }
    }

    private func applyRestoredProjectFile(_ file: ProjectFile) {
        clearCanvasObject()
        selectedClipIds = []
        applyProjectFile(file)
        let unloaded = trackedMaskFiles.filter { id, _ in
            trackedMask(id: id) != nil && !MatteStore.shared.contains(maskId: id)
        }
        restoreTrackedMasks(files: unloaded)
        notifyTimelineChanged()
    }
}
