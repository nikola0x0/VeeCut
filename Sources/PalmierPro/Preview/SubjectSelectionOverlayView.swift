import AppKit
import SwiftUI

/// Scribble over, circle, or click the subject on the preview to mark what to track,
/// or paint over a region with the brush. While paused, subjects Vision finds light up under the cursor.
struct SubjectSelectionOverlayView: View {
    @Environment(EditorViewModel.self) private var editor
    let kind: CanvasSelectionKind
    @State private var stroke: [CGPoint] = []
    @State private var candidates: (target: ForegroundDetectionTarget, result: ForegroundCandidates)?
    @State private var hoveredLabel: UInt8?

    /// Lets scrubbing settle before decoding and analyzing a frame.
    private static let detectionDelay: Duration = .milliseconds(150)

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(AppTheme.Background.clearColor)
                    .contentShape(Rectangle())
                    .onHover { hovering in (hovering ? NSCursor.crosshair : NSCursor.arrow).set() }
                if stroke.isEmpty, let (instance, clipId) = hoveredCandidate, let tint = instance.tint,
                   let clip = editor.clipFor(id: clipId),
                   let placement = PreviewHitTester.placement(
                       ofSource: CGRect(x: 0, y: 0, width: 1, height: 1), clip: clip, frame: editor.activeFrame,
                       videoRect: PreviewHitTester.videoContentRect(in: geometry.size, timeline: editor.timeline)
                   ) {
                    SourceTintView(image: tint, placement: placement)
                }
                if kind == .brush, let first = stroke.first {
                    Path { path in
                        path.move(to: first)
                        path.addLines(stroke)
                        if stroke.count == 1 { path.addLine(to: first) }
                    }
                    .stroke(
                        AppTheme.Accent.canvasAI.opacity(AppTheme.Opacity.medium),
                        style: StrokeStyle(lineWidth: AppTheme.Canvas.brushRadius * 2, lineCap: .round, lineJoin: .round)
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
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hoveredLabel = candidate(at: location, viewSize: geometry.size)?.instance.label
                case .ended: hoveredLabel = nil
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
                        case .brush:
                            commitBrush(finished, viewSize: geometry.size)
                        }
                    }
            )
        }
        .onDisappear { NSCursor.arrow.set() }
        .task(id: kind == .subject ? editor.foregroundDetectionTarget : nil) { await detectCandidates() }
    }

    private var hoveredCandidate: (ForegroundCandidates.Instance, String)? {
        guard let hoveredLabel, let candidates, candidates.target == editor.foregroundDetectionTarget,
              let instance = candidates.result.instances.first(where: { $0.label == hoveredLabel }) else { return nil }
        return (instance, candidates.target.clipId)
    }

    /// The Vision candidate under a view point, when the candidates still describe the frame on screen.
    private func candidate(at location: CGPoint, viewSize: CGSize) -> (instance: ForegroundCandidates.Instance, clipId: String)? {
        guard let candidates, candidates.target == editor.foregroundDetectionTarget,
              let clip = editor.clipFor(id: candidates.target.clipId),
              let source = PreviewHitTester.sourcePoint(
                  of: location, clip: clip, frame: editor.activeFrame,
                  videoRect: PreviewHitTester.videoContentRect(in: viewSize, timeline: editor.timeline)
              ),
              let instance = candidates.result.instance(at: source) else { return nil }
        return (instance, clip.id)
    }

    private func detectCandidates() async {
        candidates = nil
        hoveredLabel = nil
        guard let target = editor.foregroundDetectionTarget, kind == .subject else { return }
        do {
            try await Task.sleep(for: Self.detectionDelay)
            let result = try await ForegroundCandidates.detect(url: target.url, sourceSeconds: target.sourceSeconds, tint: SubjectTint.rgba)
            guard !Task.isCancelled, target == editor.foregroundDetectionTarget else { return }
            candidates = (target, result)
        } catch is CancellationError {
        } catch {
            Log.editor.error("foreground detection failed clip=\(target.clipId) error=\(String(describing: error))")
        }
    }

    private func commit(_ mark: SubjectMark, viewSize: CGSize) {
        if case .point(let point) = mark, !NSEvent.modifierFlags.contains(.option),
           let (instance, clipId) = candidate(at: point, viewSize: viewSize) {
            editor.pickForegroundCandidate(instance, clipId: clipId)
            return
        }
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

    /// Hands the painted region to SAM: the area the brush covered as the box, points along the stroke as hints.
    private func commitBrush(_ stroke: [CGPoint], viewSize: CGSize) {
        guard let first = stroke.first, let covered = BrushMark.covered(stroke, radius: AppTheme.Canvas.brushRadius),
              let clipId = PreviewHitTester.clipID(at: first, viewSize: viewSize, editor: editor),
              let clip = editor.clipFor(id: clipId), clip.mediaType == .video else { return NSSound.beep() }
        let frame = editor.activeFrame
        let videoRect = PreviewHitTester.videoContentRect(in: viewSize, timeline: editor.timeline)
        func source(_ point: CGPoint) -> CGPoint? {
            PreviewHitTester.sourcePoint(of: point, clip: clip, frame: frame, videoRect: videoRect)
                .map { CGPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) }
        }
        let corners = [
            CGPoint(x: covered.minX, y: covered.minY), CGPoint(x: covered.maxX, y: covered.minY),
            CGPoint(x: covered.maxX, y: covered.maxY), CGPoint(x: covered.minX, y: covered.maxY),
        ].compactMap(source)
        let box = SubjectMark.boundingBox(corners)
        let hints = BrushMark.hintPoints(stroke).compactMap(source).map { TrackingPoint(x: $0.x, y: $0.y) }
        guard corners.count == 4, box.width > 0, box.height > 0, !hints.isEmpty else { return NSSound.beep() }
        editor.selectSubject(clipId: clipId, box: box, points: hints)
    }
}
