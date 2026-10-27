import Foundation

struct UndoHistoryEntry: Identifiable, Equatable {
    let id = UUID()
    let actionName: String
    let date: Date
}

/// One undo or redo step, published so the editor can show which action moved and where history now stands.
struct UndoStepEvent: Equatable {
    enum Direction { case undo, redo }
    let id = UUID()
    let direction: Direction
    let actionName: String
    let position: Int
    let count: Int
}

@MainActor
@Observable
final class EditorUndo {
    static let historyLimit = 200

    @ObservationIgnored private weak var manager: UndoManager?
    @ObservationIgnored private var transactionActive = false
    @ObservationIgnored private var transactionGroupOpened = false
    @ObservationIgnored private var managerObservers: [NSObjectProtocol] = []
    @ObservationIgnored var onActionCommitted: (() -> Void)?

    /// Editor actions in commit order; the first `historyPosition` are applied, the rest can be redone.
    private(set) var history: [UndoHistoryEntry] = []
    private(set) var historyPosition = 0
    private(set) var lastStep: UndoStepEvent?

    func attach(_ manager: UndoManager?) {
        managerObservers.forEach(NotificationCenter.default.removeObserver)
        managerObservers = []
        history = []
        historyPosition = 0
        lastStep = nil
        self.manager = manager
        guard let manager else { return }
        for (name, step) in [(Notification.Name.NSUndoManagerDidUndoChange, -1), (.NSUndoManagerDidRedoChange, 1)] {
            managerObservers.append(NotificationCenter.default.addObserver(forName: name, object: manager, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.followManager(step: step) }
            })
        }
    }

    func perform<T>(_ actionName: String, _ work: () throws -> T) rethrows -> T {
        guard let manager, !manager.isUndoing, !manager.isRedoing else {
            return try work()
        }
        guard !transactionActive else { return try work() }

        let initialGroupingLevel = manager.groupingLevel
        // Prevent Foundation from wrapping an explicit editor transaction in an event group.
        let restoresEventGrouping = manager.groupsByEvent && initialGroupingLevel == 0
        if restoresEventGrouping { manager.groupsByEvent = false }
        transactionActive = true
        transactionGroupOpened = false
        defer {
            let groupOpened = transactionGroupOpened
            transactionActive = false
            transactionGroupOpened = false
            if groupOpened {
                manager.setActionName(actionName)
                manager.endUndoGrouping()
                recordCommit(actionName)
                onActionCommitted?()
            }
            if restoresEventGrouping { manager.groupsByEvent = true }
            assert(manager.groupingLevel == initialGroupingLevel)
        }
        return try work()
    }

    func register<Target: AnyObject>(
        _ actionName: String,
        withTarget target: Target,
        handler: @escaping @MainActor (Target) -> Void
    ) {
        guard let manager, manager.isUndoRegistrationEnabled else { return }
        if !transactionActive, !manager.isUndoing, !manager.isRedoing {
            perform(actionName) { register(actionName, withTarget: target, handler: handler) }
            return
        }
        if transactionActive, !transactionGroupOpened {
            manager.beginUndoGrouping()
            transactionGroupOpened = true
        }
        manager.registerUndo(withTarget: target) { target in handler(target) }
    }

    func withoutRegistration<T>(_ work: () throws -> T) rethrows -> T {
        guard let manager, manager.isUndoRegistrationEnabled else {
            return try work()
        }
        manager.disableUndoRegistration()
        defer { manager.enableUndoRegistration() }
        return try work()
    }

    var isRegistrationEnabled: Bool { manager?.isUndoRegistrationEnabled ?? true }

    func undoLatest() -> String? {
        guard let manager, manager.canUndo else { return nil }
        let actionName = manager.undoActionName
        manager.undo()
        return actionName
    }

    /// Undoes or redoes editor actions until `position` of them are applied. Stops early if the
    /// manager's stack no longer matches the history (e.g. a text field's own undo intervened).
    func jump(toHistoryPosition position: Int) {
        guard let manager, (0...history.count).contains(position) else { return }
        while historyPosition != position {
            let before = historyPosition
            if historyPosition > position {
                guard manager.canUndo, manager.undoActionName == history[historyPosition - 1].actionName else { break }
                manager.undo()
            } else {
                guard manager.canRedo, manager.redoActionName == history[historyPosition].actionName else {
                    history.removeSubrange(historyPosition...)
                    break
                }
                manager.redo()
            }
            guard historyPosition != before else { break }
        }
    }

    private func recordCommit(_ actionName: String) {
        history.removeSubrange(historyPosition...)
        history.append(UndoHistoryEntry(actionName: actionName, date: .now))
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
        historyPosition = history.count
        Log.editor.debug("undo history commit action=\(actionName) position=\(self.historyPosition)")
    }

    /// Mirrors an undo or redo performed through the manager (menu, ⌘Z, agent) when it is an editor action.
    private func followManager(step: Int) {
        guard let manager else { return }
        Log.editor.debug("undo history notified step=\(step) undo=\(manager.undoActionName) redo=\(manager.redoActionName) position=\(self.historyPosition)/\(self.history.count)")
        if step < 0, historyPosition > 0, manager.redoActionName == history[historyPosition - 1].actionName {
            historyPosition -= 1
            lastStep = UndoStepEvent(direction: .undo, actionName: history[historyPosition].actionName,
                                     position: historyPosition, count: history.count)
        } else if step > 0, historyPosition < history.count, manager.undoActionName == history[historyPosition].actionName {
            historyPosition += 1
            lastStep = UndoStepEvent(direction: .redo, actionName: history[historyPosition - 1].actionName,
                                     position: historyPosition, count: history.count)
        } else {
            Log.editor.debug("undo step outside editor history step=\(step) undo=\(manager.undoActionName) redo=\(manager.redoActionName) position=\(self.historyPosition)/\(self.history.count)")
        }
    }

    func removeAllActions<Target: AnyObject>(withTarget target: Target) {
        manager?.removeAllActions(withTarget: target)
    }
}
