import CoreGraphics
import CoreImage
import Foundation
import Synchronization

/// Process-wide, render-thread-safe store of loaded tracked masks. Holds only memory; never touches disk.
final class MatteStore: Sendable {
    static let shared = MatteStore()

    private struct Entry: Sendable {
        let mask: TrackedMask
        let frames: [Int: MaskFrame]
    }

    private let entries = Mutex<[String: Entry]>([:])
    /// Rasterized drawn areas, keyed by mask id; built on first render and dropped with the mask.
    private let areaMattes = Mutex<[String: CIImage]>([:])

    func install(_ mask: TrackedMask, frames: [Int: MaskFrame]) {
        entries.withLock { $0[mask.id] = Entry(mask: mask, frames: frames) }
    }

    func remove(maskIds: some Sequence<String>) {
        let ids = Array(maskIds)
        entries.withLock { entries in
            for id in ids { entries[id] = nil }
        }
        areaMattes.withLock { mattes in
            for id in ids { mattes[id] = nil }
        }
    }

    func contains(maskId: String) -> Bool {
        entries.withLock { $0[maskId] != nil }
    }

    /// The mask and its frame at a source time; nil frame when the object is absent there.
    func frame(maskId: String, sourceSeconds: Double) -> (mask: TrackedMask, frame: MaskFrame?)? {
        guard let entry = entries.withLock({ $0[maskId] }), sourceSeconds.isFinite, entry.mask.sourceFPS > 0 else { return nil }
        let index = Int(((sourceSeconds - entry.mask.sourceStartSeconds) * entry.mask.sourceFPS).rounded())
        return (entry.mask, entry.frames[index])
    }

    /// Grayscale matte covering the full display-oriented source frame, CI bottom-left origin.
    /// Nil when the mask is not loaded or belongs to other media; black when the object is absent.
    func matte(maskId: String, mediaRef: String, sourceSeconds: Double) -> (image: CIImage, size: CGSize)? {
        if let entry = entries.withLock({ $0[maskId] }), let outline = entry.mask.area {
            guard entry.mask.mediaRef == mediaRef else { return nil }
            return (areaMatte(maskId: maskId, outline: outline), CGSize(width: entry.mask.sourceWidth, height: entry.mask.sourceHeight))
        }
        guard let (mask, maskFrame) = frame(maskId: maskId, sourceSeconds: sourceSeconds), mask.mediaRef == mediaRef else {
            return nil
        }
        let size = CGSize(width: mask.sourceWidth, height: mask.sourceHeight)
        let background = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        guard let frame = maskFrame else { return (background, size) }

        let raster = CIImage(
            bitmapData: frame.coverage(),
            bytesPerRow: frame.width,
            size: CGSize(width: frame.width, height: frame.height),
            format: .L8,
            colorSpace: nil
        )
        let boxWidth = CGFloat(frame.box.right - frame.box.left)
        let boxHeight = CGFloat(frame.box.bottom - frame.box.top)
        let placed = raster
            .transformed(by: CGAffineTransform(scaleX: boxWidth / CGFloat(frame.width), y: boxHeight / CGFloat(frame.height)))
            .transformed(by: CGAffineTransform(
                translationX: CGFloat(frame.box.left),
                y: size.height - CGFloat(frame.box.bottom)
            ))
        return (placed.composited(over: background).cropped(to: background.extent), size)
    }

    private func areaMatte(maskId: String, outline: [CGPoint]) -> CIImage {
        if let cached = areaMattes.withLock({ $0[maskId] }) { return cached }
        let image = Self.rasterize(outline, size: TrackedMask.areaRasterSize)
        areaMattes.withLock { $0[maskId] = image }
        return image
    }

    /// Antialiased white-on-black coverage of a 0…1 top-left outline, CI bottom-left origin.
    static func rasterize(_ outline: [CGPoint], size: Int) -> CIImage {
        let extent = CGRect(x: 0, y: 0, width: size, height: size)
        var bytes = Data(count: size * size)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ), let first = outline.first else { return }
            let side = CGFloat(size)
            context.setFillColor(gray: 1, alpha: 1)
            context.move(to: CGPoint(x: first.x * side, y: (1 - first.y) * side))
            for point in outline.dropFirst() { context.addLine(to: CGPoint(x: point.x * side, y: (1 - point.y) * side)) }
            context.closePath()
            context.fillPath()
        }
        return CIImage(bitmapData: bytes, bytesPerRow: size, size: extent.size, format: .L8, colorSpace: nil)
    }
}
