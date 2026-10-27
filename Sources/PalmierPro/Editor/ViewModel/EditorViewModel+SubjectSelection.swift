import Foundation

/// The tracked subject the canvas controls act on.
struct CanvasSubject: Equatable {
    let clipId: String
    let maskId: String
}

enum SubjectTrackingFailure: Equatable {
    case missingAPIKey
    case notFound
    /// SAM accepted the request but could not follow the marked spot.
    case modelFailed
    case failed
}

/// One-click looks applied to the tracked subject or its background.
enum SubjectLook: CaseIterable {
    case popSubject
    case darkenBackground
    case blurBackground

    var appliesOutside: Bool { self != .popSubject }

    var titleKey: String {
        switch self {
        case .popSubject: L10n.key("Pop Subject")
        case .darkenBackground: L10n.key("Darken Background")
        case .blurBackground: L10n.key("Blur Background")
        }
    }

    var effects: [Effect] {
        switch self {
        case .popSubject:
            [.make("color.exposure", ["ev": 0.3]), .make("color.contrast", ["amount": 1.08]), .make("color.vibrance", ["amount": 0.3])]
        case .darkenBackground:
            [.make("color.exposure", ["ev": -1.2]), .make("color.saturation", ["amount": 0.7])]
        case .blurBackground:
            [.make(Effect.gaussianBlurType, [Effect.gaussianBlurRadiusKey: 14])]
        }
    }
}

/// Canvas subject selection: draw on the preview, track with SAM 3.1, apply looks to the result.
extension EditorViewModel {
    static let subjectFeather = 6.0

    var isSubjectTracking: Bool { subjectTrackingTask != nil }

    func toggleSubjectSelection() {
        if subjectSelectionActive {
            subjectSelectionActive = false
            return
        }
        cancelChromaKeySampling()
        cropEditingActive = false
        subjectTrackingFailure = nil
        subjectSelectionActive = true
    }

    /// Escape handling, innermost first. Returns whether anything was dismissed.
    func cancelSubjectInteraction() -> Bool {
        if let task = subjectTrackingTask {
            task.cancel()
            return true
        }
        if subjectSelectionActive {
            subjectSelectionActive = false
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
        subjectSelectionActive = false
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
                self.canvasSubject = CanvasSubject(clipId: clipId, maskId: result.mask.id)
                self.selectedClipIds = [clipId]
                self.inspectorPanelVisible = true
                self.inspectorClipTabRequest = .subject
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

    /// Merges a look into the subject's inside or outside region as one undoable edit.
    func applySubjectLook(_ look: SubjectLook, clipId: String, maskId: String) {
        guard clipFor(id: clipId) != nil else { return }
        let matte = EffectMatte(maskId: maskId, invert: look.appliesOutside, feather: Self.subjectFeather)
        let actionName = L10n.string("Apply Look")
        undo.perform(actionName) {
            mutateClips(ids: [clipId], actionName: actionName) { clip in
                clip.updateRegion(matching: matte) { stack in
                    for effect in look.effects {
                        stack.removeAll { $0.type == effect.type }
                        stack.insert(effect, at: EffectRegistry.insertIndex(stack, for: effect.type))
                    }
                }
            }
        }
    }

    /// Adds `type` with default settings to the subject's inside or outside, unless already there.
    func addSubjectEffect(_ type: String, outside: Bool, clipId: String, maskId: String) {
        guard let descriptor = EffectRegistry.descriptor(id: type), clipFor(id: clipId) != nil else { return }
        let matte = EffectMatte(maskId: maskId, invert: outside, feather: Self.subjectFeather)
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

    /// Effects that can run inside a subject region: tunable numeric settings, no keying.
    static let subjectEffectDescriptors: [EffectDescriptor] = EffectRegistry.all.filter {
        !$0.params.isEmpty && !$0.id.hasPrefix("key.")
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
            .filter { $0.effectRegions?.contains { $0.matte.maskId == maskId } == true }
            .map(\.id)
        let usedElsewhere = timelines.contains { other in
            other.id != timeline.id && other.tracks.contains { track in
                track.clips.contains { $0.effectRegions?.contains { $0.matte.maskId == maskId } == true }
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
