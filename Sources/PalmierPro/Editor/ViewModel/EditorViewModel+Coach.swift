import Foundation

enum CoachState: Equatable {
    case hidden
    case asking(overview: String)
    case planning
    case failed(CoachFailure)
}

struct MadePlan: Equatable {
    let plan: EditPlan
    let fromTemplate: Bool
}

/// The coach session: ask what the user is making, read the footage once, plan with Muse Spark.
extension EditorViewModel {
    /// The coach card waits while the tour runs, so the two never overlap.
    var showsCoachCard: Bool { coach != .hidden && tour.stepIndex == nil }

    var hasCoachFootage: Bool { mediaAssets.contains { $0.type == .video && !$0.isGenerating } }

    /// The Plan the Edit tooltip; says what's missing while planning is unavailable.
    var planTheEditHelp: String {
        hasCoachFootage ? L10n.string("Plan the Edit") : L10n.string("Import a video clip to plan your edit.")
    }

    /// Asks on a timeline with video media and no plan, unless the user dismissed it there.
    func showCoachIfNeeded() {
        switch coach {
        case .hidden, .asking: break
        default: return
        }
        let wanted = coachRequestedTimelineId == activeTimelineId
            || (timeline.plan == nil && !dismissedCoachTimelineIds.contains(activeTimelineId))
        coach = wanted && hasCoachFootage ? .asking(overview: coachOverview()) : .hidden
        if case .asking(let overview) = coach {
            sayOnce("ask:\(activeTimelineId)", coachQuestion(overview: overview))
        }
    }

    /// The opening question: Muse Spark's read of the footage when there is one, else the on-device overview.
    func coachQuestion(overview: String) -> String {
        footageRecommendation.map { L10n.string("\($0.summary) What are we making today?") }
            ?? L10n.string("I see \(overview). What are we making today?")
    }

    func askForPlan() {
        dismissedCoachTimelineIds.remove(activeTimelineId)
        coachRequestedTimelineId = activeTimelineId
        if case .asking = coach { return }
        cancelCoachTask()
        coach = .hidden
        showCoachIfNeeded()
    }

    func dismissCoach() {
        cancelCoachTask()
        dismissedCoachTimelineIds.insert(activeTimelineId)
        coachRequestedTimelineId = nil
        coach = .hidden
        onProjectCheckpointRequired?()
    }

    /// Stops reading or planning without a partial plan and asks again.
    func cancelCoach() {
        cancelCoachTask()
        coach = .hidden
        showCoachIfNeeded()
    }

    func startStarterPlan(_ style: PlanStyle) {
        cancelCoachTask()
        _ = applyTemplate(style, brief: "", totalSeconds: PlanTemplates.defaultTotalSeconds)
    }

    func startIdea(_ idea: PlanIdea) {
        submitBrief(idea.brief, style: idea.style, targetSeconds: idea.targetSeconds)
    }

    /// Plans in the coach's one owned task, so the card's Cancel stops it whoever started it.
    @discardableResult
    func submitBrief(_ brief: String, style: PlanStyle?, targetSeconds: Double? = nil) -> Task<Result<MadePlan, CoachFailure>, Never> {
        cancelCoachTask()
        let generation = coachGeneration
        let task = Task { [weak self] () -> Result<MadePlan, CoachFailure> in
            guard let self else { return .failure(.cancelled) }
            let result = await makePlan(brief: brief, style: style, targetSeconds: targetSeconds)
            guard coachGeneration == generation else { return result }
            coachTask = nil
            switch result {
            case .failure(.cancelled):
                if coach == .planning {
                    coach = .hidden
                    showCoachIfNeeded()
                }
            case .failure(let failure):
                coach = .failed(failure)
            case .success:
                break
            }
            return result
        }
        coachTask = task
        return task
    }

    /// Reads unread footage, drafts the plan and installs it as one undo step; without a key, applies the style template.
    func makePlan(brief: String, style: PlanStyle?, targetSeconds: Double? = nil) async -> Result<MadePlan, CoachFailure> {
        let timelineId = activeTimelineId
        let startPlan = timeline.plan
        let videos = mediaAssets.filter { $0.type == .video && !$0.isGenerating }
        guard !videos.isEmpty else { return .failure(.noFootage) }
        let model: any CoachModel
        do {
            model = try await coachModelProvider()
        } catch {
            guard !Task.isCancelled else { return .failure(.cancelled) }
            guard error == .missingAPIKey else { return fail(.service(String(describing: error))) }
            guard activeTimelineId == timelineId, timeline.plan == startPlan else { return stale() }
            return .success(applyTemplate(style ?? .travelVlog, brief: brief, totalSeconds: targetSeconds ?? PlanTemplates.defaultTotalSeconds))
        }

        let inputs = await Self.scanInputs(videos.map { ($0.id, $0.url, $0.duration) })
        guard !Task.isCancelled else { return .failure(.cancelled) }
        for input in inputs where footageNotes[input.assetId]?.fileKey != input.fileKey {
            footageNotes[input.assetId] = FootageNote(assetId: input.assetId, fileKey: input.fileKey, durationSeconds: input.durationSeconds, hasSpeech: false, labels: [], summary: nil, moments: [])
        }
        coach = .planning
        readFootageInBackground()
        await awaitFootageRead()
        guard !Task.isCancelled else { return .failure(.cancelled) }
        let notes = inputs.compactMap { footageNotes[$0.assetId] }
        guard !notes.isEmpty else { return fail(.noFootage) }
        guard !Task.isCancelled else { return .failure(.cancelled) }

        var song: CoachPlanner.Song?
        if let asset = planningSong, let map = await musicMap(for: asset) {
            song = CoachPlanner.Song(map: targetSeconds.map { map.cut(nearest: $0) } ?? map, assetId: asset.id)
        }
        guard !Task.isCancelled else { return .failure(.cancelled) }

        let raw: RawPlan
        do {
            raw = try await CoachPlanner.plan(brief: brief, style: style, notes: notes, placed: placedMoments(), music: song?.map, client: model)
        } catch {
            return Task.isCancelled || error is CancellationError ? .failure(.cancelled) : fail(.service(error.localizedDescription))
        }
        guard !Task.isCancelled else { return .failure(.cancelled) }
        guard activeTimelineId == timelineId, timeline.plan == startPlan else { return stale() }
        let plan: EditPlan
        do {
            plan = try CoachPlanner.validated(raw, notes: notes, trackId: startPlan?.trackId ?? mainTrackId ?? "", brief: brief, style: style, music: song)
        } catch {
            return fail(error)
        }
        setPlan(plan, actionName: "Make Plan")
        coachRequestedTimelineId = nil
        coach = .hidden
        showsSuggestedTimeline = true
        return .success(MadePlan(plan: timeline.plan ?? plan, fromTemplate: false))
    }

    /// Waits for the background read to finish, returning early when this task is cancelled.
    private func awaitFootageRead() async {
        while footageReadTask != nil, !Task.isCancelled {
            let id = UUID()
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    if Task.isCancelled || footageReadTask == nil {
                        continuation.resume()
                    } else {
                        footageReadWaiters[id] = continuation
                    }
                }
            } onCancel: {
                Task { @MainActor [weak self] in self?.footageReadWaiters.removeValue(forKey: id)?.resume() }
            }
        }
    }

    /// Stops all coach work when the project closes; nothing commits afterwards.
    func tearDownCoach() {
        cancelCoachTask()
        for task in [footageScanTask, footageReadTask, footageRecommendTask, coachNudgeTask, coachListenTask, veeCaptionTask] { task?.cancel() }
        footageScanTask = nil
        footageReadTask = nil
        footageRecommendTask = nil
        footageReadPending = false
        footageScanPending = false
        resumeFootageReadWaiters()
        coachVoice.stop()
        let capture = voiceCapture
        Task.detached { _ = try? await capture.stop() }
    }

    func resumeFootageReadWaiters() {
        let waiters = footageReadWaiters.values
        footageReadWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func applyTemplate(_ style: PlanStyle, brief: String, totalSeconds: Double) -> MadePlan {
        var plan = PlanTemplates.plan(style, totalSeconds: totalSeconds, trackId: timeline.plan?.trackId ?? mainTrackId ?? "")
        plan.brief = brief
        setPlan(plan, actionName: "Make Plan")
        coachRequestedTimelineId = nil
        coach = .hidden
        return MadePlan(plan: timeline.plan ?? plan, fromTemplate: true)
    }

    private func cancelCoachTask() {
        coachGeneration += 1
        coachTask?.cancel()
        coachTask = nil
    }

    private func fail(_ failure: CoachFailure) -> Result<MadePlan, CoachFailure> {
        coach = .hidden
        return .failure(failure)
    }

    /// The timeline changed under the request; drop the result and re-evaluate the card.
    private func stale() -> Result<MadePlan, CoachFailure> {
        coach = .hidden
        showCoachIfNeeded()
        return .failure(.cancelled)
    }

    private func coachOverview() -> String {
        let notes = mediaAssets.filter { $0.type == .video && !$0.isGenerating }.map { asset in
            footageNotes[asset.id] ?? FootageNote(assetId: asset.id, fileKey: "", durationSeconds: asset.duration, hasSpeech: false, labels: [], summary: nil, moments: [])
        }
        return FootageScanner.overview(notes)
    }

    private func placedMoments() -> [PlanMoment] {
        let trackId = timeline.plan?.trackId ?? mainTrackId
        guard let track = timeline.tracks.first(where: { $0.id == trackId }) else { return [] }
        let fps = Double(max(timeline.fps, 1))
        return track.clips.map { clip in
            let start = Double(clip.trimStartFrame) / fps
            return PlanMoment(assetId: clip.mediaRef, start: start, end: start + Double(clip.sourceFramesConsumed) / fps, note: "")
        }
    }
}
