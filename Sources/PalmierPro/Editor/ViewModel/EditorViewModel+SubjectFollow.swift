import CoreGraphics
import Foundation

enum SubjectFollowFailure: Error, Equatable {
    case clipNotFound, notVisual, sameClip, maskNotLoaded, noOverlap, subjectAbsent
}

/// Where a follower starts out relative to the subject's box; it is then kept at that spot of the box.
enum SubjectFollowPlacement: String, CaseIterable, Sendable {
    /// Keeps the spot of the box the follower covers now.
    case keepOffset
    case above, below, center
}

/// A follower's generated path and the link it was made from.
struct SubjectFollow: Equatable {
    let track: KeyframeTrack<AnimPair>
    let link: SubjectFollowLink
}

/// Clips that ride on a tracked subject: position keyframes generated from the subject's track.
extension EditorViewModel {
    /// Canvas gap between a follower placed above or below and the subject's box.
    static let followGap = 0.02

    /// Keys the clip's position to ride on the subject, replacing earlier position keys. One undo step.
    func followSubject(
        clipId: String,
        subject: CanvasSubject,
        placement: SubjectFollowPlacement = .keepOffset,
        actionName: String = "Follow Subject"
    ) -> Result<SubjectFollow, SubjectFollowFailure> {
        guard let follower = clipFor(id: clipId) else { return .failure(.clipNotFound) }
        let result = followPath(for: follower, subject: subject, placement: placement)
        if case .success(let follow) = result {
            commitClipProperty(clipId: clipId, actionName: actionName) {
                $0.positionTrack = follow.track
                $0.subjectFollow = follow.link
            }
        }
        return result
    }

    /// Moves a following clip to another spot of the object's box, e.g. its top edge. One undo step.
    func setFollowAnchor(clipId: String, anchor: CGPoint) {
        guard let clip = clipFor(id: clipId), var link = clip.subjectFollow else { return }
        link.anchorX = anchor.x
        link.anchorY = anchor.y
        switch followPath(for: clip, link: link) {
        case .failure(let failure):
            subjectFollowFailure = failure
        case .success(let track):
            commitClipProperty(clipId: clipId, actionName: "Move on Object") {
                $0.positionTrack = track
                $0.subjectFollow = link
            }
        }
    }

    /// A drag or typed position on a following clip: re-measures its spot of the box at `frame`
    /// and rebuilds the whole path from it. False when the object's track isn't available.
    func refollow(_ clip: inout Clip, centeredAt center: CGPoint, frame: Int) -> Bool {
        guard var link = clip.subjectFollow, case .success(let boxes) = followBoxes(for: clip, link: link),
              let box = boxes.min(by: { abs($0.frame - frame) < abs($1.frame - frame) })?.box,
              box.width > 0, box.height > 0 else { return false }
        link.anchorX = (center.x - box.minX) / box.width
        link.anchorY = (center.y - box.minY) / box.height
        guard case .success(let track) = followPath(for: clip, link: link) else { return false }
        clip.positionTrack = track
        clip.subjectFollow = link
        return true
    }

    /// Adds the object's name as text above it (below when there's no room), following it while it shows. One undo step.
    func addFollowingLabel(for subject: CanvasSubject) -> Result<String, SubjectFollowFailure> {
        guard let maskId = subject.maskId, let source = clipFor(id: subject.clipId) else { return .failure(.clipNotFound) }
        guard let mask = trackedMask(id: maskId) else { return .failure(.maskNotLoaded) }
        let present = (source.startFrame..<source.endFrame).filter { subjectBox(of: maskId, in: source, at: $0) != nil }
        guard let first = present.first, let last = present.last,
              let anchorBox = subjectBox(of: maskId, in: source, at: nearest(activeFrame, in: present) ?? first) else {
            return .failure(.subjectAbsent)
        }

        let style = TextStyle.caption
        let natural = TextLayout.naturalSize(
            content: mask.label, style: style,
            maxWidth: CGFloat(timeline.width) * 0.9, canvasHeight: CGFloat(timeline.height)
        )
        let width = Double(natural.width) / Double(timeline.width)
        let height = Double(natural.height) / Double(timeline.height)
        var clip = Clip(
            mediaRef: "", mediaType: .text, sourceClipType: .text,
            startFrame: first, durationFrames: last - first + 1,
            transform: Transform(topLeft: (0, 0), width: width, height: height)
        )
        clip.textContent = mask.label
        clip.textStyle = style
        let placement: SubjectFollowPlacement = anchorBox.minY - Self.followGap - height >= 0 ? .above : .below
        switch followPath(for: clip, subject: subject, placement: placement) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let follow):
            clip.positionTrack = follow.track
            clip.subjectFollow = follow.link
        }
        let clipId = clip.id
        withTimelineSwap(actionName: "Add Label") {
            let trackIndex = insertTrack(at: 0, type: .video)
            timeline.tracks[trackIndex].clips.append(clip)
        }
        selectedClipIds = [clipId]
        return .success(clipId)
    }

    /// Tracked objects in the video clips that overlap the clip on the timeline, top track first.
    func followableSubjects(for clipId: String) -> [(subject: CanvasSubject, mask: TrackedMask)] {
        guard let follower = clipFor(id: clipId) else { return [] }
        return timeline.tracks.flatMap(\.clips)
            .filter { $0.mediaType == .video && $0.id != clipId && $0.startFrame < follower.endFrame && follower.startFrame < $0.endFrame }
            .flatMap { clip in canvasObjects(clipId: clip.id).map { (CanvasSubject(clipId: clip.id, maskId: $0.id), $0) } }
    }

    /// Drops the clip's follow path, leaving it where it is at the playhead. One undo step.
    func stopFollowing(clipId: String) {
        guard let clip = clipFor(id: clipId), clip.subjectFollow != nil else { return }
        let frame = min(max(activeFrame, clip.startFrame), clip.endFrame - 1)
        let topLeft = clip.topLeftAt(frame: frame)
        let size = clip.sizeAt(frame: frame)
        commitClipProperty(clipId: clipId, actionName: "Stop Following") {
            $0.positionTrack = nil
            $0.subjectFollow = nil
            $0.transform.centerX = topLeft.x + size.width / 2
            $0.transform.centerY = topLeft.y + size.height / 2
        }
    }

    /// Starts following: measures which spot of the subject's box the follower should keep, at the shown frame
    /// nearest the playhead, and builds its path.
    func followPath(
        for follower: Clip,
        subject: CanvasSubject,
        placement: SubjectFollowPlacement
    ) -> Result<SubjectFollow, SubjectFollowFailure> {
        guard let maskId = subject.maskId else { return .failure(.clipNotFound) }
        var link = SubjectFollowLink(clipId: subject.clipId, maskId: maskId, anchorX: 0.5, anchorY: 0.5)
        let boxes: [(frame: Int, box: CGRect)]
        switch followBoxes(for: follower, link: link) {
        case .failure(let failure): return .failure(failure)
        case .success(let found): boxes = found
        }
        guard let (frame, box) = boxes.min(by: { abs($0.frame - activeFrame) < abs($1.frame - activeFrame) }),
              box.width > 0, box.height > 0 else { return .failure(.subjectAbsent) }
        let topLeft = follower.topLeftAt(frame: frame)
        let size = follower.sizeAt(frame: frame)
        let center = switch placement {
        case .keepOffset: CGPoint(x: topLeft.x + size.width / 2, y: topLeft.y + size.height / 2)
        case .above: CGPoint(x: box.midX, y: box.minY - Self.followGap - size.height / 2)
        case .below: CGPoint(x: box.midX, y: box.maxY + Self.followGap + size.height / 2)
        case .center: CGPoint(x: box.midX, y: box.midY)
        }
        link.anchorX = (center.x - box.minX) / box.width
        link.anchorY = (center.y - box.minY) / box.height
        return followPath(for: follower, link: link).map { SubjectFollow(track: $0, link: link) }
    }

    /// The follower's position track: its center at the link's spot of the subject's box (fractions of the box,
    /// possibly outside it) on every frame both clips share where the subject shows.
    func followPath(for follower: Clip, link: SubjectFollowLink) -> Result<KeyframeTrack<AnimPair>, SubjectFollowFailure> {
        followBoxes(for: follower, link: link).flatMap { boxes in
            let samples = boxes.map { frame, box in
                let size = follower.sizeAt(frame: frame)
                return SubjectFollowPath.Sample(
                    offset: frame - follower.startFrame,
                    topLeft: CGPoint(
                        x: box.minX + link.anchorX * box.width - size.width / 2,
                        y: box.minY + link.anchorY * box.height - size.height / 2
                    )
                )
            }
            guard let track = SubjectFollowPath.track(samples) else { return .failure(.subjectAbsent) }
            return .success(track)
        }
    }

    /// The subject's canvas box on every frame the follower and the subject's clip share where it shows.
    private func followBoxes(for follower: Clip, link: SubjectFollowLink) -> Result<[(frame: Int, box: CGRect)], SubjectFollowFailure> {
        guard let source = clipFor(id: link.clipId) else { return .failure(.clipNotFound) }
        guard follower.mediaType != .audio else { return .failure(.notVisual) }
        guard follower.id != source.id else { return .failure(.sameClip) }
        guard MatteStore.shared.contains(maskId: link.maskId) else { return .failure(.maskNotLoaded) }
        let lower = max(follower.startFrame, source.startFrame)
        let upper = min(follower.endFrame, source.endFrame)
        guard lower < upper else { return .failure(.noOverlap) }
        let boxes = (lower..<upper).compactMap { frame in subjectBox(of: link.maskId, in: source, at: frame).map { (frame, $0) } }
        return boxes.isEmpty ? .failure(.subjectAbsent) : .success(boxes)
    }

    /// The subject's box on the canvas (0…1, top-left origin) at a timeline frame; nil where it doesn't show.
    func subjectBox(of maskId: String, in clip: Clip, at frame: Int) -> CGRect? {
        guard clip.contains(timelineFrame: frame),
              let seconds = clip.sourceSeconds(atTimelineFrame: frame, fps: timeline.fps),
              let bounds = MatteStore.shared.sourceBounds(maskId: maskId, sourceSeconds: seconds) else { return nil }
        return canvasBox(ofSource: bounds, in: clip, at: frame)
    }

    /// Where a 0…1 region of the clip's source lands on the canvas (0…1, top-left origin), as an upright box.
    func canvasBox(ofSource bounds: CGRect, in clip: Clip, at frame: Int) -> CGRect? {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let corners = [
            CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.maxY), CGPoint(x: bounds.minX, y: bounds.maxY),
        ].compactMap { PreviewHitTester.viewPoint(ofSource: $0, clip: clip, frame: frame, videoRect: unit) }
        return corners.count == 4 ? SubjectMark.boundingBox(corners) : nil
    }

    private func nearest(_ frame: Int, in frames: [Int]) -> Int? {
        frames.min { abs($0 - frame) < abs($1 - frame) }
    }
}
