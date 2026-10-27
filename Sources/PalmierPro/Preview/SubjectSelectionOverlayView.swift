import AppKit
import SwiftUI

/// Scribble over, circle, or click the subject on the preview to mark what to track.
struct SubjectSelectionOverlayView: View {
    @Environment(EditorViewModel.self) private var editor
    @State private var stroke: [CGPoint] = []

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(AppTheme.Background.clearColor)
                    .contentShape(Rectangle())
                    .onHover { hovering in (hovering ? NSCursor.crosshair : NSCursor.arrow).set() }
                if stroke.count > 1 {
                    Path { path in path.addLines(stroke) }
                        .stroke(
                            AppTheme.Accent.canvasAI,
                            style: StrokeStyle(lineWidth: AppTheme.Canvas.markerWidth, lineCap: .round, lineJoin: .round)
                        )
                        .shadow(color: AppTheme.Accent.canvasAI.opacity(AppTheme.Opacity.strong), radius: AppTheme.Canvas.markerGlow)
                        .allowsHitTesting(false)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in stroke.append(value.location) }
                    .onEnded { _ in
                        let mark = SubjectMark.classify(stroke)
                        stroke = []
                        if let mark { commit(mark, viewSize: geometry.size) }
                    }
            )
        }
        .onDisappear { NSCursor.arrow.set() }
    }

    private func commit(_ mark: SubjectMark, viewSize: CGSize) {
        let anchor: CGPoint = switch mark {
        case .point(let point): point
        case .loop(let points), .scribble(let points): points[0]
        }
        let frame = editor.activeFrame
        let videoRect = PreviewHitTester.videoContentRect(in: viewSize, timeline: editor.timeline)
        guard let clipId = PreviewHitTester.clipID(at: anchor, viewSize: viewSize, editor: editor),
              let clip = editor.clipFor(id: clipId), clip.mediaType == .video else {
            NSSound.beep()
            return
        }
        func source(_ point: CGPoint) -> CGPoint? {
            PreviewHitTester.sourcePoint(of: point, clip: clip, frame: frame, videoRect: videoRect)
                .map { CGPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) }
        }
        switch mark {
        case .point(let point):
            guard let point = source(point) else { return NSSound.beep() }
            editor.selectSubject(clipId: clipId, box: nil, points: [TrackingPoint(x: point.x, y: point.y)])
        case .loop(let points):
            let mapped = points.compactMap(source)
            let box = SubjectMark.boundingBox(mapped)
            guard mapped.count == points.count, box.width > 0, box.height > 0 else { return NSSound.beep() }
            editor.selectSubject(clipId: clipId, box: box, points: [])
        case .scribble(let points):
            let mapped = points.compactMap(source).map { TrackingPoint(x: $0.x, y: $0.y) }
            guard !mapped.isEmpty else { return NSSound.beep() }
            editor.selectSubject(clipId: clipId, box: nil, points: mapped)
        }
    }
}
