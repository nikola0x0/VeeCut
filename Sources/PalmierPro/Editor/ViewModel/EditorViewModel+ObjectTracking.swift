import Foundation

enum ObjectTrackingError: Error, Equatable {
    case clipNotFound
    case unsupportedClip
    case mediaOffline
    case alreadyTracking
    case emptyRange
}

/// Tracks an object through the source range a clip uses and registers the resulting mask.
extension EditorViewModel {

    func trackObject(
        clipId: String,
        prompt: TrackingPrompt,
        label: String,
        within: [TimedBox] = [],
        face: FaceLink? = nil
    ) async throws -> TrackingResult {
        guard let clip = clipFor(id: clipId) else { throw ObjectTrackingError.clipNotFound }
        guard clip.mediaType == .video, clip.sourceClipType == .video else { throw ObjectTrackingError.unsupportedClip }
        guard let asset = mediaAssets.first(where: { $0.id == clip.mediaRef }), asset.type == .video else {
            throw ObjectTrackingError.unsupportedClip
        }
        guard objectTrackingProgress[clipId] == nil else { throw ObjectTrackingError.alreadyTracking }
        let fps = Double(timeline.fps)
        let start = Double(clip.trimStartFrame) / fps
        let end = min(Double(clip.trimStartFrame + clip.sourceFramesConsumed) / fps, asset.duration)
        guard end > start else { throw ObjectTrackingError.emptyRange }
        let request = TrackingRequest(
            mediaRef: clip.mediaRef,
            sourceURL: asset.url,
            sourceRange: start...end,
            label: label,
            prompt: prompt,
            within: within
        )
        let client = try await MetaModelClient.configured()

        objectTrackingProgress[clipId] = 0
        defer { objectTrackingProgress[clipId] = nil }
        let result = try await ObjectTracker.track(request, client: client) { fraction in
            Task { @MainActor [weak self] in
                guard let self, self.objectTrackingProgress[clipId] != nil else { return }
                self.objectTrackingProgress[clipId] = fraction
            }
        }
        try Task.checkCancellation()
        var mask = result.mask
        mask.face = face
        registerTrackedMask(mask, frames: result.frames, file: result.file)
        Log.editor.notice("tracked object mask=\(mask.id) frames=\(result.frames.count) clip=\(clipId)")
        return TrackingResult(mask: mask, frames: result.frames, file: result.file)
    }
}
