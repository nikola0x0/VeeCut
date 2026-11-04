import Foundation

/// The canvas object the tag and card act on: one subject or area, or the whole clip when `maskId` is nil.
struct CanvasSubject: Hashable {
    let clipId: String
    let maskId: String?
}

/// The canvas tool in use: Pick marks a subject with a scribble, circle or click; Brush paints over a region.
/// Both hand the mark to SAM to track.
enum CanvasSelectionKind: Equatable {
    case subject
    case brush
}

enum SubjectTrackingFailure: Equatable {
    case missingAPIKey
    case notFound
    /// SAM accepted the request but could not follow the marked spot.
    case modelFailed
    /// Meta's service failed while tracking; nothing about the mark was wrong.
    case serviceFailed
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
        if subjectTrackingFailure != nil {
            subjectTrackingFailure = nil
            return true
        }
        if subjectFollowFailure != nil {
            subjectFollowFailure = nil
            return true
        }
        if objectCardOpen {
            objectCardOpen = false
            return true
        }
        if canvasSubject != nil {
            clearCanvasObject()
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
        runSubjectTracking(clipId: clipId) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.trackObject(clipId: clipId, prompt: prompt, label: label).mask
        }
    }

    /// Runs one tracking job with the dock's progress, Escape cancel and failure messages, then selects the result.
    func runSubjectTracking(
        clipId: String,
        track: @escaping @MainActor () async throws -> TrackedMask,
        then completion: @escaping @MainActor (TrackedMask) -> Void = { _ in }
    ) {
        canvasSelection = nil
        subjectTrackingFailure = nil
        clearCanvasObject()
        subjectTrackingClipId = clipId
        subjectTrackingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.subjectTrackingTask = nil
                self.subjectTrackingClipId = nil
            }
            do {
                let mask = try await track()
                guard !Task.isCancelled, self.clipFor(id: clipId) != nil else { return }
                self.selectCanvasObject(clipId: clipId, maskId: mask.id)
                completion(mask)
            } catch is CancellationError {
            } catch MetaModelError.missingAPIKey {
                self.subjectTrackingFailure = .missingAPIKey
            } catch TrackingError.objectNotFound {
                self.subjectTrackingFailure = .notFound
            } catch MetaModelError.serverFailed(let detail) {
                guard !Task.isCancelled else { return }
                Log.editor.error("subject tracking server failure clip=\(clipId) detail=\(detail)")
                self.subjectTrackingFailure = .serviceFailed
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

    /// The clip's background matte: its existing background region, else outside every subject on its media;
    /// `keeping` is always among the subjects it leaves sharp.
    func backgroundMatte(clipId: String, keeping maskId: String? = nil) -> EffectMatte? {
        guard let clip = clipFor(id: clipId) else { return nil }
        let existing = clip.effectRegions?.first(where: { $0.matte.invert })?.matte
        var ids = existing?.maskIds ?? trackedMasks(forMedia: clip.mediaRef).map(\.id)
        if let maskId, !ids.contains(maskId) { ids.append(maskId) }
        return ids.isEmpty ? nil : EffectMatte(maskIds: ids, invert: true, feather: existing?.feather ?? Self.subjectFeather)
    }

    private func lookMatte(outside: Bool, clipId: String, maskId: String) -> EffectMatte? {
        outside ? backgroundMatte(clipId: clipId, keeping: maskId) : EffectMatte(maskId: maskId, feather: Self.subjectFeather)
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

    /// Edge softness of the clip's regions: the region inside `maskId`, else the first; `mixed` when they differ.
    func edgeSoftness(clipId: String, preferring maskId: String?) -> (value: Double, mixed: Bool)? {
        guard let regions = clipFor(id: clipId)?.effectRegions, let first = regions.first else { return nil }
        let preferred = regions.first { !$0.matte.invert && $0.matte.maskId == maskId } ?? first
        return (preferred.matte.feather, regions.contains { $0.matte.feather != preferred.matte.feather })
    }

    /// Sets every region's edge softness on the clip: live while dragging, one undo step on `commit`.
    func setEdgeSoftness(_ value: Double, clipId: String, commit: Bool) {
        guard value.isFinite, clipFor(id: clipId)?.effectRegions?.isEmpty == false else { return }
        let feather = min(max(value, EffectMatte.featherRange.lowerBound), EffectMatte.featherRange.upperBound)
        let body: (inout Clip) -> Void = { clip in
            clip.effectRegions = clip.effectRegions?.map { region in
                var region = region
                region.matte.feather = feather
                return region
            }
        }
        if commit {
            commitClipProperties(clipIds: [clipId], actionName: L10n.string("Change Edge Softness"), body)
        } else {
            applyClipProperties(clipIds: [clipId], body)
        }
    }

    /// Effects that can run inside a subject region: tunable numeric settings, no keying, no file resources,
    /// and not Smooth Skin, which only goes on a face.
    static let subjectEffectDescriptors: [EffectDescriptor] = EffectRegistry.all.filter {
        !$0.params.isEmpty && !$0.id.hasPrefix("key.") && $0.resourceKey == nil && $0.id != smoothSkinEffect
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
        L10n.string("Subject \(trackedMasks(forMedia: mediaRef).count + 1)")
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
        if canvasSubject?.maskId == maskId { clearCanvasObject() }
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
