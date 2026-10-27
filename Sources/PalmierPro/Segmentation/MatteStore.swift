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

    func install(_ mask: TrackedMask, frames: [Int: MaskFrame]) {
        entries.withLock { $0[mask.id] = Entry(mask: mask, frames: frames) }
    }

    func remove(maskIds: some Sequence<String>) {
        entries.withLock { entries in
            for id in maskIds { entries[id] = nil }
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
