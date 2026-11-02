import Foundation

/// What Vee says over the preview and the actions under it; one line at a time.
extension EditorViewModel {
    var veeLine: VeeLine? {
        if let message = canvasFailureMessage {
            return VeeLine(id: "failure:\(message)", text: message, pose: .oops,
                           actions: [VeeAction(kind: .dismissFailure, title: Self.title(for: .dismissFailure))])
        }
        guard coach == .hidden, !isPlaying, dragBefore.isEmpty, preDragTimeline == nil else { return nil }
        if let line = selectionLine { return line }
        if showsSuggestedTimeline, !suggestedGhosts.isEmpty {
            return VeeLine(
                id: "suggestions", text: firstCutLine, pose: .avatar,
                actions: [.keepAllSuggestions, .hideSuggestions].map { VeeAction(kind: $0, title: Self.title(for: $0)) }
            )
        }
        if let plan = timeline.plan, let nudge = coachNudges.first {
            return VeeLine(
                id: nudge.id, text: nudge.message(in: plan), pose: .avatar,
                actions: [.applyNudge(nudge), .dismissNudge(nudge)].map { VeeAction(kind: $0, title: Self.title(for: $0)) }
            )
        }
        return nil
    }

    private var firstCutLine: String {
        guard let music = timeline.plan?.music, musicClips.contains(where: { $0.mediaRef == music.assetId }) else {
            return L10n.string("Here\u{2019}s a first cut from your clips. Keep the ones you like.")
        }
        guard let drop = music.drop else { return L10n.string("Here\u{2019}s a first cut on the beat. Keep the ones you like.") }
        let total = Int(drop.rounded())
        let clock = String(format: "%d:%02d", total / 60, total % 60)
        return L10n.string("Here\u{2019}s a first cut on the beat. The drop hits at \(clock), so your best shot is there.")
    }

    func perform(_ action: VeeAction) {
        switch action.kind {
        case .applyNudge(let nudge): apply(nudge)
        case .dismissNudge(let nudge): dismiss(nudge)
        case .keepAllSuggestions: keepAllSuggestions()
        case .hideSuggestions: showsSuggestedTimeline = false
        case .dismissFailure: dismissCanvasFailure()
        case .smoothSkin(let clipId): smoothSkin(clipId: clipId, person: nil)
        case .addCaptions(let clipId): addCaptions(for: clipId)
        case .cutPauses(let clipId): cutPauses(in: clipId)
        case .snapToBeat(let sectionId): snapCutsToBeats(in: sectionId, beatFrames: coachBeatFrames)
        }
    }

    private var selectionLine: VeeLine? {
        guard let clip = selectedSingleVideoClip else { return nil }
        let offBeat = coachNudges.lazy.compactMap { nudge -> String? in
            guard case .offBeatCuts(let sectionId, let cuts) = nudge.kind, clip.planSectionId == sectionId,
                  cuts.contains(clip.startFrame) || cuts.contains(clip.endFrame) else { return nil }
            return sectionId
        }.first
        let canCutPauses = MLXRuntime.isAvailable && linkedPartnerIds(of: clip.id).contains { clipFor(id: $0)?.mediaType == .audio }
        let kinds = VeeSuggestions.kinds(for: clip, note: footageNotes[clip.mediaRef], canCutPauses: canCutPauses, offBeatSectionId: offBeat)
        guard let first = kinds.first else { return nil }
        let text = if case .snapToBeat = first {
            L10n.string("This cut is just off the beat. Snap it?")
        } else {
            L10n.string("You\u{2019}re talking to the camera here. Want me to tidy it up?")
        }
        return VeeLine(id: "selection:\(clip.id)", text: text, pose: .avatar, actions: kinds.map { VeeAction(kind: $0, title: Self.title(for: $0)) })
    }

    private static func title(for kind: VeeAction.Kind) -> String {
        switch kind {
        case .smoothSkin: L10n.string("Smooth Skin")
        case .addCaptions: L10n.string("Add Captions")
        case .cutPauses: L10n.string("Cut Pauses")
        case .snapToBeat: L10n.string("Snap to Beat")
        case .applyNudge(let nudge): nudge.actionTitle
        case .dismissNudge, .hideSuggestions: L10n.string("Not Now")
        case .keepAllSuggestions: L10n.string("Keep All")
        case .dismissFailure: L10n.string("Dismiss")
        }
    }

    /// The one selected video clip, counting its own linked audio as part of it.
    var selectedSingleVideoClip: Clip? {
        InspectorClipSelection.resolve(timeline: timeline, selectedIds: selectedClipIds)
            .singleVideoClip { linkedPartnerIds(of: $0) }
    }

    /// The clip and its linked partners, so the audio side is heard.
    private func linkedClipIds(of clipId: String) -> [String] {
        [clipId] + linkedPartnerIds(of: clipId)
    }

    /// One caption job at a time; a second tap while it runs does nothing.
    private func addCaptions(for clipId: String) {
        guard veeCaptionTask == nil else { return }
        let request = CaptionRequest(sourceClipIds: linkedClipIds(of: clipId))
        veeCaptionTask = Task { [weak self] in
            guard let self else { return }
            defer { veeCaptionTask = nil }
            do {
                let generation = try await generateCaptions(for: request)
                if let message = captionOutcomeMessage(generation) { mediaPanelToast = MediaPanelToast(message: message) }
            } catch is CancellationError {
            } catch {
                mediaPanelToast = MediaPanelToast(message: localizedCaptionError(error))
                Log.editor.error("vee captions failed clip=\(clipId) error=\(String(describing: error))")
            }
        }
    }

    private func cutPauses(in clipId: String) {
        do {
            let result = try undo.perform("Cut Pauses") {
                try removeDeadAir(clipIds: linkedClipIds(of: clipId), settings: silenceRemovalSettings)
            }
            if let refusal = result?.refusal {
                mediaPanelToast = MediaPanelToast(message: refusal)
            } else if (result?.sections ?? 0) == 0 {
                mediaPanelToast = MediaPanelToast(message: L10n.string("No pauses to cut in this clip."))
            }
        } catch {
            mediaPanelToast = MediaPanelToast(message: (error as? DeadAirSelectionError)?.message ?? error.localizedDescription)
        }
    }
}
