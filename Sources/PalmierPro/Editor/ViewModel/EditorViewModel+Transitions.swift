import Foundation

struct TransitionReceipt: Equatable, Sendable {
    var applied: [Int] = []
    var skipped: [(frame: Int, reason: CutTransition.Skip)] = []
    /// The track the flash clips went on; nil for the other transitions.
    var flashTrackIndex: Int?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.applied == rhs.applied && lhs.flashTrackIndex == rhs.flashTrackIndex
            && lhs.skipped.map(\.frame) == rhs.skipped.map(\.frame) && lhs.skipped.map(\.reason) == rhs.skipped.map(\.reason)
    }
}

enum TransitionFailure: Error, Equatable {
    case notAVideoTrack
    case noCuts
}

extension EditorViewModel {
    static let flashMatteName = "White Flash"
    static let flashMatteHex = "#FFFFFF"

    /// The cuts on a video track at the given frames, in timeline order.
    func transitionCuts(trackIndex: Int, frames: Set<Int>) throws(TransitionFailure) -> [CutTransition.Cut] {
        guard timeline.tracks.indices.contains(trackIndex), timeline.tracks[trackIndex].type == .video else { throw .notAVideoTrack }
        let cuts = CutTransition.cuts(on: timeline.tracks[trackIndex]).filter { frames.contains($0.frame) }
        guard !cuts.isEmpty else { throw .noCuts }
        return cuts
    }

    /// The song's drop on the timeline, from the plan's music and where its clip sits.
    func planDropFrame() -> Int? {
        guard let music = timeline.plan?.music, let drop = music.drop,
              let song = timeline.tracks.flatMap(\.clips).first(where: { $0.mediaRef == music.assetId }) else { return nil }
        let sourceFrame = secondsToFrame(seconds: drop, fps: timeline.fps) - song.trimStartFrame
        let frame = song.startFrame + Int((Double(sourceFrame) / song.speed).rounded())
        return song.contains(timelineFrame: frame) ? frame : nil
    }

    /// Puts one transition on each cut as a single undo step; clips it can't change are reported, not touched.
    func addTransitions(_ transition: CutTransition, trackIndex: Int, cuts: [CutTransition.Cut]) async throws -> TransitionReceipt {
        let flashAsset = transition == .flash ? try await flashMatte() : nil
        let actionName = L10n.string("Add Transitions")
        var receipt = TransitionReceipt()
        let fps = timeline.fps
        undo.perform(actionName) {
            withTimelineSwap(actionName: actionName) {
                if let flashAsset {
                    let flashTrack = insertTrack(at: 0, type: .video)
                    let length = transition.frames(fps: fps)
                    for cut in cuts {
                        guard let id = placeClip(asset: flashAsset, trackIndex: flashTrack, startFrame: cut.frame, durationFrames: length, addLinkedAudio: false).first,
                              let location = findClip(id: id) else { continue }
                        timeline.tracks[location.trackIndex].clips[location.clipIndex].opacityTrack = KeyframeTrack(keyframes: [
                            Keyframe(frame: 0, value: 1, interpolationOut: .linear), Keyframe(frame: length - 1, value: 0),
                        ])
                        if let incoming = findClip(id: cut.incomingId) {
                            timeline.tracks[incoming.trackIndex].clips[incoming.clipIndex].cutTransition = .flash
                        }
                        receipt.applied.append(cut.frame)
                    }
                    receipt.flashTrackIndex = flashTrack
                    return
                }
                for cut in cuts {
                    guard let incomingAt = findClip(id: cut.incomingId) else { continue }
                    var incoming = timeline.tracks[incomingAt.trackIndex].clips[incomingAt.clipIndex]
                    let outgoingAt = cut.outgoingId.flatMap { findClip(id: $0) }
                    var outgoing = outgoingAt.map { timeline.tracks[$0.trackIndex].clips[$0.clipIndex] }
                    if let skip = transition.apply(incoming: &incoming, outgoing: &outgoing, fps: fps) {
                        receipt.skipped.append((cut.frame, skip))
                        continue
                    }
                    timeline.tracks[incomingAt.trackIndex].clips[incomingAt.clipIndex] = incoming
                    if let outgoingAt, let outgoing { timeline.tracks[outgoingAt.trackIndex].clips[outgoingAt.clipIndex] = outgoing }
                    receipt.applied.append(cut.frame)
                }
            }
        }
        if !receipt.applied.isEmpty { onProjectCheckpointRequired?() }
        return receipt
    }

    /// The project's white flash image, made once and reused.
    private func flashMatte() async throws -> MediaAsset {
        if let existing = mediaAssets.first(where: { $0.type == .image && $0.name == Self.flashMatteName }) { return existing }
        return try await createMatte(hex: Self.flashMatteHex, name: Self.flashMatteName)
    }
}
