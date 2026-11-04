import Foundation

extension ToolExecutor {
    private static let addTransitionsAllowedKeys: Set<String> = ["transition", "at", "trackIndex", "fromSeconds", "toSeconds", "every"]
    /// How far from the song's drop a cut may sit and still count as the drop's cut.
    static let dropCutToleranceSeconds = 0.5

    func addTransitions(_ editor: EditorViewModel, _ args: [String: Any]) async throws -> ToolResult {
        try validateUnknownKeys(args, allowed: Self.addTransitionsAllowedKeys, path: "add_transitions")
        let transitionId = try args.requireString("transition")
        guard let transition = CutTransition(rawValue: transitionId) else {
            throw ToolError("add_transitions: unknown transition '\(transitionId)'. Use one of: \(CutTransition.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        let at = args["at"] as? String ?? "cuts"
        guard ["cuts", "drop"].contains(at) else { throw ToolError("add_transitions.at must be \"cuts\" or \"drop\".") }
        func seconds(_ key: String) throws -> Double? {
            guard args[key] != nil else { return nil }
            guard let value = args.double(key), value.isFinite, value >= 0 else { throw ToolError("add_transitions.\(key) must be a number of seconds, 0 or more.") }
            return value
        }
        let from = try seconds("fromSeconds"), to = try seconds("toSeconds")
        if let from, let to, from > to { throw ToolError("add_transitions: fromSeconds must not be after toSeconds.") }
        let every: Int
        if args["every"] != nil {
            guard let value = args.int("every"), value >= 1 else { throw ToolError("add_transitions.every must be at least 1.") }
            every = value
        } else {
            every = 1
        }

        let trackIndex: Int
        if args["trackIndex"] != nil {
            guard let value = args.int("trackIndex") else { throw ToolError("add_transitions.trackIndex must be an integer.") }
            trackIndex = value
        } else if let planTrack = editor.planTrackIndex() {
            trackIndex = planTrack
        } else {
            throw ToolError("add_transitions: there's no plan track; pass trackIndex for the video track to cut on.")
        }
        guard editor.timeline.tracks.indices.contains(trackIndex), editor.timeline.tracks[trackIndex].type == .video else {
            throw ToolError("add_transitions: track \(trackIndex) isn't a video track.")
        }

        let fps = editor.timeline.fps
        var cuts = CutTransition.cuts(on: editor.timeline.tracks[trackIndex])
        if at == "drop" {
            guard let drop = editor.planDropFrame() else {
                throw ToolError("add_transitions: the plan has no song with a drop; add music in the plan, or use at \"cuts\".")
            }
            let tolerance = secondsToFrame(seconds: Self.dropCutToleranceSeconds, fps: fps)
            guard let nearest = cuts.min(by: { abs($0.frame - drop) < abs($1.frame - drop) }), abs(nearest.frame - drop) <= tolerance else {
                throw ToolError("add_transitions: no cut sits on the drop at \(String(format: "%.2f", Double(drop) / Double(fps))) s.")
            }
            cuts = [nearest]
        } else {
            cuts = cuts.filter { cut in
                let time = Double(cut.frame) / Double(fps)
                return (from.map { time >= $0 } ?? true) && (to.map { time <= $0 } ?? true)
            }
            cuts = cuts.enumerated().filter { $0.offset % every == 0 }.map(\.element)
        }
        guard !cuts.isEmpty else { throw ToolError("add_transitions: no cuts in that range on track \(trackIndex).") }

        let snapshot = timelineSnapshot(editor)
        let receipt: TransitionReceipt
        do {
            receipt = try await editor.addTransitions(transition, trackIndex: trackIndex, cuts: cuts)
        } catch let error as Matte.Error {
            throw ToolError("add_transitions: couldn't make the white flash image (\(error)).")
        }
        let skipped: [[String: Any]] = receipt.skipped.map { ["frame": $0.frame, "reason": $0.reason.rawValue] }
        guard !receipt.applied.isEmpty else {
            throw ToolError("add_transitions: nothing changed; every cut was skipped: \(Self.jsonString(skipped) ?? "").")
        }
        var extra: [String: Any] = [
            "transition": transition.rawValue,
            "trackIndex": trackIndex,
            "applied": receipt.applied.map { ["frame": $0, "seconds": Double($0) / Double(fps)] as [String: Any] },
        ]
        if !skipped.isEmpty { extra["skipped"] = skipped }
        if let flash = receipt.flashTrackIndex { extra["flashTrackIndex"] = flash }
        return mutationResult(editor, since: snapshot, extra: extra)
    }
}
