import Foundation

/// The paused frame Vision looks at while the pick tool is on.
struct ForegroundDetectionTarget: Hashable {
    let clipId: String
    let url: URL
    let sourceSeconds: Double
}

/// Hover previews in the pick tool: Apple Vision suggests subjects on the paused frame, a click tracks one with SAM.
extension EditorViewModel {
    /// The frame to analyze: the shelf's clip at the playhead while paused with the pick tool on; nil otherwise.
    var foregroundDetectionTarget: ForegroundDetectionTarget? {
        guard canvasSelection == .subject, !isPlaying, !isSubjectTracking, let clipId = shelfClipId,
              let clip = clipFor(id: clipId), clip.contains(timelineFrame: activeFrame),
              let asset = mediaAssets.first(where: { $0.id == clip.mediaRef }), asset.type == .video,
              let seconds = clip.sourceSeconds(atTimelineFrame: activeFrame, fps: timeline.fps), seconds.isFinite else { return nil }
        return ForegroundDetectionTarget(clipId: clipId, url: asset.url, sourceSeconds: seconds)
    }

    /// Tracks a Vision candidate with SAM from its box and interior points.
    func pickForegroundCandidate(_ candidate: ForegroundCandidates.Instance, clipId: String) {
        guard !candidate.box.isEmpty, !candidate.points.isEmpty else { return }
        selectSubject(clipId: clipId, box: candidate.box, points: candidate.points.map { TrackingPoint(x: $0.x, y: $0.y) })
    }
}
