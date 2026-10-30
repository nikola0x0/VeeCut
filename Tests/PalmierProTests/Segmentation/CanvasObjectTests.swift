import CoreGraphics
import Foundation
import Testing
@testable import PalmierPro

@Suite("Canvas objects")
@MainActor
struct CanvasObjectTests {
    private let undoManager = UndoManager()

    private func editor(clips: [Clip] = [Fixtures.clip(id: "clip", start: 0, duration: 30)]) -> EditorViewModel {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: clips.map { Fixtures.videoTrack(clips: [$0]) })
        editor.undo.attach(undoManager)
        return editor
    }

    @discardableResult
    private func trackedMask(in editor: EditorViewModel, presentAt seconds: [Double]) -> TrackedMask {
        Fixtures.trackedMask(in: editor, presentAt: seconds)
    }

    @Test func shelfShowsTheSelectedVideoClipElseTheTopmostUnderThePlayhead() {
        let editor = editor(clips: [Fixtures.clip(id: "top", start: 0, duration: 30), Fixtures.clip(id: "below", start: 0, duration: 30)])
        #expect(editor.shelfClipId == "top")
        editor.selectedClipIds = ["below"]
        #expect(editor.shelfClipId == "below")
    }

    @Test func trackedObjectQualifiesOnlyWhenPresentInTheClipsSourceRange() {
        let editor = editor(clips: [Fixtures.clip(id: "clip", start: 0, duration: 30, trimStart: 60, speed: 2)])
        let early = trackedMask(in: editor, presentAt: [1, 1.5])
        let inside = trackedMask(in: editor, presentAt: [3])
        let ids = editor.canvasObjects(clipId: "clip").map(\.id)
        #expect(ids == [inside.id])
        #expect(!ids.contains(early.id))
    }

    @Test func unloadedTrackedMaskIsNotListed() {
        let editor = editor()
        editor.trackedMasks = [TrackedMask(id: UUID().uuidString, mediaRef: "media-1", label: "Cat", sourceFPS: 30, sourceWidth: 64, sourceHeight: 48)]
        #expect(editor.canvasObjects(clipId: "clip").isEmpty)
    }

    @Test func coversUsesTheMaskBitAtThatTime() {
        let editor = editor()
        let mask = trackedMask(in: editor, presentAt: [0.5])
        let store = MatteStore.shared
        #expect(store.covers(maskId: mask.id, sourcePoint: CGPoint(x: 0.3, y: 0.5), sourceSeconds: 0.5))
        #expect(!store.covers(maskId: mask.id, sourcePoint: CGPoint(x: 0.7, y: 0.5), sourceSeconds: 0.5))
        #expect(!store.covers(maskId: mask.id, sourcePoint: CGPoint(x: 0.1, y: 0.5), sourceSeconds: 0.5))
        #expect(!store.covers(maskId: mask.id, sourcePoint: CGPoint(x: 0.3, y: 0.5), sourceSeconds: 2))
        #expect(store.sourceBounds(maskId: mask.id, sourceSeconds: 0.5) == CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    }

    @Test func selectingAnOffscreenObjectSeeksToItsNearestVisibleFrame() {
        let editor = editor(clips: [Fixtures.clip(id: "clip", start: 0, duration: 120)])
        let mask = trackedMask(in: editor, presentAt: [3])
        editor.selectCanvasObject(clipId: "clip", maskId: mask.id)
        #expect(editor.activeFrame == 90)
        #expect(editor.validCanvasSubject == CanvasSubject(clipId: "clip", maskId: mask.id))
        #expect(editor.objectCardOpen)
        #expect(editor.selectedClipIds == ["clip"])
    }

    @Test func clickInsideAnOutlineSelectsTheNewestObject() {
        let editor = editor()
        trackedMask(in: editor, presentAt: [0])
        let newer = trackedMask(in: editor, presentAt: [0])
        #expect(editor.canvasObjectId(atSource: CGPoint(x: 0.3, y: 0.5), clipId: "clip") == newer.id)
        #expect(editor.canvasObjectId(atSource: CGPoint(x: 0.6, y: 0.5), clipId: "clip") == nil)
        #expect(editor.canvasObjectId(atSource: CGPoint(x: 0.9, y: 0.9), clipId: "clip") == nil)
    }

    @Test func selectionClearsWhenItsMaskOrClipDisappears() {
        let editor = editor()
        let mask = trackedMask(in: editor, presentAt: [0])
        editor.selectCanvasObject(clipId: "clip", maskId: mask.id)
        editor.deleteSubject(maskId: mask.id)
        #expect(editor.validCanvasSubject == nil)
        #expect(!editor.objectCardOpen)

        let other = trackedMask(in: editor, presentAt: [0])
        editor.selectCanvasObject(clipId: "clip", maskId: other.id)
        editor.deleteSelectedClips()
        #expect(editor.validCanvasSubject == nil)
    }

    @Test func playingClosesTheCardButKeepsTheSelection() {
        let editor = editor()
        editor.selectCanvasObject(clipId: "clip", maskId: nil)
        #expect(editor.objectCardOpen)
        editor.play()
        #expect(!editor.objectCardOpen)
        #expect(editor.validCanvasSubject == CanvasSubject(clipId: "clip", maskId: nil))
    }

    @Test func deleteKeyRemovesTheSelectedObjectOnlyWhenThePreviewHasFocus() {
        let editor = editor()
        let mask = trackedMask(in: editor, presentAt: [0])
        editor.selectCanvasObject(clipId: "clip", maskId: mask.id)
        editor.focusedPanel = .timeline
        #expect(!editor.deleteSelectedCanvasObject())
        editor.focusedPanel = .preview
        #expect(editor.deleteSelectedCanvasObject())
        #expect(editor.trackedMask(id: mask.id) == nil)
    }

    @Test func clickingASelectedChipAgainDeselectsIt() {
        let editor = editor()
        editor.toggleCanvasObject(clipId: "clip", maskId: nil)
        #expect(editor.validCanvasSubject == CanvasSubject(clipId: "clip", maskId: nil))
        editor.toggleCanvasObject(clipId: "clip", maskId: nil)
        #expect(editor.validCanvasSubject == nil)
        #expect(!editor.objectCardOpen)

        let mask = trackedMask(in: editor, presentAt: [0])
        editor.toggleCanvasObject(clipId: "clip", maskId: nil)
        editor.toggleCanvasObject(clipId: "clip", maskId: mask.id)
        #expect(editor.validCanvasSubject?.maskId == mask.id)
    }
}

private actor RenderCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

@MainActor
@Test func thumbnailRequestsAreDeduplicatedPerMask() async throws {
    let image = try #require(CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )?.makeImage())
    let counter = RenderCounter()
    let (gate, release) = AsyncStream<Void>.makeStream()
    let thumbnails = ObjectThumbnails { _, _, _ in
        await counter.increment()
        for await _ in gate { break }
        return image
    }
    let url = URL(fileURLWithPath: "/dev/null")
    async let first: Void = thumbnails.load(maskId: "mask", url: url, sourceSeconds: 0, bounds: .zero)
    async let second: Void = thumbnails.load(maskId: "mask", url: url, sourceSeconds: 0, bounds: .zero)
    release.yield()
    _ = await (first, second)
    #expect(await counter.count == 1)
    #expect(thumbnails.images["mask"] != nil)
}
