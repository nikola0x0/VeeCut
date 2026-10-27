import AVFoundation
import Foundation

/// Writes the slice of a video that tracking uploads: display-oriented, at most 1920×1080,
/// constant frame rate from zero. Frame indices sent to SAM are exactly the frames written,
/// whatever the source's codec, container timing or variable frame rate.
enum TrackingExcerpt {
    struct Output: Sendable {
        let frameCount: Int
        let fps: Int32
        let width: Int
        let height: Int
    }

    static let maxLongSide: CGFloat = 1920
    static let maxShortSide: CGFloat = 1080
    static let maxFrameRate: Int32 = 30

    /// The source rate rounded to whole frames and capped, or the cap when the source reports none.
    static func frameRate(forNominal nominal: Float) -> Int32 {
        guard nominal.isFinite, nominal >= 1 else { return maxFrameRate }
        return min(Int32(nominal.rounded()), maxFrameRate)
    }

    /// Even pixel dimensions that fit the display size inside the excerpt bounds.
    static func outputSize(forDisplay display: CGSize) -> (width: Int, height: Int) {
        let long = max(display.width, display.height), short = min(display.width, display.height)
        guard long > 0, short > 0 else { return (0, 0) }
        let scale = min(1, maxLongSide / long, maxShortSide / short)
        func even(_ value: CGFloat) -> Int { max(2, Int((value * scale / 2).rounded()) * 2) }
        return (even(display.width), even(display.height))
    }

    @concurrent
    static func write(sourceURL: URL, range: ClosedRange<Double>, to outputURL: URL) async throws -> Output {
        let asset = AVURLAsset(url: sourceURL)
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .video).first else { throw TrackingError.noVideoTrack }
        let (naturalSize, transform, nominal) = try await sourceTrack.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let display = naturalSize.applying(transform)
        let size = outputSize(forDisplay: CGSize(width: abs(display.width), height: abs(display.height)))
        guard size.width > 0, size.height > 0 else { throw TrackingError.noVideoTrack }
        let fps = frameRate(forNominal: nominal)

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw TrackingError.exportFailed("could not create video track")
        }
        try track.insertTimeRange(
            CMTimeRange(
                start: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
                end: CMTime(seconds: range.upperBound, preferredTimescale: 600)
            ),
            of: sourceTrack,
            at: .zero
        )
        track.preferredTransform = transform
        var config = try await AVVideoComposition.videoComposition(withPropertiesOf: composition).palmierConfiguration()
        config.frameDuration = CMTime(value: 1, timescale: fps)

        let reader = try AVAssetReader(asset: composition)
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: [track],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.videoComposition = AVVideoComposition(configuration: config)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw TrackingError.exportFailed("cannot read source frames") }
        reader.add(output)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            // No B-frames: presentation order equals decode order, so every decoder counts the same frames.
            AVVideoCompressionPropertiesKey: [
                AVVideoAllowFrameReorderingKey: false,
                AVVideoExpectedSourceFrameRateKey: Int(fps),
                AVVideoMaxKeyFrameIntervalKey: Int(fps),
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { throw TrackingError.exportFailed("cannot write excerpt") }
        writer.add(input)

        guard reader.startReading() else {
            throw TrackingError.exportFailed(reader.error?.localizedDescription ?? "reader failed to start")
        }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw TrackingError.exportFailed(writer.error?.localizedDescription ?? "writer failed to start")
        }
        writer.startSession(atSourceTime: .zero)

        var frameCount = 0
        do {
            while let sample = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(2))
                }
                guard adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frameCount), timescale: fps)) else {
                    throw TrackingError.exportFailed(writer.error?.localizedDescription ?? "frame append failed")
                }
                frameCount += 1
            }
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            throw error
        }
        guard reader.status == .completed else {
            writer.cancelWriting()
            throw TrackingError.exportFailed(reader.error?.localizedDescription ?? "reading source frames failed")
        }
        guard frameCount > 0 else {
            writer.cancelWriting()
            throw TrackingError.invalidRange
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw TrackingError.exportFailed(writer.error?.localizedDescription ?? "writing excerpt failed")
        }
        return Output(frameCount: frameCount, fps: fps, width: size.width, height: size.height)
    }
}
