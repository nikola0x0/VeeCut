import Foundation
import Testing
@testable import PalmierPro

@MainActor
@Test(arguments: [
    (0.0, false, false), (30.0, false, false), (-75.0, true, false), (180.0, false, true), (12.5, true, true),
] as [(Double, Bool, Bool)])
func previewSourceMappingRoundTrips(rotation: Double, flipHorizontal: Bool, flipVertical: Bool) throws {
    var clip = Fixtures.clip(start: 0, duration: 30)
    clip.transform = Transform(centerX: 0.4, centerY: 0.6, width: 0.5, height: 0.7, rotation: rotation)
    clip.transform.flipHorizontal = flipHorizontal
    clip.transform.flipVertical = flipVertical
    let videoRect = CGRect(x: 20, y: 10, width: 640, height: 360)

    for source in [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.9, y: 0.75)] {
        let view = try #require(PreviewHitTester.viewPoint(ofSource: source, clip: clip, frame: 0, videoRect: videoRect))
        let back = try #require(PreviewHitTester.sourcePoint(of: view, clip: clip, frame: 0, videoRect: videoRect))
        #expect(abs(back.x - source.x) < 1e-9 && abs(back.y - source.y) < 1e-9)
    }
}

@MainActor
@Test func unrotatedClipMapsSourceCornersToClipRect() throws {
    var clip = Fixtures.clip(start: 0, duration: 30)
    clip.transform = Transform(centerX: 0.5, centerY: 0.5, width: 0.5, height: 0.5)
    let videoRect = CGRect(x: 0, y: 0, width: 400, height: 200)
    let topLeft = try #require(PreviewHitTester.viewPoint(ofSource: .zero, clip: clip, frame: 0, videoRect: videoRect))
    #expect(topLeft == CGPoint(x: 100, y: 50))
}

@Test func targetPromptMapsNormalizedBoxAndPointsToSourcePixelsOnTheRightFrame() throws {
    let target = TrackingTarget(
        sourceSeconds: 2.5,
        box: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25),
        points: [TrackingPoint(x: 0.5, y: 0.6), TrackingPoint(x: 0.1, y: 0.1, isPositive: false)]
    )
    let text = try ObjectTracker.targetPrompt(target, rangeStart: 2, fps: 30, frameCount: 60, width: 1920, height: 1080)
    #expect(text == "<15f>1<|box;x1=480;y1=540;x2=1440;y2=810;w=1920;h=1080|>"
        + "<|point;x=960;y=648;w=1920;h=1080|>-<|point;x=192;y=108;w=1920;h=1080|>")
}

@Test(arguments: [
    TrackingTarget(sourceSeconds: 1, box: nil, points: []),
    TrackingTarget(sourceSeconds: .nan, box: nil, points: [TrackingPoint(x: 0.5, y: 0.5)]),
    TrackingTarget(sourceSeconds: 1, box: nil, points: [TrackingPoint(x: 1.5, y: 0.5)]),
    TrackingTarget(sourceSeconds: 1, box: CGRect(x: 0.5, y: 0.5, width: 0, height: 0.2)),
])
func targetPromptRejectsInvalidTargets(target: TrackingTarget) {
    #expect(throws: TrackingError.invalidTarget) {
        try ObjectTracker.targetPrompt(target, rangeStart: 0, fps: 30, frameCount: 60, width: 100, height: 100)
    }
}

@Suite("Subject looks")
@MainActor
struct SubjectLookTests {
    private let undoManager = UndoManager()

    private func editorWithSubject() -> EditorViewModel {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [Fixtures.clip(id: "clip", start: 0, duration: 30)])])
        editor.undo.attach(undoManager)
        editor.canvasSubject = CanvasSubject(clipId: "clip", maskId: "mask")
        return editor
    }

    @Test func eachLookIsOneUndoStepInItsRegion() throws {
        let editor = editorWithSubject()
        editor.applySubjectLook(.darkenBackground)
        editor.applySubjectLook(.popSubject)

        let regions = try #require(editor.clipFor(id: "clip")?.effectRegions)
        #expect(regions.count == 2)
        #expect(regions.first { $0.matte.invert }?.effects.map(\.type) == ["color.exposure", "color.saturation"])
        #expect(editor.clipFor(id: "clip")?.effects == nil)

        undoManager.undo()
        #expect(editor.clipFor(id: "clip")?.effectRegions?.count == 1)
        undoManager.undo()
        #expect(editor.clipFor(id: "clip")?.effectRegions == nil)
    }

    @Test func reapplyingALookDoesNotDuplicateEffects() throws {
        let editor = editorWithSubject()
        editor.applySubjectLook(.blurBackground)
        editor.applySubjectLook(.blurBackground)
        #expect(editor.clipFor(id: "clip")?.effectRegions?.first?.effects.count == 1)
    }

    @Test func escapeDismissesSelectionModeBeforeSubject() {
        let editor = editorWithSubject()
        editor.toggleSubjectSelection()
        #expect(editor.cancelSubjectInteraction())
        #expect(!editor.subjectSelectionActive)
        #expect(editor.canvasSubject != nil)
        #expect(editor.cancelSubjectInteraction())
        #expect(editor.canvasSubject == nil)
        #expect(!editor.cancelSubjectInteraction())
    }
}
