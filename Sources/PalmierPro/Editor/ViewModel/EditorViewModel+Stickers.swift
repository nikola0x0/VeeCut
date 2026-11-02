import CoreGraphics
import Foundation

enum StickerFailure: Error, Equatable {
    case noProject, emptyDescription, missingAPIKey, contentPolicy, nothingToCutOut
    case subject(SubjectFollowFailure)
    case failed(String)
}

struct StickerReceipt {
    let assetId: String
    let clipId: String
    /// Set when the sticker was placed but couldn't follow the subject.
    let followFailure: SubjectFollowFailure?
}

/// Stickers: Muse Image draws one, it lands in Media and on the timeline, optionally riding on a tracked subject.
extension EditorViewModel {
    static let stickerDescriptionLimit = 200
    /// A sticker without a subject fills this fraction of the canvas height.
    static let stickerHeight = 0.3
    /// A sticker on a subject spans this fraction of the subject's width, within the bounds below.
    static let stickerSubjectWidth = 0.5
    static let stickerWidthRange = 0.06...0.5

    var isMakingSticker: Bool { stickerTask != nil }

    /// Starts a sticker from the dock; progress and failures show there.
    func makeSticker(description: String, subject: CanvasSubject?) {
        guard stickerTask == nil else { return }
        stickerFailure = nil
        stickerTask = Task { [weak self] in
            guard let self else { return }
            defer { stickerTask = nil }
            do {
                let receipt = try await addSticker(description: description, subject: subject)
                if let failure = receipt.followFailure { subjectFollowFailure = failure }
            } catch is CancellationError {
                return
            } catch let failure as StickerFailure {
                Log.editor.error("sticker failed subject=\(subject.flatMap(\.maskId) ?? "none") failure=\(String(describing: failure))")
                stickerFailure = failure
            } catch {
                Log.editor.error("sticker failed subject=\(subject.flatMap(\.maskId) ?? "none") error=\(String(describing: error))")
                stickerFailure = .failed(error.localizedDescription)
            }
        }
    }

    func cancelSticker() {
        stickerTask?.cancel()
    }

    /// Draws a sticker, adds it to Media, and places it at `startFrame` (default: the playhead) on a new top track. With a subject it
    /// spans the subject's frames and rides on it, by default sitting on the top edge of its box. One undo step.
    func addSticker(
        description rawDescription: String,
        subject: CanvasSubject?,
        placement: SubjectFollowPlacement? = nil,
        startFrame: Int? = nil,
        actionName: String = "Add Sticker"
    ) async throws -> StickerReceipt {
        let description = rawDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty, description.count <= Self.stickerDescriptionLimit else { throw StickerFailure.emptyDescription }
        guard let targetProject = projectURL else { throw StickerFailure.noProject }
        if let subject { _ = try stickerSpan(on: subject) }

        let image: StickerImage
        do {
            image = try await stickerImageSource(description)
        } catch let error as MetaModelError {
            switch error {
            case .missingAPIKey: throw StickerFailure.missingAPIKey
            case .contentPolicy: throw StickerFailure.contentPolicy
            default: throw StickerFailure.failed(String(describing: error))
            }
        } catch StickerError.nothingToCutOut {
            throw StickerFailure.nothingToCutOut
        }
        guard !Task.isCancelled, projectURL?.standardizedFileURL == targetProject.standardizedFileURL else {
            try? FileManager.default.removeItem(at: image.stagedURL)
            throw CancellationError()
        }

        do {
            try projectPackageCoordinator.beginMutation()
        } catch {
            try? FileManager.default.removeItem(at: image.stagedURL)
            throw error
        }
        defer { projectPackageCoordinator.endMutation() }
        let committedURL = try await commitStagedProjectMedia(
            image.stagedURL, filename: "sticker-\(UUID().uuidString.prefix(8)).png", workAlreadyAdmitted: true
        )
        try Task.checkCancellation()

        let asset = MediaAsset(url: committedURL, type: .image, name: description, duration: Defaults.imageDurationSeconds)
        asset.sourceWidth = image.width
        asset.sourceHeight = image.height
        let span = subject.flatMap { try? stickerSpan(on: $0) }
        let layout = stickerLayout(imageWidth: image.width, imageHeight: image.height, on: span?.anchorBox)
        let start = span?.frames.lowerBound ?? max(0, startFrame ?? currentFrame)
        let duration = span.map { $0.frames.count }
            ?? max(1, secondsToFrame(seconds: Defaults.imageDurationSeconds, fps: timeline.fps))

        var clipId: String?
        var followFailure: SubjectFollowFailure?
        undo.perform(actionName) {
            let before = mediaLibraryUndoSnapshot()
            importMediaAsset(asset)
            searchIndex.schedule(asset)
            undo.register(actionName, withTarget: self) { editor in
                editor.restoreMediaLibraryUndoSnapshot(before, actionName: actionName)
            }
            withTimelineSwap(actionName: actionName) {
                let trackIndex = insertTrack(at: 0, type: .video)
                guard let id = placeClip(asset: asset, trackIndex: trackIndex, startFrame: start, durationFrames: duration, addLinkedAudio: false).first,
                      let location = findClip(id: id) else { return }
                var clip = timeline.tracks[location.trackIndex].clips[location.clipIndex]
                clip.transform = layout
                if let subject, span != nil {
                    switch followPath(for: clip, subject: subject, placement: placement ?? .keepOffset) {
                    case .success(let follow):
                        clip.positionTrack = follow.track
                        clip.subjectFollow = follow.link
                    case .failure(let failure): followFailure = failure
                    }
                }
                timeline.tracks[location.trackIndex].clips[location.clipIndex] = clip
                clipId = id
            }
            onProjectCheckpointRequired?()
        }
        guard let clipId else { throw StickerFailure.failed("The sticker couldn't be placed on the timeline.") }
        selectedClipIds = [clipId]
        return StickerReceipt(assetId: asset.id, clipId: clipId, followFailure: span == nil && subject != nil ? .subjectAbsent : followFailure)
    }

    /// The timeline frames a subject shows in its clip, and its canvas box at the shown frame nearest the playhead.
    func stickerSpan(on subject: CanvasSubject) throws(StickerFailure) -> (frames: ClosedRange<Int>, anchorBox: CGRect) {
        guard let maskId = subject.maskId, let source = clipFor(id: subject.clipId) else { throw .subject(.clipNotFound) }
        guard MatteStore.shared.contains(maskId: maskId) else { throw .subject(.maskNotLoaded) }
        let shown = (source.startFrame..<source.endFrame).filter { subjectBox(of: maskId, in: source, at: $0) != nil }
        guard let first = shown.first, let last = shown.last,
              let anchor = shown.min(by: { abs($0 - activeFrame) < abs($1 - activeFrame) }),
              let box = subjectBox(of: maskId, in: source, at: anchor) else { throw .subject(.subjectAbsent) }
        return (first...last, box)
    }

    /// The sticker's box: centered on the canvas, or sized to the subject and sitting on its box's top edge, at most half above the frame.
    func stickerLayout(imageWidth: Int, imageHeight: Int, on box: CGRect?) -> Transform {
        let canvasAspect = Double(timeline.width) / Double(max(timeline.height, 1))
        let imageAspect = Double(imageWidth) / Double(max(imageHeight, 1))
        let width: Double, height: Double, center: CGPoint
        if let box {
            width = min(max(box.width * Self.stickerSubjectWidth, Self.stickerWidthRange.lowerBound), Self.stickerWidthRange.upperBound)
            height = width / imageAspect * canvasAspect
            center = CGPoint(x: box.midX, y: max(box.minY - height / 2, 0))
        } else {
            height = Self.stickerHeight
            width = height * imageAspect / canvasAspect
            center = CGPoint(x: 0.5, y: 0.5)
        }
        return Transform(topLeft: (center.x - width / 2, center.y - height / 2), width: width, height: height)
    }
}
