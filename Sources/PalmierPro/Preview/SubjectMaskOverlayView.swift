import SwiftUI

/// Tints the tracked subject on the preview so the user can confirm SAM grabbed the right thing.
struct SubjectMaskOverlayView: View {
    @Environment(EditorViewModel.self) private var editor
    let subject: CanvasSubject

    var body: some View {
        GeometryReader { geometry in
            let frame = editor.playheadState.timelineFrame
            if let placement = placement(frame: frame, viewSize: geometry.size) {
                Image(decorative: placement.image, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: placement.size.width, height: placement.size.height)
                    .scaleEffect(x: placement.flipX ? -1 : 1, y: placement.flipY ? -1 : 1)
                    .rotationEffect(.degrees(placement.rotation))
                    .position(placement.center)
                    .allowsHitTesting(false)
            }
        }
    }

    private struct Placement {
        let image: CGImage
        let center: CGPoint
        let size: CGSize
        let rotation: Double
        let flipX: Bool
        let flipY: Bool
    }

    private func placement(frame: Int, viewSize: CGSize) -> Placement? {
        guard let clip = editor.clipFor(id: subject.clipId), clip.contains(timelineFrame: frame),
              let seconds = clip.sourceSeconds(atTimelineFrame: frame, fps: editor.timeline.fps),
              let (mask, maskFrame) = MatteStore.shared.frame(maskId: subject.maskId, sourceSeconds: seconds),
              let maskFrame, let image = SubjectTint.image(for: maskFrame) else { return nil }
        let videoRect = PreviewHitTester.videoContentRect(in: viewSize, timeline: editor.timeline)
        let box = maskFrame.box
        let w = Double(mask.sourceWidth), h = Double(mask.sourceHeight)
        let center = CGPoint(x: Double(box.left + box.right) / 2 / w, y: Double(box.top + box.bottom) / 2 / h)
        guard let viewCenter = PreviewHitTester.viewPoint(ofSource: center, clip: clip, frame: frame, videoRect: videoRect) else {
            return nil
        }
        let t = clip.transformAt(frame: frame)
        let clipSize = CGSize(width: t.width * videoRect.width, height: t.height * videoRect.height)
        return Placement(
            image: image,
            center: viewCenter,
            size: CGSize(
                width: Double(box.right - box.left) / w * clipSize.width,
                height: Double(box.bottom - box.top) / h * clipSize.height
            ),
            rotation: t.rotation,
            flipX: t.flipHorizontal,
            flipY: t.flipVertical
        )
    }
}

/// Builds and caches the tint image for the most recent mask frame.
@MainActor
private enum SubjectTint {
    private static var cached: (frame: MaskFrame, image: CGImage)?

    static func image(for frame: MaskFrame) -> CGImage? {
        if let cached, cached.frame == frame { return cached.image }
        let color = AppTheme.Accent.canvasAINSColor.usingColorSpace(.sRGB) ?? AppTheme.Accent.canvasAINSColor
        let alpha = AppTheme.Opacity.medium
        let r = UInt8(color.redComponent * alpha * 255), g = UInt8(color.greenComponent * alpha * 255)
        let b = UInt8(color.blueComponent * alpha * 255), a = UInt8(alpha * 255)
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
