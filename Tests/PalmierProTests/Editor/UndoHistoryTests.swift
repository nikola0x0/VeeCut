import Foundation
import Testing
@testable import PalmierPro

@Suite("Undo history")
@MainActor
struct UndoHistoryTests {
    private final class Counter { var value = 0 }

    private let manager = UndoManager()
    private let undo = EditorUndo()
    private let counter = Counter()

    init() {
        manager.groupsByEvent = false
        undo.attach(manager)
    }

    private func edit(_ name: String) {
        undo.perform(name) {
            let before = counter.value
            counter.value += 1
            registerRestore(name, to: before)
        }
    }

    private func registerRestore(_ name: String, to value: Int) {
        undo.register(name, withTarget: counter) { [self] counter in
            let current = counter.value
            counter.value = value
            registerRestore(name, to: current)
        }
    }

    @Test func committedActionsAreRecordedInOrder() {
        edit("Move Clip"); edit("Apply Look")
        #expect(undo.history.map(\.actionName) == ["Move Clip", "Apply Look"])
        #expect(undo.historyPosition == 2)
    }

    @Test func undoAndRedoFromTheManagerMoveThePositionAndAnnounceTheStep() {
        edit("Move Clip"); edit("Apply Look")
        manager.undo()
        #expect(undo.historyPosition == 1)
        let step = undo.lastStep
        #expect(step?.direction == .undo && step?.actionName == "Apply Look" && step?.position == 1 && step?.count == 2)
        manager.redo()
        #expect(undo.historyPosition == 2)
        #expect(undo.lastStep?.direction == .redo)
        #expect(counter.value == 2)
    }

    @Test func aNewActionAfterUndoReplacesTheUndoneOnes() {
        edit("Move Clip"); edit("Apply Look")
        manager.undo()
        edit("Trim Clip")
        #expect(undo.history.map(\.actionName) == ["Move Clip", "Trim Clip"])
        #expect(undo.historyPosition == 2)
    }

    @Test func jumpingUndoesAndRedoesToTheChosenPoint() {
        edit("A"); edit("B"); edit("C")
        undo.jump(toHistoryPosition: 0)
        #expect(undo.historyPosition == 0)
        #expect(counter.value == 0)
        undo.jump(toHistoryPosition: 2)
        #expect(undo.historyPosition == 2)
        #expect(counter.value == 2)
    }

    @Test func foreignUndoActionsDoNotMoveTheHistory() {
        edit("Move Clip")
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: counter) { _ in }
        manager.setActionName("Typing")
        manager.endUndoGrouping()
        manager.undo()
        #expect(undo.historyPosition == 1)
        #expect(undo.lastStep == nil)
    }

    @Test func historyIsCappedKeepingTheNewestActions() {
        for index in 0..<(EditorUndo.historyLimit + 5) { edit("Edit \(index)") }
        #expect(undo.history.count == EditorUndo.historyLimit)
        #expect(undo.history.last?.actionName == "Edit \(EditorUndo.historyLimit + 4)")
        #expect(undo.historyPosition == EditorUndo.historyLimit)
    }
}
