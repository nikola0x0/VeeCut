import CoreImage
import Testing
@testable import PalmierPro

@Suite("Compositor — masked effects")
@MainActor
struct MaskedEffectRenderTests {
    private static let isRed = CompositorFixtures.isRed
    private static let isGreen = CompositorFixtures.isGreen

    /// Installs a mask over the whole 320×180 frame whose 2×2 raster sets only the top-left cell.
    private static func installTopLeftMask(frames: ClosedRange<Int>? = 0...120) -> String {
        let id = UUID().uuidString
        let box = SAMBox(left: 0, top: 0, right: 320, bottom: 180, sourceWidth: 320, sourceHeight: 180)
        let object = SAMObjectRecord(objectID: 1, box: box, mask: SAMMaskRaster(width: 2, height: 2, bits: [1, 0, 0, 0]), confidence: nil)
        let timelineFPS = Fixtures.timeline(tracks: []).fps
        let mask = TrackedMask(id: id, mediaRef: "pattern", label: "corner", sourceFPS: Double(timelineFPS), sourceWidth: 320, sourceHeight: 180)
        let keyed = (frames.map { Array($0) } ?? []).map { ($0, MaskFrame(object)) }
        MatteStore.shared.install(mask, frames: Dictionary(uniqueKeysWithValues: keyed))
        return id
    }

    private static func invertedClip(matte: EffectMatte) -> Clip {
        var clip = CompositorFixtures.patternClip()
        clip.effectRegions = [EffectRegion(matte: matte, effects: [Effect(type: "stylize.invert")])]
        return clip
    }

    private static func render(_ clip: Clip) async throws -> CompositorRenderTests.Frame {
        try await CompositorRenderTests.render(
            CompositorFixtures.timeline([Fixtures.videoTrack(clips: [clip])]), frame: 15
        )
    }

    @Test func effectAppliesOnlyInsideTrackedMask() async throws {
        let frame = try await Self.render(Self.invertedClip(matte: EffectMatte(maskId: Self.installTopLeftMask())))

        #expect(!Self.isRed(frame.tl), "inside the mask should be inverted: \(frame.tl)")
        #expect(Self.isGreen(frame.tr), "outside the mask should be untouched: \(frame.tr)")
    }

    @Test func invertedMatteAppliesEffectOutsideMask() async throws {
        let frame = try await Self.render(Self.invertedClip(matte: EffectMatte(maskId: Self.installTopLeftMask(), invert: true)))

        #expect(Self.isRed(frame.tl), "inside an inverted matte should be untouched: \(frame.tl)")
        #expect(!Self.isGreen(frame.tr), "outside an inverted matte should be inverted: \(frame.tr)")
    }

    @Test func frameWithoutTrackedObjectLeavesClipUntouched() async throws {
        let frame = try await Self.render(Self.invertedClip(matte: EffectMatte(maskId: Self.installTopLeftMask(frames: nil))))

        #expect(Self.isRed(frame.tl), "no object on this frame means nothing to affect: \(frame.tl)")
    }

    @Test func unloadedMaskSkipsTheEffect() async throws {
        let frame = try await Self.render(Self.invertedClip(matte: EffectMatte(maskId: "missing-mask")))

        #expect(Self.isRed(frame.tl))
        #expect(Self.isGreen(frame.tr))
    }
}
