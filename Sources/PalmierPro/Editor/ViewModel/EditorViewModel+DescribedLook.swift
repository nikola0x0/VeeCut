import Foundation

enum LookRequestFailure: Equatable {
    case missingAPIKey
    /// Muse Spark answered with nothing VeeCut could apply.
    case unusable
    case failed
}

enum LookRequestStatus: Equatable {
    case running(clipId: String)
    case applied(clipId: String, name: String, wholeClip: Bool, skipped: [String])
    case failed(clipId: String, LookRequestFailure)

    var clipId: String {
        switch self {
        case .running(let clipId), .applied(let clipId, _, _, _), .failed(let clipId, _): clipId
        }
    }
}

/// Described looks: Muse Spark picks the effects, VeeCut applies them as tunable subject and background regions.
extension EditorViewModel {
    var isRequestingLook: Bool { lookRequestTask != nil }

    /// Asks Muse Spark for a look around `maskId`, or for the whole clip when there is no subject.
    func requestLook(described description: String, clipId: String, maskId: String?) {
        let description = String(description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(DescribedLook.maxDescriptionLength))
        guard !isRequestingLook, !description.isEmpty, clipFor(id: clipId)?.mediaType == .video,
              maskId.map({ trackedMask(id: $0) != nil }) ?? true else { return }
        let hasSubject = maskId != nil
        let instructions = DescribedLook.instructions(hasSubject: hasSubject)
        let schemaJSON: Data
        do {
            schemaJSON = try JSONSerialization.data(withJSONObject: DescribedLook.schema(hasSubject: hasSubject))
        } catch {
            Log.editor.error("described look schema encoding failed error=\(String(describing: error))")
            lookRequestStatus = .failed(clipId: clipId, .failed)
            return
        }
        lookRequestStatus = .running(clipId: clipId)
        lookRequestTask = Task { [weak self] in
            let outcome: Result<DescribedLook.Result, Error>
            do {
                let client = try await MetaModelClient.configured()
                let text = try await client.structuredResponse(
                    model: DescribedLook.model, instructions: instructions, prompt: description,
                    schemaName: "look", schemaJSON: schemaJSON
                )
                outcome = .success(try DescribedLook.parse(text, hasSubject: hasSubject))
            } catch {
                outcome = .failure(error)
            }
            guard let self else { return }
            defer { self.lookRequestTask = nil }
            guard !Task.isCancelled else {
                self.lookRequestStatus = nil
                return
            }
            self.finishLookRequest(outcome, clipId: clipId, maskId: maskId)
        }
    }

    func cancelLookRequest() {
        lookRequestTask?.cancel()
    }

    private func finishLookRequest(_ outcome: Result<DescribedLook.Result, Error>, clipId: String, maskId: String?) {
        switch outcome {
        case .success(let look):
            guard clipFor(id: clipId) != nil, maskId.map({ trackedMask(id: $0) != nil }) ?? true else {
                lookRequestStatus = nil
                return
            }
            let name = look.name.isEmpty ? L10n.string("Custom Look") : look.name
            applyLook(look.plan, clipId: clipId, maskId: maskId, actionName: L10n.string("Apply \(name)"))
            lookRequestStatus = .applied(clipId: clipId, name: name, wholeClip: maskId == nil, skipped: look.skipped)
        case .failure(MetaModelError.missingAPIKey):
            lookRequestStatus = .failed(clipId: clipId, .missingAPIKey)
        case .failure(let error as DescribedLookError):
            Log.editor.error("described look unusable clip=\(clipId) error=\(String(describing: error))")
            lookRequestStatus = .failed(clipId: clipId, .unusable)
        case .failure(let error):
            Log.editor.error("described look failed clip=\(clipId) error=\(String(describing: error))")
            lookRequestStatus = .failed(clipId: clipId, .failed)
        }
    }
}
