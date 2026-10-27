import AppKit
import SwiftUI

/// Drag a box (or click a point) on the preview to mark the subject to track.
struct SubjectSelectionOverlayView: View {
    @Environment(EditorViewModel.self) private var editor
    @State private var dragRect: CGRect?

    private static let minimumBoxSide: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(AppTheme.Background.clearColor)
                    .contentShape(Rectangle())
                    .onHover { hovering in (hovering ? NSCursor.crosshair : NSCursor.arrow).set() }
                if let dragRect {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                        .fill(AppTheme.Accent.canvasAI.opacity(AppTheme.Opacity.muted))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                .stroke(AppTheme.Accent.canvasAI, style: StrokeStyle(lineWidth: AppTheme.BorderWidth.medium, dash: AppTheme.Accent.canvasSelectionDash))
                        )
                        .frame(width: dragRect.width, height: dragRect.height)
                        .offset(x: dragRect.minX, y: dragRect.minY)
                        .allowsHitTesting(false)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragRect = CGRect(
                            x: min(value.startLocation.x, value.location.x),
                            y: min(value.startLocation.y, value.location.y),
                            width: abs(value.location.x - value.startLocation.x),
                            height: abs(value.location.y - value.startLocation.y)
                        )
                    }
                    .onEnded { value in
                        let rect = dragRect ?? .zero
                        dragRect = nil
                        commit(start: value.startLocation, rect: rect, viewSize: geometry.size)
                    }
            )
        }
        .onDisappear { NSCursor.arrow.set() }
    }

    private func commit(start: CGPoint, rect: CGRect, viewSize: CGSize) {
        let frame = editor.activeFrame
        let videoRect = PreviewHitTester.videoContentRect(in: viewSize, timeline: editor.timeline)
        guard let clipId = PreviewHitTester.clipID(at: start, viewSize: viewSize, editor: editor),
              let clip = editor.clipFor(id: clipId), clip.mediaType == .video else {
            NSSound.beep()
            return
        }
        func source(_ point: CGPoint) -> CGPoint? {
            PreviewHitTester.sourcePoint(of: point, clip: clip, frame: frame, videoRect: videoRect)
                .map { CGPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) }
        }
        if rect.width < Self.minimumBoxSide || rect.height < Self.minimumBoxSide {
            guard let point = source(start) else { return NSSound.beep() }
            editor.selectSubject(clipId: clipId, box: nil, points: [TrackingPoint(x: point.x, y: point.y)])
            return
        }
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)].compactMap(source)
        guard corners.count == 4 else { return NSSound.beep() }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        let box = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        guard box.width > 0, box.height > 0 else { return NSSound.beep() }
        editor.selectSubject(clipId: clipId, box: box, points: [])
    }
}
