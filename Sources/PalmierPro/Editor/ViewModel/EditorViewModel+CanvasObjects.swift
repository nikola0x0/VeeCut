import Foundation

struct ObjectThumbnailSource: Equatable {
    let url: URL
    let sourceSeconds: Double
    let bounds: CGRect
}

/// Canvas objects: which clip's subjects and areas the shelf lists, selecting one, and finding one under a click.
extension EditorViewModel {
    /// The single selected video clip, else the topmost visible video clip under the playhead.
    var shelfClipId: String? {
        let selectedVideo = selectedClipIds.filter { clipFor(id: $0)?.mediaType == .video }
        if selectedVideo.count == 1 { return selectedVideo.first }
        let frame = activeFrame
        for track in timeline.tracks where track.type != .audio && !track.hidden {
            if let clip = track.clips.first(where: { $0.mediaType == .video && $0.contains(timelineFrame: frame) }) {
                return clip.id
            }
        }
        return nil
    }

    /// Objects on the clip's media present somewhere in the clip's source range, oldest first.
    func canvasObjects(clipId: String) -> [TrackedMask] {
        guard let clip = clipFor(id: clipId), let range = sourceRange(of: clip) else { return [] }
        return trackedMasks(forMedia: clip.mediaRef).filter { mask in
            MatteStore.shared.presentSourceSeconds(maskId: mask.id)?.contains(where: range.contains) == true
        }
    }

    /// `canvasSubject` while its clip and mask still exist.
    var validCanvasSubject: CanvasSubject? {
        guard let subject = canvasSubject, clipFor(id: subject.clipId) != nil,
              subject.maskId.map({ trackedMask(id: $0) != nil }) ?? true else { return nil }
        return subject
    }

    /// Selects an object (or the whole clip when `maskId` is nil) and opens its card,
    /// moving the playhead to the nearest frame of the clip where the object shows.
    func selectCanvasObject(clipId: String, maskId: String?) {
        guard let clip = clipFor(id: clipId), clip.mediaType == .video,
              maskId.map({ trackedMask(id: $0) != nil }) ?? true else { return }
        pause()
        if let frame = nearestVisibleFrame(maskId: maskId, clip: clip), frame != activeFrame {
            seekToFrame(frame)
        }
        canvasSubject = CanvasSubject(clipId: clipId, maskId: maskId)
        renamingObjectId = nil
        objectCardOpen = true
        selectPreviewClip(clipId)
    }

    /// A dock chip click: selects the object, or clears it when it is already selected.
    func toggleCanvasObject(clipId: String, maskId: String?) {
        if validCanvasSubject == CanvasSubject(clipId: clipId, maskId: maskId) {
            clearCanvasObject()
        } else {
            selectCanvasObject(clipId: clipId, maskId: maskId)
        }
    }

    func clearCanvasObject() {
        canvasSubject = nil
        objectCardOpen = false
        renamingObjectId = nil
    }

    /// The newest object on `clipId` covering a 0…1 source point at the playhead.
    func canvasObjectId(atSource point: CGPoint, clipId: String) -> String? {
        guard let clip = clipFor(id: clipId), clip.contains(timelineFrame: activeFrame),
              let seconds = clip.sourceSeconds(atTimelineFrame: activeFrame, fps: timeline.fps) else { return nil }
        return canvasObjects(clipId: clipId).last {
            MatteStore.shared.covers(maskId: $0.id, sourcePoint: point, sourceSeconds: seconds)
        }?.id
    }

    /// Tags an object, or the whole clip, in the agent chat and focuses its input.
    func insertObjectMention(_ subject: CanvasSubject) {
        if let maskId = subject.maskId {
            agentService.attachMention(forObject: maskId, clipId: subject.clipId)
        } else if clipFor(id: subject.clipId) != nil {
            agentService.attachMentions(forClipIds: [subject.clipId])
            agentService.inputFocusRequested = true
        }
    }

    /// Deletes the selected object when the preview has focus. Returns whether it did.
    func deleteSelectedCanvasObject() -> Bool {
        guard focusedPanel == .preview, let maskId = validCanvasSubject?.maskId else { return false }
        deleteSubject(maskId: maskId)
        return true
    }

    /// Opens the inspector on the selected object's sliders, or the clip's Adjust tab for the whole clip.
    func showCanvasObjectDetails() {
        guard let subject = validCanvasSubject else { return }
        selectPreviewClip(subject.clipId)
        inspectorPanelVisible = true
        inspectorClipTabRequest = subject.maskId == nil ? .effects : .subject
    }

    /// Where a dock thumbnail comes from: the object's first tracked frame.
    func thumbnailSource(maskId: String, clipId: String) -> ObjectThumbnailSource? {
        guard let mask = trackedMask(id: maskId), clipFor(id: clipId) != nil,
              let url = mediaAssets.first(where: { $0.id == mask.mediaRef })?.url else { return nil }
        let seconds = MatteStore.shared.presentSourceSeconds(maskId: maskId)?.first
        guard let seconds, let bounds = MatteStore.shared.sourceBounds(maskId: maskId, sourceSeconds: seconds) else { return nil }
        return ObjectThumbnailSource(url: url, sourceSeconds: seconds, bounds: bounds)
    }

    private func sourceRange(of clip: Clip) -> Range<Double>? {
        guard let start = clip.sourceSeconds(atTimelineFrame: clip.startFrame, fps: timeline.fps),
              let end = clip.sourceSeconds(atTimelineFrame: clip.endFrame, fps: timeline.fps),
              start.isFinite, end.isFinite, start != end else { return nil }
        return min(start, end)..<max(start, end)
    }

    /// The playhead when the object already shows there, else the closest clip frame where it does.
    private func nearestVisibleFrame(maskId: String?, clip: Clip) -> Int? {
        let current = activeFrame
        let lastFrame = clip.endFrame - 1
        guard lastFrame >= clip.startFrame else { return nil }
        let clamped = min(max(current, clip.startFrame), lastFrame)
        guard let maskId else { return clamped }
        let fps = timeline.fps
        if clip.contains(timelineFrame: current), let seconds = clip.sourceSeconds(atTimelineFrame: current, fps: fps),
           MatteStore.shared.sourceBounds(maskId: maskId, sourceSeconds: seconds) != nil {
            return current
        }
        return (MatteStore.shared.presentSourceSeconds(maskId: maskId) ?? [])
            .compactMap { clip.timelineFrame(sourceSeconds: $0, fps: fps) }
            .min { abs($0 - current) < abs($1 - current) }
    }
}
