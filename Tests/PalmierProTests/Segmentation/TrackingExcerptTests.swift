import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import PalmierPro

@Test(arguments: [
    (Float(23.976), Int32(24)), (Float(29.97), Int32(30)), (Float(59.94), Int32(30)), (Float(25), Int32(25)),
    (Float(0), Int32(30)), (Float.nan, Int32(30)),
] as [(Float, Int32)])
func trackingFrameRateRoundsAndCapsTheSourceRate(nominal: Float, expected: Int32) {
    #expect(TrackingExcerpt.frameRate(forNominal: nominal) == expected)
}

@Test(arguments: [
    (CGSize(width: 3840, height: 2160), 1920, 1080),
    (CGSize(width: 1080, height: 1920), 1080, 1920),
    (CGSize(width: 2160, height: 3840), 1080, 1920),
    (CGSize(width: 640, height: 360), 640, 360),
    (CGSize(width: 641, height: 361), 642, 362),
] as [(CGSize, Int, Int)])
func trackingExcerptFitsInsideHDWithEvenDimensions(display: CGSize, width: Int, height: Int) {
    let size = TrackingExcerpt.outputSize(forDisplay: display)
    #expect(size.width == width && size.height == height)
}

@Test func excerptHasExactlyTheFramesItReportsStartingAtZero() async throws {
    let source = FileManager.default.temporaryDirectory.appending(path: "veecut-excerpt-src-\(UUID().uuidString).mov")
    let excerpt = FileManager.default.temporaryDirectory.appending(path: "veecut-excerpt-\(UUID().uuidString).mp4")
    defer {
        try? FileManager.default.removeItem(at: source)
        try? FileManager.default.removeItem(at: excerpt)
    }
    try await writeSolidVideo(to: source, frames: 72, timescale: 30_000, frameDuration: 1001)

    let output = try await TrackingExcerpt.write(sourceURL: source, range: 0.5...2.0, to: excerpt)
    #expect(output.fps == 30)
    #expect(output.frameCount == 45)

    let asset = AVURLAsset(url: excerpt)
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let reader = try AVAssetReader(asset: asset)
    let decoded = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(decoded)
    reader.startReading()
    var times: [Double] = []
    while let sample = decoded.copyNextSampleBuffer() {
        guard CMSampleBufferGetImageBuffer(sample) != nil else { continue }
        times.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
    }
    #expect(times.count == output.frameCount)
    #expect(times.first == 0)
    #expect(zip(times, times.dropFirst()).allSatisfy { abs(($1 - $0) - 1.0 / 30) < 1e-6 })
}

func writeSolidVideo(to url: URL, frames: Int, timescale: CMTimeScale, frameDuration: CMTimeValue) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: 320, AVVideoHeightKey: 180,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    for index in 0..<frames {
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
        let pool = try #require(adaptor.pixelBufferPool)
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        adaptor.append(try #require(buffer), withPresentationTime: CMTime(value: CMTimeValue(index) * frameDuration, timescale: timescale))
    }
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
}
