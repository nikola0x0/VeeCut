import CoreGraphics
import Foundation

enum SmoothSkinFailure: Error, Equatable {
    case clipNotFound, notVideo, personNotFound
}

/// Smooth Skin retouches faces only: the face of a person, or the clip's most visible face, found once with SAM and reused.
extension EditorViewModel {
    nonisolated static let smoothSkinEffect = "retouch.smoothSkin"
    static let smoothSkinDefaults = (smoothing: 0.6, blemishes: 1.0)

    /// The face already found for `person` (nil: the clip's most visible face), or `person` itself when it is a face.
    func trackedFace(clipId: String, person: String?) -> TrackedMask? {
        if let person, let mask = trackedMask(id: person), mask.face != nil { return mask }
        return canvasObjects(clipId: clipId).first { $0.face == FaceLink(personMaskId: person) }
    }

    /// Smooth Skin from the dock: reuses the face or finds it with the dock's progress, then retouches it.
    func smoothSkin(clipId: String, person: String?) {
        if let face = trackedFace(clipId: clipId, person: person) {
            applySmoothSkin(clipId: clipId, faceId: face.id)
            selectCanvasObject(clipId: clipId, maskId: face.id)
            return
        }
        guard !isSubjectTracking else { return }
        runSubjectTracking(clipId: clipId, track: { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.findFace(clipId: clipId, person: person)
        }, then: { [weak self] face in
            self?.applySmoothSkin(clipId: clipId, faceId: face.id)
        })
    }

    /// The face to retouch, tracking it with SAM when it hasn't been found yet.
    func findFace(clipId: String, person: String?) async throws -> TrackedMask {
        guard let clip = clipFor(id: clipId) else { throw SmoothSkinFailure.clipNotFound }
        guard clip.mediaType == .video else { throw SmoothSkinFailure.notVideo }
        if let face = trackedFace(clipId: clipId, person: person) { return face }
        var label = L10n.string("Face")
        var within: [TimedBox] = []
        if let person {
            guard let mask = trackedMask(id: person) else { throw SmoothSkinFailure.personNotFound }
            label = L10n.string("\(mask.label)’s face")
            within = sourceBoxes(of: person, in: clip)
        }
        return try await trackObject(
            clipId: clipId, prompt: .concept("face"), label: label, within: within, face: FaceLink(personMaskId: person)
        ).mask
    }

    /// Puts Smooth Skin inside the face, replacing earlier settings there. One undo step.
    func applySmoothSkin(
        clipId: String,
        faceId: String,
        smoothing: Double = smoothSkinDefaults.smoothing,
        blemishes: Double = smoothSkinDefaults.blemishes
    ) {
        let effect = Effect.make(Self.smoothSkinEffect, ["amount": smoothing, "blemishes": blemishes])
        applyLook(LookPlan(subject: [effect]), clipId: clipId, maskId: faceId, actionName: L10n.string("Smooth Skin"))
    }

    /// Where a tracked object sits in its source on each frame the clip shows.
    private func sourceBoxes(of maskId: String, in clip: Clip) -> [TimedBox] {
        (clip.startFrame..<clip.endFrame).compactMap { frame in
            guard let seconds = clip.sourceSeconds(atTimelineFrame: frame, fps: timeline.fps),
                  let box = MatteStore.shared.sourceBounds(maskId: maskId, sourceSeconds: seconds) else { return nil }
            return TimedBox(seconds: seconds, box: box)
        }
    }
}
