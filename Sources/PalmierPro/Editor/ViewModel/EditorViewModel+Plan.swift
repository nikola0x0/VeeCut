import Foundation

enum PlanPlacementFailure: Error, Equatable {
    case noPlan, unknownSection, unknownAsset, invalidRange, rippleBlocked
}

/// The timeline's edit plan: sections, membership and placing moments. Every change is one undo step.
extension EditorViewModel {
    /// Where the plan's sections start and end on the timeline, as the plan bar draws them; clips snap to these.
    func planSectionSnapFrames() -> [Int] {
        guard let plan = timeline.plan else { return [] }
        let bands = PlanLayout.bands(plan, in: timeline)
        return Set(bands.flatMap { [$0.slot.lowerBound, $0.slot.upperBound] }).sorted()
    }

    func planTrackIndex() -> Int? {
        guard let trackId = timeline.plan?.trackId else { return nil }
        return timeline.tracks.firstIndex { $0.id == trackId && $0.type == .video }
    }

    /// Installs or removes the plan; placed clips are re-tagged to the new sections by position.
    func setPlan(_ plan: EditPlan?, actionName: String) {
        withTimelineSwap(actionName: actionName) {
            guard var plan else {
                timeline.plan = nil
                retagPlanMembership { _ in nil }
                return
            }
            if !timeline.tracks.contains(where: { $0.id == plan.trackId && $0.type == .video }) {
                plan.trackId = mainTrackId ?? plan.trackId
            }
            timeline.plan = plan
            let membership = PlanLayout.membership(byPosition: plan, timeline: timeline)
            retagPlanMembership { membership[$0.id] }
            if let music = plan.music { fitSong(music.assetId, toSeconds: plan.sections.reduce(0) { $0 + $1.targetSeconds }) }
        }
    }

    /// Ends the plan's song clips with the plan, within what their source has left. Call inside a timeline swap.
    private func fitSong(_ assetId: String, toSeconds seconds: Double) {
        guard seconds.isFinite, seconds > 0, let asset = mediaAssetsById[assetId] else { return }
        let fps = timeline.fps
        let end = secondsToFrame(seconds: seconds, fps: fps)
        let sourceFrames = secondsToFrame(seconds: asset.duration, fps: fps)
        for ti in timeline.tracks.indices where timeline.tracks[ti].type == .audio {
            for ci in timeline.tracks[ti].clips.indices {
                var clip = timeline.tracks[ti].clips[ci]
                guard clip.mediaRef == assetId, clip.linkGroupId == nil, clip.startFrame < end, clip.speed > 0 else { continue }
                let available = Int((Double(max(0, sourceFrames - clip.trimStartFrame)) / clip.speed).rounded(.down))
                let duration = min(end - clip.startFrame, available)
                guard duration > 0, duration != clip.durationFrames else { continue }
                clip.durationFrames = duration
                clip.trimEndFrame = max(0, sourceFrames - clip.trimStartFrame - Int((Double(duration) * clip.speed).rounded()))
                timeline.tracks[ti].clips[ci] = clip
            }
        }
    }

    /// Applies the edits as one undo step; returns why nothing changed when they are invalid.
    @discardableResult
    func editPlan(_ edits: [PlanEdit], actionName: String) -> PlanEditFailure? {
        guard let plan = timeline.plan else { return .noPlan }
        let edited: EditPlan
        do { edited = try plan.applying(edits) } catch { return error }
        let sectionIds = Set(edited.sections.map(\.id))
        withTimelineSwap(actionName: actionName) {
            timeline.plan = edited
            for ti in timeline.tracks.indices {
                for ci in timeline.tracks[ti].clips.indices {
                    if let id = timeline.tracks[ti].clips[ci].planSectionId, !sectionIds.contains(id) {
                        timeline.tracks[ti].clips[ci].planSectionId = nil
                    }
                }
            }
        }
        return nil
    }

    func renamePlanSection(_ id: String, to title: String) {
        editPlan([.rename(id, to: title)], actionName: "Rename Section")
    }

    func setPlanSectionTarget(_ id: String, seconds: Double) {
        editPlan([.setTarget(id, seconds: seconds)], actionName: "Set Section Length")
    }

    func movePlanSection(_ id: String, by offset: Int) {
        editPlan([.move(id, by: offset)], actionName: "Move Section")
    }

    @discardableResult
    func addPlanSection(after id: String?) -> String? {
        let section = PlanSection(title: L10n.string("New Section"), targetSeconds: PlanSection.newSectionSeconds, hint: "")
        return editPlan([.add(section, after: id)], actionName: "Add Section") == nil ? section.id : nil
    }

    func deletePlanSection(_ id: String) {
        editPlan([.delete(id)], actionName: "Delete Section")
    }

    /// Where a kept clip's own sound sits under the song in a music plan.
    static let musicEditClipSoundDb = -18.0

    /// Ripple-inserts the moment, already trimmed, at the end of its section on the plan track.
    @discardableResult
    func placeMoment(_ moment: PlanMoment, in sectionId: String) -> Result<[String], PlanPlacementFailure> {
        placeMoments([moment], in: sectionId)
    }

    /// Places the moments in order at the end of the section as one undo step; any invalid moment refuses them all.
    @discardableResult
    func placeMoments(_ moments: [PlanMoment], in sectionId: String) -> Result<[String], PlanPlacementFailure> {
        guard let plan = timeline.plan else { return .failure(.noPlan) }
        guard plan.sections.contains(where: { $0.id == sectionId }) else { return .failure(.unknownSection) }
        var placements: [(asset: MediaAsset, range: ClosedRange<Double>)] = []
        for moment in moments {
            switch placeableAsset(for: moment) {
            case .success(let asset): placements.append((asset, moment.start...moment.end))
            case .failure(let failure): return .failure(failure)
            }
        }
        guard !placements.isEmpty else { return .success([]) }
        var created: [String] = []
        // The song is the plan's clock, so placing shots never moves it.
        let song = Set(plan.music.map { music in musicClips.filter { $0.mediaRef == music.assetId }.map(\.id) } ?? [])
        withTimelineSwap(actionName: "Add to Section") {
            let before = timeline
            let trackIndex = resolvePlanTrack()
            for placement in placements {
                guard let frame = timeline.plan.flatMap({ PlanLayout.insertionFrame(for: sectionId, plan: $0, timeline: timeline) }) else { break }
                let ids = rippleInsertClips(assets: [placement.asset], trackIndex: trackIndex, atFrame: frame, segments: [placement.asset.id: placement.range], pinned: song)
                guard !ids.isEmpty else {
                    timeline = before
                    created = []
                    break
                }
                for id in ids {
                    guard let loc = findClip(id: id) else { continue }
                    timeline.tracks[loc.trackIndex].clips[loc.clipIndex].planSectionId = sectionId
                    if plan.music != nil, timeline.tracks[loc.trackIndex].clips[loc.clipIndex].mediaType == .audio {
                        timeline.tracks[loc.trackIndex].clips[loc.clipIndex].volume = VolumeScale.linearFromDb(Self.musicEditClipSoundDb)
                    }
                }
                created += ids
            }
        }
        return created.isEmpty ? .failure(.rippleBlocked) : .success(created)
    }

    /// The asset a moment places from, or why it can't be placed.
    func placeableAsset(for moment: PlanMoment) -> Result<MediaAsset, PlanPlacementFailure> {
        guard let asset = mediaAssetsById[moment.assetId],
              asset.type == .video || asset.type == .image else { return .failure(.unknownAsset) }
        guard moment.start.isFinite, moment.end.isFinite, moment.start >= 0,
              moment.end > moment.start, moment.end <= asset.duration else { return .failure(.invalidRange) }
        return .success(asset)
    }

    /// The plan's track, adopting the main video track or inserting one when it was removed (empty tracks are pruned). Call inside a timeline swap.
    private func resolvePlanTrack() -> Int {
        if let index = planTrackIndex() { return index }
        let index = mainTrackId.flatMap { id in timeline.tracks.firstIndex { $0.id == id } } ?? {
            let index = partitionedInsertionIndex(for: .video, requested: zones.firstAudioIndex)
            timeline.tracks.insert(Track(type: .video), at: index)
            return index
        }()
        let trackId = timeline.tracks[index].id
        timeline.plan?.trackId = trackId
        return index
    }

    /// Plan-track clips take `section(clip)`; their linked partners follow them; every other clip leaves the plan.
    private func retagPlanMembership(_ section: (Clip) -> String?) {
        let planTrackId = timeline.plan?.trackId
        var byLinkGroup: [String: String] = [:]
        if let ti = timeline.tracks.firstIndex(where: { $0.id == planTrackId }) {
            for ci in timeline.tracks[ti].clips.indices {
                let id = section(timeline.tracks[ti].clips[ci])
                timeline.tracks[ti].clips[ci].planSectionId = id
                if let id, let group = timeline.tracks[ti].clips[ci].linkGroupId { byLinkGroup[group] = id }
            }
        }
        for ti in timeline.tracks.indices where timeline.tracks[ti].id != planTrackId {
            for ci in timeline.tracks[ti].clips.indices {
                timeline.tracks[ti].clips[ci].planSectionId = timeline.tracks[ti].clips[ci].linkGroupId.flatMap { byLinkGroup[$0] }
            }
        }
    }
}

/// Keeping the suggested timeline's ghost clips; each keep is one undo step.
extension EditorViewModel {
    var suggestedGhosts: [GhostClip] {
        guard let plan = timeline.plan else { return [] }
        let songOnTimeline = plan.music.flatMap { music in musicClips.contains { $0.mediaRef == music.assetId } ? music : nil }
        return SuggestedTimeline.ghosts(plan: plan, timeline: timeline, beatSeconds: songOnTimeline?.beatSeconds,
                                        beatFrames: songOnTimeline == nil ? [] : coachBeatFrames) { moment in
            guard case .success(let asset) = placeableAsset(for: moment) else { return nil }
            return clipDurationFrames(for: asset, segment: moment.start...moment.end)
        }
    }

    func keepSuggestion(_ ghost: GhostClip) {
        placeMomentsReportingFailure([ghost.moment], in: ghost.sectionId)
        hideSuggestionsWhenKept()
    }

    /// Places every ghost section by section in one undo step; a section that can't be placed is skipped and reported.
    func keepAllSuggestions() {
        let ghosts = suggestedGhosts
        guard let plan = timeline.plan, !ghosts.isEmpty else { return }
        var failure: PlanPlacementFailure?
        withTimelineSwap(actionName: "Keep Suggestions") {
            for section in plan.sections {
                let moments = ghosts.filter { $0.sectionId == section.id }.map(\.moment)
                guard !moments.isEmpty else { continue }
                if case .failure(let reason) = placeMoments(moments, in: section.id), failure == nil { failure = reason }
            }
        }
        if let failure { reportPlacementFailure(failure) }
        hideSuggestionsWhenKept()
    }

    private func hideSuggestionsWhenKept() {
        if showsSuggestedTimeline, suggestedGhosts.isEmpty { showsSuggestedTimeline = false }
    }
}
