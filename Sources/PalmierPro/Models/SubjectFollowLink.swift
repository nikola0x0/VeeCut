import Foundation

/// A clip riding on a tracked object: the video clip the object was tracked in, the object's mask,
/// and the spot of the object's box the clip's center keeps, as fractions of the box (outside 0…1 is beyond it).
struct SubjectFollowLink: Codable, Sendable, Equatable, Hashable {
    var clipId: String
    var maskId: String
    var anchorX: Double
    var anchorY: Double
}

extension KeyframeTrack where Value == AnimPair {
    /// Every keyframe moved by the same offset, so the path keeps its shape.
    func translated(dx: Double, dy: Double) -> KeyframeTrack {
        KeyframeTrack(keyframes: keyframes.map {
            Keyframe(frame: $0.frame, value: AnimPair(a: $0.value.a + dx, b: $0.value.b + dy), interpolationOut: $0.interpolationOut)
        })
    }
}
