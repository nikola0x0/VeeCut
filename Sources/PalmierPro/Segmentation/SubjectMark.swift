import CoreGraphics

/// What a freehand mark on the preview means: a tap picks a point, a loop encloses the subject,
/// an open scribble lays positive points across it. Measured in view points.
enum SubjectMark: Equatable {
    case point(CGPoint)
    case loop([CGPoint])
    case scribble([CGPoint])

    static let tapLength: CGFloat = 8
    static let maxScribblePoints = 8
    /// A stroke whose ends meet within this fraction of its size counts as a loop.
    static let loopClosureRatio: CGFloat = 0.25

    static func classify(_ stroke: [CGPoint]) -> SubjectMark? {
        guard let first = stroke.first, let last = stroke.last else { return nil }
        let bounds = boundingBox(stroke)
        let extent = max(bounds.width, bounds.height)
        guard extent >= tapLength else { return .point(first) }
        let gap = hypot(last.x - first.x, last.y - first.y)
        if gap <= extent * loopClosureRatio, min(bounds.width, bounds.height) >= tapLength {
            return .loop(stroke)
        }
        return .scribble(resample(stroke, count: maxScribblePoints))
    }

    static func boundingBox(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Points evenly spaced by arc length, both ends included.
    static func resample(_ stroke: [CGPoint], count: Int) -> [CGPoint] {
        guard stroke.count > 1, count > 1 else { return Array(stroke.prefix(1)) }
        var cumulative: [CGFloat] = [0]
        for (a, b) in zip(stroke, stroke.dropFirst()) {
            cumulative.append(cumulative[cumulative.count - 1] + hypot(b.x - a.x, b.y - a.y))
        }
        let total = cumulative[cumulative.count - 1]
        guard total > 0 else { return [stroke[0]] }
        var result: [CGPoint] = []
        var segment = 0
        for index in 0..<count {
            let target = total * CGFloat(index) / CGFloat(count - 1)
            while segment < stroke.count - 2, cumulative[segment + 1] < target { segment += 1 }
            let span = cumulative[segment + 1] - cumulative[segment]
            let t = span > 0 ? (target - cumulative[segment]) / span : 0
            let a = stroke[segment], b = stroke[segment + 1]
            result.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        return result
    }
}

/// What a drag on the preview draws in area mode, in view points:
/// a closed loop is a freehand outline, any other drag is the rectangle it spans.
enum AreaMark {
    static let maxOutlinePoints = 64
    /// Smallest drawn area, as a fraction of the source frame on each side.
    static let minSourceExtent: CGFloat = 0.01

    static func outline(_ stroke: [CGPoint]) -> [CGPoint]? {
        guard case .loop(let loop)? = SubjectMark.classify(stroke) else {
            let box = SubjectMark.boundingBox(stroke)
            guard !box.isNull, min(box.width, box.height) >= SubjectMark.tapLength else { return nil }
            return [
                CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY),
            ]
        }
        return SubjectMark.resample(loop, count: min(loop.count, maxOutlinePoints))
    }

    /// The outline in 0…1 source coordinates when it is finite and encloses a usable area.
    static func validatedSourceOutline(_ outline: [CGPoint]) -> [CGPoint]? {
        guard outline.count >= 3, outline.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let clamped = outline.map { CGPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) }
        let box = SubjectMark.boundingBox(clamped)
        guard box.width >= minSourceExtent, box.height >= minSourceExtent else { return nil }
        return clamped
    }
}
