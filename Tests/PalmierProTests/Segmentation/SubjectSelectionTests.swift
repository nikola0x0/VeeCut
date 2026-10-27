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
        editor.registerTrackedMask(
            TrackedMask(id: "mask", mediaRef: "media-1", label: "Subject 1", sourceFPS: 30, sourceWidth: 64, sourceHeight: 48),
            frames: [:], file: Data()
        )
        editor.canvasSubject = CanvasSubject(clipId: "clip", maskId: "mask")
        return editor
    }

    @Test func eachLookIsOneUndoStepInItsRegion() throws {
        let editor = editorWithSubject()
        editor.applySubjectLook(.darkenBackground, clipId: "clip", maskId: "mask")
        editor.applySubjectLook(.popSubject, clipId: "clip", maskId: "mask")

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
        editor.applySubjectLook(.blurBackground, clipId: "clip", maskId: "mask")
        editor.applySubjectLook(.blurBackground, clipId: "clip", maskId: "mask")
        #expect(editor.clipFor(id: "clip")?.effectRegions?.first?.effects.count == 1)
    }

    @Test func draggingARegionSliderIsOneUndoStep() throws {
        let editor = editorWithSubject()
        editor.applySubjectLook(.blurBackground, clipId: "clip", maskId: "mask")
        let region = try #require(editor.clipFor(id: "clip")?.effectRegions?.first)
        for radius in [20.0, 30.0, 40.0] {
            editor.editSubjectRegion(clipId: "clip", regionId: region.id, commit: false, actionName: "Change Radius") {
                $0.effects[0].params[Effect.gaussianBlurRadiusKey] = EffectParam(value: radius)
            }
        }
        editor.editSubjectRegion(clipId: "clip", regionId: region.id, commit: true, actionName: "Change Radius") {
            $0.effects[0].params[Effect.gaussianBlurRadiusKey] = EffectParam(value: 40)
        }
        #expect(editor.clipFor(id: "clip")?.effectRegions?.first?.effects.first?.params[Effect.gaussianBlurRadiusKey]?.value == 40)

        undoManager.undo()
        #expect(editor.clipFor(id: "clip")?.effectRegions?.first?.effects.first?.params[Effect.gaussianBlurRadiusKey]?.value == 14)
    }

    @Test func removingTheLastEffectRemovesTheRegion() throws {
        let editor = editorWithSubject()
        editor.applySubjectLook(.blurBackground, clipId: "clip", maskId: "mask")
        let region = try #require(editor.clipFor(id: "clip")?.effectRegions?.first)
        editor.editSubjectRegion(clipId: "clip", regionId: region.id, commit: true, actionName: "Remove Effect") {
            $0.effects.removeAll()
        }
        #expect(editor.clipFor(id: "clip")?.effectRegions == nil)
    }

    @Test func deletingASubjectRemovesItAndItsLooksInOneUndoStep() {
        let editor = editorWithSubject()
        editor.applySubjectLook(.popSubject, clipId: "clip", maskId: "mask")
        editor.applySubjectLook(.darkenBackground, clipId: "clip", maskId: "mask")
        editor.deleteSubject(maskId: "mask")
        #expect(editor.clipFor(id: "clip")?.effectRegions == nil)
        #expect(editor.trackedMasks.isEmpty)
        #expect(editor.canvasSubject == nil)

        undoManager.undo()
        #expect(editor.clipFor(id: "clip")?.effectRegions?.count == 2)
        #expect(editor.trackedMask(id: "mask") != nil)
        undoManager.redo()
        #expect(editor.trackedMasks.isEmpty)
    }

    @Test func undoingALookKeepsTheSubject() {
        let editor = editorWithSubject()
        editor.applySubjectLook(.blurBackground, clipId: "clip", maskId: "mask")
        undoManager.undo()
        #expect(editor.clipFor(id: "clip")?.effectRegions == nil)
        #expect(editor.trackedMask(id: "mask") != nil)
    }

    @Test func renamingASubjectIsUndoableAndIgnoresBlankNames() {
        let editor = editorWithSubject()
        editor.renameSubject(maskId: "mask", to: "  ")
        #expect(!undoManager.canUndo)
        editor.renameSubject(maskId: "mask", to: " Me ")
        #expect(editor.trackedMask(id: "mask")?.label == "Me")
        undoManager.undo()
        #expect(editor.trackedMask(id: "mask")?.label == "Subject 1")
    }

    @Test func subjectsWithoutLooksAreStillSaved() {
        let editor = editorWithSubject()
        editor.mediaAssets = [MediaAsset(id: "media-1", url: URL(fileURLWithPath: "/tmp/x.mov"), type: .video, name: "x", duration: 1)]
        #expect(editor.savedTrackedMasks()?.map(\.id) == ["mask"])
    }

    @Test func newSubjectsAreNumberedPerMedia() {
        let editor = editorWithSubject()
        #expect(editor.nextSubjectName(mediaRef: "media-1") == "Subject 2")
        #expect(editor.nextSubjectName(mediaRef: "other") == "Subject 1")
    }

    @Test func addingAnEffectCreatesTheRegionOnceAndUndoesInOneStep() {
        let editor = editorWithSubject()
        editor.addSubjectEffect("stylize.vignette", outside: true, clipId: "clip", maskId: "mask")
        editor.addSubjectEffect("stylize.vignette", outside: true, clipId: "clip", maskId: "mask")
        let region = editor.clipFor(id: "clip")?.effectRegions?.first
        #expect(region?.matte.invert == true)
        #expect(region?.effects.map(\.type) == ["stylize.vignette"])
        undoManager.undo()
        #expect(editor.clipFor(id: "clip")?.effectRegions == nil)
    }

    @Test func subjectEffectsExcludeKeyingAndSettinglessEffects() {
        let ids = EditorViewModel.subjectEffectDescriptors.map(\.id)
        #expect(ids.contains("color.exposure"))
        #expect(!ids.contains { $0.hasPrefix("key.") })
        #expect(EditorViewModel.subjectEffectDescriptors.allSatisfy { !$0.params.isEmpty })
    }

    @Test func trackingByABlankNameDoesNothing() {
        let editor = editorWithSubject()
        editor.trackSubject(named: "   ", clipId: "clip")
        #expect(!editor.isSubjectTracking)
    }

    private func addDog(_ editor: EditorViewModel) {
        editor.registerTrackedMask(
            TrackedMask(id: "dog", mediaRef: "media-1", label: "Dog", sourceFPS: 30, sourceWidth: 64, sourceHeight: 48),
            frames: [:], file: Data()
        )
    }

    @Test func backgroundLooksKeepEverySubjectSharpInOneSharedRegion() {
        let editor = editorWithSubject()
        addDog(editor)
        editor.applySubjectLook(.blurBackground, clipId: "clip", maskId: "mask")
        editor.applySubjectLook(.darkenBackground, clipId: "clip", maskId: "dog")
        let backgrounds = editor.clipFor(id: "clip")?.effectRegions?.filter(\.matte.invert) ?? []
        #expect(backgrounds.count == 1)
        #expect(backgrounds.first?.matte.maskIds == ["mask", "dog"])
        #expect(backgrounds.first?.effects.count == 3)
    }

    @Test func keepSharpTogglesASubjectButNeverEmptiesTheBackground() {
        let editor = editorWithSubject()
        addDog(editor)
        editor.applySubjectLook(.blurBackground, clipId: "clip", maskId: "mask")
        editor.setKeepsSharp(false, maskId: "dog", clipId: "clip")
        #expect(editor.clipFor(id: "clip")?.effectRegions?.first?.matte.maskIds == ["mask"])
        editor.setKeepsSharp(false, maskId: "mask", clipId: "clip")
        #expect(editor.clipFor(id: "clip")?.effectRegions?.first?.matte.maskIds == ["mask"])
        undoManager.undo()
        #expect(editor.clipFor(id: "clip")?.effectRegions?.first?.matte.maskIds == ["mask", "dog"])
    }

    @Test func deletingOneSubjectKeepsTheBackgroundForTheOthers() {
        let editor = editorWithSubject()
        addDog(editor)
        editor.applySubjectLook(.blurBackground, clipId: "clip", maskId: "mask")
        editor.deleteSubject(maskId: "dog")
        #expect(editor.clipFor(id: "clip")?.effectRegions?.first?.matte.maskIds == ["mask"])
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
