import AVFoundation
import CoreGraphics
import Foundation
import MCP
import Testing
@testable import PalmierPro

/// End-to-end against the real Meta Model API. Opt in with VEECUT_LIVE_SAM=1 and MODEL_API_KEY.
@Suite("Live — SAM 3.1 tracking through MCP", .serialized, .enabled(if: ProcessInfo.processInfo.environment["VEECUT_LIVE_SAM"] == "1"))
@MainActor
struct LiveObjectTrackingTests {
    static let size = CGSize(width: 320, height: 180)
    static let fps: Int32 = 30
    static let frameCount = 60
    static let radius: CGFloat = 28

    /// Disk center in top-left pixel coordinates at a frame.
    static func diskCenter(frame: Int) -> CGPoint {
        CGPoint(x: 60 + CGFloat(frame) * 3, y: 90)
    }

    @Test func trackObjectThenRegionEffectRendersOnlyOnTheObject() async throws {
        let videoURL = try await Self.makeDiskVideo()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let clip = Fixtures.clip(id: "disk-clip", mediaRef: "disk-video", start: 0, duration: Self.frameCount)
        var timeline = CompositorFixtures.timeline([Fixtures.videoTrack(clips: [clip])])
        timeline.fps = Int(Self.fps)
        let harness = ToolHarness(timeline: timeline)
        let undoManager = UndoManager()
        harness.editor.undo.attach(undoManager)
        harness.editor.mediaAssets.append(MediaAsset(id: "disk-video", url: videoURL, type: .video, name: "disk", duration: 2))
        defer { harness.editor.releaseTrackedMasks() }

        let server = Server(name: "live-sam", version: "1.0.0", capabilities: .init(tools: .init(listChanged: false)))
        await MCPService.registerTools(on: server, executor: harness.executor)
        let transports = await InMemoryTransport.createConnectedPair()
        let client = Client(name: "live-sam", version: "1.0.0")
        try await server.start(transport: transports.server)
        _ = try await client.connect(transport: transports.client)

        let tracked = try await client.callTool(name: "track_object", arguments: [
            "clipId": .string(clip.id), "object": .string("white circle"),
        ])
        let trackedText = try text(tracked.content)
        #expect(tracked.isError != true, "\(trackedText)")
        let receipt = try #require(JSONSerialization.jsonObject(with: Data(trackedText.utf8)) as? [String: Any])
        let maskId = try #require(receipt["maskId"] as? String)
        #expect((receipt["trackedFrames"] as? Int ?? 0) >= Self.frameCount - 5)

        let applied = try await client.callTool(name: "apply_effect", arguments: [
            "clipIds": .array([.string(clip.id)]),
            "effects": .array([.object(["type": .string("stylize.invert")])]),
            "region": .object(["maskId": .string(maskId), "side": .string("inside")]),
        ])
        #expect(applied.isError != true)
        await server.stop()
        await client.disconnect()

        let frame = 30
        let rendered = try await CompositorRenderTests.render(
            harness.editor.timeline, frame: frame, imageURLs: ["disk-video": videoURL]
        )
        let center = Self.diskCenter(frame: frame)
        let onDisk = rendered.at(Int(center.x), Int(center.y))
        let background = rendered.at(Int(center.x + Self.radius * 2), Int(center.y))
        #expect(onDisk.r < 80 && onDisk.g < 80 && onDisk.b < 80, "tracked disk should be inverted to dark: \(onDisk)")
        #expect(background.b > background.r + 40, "background should stay blue: \(background)")
    }

    private static func makeDiskVideo() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "veecut-disk-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for index in 0..<frameCount {
            while !input.isReadyForMoreMediaData { await Task.yield() }
            let pool = try #require(adaptor.pixelBufferPool)
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let context = try #require(CGContext(
                data: CVPixelBufferGetBaseAddress(pixels),
                width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixels),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ))
            context.setFillColor(CGColor(red: 0.08, green: 0.12, blue: 0.45, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            let center = diskCenter(frame: index)
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fillEllipse(in: CGRect(x: center.x - radius, y: size.height - center.y - radius, width: radius * 2, height: radius * 2))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        return url
    }

    private func text(_ content: [Tool.Content]) throws -> String {
        for item in content {
            if case .text(let text, _, _) = item { return text }
        }
        throw CocoaError(.coderReadCorrupt)
    }
}
