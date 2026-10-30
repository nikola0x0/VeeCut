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
        /// Sorted SAM frame indices where the object is present.
        let presentIndices: [Int]
    }

    private let entries = Mutex<[String: Entry]>([:])

    func install(_ mask: TrackedMask, frames: [Int: MaskFrame]) {
        let entry = Entry(mask: mask, frames: frames, presentIndices: frames.keys.sorted())
        entries.withLock { $0[mask.id] = entry }
    }

    func remove(maskIds: some Sequence<String>) {
        let ids = Array(maskIds)
        entries.withLock { entries in
            for id in ids { entries[id] = nil }
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

    /// Sorted source seconds where the object is present; nil while the mask is not loaded.
    func presentSourceSeconds(maskId: String) -> [Double]? {
        guard let entry = entries.withLock({ $0[maskId] }), entry.mask.sourceFPS > 0 else { return nil }
        return entry.presentIndices.map { entry.mask.sourceStartSeconds + Double($0) / entry.mask.sourceFPS }
    }

    /// The object's box at a source time, 0…1 from the top left; nil when absent or not loaded.
    func sourceBounds(maskId: String, sourceSeconds: Double) -> CGRect? {
        guard let (mask, maskFrame) = frame(maskId: maskId, sourceSeconds: sourceSeconds), let box = maskFrame?.box,
              mask.sourceWidth > 0, mask.sourceHeight > 0 else { return nil }
        let w = Double(mask.sourceWidth), h = Double(mask.sourceHeight)
        return CGRect(x: Double(box.left) / w, y: Double(box.top) / h,
                      width: Double(box.right - box.left) / w, height: Double(box.bottom - box.top) / h)
    }

    /// Whether the object covers a 0…1 top-left source point at a source time.
    func covers(maskId: String, sourcePoint point: CGPoint, sourceSeconds: Double) -> Bool {
        guard point.x.isFinite, point.y.isFinite else { return false }
        guard let (mask, maskFrame) = frame(maskId: maskId, sourceSeconds: sourceSeconds), let maskFrame else { return false }
        let box = maskFrame.box
        let px = point.x * Double(mask.sourceWidth), py = point.y * Double(mask.sourceHeight)
        let boxWidth = Double(box.right - box.left), boxHeight = Double(box.bottom - box.top)
        guard boxWidth > 0, boxHeight > 0, px >= Double(box.left), px < Double(box.right),
              py >= Double(box.top), py < Double(box.bottom) else { return false }
        let column = min(maskFrame.width - 1, Int((px - Double(box.left)) / boxWidth * Double(maskFrame.width)))
        let row = min(maskFrame.height - 1, Int((py - Double(box.top)) / boxHeight * Double(maskFrame.height)))
        let index = row * maskFrame.width + column
        return maskFrame.packedBits[index >> 3] & (0x80 >> UInt8(index & 7)) != 0
    }

    /// Grayscale matte covering the full display-oriented source frame, CI bottom-left origin.
    /// Nil when the mask is not loaded or belongs to other media; black when the object is absent.
    func matte(maskId: String, mediaRef: String, sourceSeconds: Double) -> (image: CIImage, size: CGSize)? {
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
}
