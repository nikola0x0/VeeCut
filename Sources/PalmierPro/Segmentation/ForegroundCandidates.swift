import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// Subjects Apple Vision finds on one source frame, for hover previews in the pick tool. Never tracked: a click hands
/// the candidate's box and interior points to SAM. Coordinates are 0…1 from the top left of the display-oriented source.
struct ForegroundCandidates: Sendable {
    struct Instance: Sendable {
        let label: UInt8
        let box: CGRect
        /// Interior points spread top to bottom, nearest the instance's centroid within each band.
        let points: [CGPoint]
        /// Canvas-accent tint over the full source frame, transparent outside the instance.
        let tint: CGImage?
    }

    static let pointCount = 3
    /// Shapes covering more of the frame than this are scenery (a table with hands on it), not a pickable subject.
    static let maxFrameCoverage = 0.4
    static let maxFrameSize: CGFloat = 1024

    let width: Int
    let height: Int
    /// Row-major from the top row; 0 is background, otherwise an instance label.
    let labels: [UInt8]
    let instances: [Instance]

    func instance(at point: CGPoint) -> Instance? {
        guard width > 0, height > 0, point.x >= 0, point.x < 1, point.y >= 0, point.y < 1 else { return nil }
        let label = labels[Int(point.y * Double(height)) * width + Int(point.x * Double(width))]
        guard label != 0 else { return nil }
        return instances.first { $0.label == label }
    }

    /// Boxes, interior points and tints for every labelled instance in a label map.
    static func analyze(labels: [UInt8], width: Int, height: Int, tint: RGBA? = nil) -> ForegroundCandidates {
        guard width > 0, height > 0, labels.count == width * height else {
            return ForegroundCandidates(width: 0, height: 0, labels: [], instances: [])
        }
        var stats: [UInt8: (minX: Int, minY: Int, maxX: Int, maxY: Int, sumX: Int, sumY: Int, count: Int)] = [:]
        for y in 0..<height {
            for x in 0..<width {
                let label = labels[y * width + x]
                guard label != 0 else { continue }
                var s = stats[label] ?? (x, y, x, y, 0, 0, 0)
                s = (min(s.minX, x), min(s.minY, y), max(s.maxX, x), max(s.maxY, y), s.sumX + x, s.sumY + y, s.count + 1)
                stats[label] = s
            }
        }
        let w = Double(width), h = Double(height)
        let pickable = stats.keys.sorted().filter { Double(stats[$0]!.count) / (w * h) <= maxFrameCoverage }
        let instances = pickable.map { label -> Instance in
            let s = stats[label]!
            let centroidX = Double(s.sumX) / Double(s.count)
            let bandHeight = Double(s.maxY - s.minY + 1) / Double(pointCount)
            var points: [CGPoint] = []
            for band in 0..<pointCount {
                let top = s.minY + Int(Double(band) * bandHeight)
                let bottom = min(s.maxY, s.minY + Int(Double(band + 1) * bandHeight) - 1)
                let midY = Double(top + bottom) / 2
                var best: (x: Int, y: Int, distance: Double)?
                for y in top...max(top, bottom) {
                    for x in s.minX...s.maxX where labels[y * width + x] == label {
                        let distance = abs(Double(x) - centroidX) + abs(Double(y) - midY)
                        if best.map({ distance < $0.distance }) ?? true { best = (x, y, distance) }
                    }
                }
                if let best { points.append(CGPoint(x: (Double(best.x) + 0.5) / w, y: (Double(best.y) + 0.5) / h)) }
            }
            return Instance(
                label: label,
                box: CGRect(x: Double(s.minX) / w, y: Double(s.minY) / h,
                            width: Double(s.maxX - s.minX + 1) / w, height: Double(s.maxY - s.minY + 1) / h),
                points: points,
                tint: tint.flatMap { tintImage(labels: labels, width: width, height: height, label: label, color: $0) }
            )
        }
        return ForegroundCandidates(width: width, height: height, labels: labels, instances: instances)
    }

    /// Premultiplied 8-bit color.
    struct RGBA: Sendable {
        let r: UInt8, g: UInt8, b: UInt8, a: UInt8
    }

    private static func tintImage(labels: [UInt8], width: Int, height: Int, label: UInt8, color: RGBA) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in labels.indices where labels[index] == label {
            pixels[index * 4] = color.r
            pixels[index * 4 + 1] = color.g
            pixels[index * 4 + 2] = color.b
            pixels[index * 4 + 3] = color.a
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    /// Decodes the source frame and runs Vision's foreground instance model on it, on device.
    @concurrent
    static func detect(url: URL, sourceSeconds: Double, tint: RGBA) async throws -> ForegroundCandidates {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxFrameSize, height: maxFrameSize)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(seconds: max(0, sourceSeconds), preferredTimescale: 600)).image
        try Task.checkCancellation()

        let request = VNGenerateForegroundInstanceMaskRequest()
        try VNImageRequestHandler(cgImage: frame).perform([request])
        try Task.checkCancellation()
        guard let observation = request.results?.first else {
            return ForegroundCandidates(width: 0, height: 0, labels: [], instances: [])
        }
        let buffer = observation.instanceMask
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else {
            return ForegroundCandidates(width: 0, height: 0, labels: [], instances: [])
        }
        var labels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width { labels[y * width + x] = base[y * rowBytes + x] }
        }
        return analyze(labels: labels, width: width, height: height, tint: tint)
    }
}
