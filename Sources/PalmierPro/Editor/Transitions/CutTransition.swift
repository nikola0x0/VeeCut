import Foundation

/// Quick trailer transitions placed on a cut, built from the clips' own fades and keyframes.
enum CutTransition: String, CaseIterable, Codable, Sendable {
    case zoomPunch = "zoom_punch"
    case blurReveal = "blur_reveal"
    case whipBlur = "whip_blur"
    case dipToBlack = "dip_to_black"
    case flash

    /// A place where a clip starts on a track: right after the previous clip ends, or after a gap.
    struct Cut: Equatable, Sendable {
        let frame: Int
        let incomingId: String
        let outgoingId: String?
    }

    enum Skip: String, Equatable, Sendable {
        case hasKeyframes
        case tooShort
        case nothingBefore
    }

    static let zoomPunchScale = 1.1
    static let blurRevealRadius = 40.0
    static let whipBlurRadius = 30.0

    /// How long the transition runs on each clip it touches.
    func seconds() -> Double {
        switch self {
        case .zoomPunch: 0.2
        case .blurReveal: 0.4
        case .whipBlur: 0.1
        case .dipToBlack: 0.25
        case .flash: 0.2
        }
    }

    func frames(fps: Int) -> Int { max(1, Int((seconds() * Double(fps)).rounded())) }

    static func cuts(on track: Track) -> [Cut] {
        let clips = track.clips.sorted { $0.startFrame < $1.startFrame }
        return clips.indices.map { index in
            let previous = index > 0 ? clips[index - 1] : nil
            let adjacent = previous.map { $0.endFrame == clips[index].startFrame } ?? false
            return Cut(frame: clips[index].startFrame, incomingId: clips[index].id, outgoingId: adjacent ? previous?.id : nil)
        }
    }

    /// Writes the transition into the clips on either side of a cut; leaves both untouched when it skips.
    /// The flash adds its own clip instead, so it changes neither.
    func apply(incoming: inout Clip, outgoing: inout Clip?, fps: Int) -> Skip? {
        let length = frames(fps: fps)
        switch self {
        case .zoomPunch:
            guard incoming.scaleTrack == nil, incoming.positionTrack == nil, incoming.subjectFollow == nil else { return .hasKeyframes }
            guard incoming.durationFrames > length else { return .tooShort }
            let base = AnimPair(a: incoming.transform.width, b: incoming.transform.height)
            let punched = AnimPair(a: base.a * Self.zoomPunchScale, b: base.b * Self.zoomPunchScale)
            incoming.scaleTrack = KeyframeTrack(keyframes: [Keyframe(frame: 0, value: punched), Keyframe(frame: length, value: base)])
        case .blurReveal:
            guard incoming.blurKeyframeTrack == nil else { return .hasKeyframes }
            guard incoming.durationFrames > length else { return .tooShort }
            incoming.setBlurKeyframeTrack(KeyframeTrack(keyframes: [
                Keyframe(frame: 0, value: Self.blurRevealRadius), Keyframe(frame: length, value: 0),
            ]))
        case .whipBlur:
            guard var before = outgoing else { return .nothingBefore }
            guard incoming.blurKeyframeTrack == nil, before.blurKeyframeTrack == nil else { return .hasKeyframes }
            guard incoming.durationFrames > length, before.durationFrames > length else { return .tooShort }
            let last = before.durationFrames - 1
            before.setBlurKeyframeTrack(KeyframeTrack(keyframes: [
                Keyframe(frame: last - length, value: 0), Keyframe(frame: last, value: Self.whipBlurRadius),
            ]))
            incoming.setBlurKeyframeTrack(KeyframeTrack(keyframes: [
                Keyframe(frame: 0, value: Self.whipBlurRadius), Keyframe(frame: length, value: 0),
            ]))
            outgoing = before
        case .dipToBlack:
            guard incoming.fadeOutFrames + length <= incoming.durationFrames else { return .tooShort }
            if var before = outgoing {
                guard before.fadeInFrames + length <= before.durationFrames else { return .tooShort }
                before.fadeOutFrames = length
                outgoing = before
            }
            incoming.fadeInFrames = length
        case .flash:
            break
        }
        incoming.cutTransition = self
        return nil
    }
}
