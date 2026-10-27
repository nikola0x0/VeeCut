import Foundation

/// How an effect parameter's value is shown and scrubbed in inspector rows.
enum EffectParamDisplay {
    static func format(for range: ClosedRange<Double>) -> String {
        (range.upperBound - range.lowerBound) <= 20 ? "%.2f" : "%.0f"
    }

    static func dragSensitivity(for range: ClosedRange<Double>) -> Double {
        max(0.01, (range.upperBound - range.lowerBound) / 200)
    }
}
