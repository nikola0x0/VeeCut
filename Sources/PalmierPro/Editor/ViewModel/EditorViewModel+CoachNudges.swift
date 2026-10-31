import Foundation

enum MusicPlacementFailure: Error, Equatable {
    case notAudio
}

/// Coaching nudges and their one-click fixes; each fix is one undo step, a dismissal none.
extension EditorViewModel {
    static let coachNudgeDelay: Duration = .seconds(1)

    /// Beats of the music clips on the timeline, in timeline frames.
    var coachBeatFrames: [Int] {
        let fps = timeline.fps
        return musicClips.flatMap { clip -> [Int] in
            guard let analysis = mediaVisualCache.beats.analysis(for: clip.mediaRef) else { return [] }
            return (analysis.beats + analysis.downbeats).compactMap { clip.timelineFrame(sourceSeconds: $0, fps: fps) }
        }
    }

    /// The first song's length on the timeline.
    var musicSeconds: Double? {
        musicClips.first.map { Double($0.durationFrames) / Double(max(timeline.fps, 1)) }
    }

    private var musicClips: [Clip] {
        timeline.tracks.filter { $0.type == .audio }.flatMap(\.clips)
            .filter { $0.linkGroupId == nil && $0.sourceClipType == .audio }
            .sorted { $0.startFrame < $1.startFrame }
    }

    /// Re-evaluates shortly after the timeline settles; never while playing or dragging.
    func scheduleCoachNudges() {
        guard timeline.plan != nil || !coachNudges.isEmpty else { return }
        coachNudgeTask?.cancel()
        coachNudgeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.coachNudgeDelay)
            guard !Task.isCancelled, let self else { return }
            coachNudgeTask = nil
            refreshCoachNudges()
        }
    }

    func refreshCoachNudges() {
        guard let plan = timeline.plan, !isPlaying, dragBefore.isEmpty, preDragTimeline == nil else {
            if !coachNudges.isEmpty { coachNudges = [] }
            return
        }
        let nudges = CoachRules.nudges(plan: plan, timeline: timeline, beatFrames: coachBeatFrames, musicSeconds: musicSeconds)
        if nudges != coachNudges { coachNudges = nudges }
        if let first = nudges.first { sayOnce(first.id, first.message(in: plan)) }
    }

    /// Speaks a coach line once per situation, in Active mode only.
    func sayOnce(_ key: String, _ line: String) {
        guard coachMode == .active, spokenCoachLines.insert(key).inserted else { return }
        coachVoice.speak(line)
    }

    func setCoachMode(_ mode: CoachMode) {
        coachMode = mode
        CoachMode.save(mode)
    }

    func apply(_ nudge: CoachNudge) {
        switch nudge.kind {
        case .sectionOver(let sectionId, _):
            trimSectionToTarget(sectionId)
        case .offBeatCuts(let sectionId, _):
            snapCutsToBeats(in: sectionId, beatFrames: coachBeatFrames)
        case .emptySection(let sectionId, let moments):
            if let first = moments.first { placeMomentsReportingFailure([first], in: sectionId) }
        case .hookCandidate(let sectionId, let moment):
            placeMomentsReportingFailure([moment], in: sectionId)
        case .fitToMusic(let seconds):
            fitPlan(toSeconds: seconds)
        }
        refreshCoachNudges()
    }

    func dismiss(_ nudge: CoachNudge) {
        timeline.plan?.dismissedNudges.insert(nudge.id)
        onProjectCheckpointRequired?()
        refreshCoachNudges()
    }

    /// Shortens the section's clips from their tails, longest first, never below a second, rippling what follows.
    func trimSectionToTarget(_ sectionId: String) {
        guard let plan = timeline.plan,
              let progress = PlanLayout.progress(plan, in: timeline).first(where: { $0.sectionId == sectionId }) else { return }
        let fps = Double(max(timeline.fps, 1))
        var excess = Int(((progress.actualSeconds - progress.targetSeconds) * fps).rounded())
        guard excess > 0 else { return }
        let minimum = Int(fps.rounded())
        let members = planMembers(of: sectionId)
        var cuts: [(clip: Clip, frames: Int)] = []
        for clip in members.sorted(by: { $0.durationFrames > $1.durationFrames }) where excess > 0 {
            let frames = min(max(clip.durationFrames - minimum, 0), excess)
            guard frames > 0 else { continue }
            cuts.append((clip, frames))
            excess -= frames
        }
        guard !cuts.isEmpty else { return }
        withTimelineSwap(actionName: "Trim Section") {
            for cut in cuts.sorted(by: { $0.clip.startFrame > $1.clip.startFrame }) {
                rippleTrimClip(clipId: cut.clip.id, edge: .right, deltaFrames: -cut.frames, propagateToLinked: true)
            }
        }
    }

    /// Moves each off-beat cut in the section to its nearest beat by trimming or extending the outgoing clip.
    func snapCutsToBeats(in sectionId: String, beatFrames: [Int]) {
        let beats = beatFrames.sorted()
        guard let plan = timeline.plan,
              let nudge = CoachRules.nudges(plan: plan, timeline: timeline, beatFrames: beats).first(where: { $0.id == "beats:\(sectionId)" }),
              case .offBeatCuts(_, let cutFrames) = nudge.kind else { return }
        let members = planMembers(of: sectionId)
        let moves = cutFrames.sorted().compactMap { cut -> (clipId: String, beat: Int)? in
            guard let outgoing = members.first(where: { $0.endFrame == cut }),
                  let beat = CoachRules.nearestBeat(to: cut, in: beats) else { return nil }
            return (outgoing.id, beat)
        }
        guard !moves.isEmpty else { return }
        withTimelineSwap(actionName: "Snap Cuts to Beats") {
            for move in moves {
                guard let end = clipFor(id: move.clipId)?.endFrame, move.beat != end else { continue }
                rippleTrimClip(clipId: move.clipId, edge: .right, deltaFrames: move.beat - end, propagateToLinked: true)
            }
        }
    }

    /// Scales every section's target so the plan runs as long as the song.
    func fitPlan(toSeconds seconds: Double) {
        guard let plan = timeline.plan, seconds.isFinite, seconds > 0 else { return }
        let total = plan.sections.reduce(0) { $0 + $1.targetSeconds }
        guard total > 0 else { return }
        let edits = plan.sections.map { section in
            PlanEdit.setTarget(section.id, seconds: min(max((section.targetSeconds * seconds / total).rounded(), EditPlan.targetRange.lowerBound), EditPlan.targetRange.upperBound))
        }
        editPlan(edits, actionName: "Fit Plan to Song")
    }

    /// Places the song from the start on a free audio track and finds its beats.
    @discardableResult
    func addMusic(_ asset: MediaAsset) -> Result<String, MusicPlacementFailure> {
        guard asset.type == .audio else { return .failure(.notAudio) }
        let durationFrames = clipDurationFrames(for: asset, segment: nil)
        var clipId: String?
        withTimelineSwap(actionName: "Add Music") {
            let free = timeline.tracks.indices.first { index in
                timeline.tracks[index].type == .audio
                    && !timeline.tracks[index].clips.contains { MagneticPacking.overlaps($0, start: 0, end: durationFrames) }
            }
            let trackIndex = free ?? {
                let index = partitionedInsertionIndex(for: .audio, requested: timeline.tracks.count)
                timeline.tracks.insert(Track(type: .audio), at: index)
                return index
            }()
            clipId = placeClip(asset: asset, trackIndex: trackIndex, startFrame: 0, durationFrames: durationFrames).first
        }
        guard let clipId else { return .failure(.notAudio) }
        if mediaVisualCache.beats.analysis(for: asset.id) == nil {
            if !markBeats { markBeats = true }
            let detection = mediaVisualCache.beats.detect(for: asset)
            Task { [weak self] in
                _ = try? await detection.value
                self?.refreshCoachNudges()
            }
        }
        return .success(clipId)
    }

    private func planMembers(of sectionId: String) -> [Clip] {
        guard let index = planTrackIndex() else { return [] }
        return timeline.tracks[index].clips.filter { $0.planSectionId == sectionId }.sorted { $0.startFrame < $1.startFrame }
    }
}
