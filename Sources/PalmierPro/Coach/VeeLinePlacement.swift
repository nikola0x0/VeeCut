import CoreGraphics
import Foundation

/// Where Vee's bubble sits over the preview: a 0–1 position within the room left once the bubble fits inside.
enum VeeLinePlacement {
    static let margin = AppTheme.Spacing.lgXl
    static let defaultPosition = CGPoint(x: 0.5, y: 1)
    private static let defaultsKeys = (x: "veeLinePositionX", y: "veeLinePositionY")

    static func center(for position: CGPoint, bubble: CGSize, in container: CGSize) -> CGPoint {
        let x = range(bubble.width, container.width), y = range(bubble.height, container.height)
        return CGPoint(x: x.lowerBound + clamp(position.x) * (x.upperBound - x.lowerBound),
                       y: y.lowerBound + clamp(position.y) * (y.upperBound - y.lowerBound))
    }

    static func position(for center: CGPoint, bubble: CGSize, in container: CGSize) -> CGPoint {
        let x = range(bubble.width, container.width), y = range(bubble.height, container.height)
        return CGPoint(x: fraction(center.x, in: x), y: fraction(center.y, in: y))
    }

    /// Corners and edge middles, home first so a dead-center drop goes home.
    static let borderSpots: [CGPoint] = [defaultPosition] + [0, 0.5, 1].flatMap { y in [0, 0.5, 1].map { CGPoint(x: $0, y: y) } }
        .filter { $0 != defaultPosition && $0 != CGPoint(x: 0.5, y: 0.5) }

    static func snapped(_ position: CGPoint) -> CGPoint {
        borderSpots.min { hypot($0.x - position.x, $0.y - position.y) < hypot($1.x - position.x, $1.y - position.y) } ?? defaultPosition
    }

    static func saved(in defaults: UserDefaults = .standard) -> CGPoint {
        guard defaults.object(forKey: defaultsKeys.x) != nil else { return defaultPosition }
        return CGPoint(x: defaults.double(forKey: defaultsKeys.x), y: defaults.double(forKey: defaultsKeys.y))
    }

    static func save(_ position: CGPoint, in defaults: UserDefaults = .standard) {
        defaults.set(Double(position.x), forKey: defaultsKeys.x)
        defaults.set(Double(position.y), forKey: defaultsKeys.y)
    }

    /// The centers that keep the bubble inside; collapses to the middle when it doesn't fit.
    private static func range(_ length: CGFloat, _ available: CGFloat) -> ClosedRange<CGFloat> {
        let low = margin + length / 2, high = available - margin - length / 2
        return low <= high ? low...high : (available / 2)...(available / 2)
    }

    private static func fraction(_ value: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? clamp((value - range.lowerBound) / span) : 0.5
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        value.isFinite ? min(max(value, 0), 1) : 0.5
    }
}
