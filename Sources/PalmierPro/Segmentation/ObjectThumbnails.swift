import AVFoundation
import CoreImage
import Foundation

/// Shelf thumbnails for canvas objects: one crop of the source frame around each object, kept in memory per mask id.
@MainActor
@Observable
final class ObjectThumbnails {
    typealias Renderer = @Sendable (_ url: URL, _ sourceSeconds: Double, _ bounds: CGRect) async -> CGImage?

    static let capacity = 128
    nonisolated static let maxPixelSize: CGFloat = 320
    /// Extra room around the object's box, as a fraction of the box.
    nonisolated static let padding: CGFloat = 0.15

    private(set) var images: [String: CGImage] = [:]
    @ObservationIgnored private var order: [String] = []
    @ObservationIgnored private var inFlight: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let render: Renderer

    init(render: @escaping Renderer = ObjectThumbnails.render) {
        self.render = render
    }

    /// Renders the thumbnail once; concurrent callers for the same mask share one render.
    func load(maskId: String, url: URL, sourceSeconds: Double, bounds: CGRect) async {
        guard images[maskId] == nil else { return }
        if let task = inFlight[maskId] { return await task.value }
        let render = render
        let task = Task {
            let image = await render(url, sourceSeconds, bounds)
            self.inFlight[maskId] = nil
            guard let image else { return }
            self.images[maskId] = image
            self.order.append(maskId)
            if self.order.count > Self.capacity { self.images[self.order.removeFirst()] = nil }
        }
        inFlight[maskId] = task
        await task.value
    }

    @concurrent
    static func render(url: URL, sourceSeconds: Double, bounds: CGRect) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize * 2, height: maxPixelSize * 2)
        let time = CMTime(seconds: max(0, sourceSeconds), preferredTimescale: 600)
        let frame: CGImage
        do {
            frame = try await generator.image(at: time).image
        } catch {
            Log.editor.error("object thumbnail failed error=\(String(describing: error))")
            return nil
        }
        let padded = bounds.insetBy(dx: -bounds.width * padding, dy: -bounds.height * padding)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !padded.isNull, padded.width > 0, padded.height > 0 else { return frame }
        let w = CGFloat(frame.width), h = CGFloat(frame.height)
        let crop = CGRect(x: padded.minX * w, y: padded.minY * h, width: padded.width * w, height: padded.height * h).integral
        return frame.cropping(to: crop) ?? frame
    }
}
