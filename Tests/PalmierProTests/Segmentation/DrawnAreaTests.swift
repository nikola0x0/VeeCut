import Foundation
import Testing
@testable import PalmierPro

@Suite("Drawn areas")
@MainActor
struct DrawnAreaTests {
    private let undoManager = UndoManager()
    private let square = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.4, y: 0.1), CGPoint(x: 0.4, y: 0.4), CGPoint(x: 0.1, y: 0.4)]

    private func editor() -> EditorViewModel {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [Fixtures.clip(id: "clip", start: 0, duration: 30)])])
        editor.undo.attach(undoManager)
        return editor
    }

    @Test func anOpenDragDrawsTheRectangleItSpans() throws {
        let outline = try #require(AreaMark.outline([CGPoint(x: 10, y: 20), CGPoint(x: 60, y: 45), CGPoint(x: 110, y: 90)]))
        #expect(outline == [CGPoint(x: 10, y: 20), CGPoint(x: 110, y: 20), CGPoint(x: 110, y: 90), CGPoint(x: 10, y: 90)])
    }

    @Test func aClosedLoopDrawsAFreehandOutline() throws {
        let loop = (0...40).map { step in
            let angle = Double(step) / 40 * 2 * .pi
            return CGPoint(x: 100 + 50 * cos(angle), y: 100 + 50 * sin(angle))
        }
        let outline = try #require(AreaMark.outline(loop))
        #expect(outline.count == loop.count)
        #expect(outline.count <= AreaMark.maxOutlinePoints)
    }

    @Test func aTapDrawsNothing() {
        #expect(AreaMark.outline([CGPoint(x: 10, y: 10), CGPoint(x: 12, y: 11)]) == nil)
    }

    @Test(arguments: [
        [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.4, y: 0.1)],
        [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.105, y: 0.1), CGPoint(x: 0.105, y: 0.4)],
        [CGPoint(x: .nan, y: 0.1), CGPoint(x: 0.4, y: 0.1), CGPoint(x: 0.4, y: 0.4)],
    ])
    func unusableOutlinesAreRejected(_ outline: [CGPoint]) {
        #expect(AreaMark.validatedSourceOutline(outline) == nil)
    }

    @Test func outlinesAreClampedToTheFrame() {
        let outline = AreaMark.validatedSourceOutline([CGPoint(x: -0.5, y: 0.2), CGPoint(x: 1.5, y: 0.2), CGPoint(x: 0.5, y: 0.9)])
        #expect(outline == [CGPoint(x: 0, y: 0.2), CGPoint(x: 1, y: 0.2), CGPoint(x: 0.5, y: 0.9)])
    }

    @Test func drawingAnAreaAddsANamedSubjectInOneUndoStep() throws {
        let editor = editor()
        editor.canvasSelection = .area
        editor.drawArea(clipId: "clip", outline: square)

        let area = try #require(editor.trackedMasks.first)
        #expect(area.label == "Area 1")
        #expect(area.area == square)
        #expect(editor.canvasSubject == CanvasSubject(clipId: "clip", maskId: area.id))
        #expect(editor.canvasSelection == nil)
        #expect(editor.nextSubjectName(mediaRef: area.mediaRef) == "Subject 1")

        undoManager.undo()
        #expect(editor.trackedMasks.isEmpty)
        undoManager.redo()
        #expect(editor.trackedMasks.map(\.id) == [area.id])
    }

    @Test func anUnusableAreaChangesNothing() {
        let editor = editor()
        editor.drawArea(clipId: "clip", outline: Array(square.prefix(2)))
        editor.drawArea(clipId: "missing", outline: square)
        #expect(editor.trackedMasks.isEmpty)
        #expect(!undoManager.canUndo)
    }

    @Test func areasSaveWithoutAMaskFileAndRestoreForRendering() throws {
        let editor = editor()
        editor.mediaAssets = [MediaAsset(id: "media-1", url: URL(fileURLWithPath: "/tmp/x.mov"), type: .video, name: "x", duration: 1)]
        editor.drawArea(clipId: "clip", outline: square)
        let saved = try #require(editor.savedTrackedMasks())
        #expect(editor.trackedMaskFileSnapshot().isEmpty)

        let reopened = EditorViewModel()
        reopened.trackedMasks = try JSONDecoder().decode([TrackedMask].self, from: JSONEncoder().encode(saved))
        MatteStore.shared.remove(maskIds: saved.map(\.id))
        reopened.restoreTrackedMasks(files: [:])
        #expect(reopened.trackedMasks.first?.area == square)
        #expect(MatteStore.shared.matte(maskId: saved[0].id, mediaRef: "media-1", sourceSeconds: 0) != nil)
        MatteStore.shared.remove(maskIds: saved.map(\.id))
    }

    @Test func aLookOnAnAreaGradesItAndTheBackground() throws {
        let editor = editor()
        editor.drawArea(clipId: "clip", outline: square)
        let area = try #require(editor.trackedMasks.first)
        editor.applySubjectLook(.moody, clipId: "clip", maskId: area.id)
        let regions = try #require(editor.clipFor(id: "clip")?.effectRegions)
        #expect(regions.count == 2)
        #expect(regions.allSatisfy { $0.matte.maskIds == [area.id] })
        MatteStore.shared.remove(maskIds: [area.id])
    }
}
