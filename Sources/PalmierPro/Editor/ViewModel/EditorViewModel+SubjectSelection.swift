import Foundation

/// The tracked subject the canvas controls act on.
struct CanvasSubject: Equatable {
    let clipId: String
    let maskId: String
}

/// What drawing on the preview creates: a subject SAM tracks, or a static area.
enum CanvasSelectionKind: Equatable {
    case subject
    case area
}

enum SubjectTrackingFailure: Equatable {
    case missingAPIKey
    case notFound
    /// SAM accepted the request but could not follow the marked spot.
    case modelFailed
    case failed
}

/// Canvas subject selection: draw on the preview, track with SAM 3.1, apply looks to the result.
extension EditorViewModel {
    static let subjectFeather = 6.0

    var isSubjectTracking: Bool { subjectTrackingTask != nil }

    /// Turns a canvas drawing tool on, switches to it from the other one, or turns it off.
    func toggleCanvasSelection(_ kind: CanvasSelectionKind) {
        if canvasSelection == kind {
            canvasSelection = nil
            return
        }
        cancelChromaKeySampling()
        cropEditingActive = false
        subjectTrackingFailure = nil
        canvasSelection = kind
    }

    /// Escape handling, innermost first. Returns whether anything was dismissed.
    func cancelSubjectInteraction() -> Bool {
        if let task = subjectTrackingTask {
            task.cancel()
            return true
        }
        if canvasSelection != nil {
            canvasSelection = nil
            return true
        }
        if canvasSubject != nil || subjectTrackingFailure != nil {
            canvasSubject = nil
            subjectTrackingFailure = nil
            return true
        }
        return false
    }

    /// Starts tracking what the user marked on `clipId` at the current playhead frame.
    func selectSubject(clipId: String, box: CGRect?, points: [TrackingPoint]) {
        guard !isSubjectTracking, let clip = clipFor(id: clipId), clip.contains(timelineFrame: activeFrame),
              let seconds = clip.sourceSeconds(atTimelineFrame: activeFrame, fps: timeline.fps) else { return }
        let target = TrackingTarget(sourceSeconds: seconds, box: box, points: points)
        startSubjectTracking(clipId: clipId, prompt: .target(target), label: nextSubjectName(mediaRef: clip.mediaRef))
    }

    /// Tracks every frame of `clipId` matching a short name such as "sky" or "the red car".
    func trackSubject(named name: String, clipId: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSubjectTracking, !name.isEmpty, clipFor(id: clipId)?.mediaType == .video else { return }
        startSubjectTracking(clipId: clipId, prompt: .concept(name), label: name)
    }

    private func startSubjectTracking(clipId: String, prompt: TrackingPrompt, label: String) {
        canvasSelection = nil
        subjectTrackingFailure = nil
        canvasSubject = nil
        subjectTrackingClipId = clipId
        subjectTrackingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.subjectTrackingTask = nil
                self.subjectTrackingClipId = nil
            }
            do {
                let result = try await self.trackObject(clipId: clipId, prompt: prompt, label: label)
                guard !Task.isCancelled, self.clipFor(id: clipId) != nil else { return }
                self.focusSubject(clipId: clipId, maskId: result.mask.id)
            } catch is CancellationError {
            } catch MetaModelError.missingAPIKey {
                self.subjectTrackingFailure = .missingAPIKey
            } catch TrackingError.objectNotFound {
                self.subjectTrackingFailure = .notFound
            } catch MetaModelError.streamFailed(let detail) {
                guard !Task.isCancelled else { return }
                Log.editor.error("subject tracking model failure clip=\(clipId) detail=\(detail)")
                self.subjectTrackingFailure = .modelFailed
            } catch {
                guard !Task.isCancelled else { return }
                Log.editor.error("subject tracking failed clip=\(clipId) error=\(String(describing: error))")
                self.subjectTrackingFailure = .failed
            }
        }
    }

    /// Adds a static area drawn on `clipId` as one undoable step. `outline` is in 0…1 source coordinates.
    func drawArea(clipId: String, outline: [CGPoint]) {
        guard !isSubjectTracking, let clip = clipFor(id: clipId), clip.mediaType == .video,
              let outline = AreaMark.validatedSourceOutline(outline) else { return }
        let areaCount = trackedMasks(forMedia: clip.mediaRef).filter(\.isDrawnArea).count
        let area = TrackedMask.drawnArea(outline: outline, mediaRef: clip.mediaRef, label: L10n.string("Area \(areaCount + 1)"))
        MatteStore.shared.install(area, frames: [:])
        let actionName = L10n.string("Draw Area")
        undo.perform(actionName) { replaceTrackedMasks(with: trackedMasks + [area], actionName: actionName) }
        canvasSelection = nil
        focusSubject(clipId: clipId, maskId: area.id)
    }

    private func focusSubject(clipId: String, maskId: String) {
        canvasSubject = CanvasSubject(clipId: clipId, maskId: maskId)
        selectedClipIds = [clipId]
        inspectorPanelVisible = true
        inspectorClipTabRequest = .subject
    }

    /// The clip's background matte: its existing background region, else outside every subject on its media.
    func backgroundMatte(clipId: String) -> EffectMatte? {
        guard let clip = clipFor(id: clipId) else { return nil }
        if let existing = clip.effectRegions?.first(where: { $0.matte.invert }) { return existing.matte }
        let ids = trackedMasks(forMedia: clip.mediaRef).map(\.id)
        return ids.isEmpty ? nil : EffectMatte(maskIds: ids, invert: true, feather: Self.subjectFeather)
    }

    private func lookMatte(outside: Bool, clipId: String, maskId: String) -> EffectMatte? {
        outside ? backgroundMatte(clipId: clipId) : EffectMatte(maskId: maskId, feather: Self.subjectFeather)
    }

    /// Applies a preset look around `maskId`, or to the whole clip when there is no subject.
    func applySubjectLook(_ look: SubjectLook, clipId: String, maskId: String?) {
        applyLook(look.plan(hasSubject: maskId != nil), clipId: clipId, maskId: maskId, actionName: L10n.string("Apply Look"))
    }

    /// Merges a look into the subject's region, the clip's background, and the clip's own effects as one undoable edit.
    /// Each effect replaces any effect of the same type already on that side.
    func applyLook(_ plan: LookPlan, clipId: String, maskId: String?, actionName: String) {
        guard clipFor(id: clipId)?.mediaType == .video else { return }
        var sides: [(matte: EffectMatte, effects: [Effect])] = []
        if let maskId {
            guard trackedMask(id: maskId) != nil else { return }
            for (effects, outside) in [(plan.subject, false), (plan.background, true)] where !effects.isEmpty {
                if let matte = lookMatte(outside: outside, clipId: clipId, maskId: maskId) { sides.append((matte, effects)) }
            }
        }
        guard !sides.isEmpty || !plan.frame.isEmpty else { return }
        undo.perform(actionName) {
            mutateClips(ids: [clipId], actionName: actionName) { clip in
                if !plan.frame.isEmpty {
                    var stack = clip.effects ?? []
                    Self.merge(plan.frame, into: &stack)
                    clip.effects = stack
                }
                for side in sides {
                    clip.updateRegion(matching: side.matte) { Self.merge(side.effects, into: &$0) }
                }
            }
        }
    }

    private static func merge(_ effects: [Effect], into stack: inout [Effect]) {
        for effect in effects {
            stack.removeAll { $0.type == effect.type }
            stack.insert(effect, at: EffectRegistry.insertIndex(stack, for: effect.type))
        }
    }

    /// Adds `type` with default settings to the subject's inside or outside, unless already there.
    func addSubjectEffect(_ type: String, outside: Bool, clipId: String, maskId: String) {
        guard let descriptor = EffectRegistry.descriptor(id: type), clipFor(id: clipId) != nil,
              let matte = lookMatte(outside: outside, clipId: clipId, maskId: maskId) else { return }
        let existing = clipFor(id: clipId)?.effectRegions?.first { $0.matte.targetsSameRegion(as: matte) }
        guard existing?.effects.contains(where: { $0.type == type }) != true else { return }
        let actionName = L10n.string("Add \(L10n.string(key: descriptor.displayName))")
        undo.perform(actionName) {
            mutateClips(ids: [clipId], actionName: actionName) { clip in
                clip.updateRegion(matching: existing?.matte ?? matte) { stack in
                    stack.insert(descriptor.makeEffect(), at: EffectRegistry.insertIndex(stack, for: type))
                }
            }
        }
    }

    /// Keeps a subject out of (or lets it into) the clip's background effects. The last kept subject stays.
    func setKeepsSharp(_ keepsSharp: Bool, maskId: String, clipId: String) {
        guard let region = clipFor(id: clipId)?.effectRegions?.first(where: { $0.matte.invert }) else { return }
        var ids = region.matte.maskIds
        if keepsSharp, !ids.contains(maskId) { ids.append(maskId) }
        if !keepsSharp { ids.removeAll { $0 == maskId } }
        guard !ids.isEmpty, ids != region.matte.maskIds else { return }
        let feather = region.matte.feather
        editSubjectRegion(clipId: clipId, regionId: region.id, commit: true, actionName: L10n.string("Change Background")) {
            $0.matte = EffectMatte(maskIds: ids, invert: true, feather: feather)
        }
    }

    /// Effects that can run inside a subject region: tunable numeric settings, no keying, no file resources.
    static let subjectEffectDescriptors: [EffectDescriptor] = EffectRegistry.all.filter {
        !$0.params.isEmpty && !$0.id.hasPrefix("key.") && $0.resourceKey == nil
    }

    /// Live (`commit == false`) or undoable edit of one subject region; an emptied region is removed.
    func editSubjectRegion(
        clipId: String,
        regionId: String,
        commit: Bool,
        actionName: String,
        _ body: @escaping (inout EffectRegion) -> Void
    ) {
        guard clipFor(id: clipId)?.effectRegions?.contains(where: { $0.id == regionId }) == true else { return }
        if commit {
            commitClipProperties(clipIds: [clipId], actionName: actionName) { $0.updateRegion(id: regionId, body) }
        } else {
            applyClipProperties(clipIds: [clipId]) { $0.updateRegion(id: regionId, body) }
        }
    }

    func nextSubjectName(mediaRef: String) -> String {
        L10n.string("Subject \(trackedMasks(forMedia: mediaRef).filter { !$0.isDrawnArea }.count + 1)")
    }

    /// Renames a subject as one undoable edit. Blank or unchanged names are ignored.
    func renameSubject(maskId: String, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = trackedMasks.firstIndex(where: { $0.id == maskId }),
              trackedMasks[index].label != name else { return }
        var masks = trackedMasks
        masks[index].label = name
        let actionName = L10n.string("Rename Subject")
        undo.perform(actionName) { replaceTrackedMasks(with: masks, actionName: actionName) }
    }

    /// Deletes a subject and every look on it in the active timeline as one undoable edit.
    /// The mask is kept while another timeline still uses it.
    func deleteSubject(maskId: String) {
        guard trackedMask(id: maskId) != nil else { return }
        let clipIds = timeline.tracks.flatMap(\.clips)
            .filter { $0.effectRegions?.contains { $0.matte.maskIds.contains(maskId) } == true }
            .map(\.id)
        let usedElsewhere = timelines.contains { other in
            other.id != timeline.id && other.tracks.contains { track in
                track.clips.contains { $0.effectRegions?.contains { $0.matte.maskIds.contains(maskId) } == true }
            }
        }
        let actionName = L10n.string("Delete Subject")
        undo.perform(actionName) {
            if !clipIds.isEmpty {
                mutateClips(ids: Set(clipIds), actionName: actionName) { $0.removeRegions(maskId: maskId) }
            }
            if !usedElsewhere {
                replaceTrackedMasks(with: trackedMasks.filter { $0.id != maskId }, actionName: actionName)
            }
        }
        if canvasSubject?.maskId == maskId { canvasSubject = nil }
    }

    /// Swaps the subject list, registering the inverse so undo and redo restore it exactly.
    private func replaceTrackedMasks(with masks: [TrackedMask], actionName: String) {
        let previous = trackedMasks
        trackedMasks = masks
        undo.register(actionName, withTarget: self) { editor in
            editor.replaceTrackedMasks(with: previous, actionName: actionName)
        }
    }
}
