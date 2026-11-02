import AVFoundation
import Foundation

/// A point on the target, normalized to the display-oriented frame (top-left origin).
struct TrackingPoint: Sendable, Equatable {
    var x: Double
    var y: Double
    var isPositive: Bool = true
}

/// What the user pointed at, at one source time. Coordinates are normalized, top-left origin.
struct TrackingTarget: Sendable, Equatable {
    var sourceSeconds: Double
    var box: CGRect?
    var points: [TrackingPoint] = []
}

enum TrackingPrompt: Sendable, Equatable {
    /// A short noun phrase; SAM finds every match and the most persistent one is kept.
    case concept(String)
    case target(TrackingTarget)
}

/// An object's 0…1 top-left source box at a source time.
struct TimedBox: Sendable, Equatable {
    let seconds: Double
    let box: CGRect
}

struct TrackingRequest: Sendable {
    let mediaRef: String
    let sourceURL: URL
    let sourceRange: ClosedRange<Double>
    let label: String
    let prompt: TrackingPrompt
    /// For a concept: keep the match that lies most inside these boxes, e.g. the face of one person.
    var within: [TimedBox] = []
}

struct TrackingResult: Sendable {
    let mask: TrackedMask
    let frames: [Int: MaskFrame]
    let file: Data
}

enum TrackingError: Error, Equatable {
    case invalidRange
    case tooLong(frames: Int)
    case noVideoTrack
    case exportFailed(String)
    case invalidTarget
    case objectNotFound
}

/// Runs one SAM 3.1 tracking job over the source range a clip uses.
enum ObjectTracker {
    static let maxFrames = 15_000

    @concurrent
    static func track(
        _ request: TrackingRequest,
        client: MetaModelClient,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TrackingResult {
        let range = request.sourceRange
        guard range.lowerBound.isFinite, range.upperBound.isFinite, range.lowerBound >= 0,
              range.upperBound > range.lowerBound else { throw TrackingError.invalidRange }

        let upperBoundFrames = Int(((range.upperBound - range.lowerBound) * Double(TrackingExcerpt.maxFrameRate)).rounded(.up))
        guard upperBoundFrames <= maxFrames else { throw TrackingError.tooLong(frames: upperBoundFrames) }

        let excerptURL = FileManager.default.temporaryDirectory
            .appending(path: "veecut-track-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: excerptURL) }
        let excerpt = try await TrackingExcerpt.write(sourceURL: request.sourceURL, range: range, to: excerptURL)
        try Task.checkCancellation()
        let fps = Double(excerpt.fps)
        let expectedFrames = excerpt.frameCount
        let width = excerpt.width
        let height = excerpt.height

        let promptText: String
        switch request.prompt {
        case .concept(let phrase):
            promptText = phrase
        case .target(let target):
            promptText = try targetPrompt(target, rangeStart: range.lowerBound, fps: fps,
                                          frameCount: expectedFrames, width: width, height: height)
        }

        let fileID = try await client.uploadFile(at: excerptURL, mimeType: "video/mp4")
        try Task.checkCancellation()

        let framesByObject = try await segmentedObjects(
            progress: { seen in progress(min(1, Double(seen) / Double(expectedFrames))) },
            segment: { client.segmentVideo(fileID: fileID, prompt: promptText) }
        )

        let chosen: [Int: MaskFrame]? = switch request.prompt {
        case .target: framesByObject[1]
        case .concept where request.within.isEmpty: framesByObject.values.max(by: { $0.count < $1.count })
        case .concept: mostInside(Array(framesByObject.values), within: request.within, startSeconds: range.lowerBound, fps: fps)
        }
        guard let frames = chosen, !frames.isEmpty else { throw TrackingError.objectNotFound }

        let mask = TrackedMask(
            mediaRef: request.mediaRef,
            label: request.label,
            sourceFPS: fps,
            sourceStartSeconds: range.lowerBound,
            sourceWidth: width,
            sourceHeight: height
        )
        return TrackingResult(mask: mask, frames: frames, file: TrackedMaskFile.encode(frames))
    }

    static let segmentAttempts = 3

    /// Each object's frames from one SAM stream; a server failure restarts the stream so no partial result is kept.
    static func segmentedObjects(
        retryDelay: Duration = .seconds(1),
        progress: (Int) -> Void = { _ in },
        segment: () -> AsyncThrowingStream<SAMFrameRecord, Error>
    ) async throws -> [Int: [Int: MaskFrame]] {
        var attempt = 1
        while true {
            var framesByObject: [Int: [Int: MaskFrame]] = [:]
            var seenFrames = Set<Int>()
            do {
                for try await record in segment() {
                    try Task.checkCancellation()
                    for object in record.objects {
                        framesByObject[object.objectID, default: [:]][record.frameIndex] = MaskFrame(object)
                    }
                    seenFrames.insert(record.frameIndex)
                    progress(seenFrames.count)
                }
                return framesByObject
            } catch MetaModelError.serverFailed(let detail) where attempt < segmentAttempts {
                Log.editor.notice("SAM server failure, retrying attempt=\(attempt) detail=\(detail.prefix(200))")
                try await Task.sleep(for: retryDelay * attempt)
                attempt += 1
            }
        }
    }

    /// The match whose boxes lie most inside `within` over the frames, or nil when none touches it.
    static func mostInside(
        _ objects: [[Int: MaskFrame]],
        within: [TimedBox],
        startSeconds: Double,
        fps: Double
    ) -> [Int: MaskFrame]? {
        let areas = within.sorted { $0.seconds < $1.seconds }
        guard !areas.isEmpty, fps > 0 else { return nil }
        func area(at seconds: Double) -> CGRect {
            var low = 0, high = areas.count - 1
            while low < high {
                let mid = (low + high) / 2
                if areas[mid].seconds < seconds { low = mid + 1 } else { high = mid }
            }
            let after = areas[low], before = areas[max(low - 1, 0)]
            return abs(before.seconds - seconds) < abs(after.seconds - seconds) ? before.box : after.box
        }
        let scored = objects.map { frames in
            (frames, frames.reduce(0.0) { total, entry in
                let box = entry.value.box
                guard box.sourceWidth > 0, box.sourceHeight > 0, box.right > box.left, box.bottom > box.top else { return total }
                let w = Double(box.sourceWidth), h = Double(box.sourceHeight)
                let rect = CGRect(x: Double(box.left) / w, y: Double(box.top) / h,
                                  width: Double(box.right - box.left) / w, height: Double(box.bottom - box.top) / h)
                let inside = rect.intersection(area(at: startSeconds + Double(entry.key) / fps))
                return inside.isNull ? total : total + inside.width * inside.height / (rect.width * rect.height)
            })
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return nil }
        return best.0
    }

    static func targetPrompt(
        _ target: TrackingTarget,
        rangeStart: Double,
        fps: Double,
        frameCount: Int,
        width: Int,
        height: Int
    ) throws(TrackingError) -> String {
        guard target.sourceSeconds.isFinite, target.box != nil || !target.points.isEmpty else { throw .invalidTarget }
        let frame = min(max(Int(((target.sourceSeconds - rangeStart) * fps).rounded()), 0), frameCount - 1)
        func pixel(_ value: Double, _ size: Int) throws(TrackingError) -> Int {
            guard value.isFinite, (0...1).contains(value) else { throw .invalidTarget }
            return min(Int(value * Double(size)), size - 1)
        }
        var prompt = SAMObjectPrompt(objectID: 1, frameIndex: frame)
        if let box = target.box {
            let left = try pixel(box.minX, width), top = try pixel(box.minY, height)
            let right = try pixel(box.maxX, width), bottom = try pixel(box.maxY, height)
            guard right > left, bottom > top else { throw .invalidTarget }
            prompt.box = SAMBox(left: left, top: top, right: right + 1, bottom: bottom + 1,
                                sourceWidth: width, sourceHeight: height)
        }
        for point in target.points {
            prompt.points.append(.init(x: try pixel(point.x, width), y: try pixel(point.y, height),
                                       isPositive: point.isPositive))
        }
        return SAMPromptBuilder.text(for: [prompt], sourceWidth: width, sourceHeight: height)
    }
}
