import AppKit
import SwiftUI

/// Scribble over, circle, or click the subject on the preview to mark what to track,
/// or drag a rectangle or loop to draw a static area.
struct SubjectSelectionOverlayView: View {
    @Environment(EditorViewModel.self) private var editor
    let kind: CanvasSelectionKind
    @State private var stroke: [CGPoint] = []

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(AppTheme.Background.clearColor)
                    .contentShape(Rectangle())
                    .onHover { hovering in (hovering ? NSCursor.crosshair : NSCursor.arrow).set() }
                if kind == .area, let outline = AreaMark.outline(stroke) {
                    Path { path in path.addLines(outline); path.closeSubpath() }
                        .fill(AppTheme.Accent.canvasAI.opacity(AppTheme.Opacity.medium))
                        .overlay(
                            Path { path in path.addLines(outline); path.closeSubpath() }
                                .stroke(AppTheme.Accent.canvasAI, style: StrokeStyle(lineWidth: AppTheme.BorderWidth.medium, dash: AppTheme.Canvas.areaDash))
                        )
                        .allowsHitTesting(false)
                } else if stroke.count > 1 {
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
                        let finished = stroke
                        stroke = []
                        switch kind {
                        case .subject:
                            if let mark = SubjectMark.classify(finished) { commit(mark, viewSize: geometry.size) }
                        case .area:
                            commitArea(finished, viewSize: geometry.size)
                        }
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

    private func commitArea(_ stroke: [CGPoint], viewSize: CGSize) {
        guard let outline = AreaMark.outline(stroke) else { return NSSound.beep() }
        let frame = editor.activeFrame
        let center = SubjectMark.boundingBox(outline)
        guard let clipId = PreviewHitTester.clipID(at: CGPoint(x: center.midX, y: center.midY), viewSize: viewSize, editor: editor),
              let clip = editor.clipFor(id: clipId), clip.mediaType == .video else { return NSSound.beep() }
        let videoRect = PreviewHitTester.videoContentRect(in: viewSize, timeline: editor.timeline)
        let source = outline.compactMap { PreviewHitTester.sourcePoint(of: $0, clip: clip, frame: frame, videoRect: videoRect) }
        guard source.count == outline.count, AreaMark.validatedSourceOutline(source) != nil else { return NSSound.beep() }
        editor.drawArea(clipId: clipId, outline: source)
    }
}
