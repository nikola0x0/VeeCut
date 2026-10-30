import CoreGraphics
import Foundation
import Testing
@testable import PalmierPro

@Suite("Smooth Skin")
@MainActor
struct SmoothSkinTests {
    private let undoManager = UndoManager()

    private func editor() -> EditorViewModel {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [Fixtures.clip(id: "clip", start: 0, duration: 30)])])
        editor.undo.attach(undoManager)
        return editor
    }

    private func smoothSkinRegions(_ editor: EditorViewModel) -> [EffectRegion] {
        (editor.clipFor(id: "clip")?.effectRegions ?? []).filter { $0.effects.contains { $0.type == EditorViewModel.smoothSkinEffect } }
    }

    @Test func retouchesOnlyThePersonsFaceInOneUndoStep() throws {
        let editor = editor()
        let person = Fixtures.trackedMask(in: editor, label: "Nikola", presentAt: [0.5])
        let face = Fixtures.trackedMask(in: editor, label: "Nikola’s face", presentAt: [0.5], face: FaceLink(personMaskId: person.id))
        defer { editor.releaseTrackedMasks() }

        editor.smoothSkin(clipId: "clip", person: person.id)

        let region = try #require(smoothSkinRegions(editor).first)
        #expect(smoothSkinRegions(editor).count == 1)
        #expect(region.matte.maskIds == [face.id] && !region.matte.invert)
        #expect(region.effects.first?.params["blemishes"]?.value == EditorViewModel.smoothSkinDefaults.blemishes)
        #expect(!editor.isSubjectTracking)
        #expect(editor.canvasSubject == CanvasSubject(clipId: "clip", maskId: face.id))
        undoManager.undo()
        #expect(editor.clipFor(id: "clip")?.effectRegions == nil)
    }

    @Test func aSelectedFaceIsRetouchedDirectly() throws {
        let editor = editor()
        let face = Fixtures.trackedMask(in: editor, label: "Face", presentAt: [0.5], face: FaceLink(personMaskId: nil))
        defer { editor.releaseTrackedMasks() }
        editor.smoothSkin(clipId: "clip", person: face.id)
        #expect(try #require(smoothSkinRegions(editor).first).matte.maskIds == [face.id])
    }

    @Test func fullFrameUsesTheClipsFaceNotAnotherPersonsFace() throws {
        let editor = editor()
        let person = Fixtures.trackedMask(in: editor, presentAt: [0.5])
        Fixtures.trackedMask(in: editor, presentAt: [0.5], face: FaceLink(personMaskId: person.id))
        let clipFace = Fixtures.trackedMask(in: editor, presentAt: [0.5], face: FaceLink(personMaskId: nil))
        defer { editor.releaseTrackedMasks() }
        #expect(editor.trackedFace(clipId: "clip", person: nil)?.id == clipFace.id)
    }

    @Test func theFaceLinkIsSavedWithTheMask() throws {
        var mask = TrackedMask(mediaRef: "media-1", label: "Face", sourceFPS: 30, sourceWidth: 64, sourceHeight: 48)
        mask.face = FaceLink(personMaskId: "person")
        let decoded = try JSONDecoder().decode(TrackedMask.self, from: JSONEncoder().encode(mask))
        #expect(decoded.face == FaceLink(personMaskId: "person"))
    }

    @Test func smoothSkinIsNotOfferedAsAGenericSubjectEffect() {
        #expect(!EditorViewModel.subjectEffectDescriptors.contains { $0.id == EditorViewModel.smoothSkinEffect })
    }

    private static func object(_ box: SAMBox, frames: Range<Int>) -> [Int: MaskFrame] {
        let frame = MaskFrame(SAMObjectRecord(objectID: 1, box: box, mask: SAMMaskRaster(width: 1, height: 1, bits: [1]), confidence: nil))
        return Dictionary(uniqueKeysWithValues: frames.map { ($0, frame) })
    }

    @Test func trackingPrefersTheMatchInsideThePersonOverTheMostPersistentOne() throws {
        let inside = Self.object(SAMBox(left: 10, top: 10, right: 20, bottom: 20, sourceWidth: 100, sourceHeight: 100), frames: 0..<10)
        let elsewhere = Self.object(SAMBox(left: 70, top: 10, right: 80, bottom: 20, sourceWidth: 100, sourceHeight: 100), frames: 0..<30)
        let person = (0..<30).map { TimedBox(seconds: 2 + Double($0) / 30, box: CGRect(x: 0, y: 0, width: 0.4, height: 0.6)) }
        let chosen = ObjectTracker.mostInside([elsewhere, inside], within: person, startSeconds: 2, fps: 30)
        #expect(chosen == inside)
        let away = person.map { TimedBox(seconds: $0.seconds, box: CGRect(x: 0.9, y: 0.9, width: 0.1, height: 0.1)) }
        #expect(ObjectTracker.mostInside([elsewhere, inside], within: away, startSeconds: 2, fps: 30) == nil)
    }
}
