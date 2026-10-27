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

struct TrackingRequest: Sendable {
    let mediaRef: String
    let sourceURL: URL
    let sourceRange: ClosedRange<Double>
    let label: String
    let prompt: TrackingPrompt
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

        var framesByObject: [Int: [Int: MaskFrame]] = [:]
        var seenFrames = Set<Int>()
        for try await record in client.segmentVideo(fileID: fileID, prompt: promptText) {
            try Task.checkCancellation()
            for object in record.objects {
                framesByObject[object.objectID, default: [:]][record.frameIndex] = MaskFrame(object)
            }
            seenFrames.insert(record.frameIndex)
            progress(min(1, Double(seenFrames.count) / Double(expectedFrames)))
        }

        let preferredID: Int? = if case .target = request.prompt { 1 } else { nil }
        guard let frames = preferredID.flatMap({ framesByObject[$0] })
            ?? framesByObject.values.max(by: { $0.count < $1.count }),
              !frames.isEmpty else { throw TrackingError.objectNotFound }

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
