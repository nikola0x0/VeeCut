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
    static let subjectMaskLabel = "subject"
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
                let result = try await self.trackObject(clipId: clipId, prompt: .target(target), label: Self.subjectMaskLabel)
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

    /// Removes every look tied to `maskId` on the clip as one undoable edit.
    func removeSubject(clipId: String, maskId: String) {
        guard clipFor(id: clipId)?.effectRegions?.contains(where: { $0.matte.maskId == maskId }) == true else { return }
        let actionName = L10n.string("Remove Subject Looks")
        undo.perform(actionName) {
            mutateClips(ids: [clipId], actionName: actionName) { $0.removeRegions(maskId: maskId) }
        }
        if canvasSubject == CanvasSubject(clipId: clipId, maskId: maskId) { canvasSubject = nil }
    }
}
