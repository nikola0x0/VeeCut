import Foundation
@testable import PalmierPro

enum Fixtures {
    static func clip(
        id: String = UUID().uuidString,
        mediaRef: String = "media-1",
        mediaType: ClipType = .video,
        start: Int,
        duration: Int,
        trimStart: Int = 0,
        trimEnd: Int = 0,
        speed: Double = 1.0,
        volume: Double = 1.0
    ) -> Clip {
        var c = Clip(mediaRef: mediaRef, startFrame: start, durationFrames: duration)
        c.id = id
        c.mediaType = mediaType
        c.sourceClipType = mediaType
        c.trimStartFrame = trimStart
        c.trimEndFrame = trimEnd
        c.speed = speed
        c.volume = volume
        return c
    }

    static func videoTrack(id: String = UUID().uuidString, clips: [Clip] = []) -> Track {
        var t = Track(type: .video, clips: clips)
        t.id = id
        return t
    }

    static func audioTrack(id: String = UUID().uuidString, clips: [Clip] = []) -> Track {
        var t = Track(type: .audio, clips: clips)
        t.id = id
        return t
    }

    static func timeline(fps: Int = 30, tracks: [Track] = []) -> Timeline {
        var t = Timeline()
        t.fps = fps
        t.tracks = tracks
        return t
    }

    /// Registers a 64×48 tracked mask on media-1 whose object fills its box's left half at each present second (30 fps).
    @MainActor
    @discardableResult
    static func trackedMask(in editor: EditorViewModel, label: String = "Dog", presentAt seconds: [Double], face: FaceLink? = nil) -> TrackedMask {
        var mask = TrackedMask(id: UUID().uuidString, mediaRef: "media-1", label: label, sourceFPS: 30, sourceWidth: 64, sourceHeight: 48)
        mask.face = face
        let box = SAMBox(left: 16, top: 12, right: 48, bottom: 36, sourceWidth: 64, sourceHeight: 48)
        let frame = MaskFrame(SAMObjectRecord(objectID: 1, box: box, mask: SAMMaskRaster(width: 2, height: 1, bits: [1, 0]), confidence: nil))
        editor.registerTrackedMask(mask, frames: Dictionary(uniqueKeysWithValues: seconds.map { (Int(($0 * 30).rounded()), frame) }), file: Data())
        return mask
    }

    /// Registers a 64×48 tracked mask on media-1 whose 16 px box moves right 1 px per frame from x = 8, present on frames 0…29 (30 fps).
    @MainActor
    static func movingTrackedMask(in editor: EditorViewModel, label: String = "Cat") -> TrackedMask {
        let mask = TrackedMask(id: UUID().uuidString, mediaRef: "media-1", label: label, sourceFPS: 30, sourceWidth: 64, sourceHeight: 48)
        let frames = Dictionary(uniqueKeysWithValues: (0..<30).map { index in
            let box = SAMBox(left: 8 + index, top: 16, right: 24 + index, bottom: 32, sourceWidth: 64, sourceHeight: 48)
            return (index, MaskFrame(SAMObjectRecord(objectID: 1, box: box, mask: SAMMaskRaster(width: 1, height: 1, bits: [1]), confidence: nil)))
        })
        editor.registerTrackedMask(mask, frames: frames, file: Data())
        return mask
    }
}
