import Foundation
import Testing
@testable import PalmierPro

private func sampleFrames() -> [Int: MaskFrame] {
    let box = SAMBox(left: 10, top: 20, right: 14, bottom: 23, sourceWidth: 64, sourceHeight: 48)
    return [
        0: MaskFrame(SAMObjectRecord(objectID: 1, box: box, mask: SAMMaskRaster(width: 4, height: 3, bits: [1, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 1]), confidence: nil)),
        7: MaskFrame(SAMObjectRecord(objectID: 1, box: box, mask: SAMMaskRaster(width: 4, height: 3, bits: Array(repeating: 1, count: 12)), confidence: nil)),
    ]
}

private func sampleMask() -> TrackedMask {
    TrackedMask(mediaRef: "media-1", label: "person", sourceFPS: 30, sourceWidth: 64, sourceHeight: 48)
}

@Test func trackedMaskFileRoundTripsFrames() throws {
    let frames = sampleFrames()
    #expect(try TrackedMaskFile.decode(TrackedMaskFile.encode(frames)) == frames)
}

@Test func projectPackagePersistsReferencedTrackedMasks() throws {
    let fm = FileManager.default
    let package = fm.temporaryDirectory.appendingPathComponent("mask-pkg-\(UUID().uuidString).palmier", isDirectory: true)
    defer { try? fm.removeItem(at: package) }
    let mask = sampleMask()
    let frames = sampleFrames()
    var clip = Fixtures.clip(mediaRef: mask.mediaRef, start: 0, duration: 30)
    clip.effects = [Effect(type: "color.exposure", matte: EffectMatte(maskId: mask.id))]
    let timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [clip])])
    let file = ProjectFile(timelines: [timeline], activeTimelineId: timeline.id, trackedMasks: [mask])

    try VideoProject.writeProjectPackage(
        ProjectPackageSnapshot(
            timeline: try JSONEncoder().encode(file),
            chatSessionFiles: [],
            maskFiles: [(name: TrackedMaskFile.fileName(maskId: mask.id), data: TrackedMaskFile.encode(frames))]
        ),
        to: package,
        sourceURL: nil
    )
    let contents = try VideoProject.readProjectPackage(at: package)

    #expect(contents.projectFile.trackedMasks == [mask])
    #expect(try TrackedMaskFile.decode(try #require(contents.maskFiles[mask.id])) == frames)
}

@MainActor
@Test func onlyMasksReferencedByEffectsAreSaved() {
    let editor = EditorViewModel()
    let used = sampleMask()
    let unused = sampleMask()
    editor.registerTrackedMask(used, frames: sampleFrames(), file: Data("used".utf8))
    editor.registerTrackedMask(unused, frames: sampleFrames(), file: Data("unused".utf8))
    defer { editor.releaseTrackedMasks() }
    var clip = Fixtures.clip(mediaRef: used.mediaRef, start: 0, duration: 30)
    clip.effects = [Effect(type: "color.exposure", matte: EffectMatte(maskId: used.id))]
    editor.timelines = [Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [clip])])]

    #expect(editor.savedTrackedMasks() == [used])
    #expect(editor.trackedMaskFileSnapshot().map(\.name) == [TrackedMaskFile.fileName(maskId: used.id)])
}
