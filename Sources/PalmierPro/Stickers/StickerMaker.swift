import CoreImage
import Foundation
import ImageIO
import Vision

/// A cut-out sticker staged as a PNG outside the project, ready to commit as media.
struct StickerImage: Sendable {
    let stagedURL: URL
    let width: Int
    let height: Int
}

enum StickerError: Error, Equatable {
    /// Vision found no drawing to lift out of the generated image.
    case nothingToCutOut
}

/// Muse Image draws the sticker on a flat background (it can't return transparency); Vision lifts it out.
enum StickerMaker {
    static func prompt(for description: String) -> String {
        "A die-cut sticker of \(description). Bold clean outline, centered, on a plain flat solid white background, no shadow."
    }

    @concurrent
    static func make(_ description: String, client: MetaModelClient) async throws -> StickerImage {
        let png = try await client.generateImage(prompt: prompt(for: description), size: "1024x1024")
        try Task.checkCancellation()
        return try cutOut(png)
    }

    /// Tolerance per channel, out of 255, for a pixel to count as the flat background.
    static let backgroundTolerance = 28

    /// The image's foreground with a transparent background, cropped to it. Vision lifts the drawing out;
    /// when it finds none, the flat background is cleared from the edges inward.
    nonisolated static func cutOut(_ imageData: Data) throws -> StickerImage {
        let handler = VNImageRequestHandler(data: imageData)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        if let observation = request.results?.first, !observation.allInstances.isEmpty {
            let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: true)
            return try stage(CIImage(cvPixelBuffer: buffer))
        }
        Log.project.warning("sticker vision found no foreground results=\(request.results?.count ?? -1); clearing flat background")
        return try stage(try clearingFlatBackground(imageData))
    }

    /// Clears every pixel connected to the image's border whose color is within `backgroundTolerance`
    /// of the corners' average, then crops to what's left.
    nonisolated static func clearingFlatBackground(_ imageData: Data) throws -> CIImage {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { throw StickerError.nothingToCutOut }
        let width = image.width, height = image.height
        guard width > 2, height > 2,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { throw StickerError.nothingToCutOut }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let corners = [0, width - 1, (height - 1) * width, height * width - 1]
        let background = (0..<3).map { channel in corners.reduce(0) { $0 + Int(pixels[$1 * 4 + channel]) } / corners.count }
        func isBackground(_ index: Int) -> Bool {
            (0..<3).allSatisfy { abs(Int(pixels[index * 4 + $0]) - background[$0]) <= backgroundTolerance }
        }
        var cleared = [Bool](repeating: false, count: width * height)
        var stack = (0..<width).flatMap { [$0, (height - 1) * width + $0] } + (0..<height).flatMap { [$0 * width, $0 * width + width - 1] }
        while let index = stack.popLast() {
            guard !cleared[index], isBackground(index) else { continue }
            cleared[index] = true
            let x = index % width, y = index / width
            if x > 0 { stack.append(index - 1) }
            if x < width - 1 { stack.append(index + 1) }
            if y > 0 { stack.append(index - width) }
            if y < height - 1 { stack.append(index + width) }
        }

        var minX = width, minY = height, maxX = -1, maxY = -1
        for index in 0..<(width * height) {
            if cleared[index] {
                for channel in 0..<4 { pixels[index * 4 + channel] = 0 }
            } else {
                let x = index % width, y = index / width
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY, let cleaned = context.makeImage() else { throw StickerError.nothingToCutOut }
        let extent = CGRect(x: minX, y: height - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
        return CIImage(cgImage: cleaned).cropped(to: extent)
    }

    private nonisolated static func stage(_ image: CIImage) throws -> StickerImage {
        guard image.extent.width >= 1, image.extent.height >= 1,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { throw StickerError.nothingToCutOut }
        let url = FileManager.default.temporaryDirectory.appending(path: "sticker-\(UUID().uuidString).png")
        let origin = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        try CIContext().writePNGRepresentation(of: origin, to: url, format: .RGBA8, colorSpace: colorSpace)
        return StickerImage(stagedURL: url, width: Int(image.extent.width), height: Int(image.extent.height))
    }
}
