import SwiftUI

/// Tints the selected subject on the preview so the user can confirm SAM grabbed the right thing.
struct SubjectMaskOverlayView: View {
    @Environment(EditorViewModel.self) private var editor
    let clipId: String
    let maskId: String

    var body: some View {
        GeometryReader { geometry in
            let frame = editor.playheadState.timelineFrame
            if let (image, placement) = tint(frame: frame, viewSize: geometry.size) {
                SourceTintView(image: image, placement: placement)
            }
        }
    }

    private func tint(frame: Int, viewSize: CGSize) -> (CGImage, PreviewHitTester.SourcePlacement)? {
        guard let clip = editor.clipFor(id: clipId), clip.contains(timelineFrame: frame),
              let seconds = clip.sourceSeconds(atTimelineFrame: frame, fps: editor.timeline.fps),
              let maskFrame = MatteStore.shared.frame(maskId: maskId, sourceSeconds: seconds)?.frame,
              let source = MatteStore.shared.sourceBounds(maskId: maskId, sourceSeconds: seconds),
              let image = SubjectTint.image(for: maskFrame) else { return nil }
        let videoRect = PreviewHitTester.videoContentRect(in: viewSize, timeline: editor.timeline)
        return PreviewHitTester.placement(ofSource: source, clip: clip, frame: frame, videoRect: videoRect).map { (image, $0) }
    }
}

/// A tint image drawn over part of a clip's source frame, following the clip's transform.
struct SourceTintView: View {
    let image: CGImage
    let placement: PreviewHitTester.SourcePlacement

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.medium)
            .frame(width: placement.size.width, height: placement.size.height)
            .scaleEffect(x: placement.flipX ? -1 : 1, y: placement.flipY ? -1 : 1)
            .rotationEffect(.degrees(placement.rotation))
            .position(placement.center)
            .allowsHitTesting(false)
    }
}

/// Builds and caches the tint image for the most recent mask frame.
@MainActor
enum SubjectTint {
    private static var cached: (frame: MaskFrame, image: CGImage)?

    /// The canvas accent at tint strength, premultiplied.
    static var rgba: ForegroundCandidates.RGBA {
        let color = AppTheme.Accent.canvasAINSColor.usingColorSpace(.sRGB) ?? AppTheme.Accent.canvasAINSColor
        let alpha = AppTheme.Opacity.medium
        return ForegroundCandidates.RGBA(
            r: UInt8(color.redComponent * alpha * 255), g: UInt8(color.greenComponent * alpha * 255),
            b: UInt8(color.blueComponent * alpha * 255), a: UInt8(alpha * 255)
        )
    }

    static func image(for frame: MaskFrame) -> CGImage? {
        if let cached, cached.frame == frame { return cached.image }
        let (r, g, b, a) = (rgba.r, rgba.g, rgba.b, rgba.a)
        let coverage = frame.coverage()
        var pixels = [UInt8](repeating: 0, count: frame.width * frame.height * 4)
        for index in 0..<(frame.width * frame.height) where coverage[index] != 0 {
            pixels[index * 4] = r
            pixels[index * 4 + 1] = g
            pixels[index * 4 + 2] = b
            pixels[index * 4 + 3] = a
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: frame.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else { return nil }
        cached = (frame, image)
        return image
    }
}
