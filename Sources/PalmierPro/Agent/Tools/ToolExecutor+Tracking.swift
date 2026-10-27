import Foundation

extension ToolExecutor {
    private static let trackObjectAllowedKeys: Set<String> = ["clipId", "object", "label"]

    func trackObject(_ editor: EditorViewModel, _ args: [String: Any]) async throws -> ToolResult {
        try validateUnknownKeys(args, allowed: Self.trackObjectAllowedKeys, path: "track_object")
        let clipId = try args.requireString("clipId")
        let object = try args.requireString("object").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !object.isEmpty, object.count <= 80 else {
            throw ToolError("track_object.object must be a short noun phrase (1–80 characters).")
        }
        let requestedLabel = (args["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let label = requestedLabel.isEmpty ? object : requestedLabel

        let result: TrackingResult
        do {
            result = try await editor.trackObject(clipId: clipId, prompt: .concept(object), label: label)
        } catch let error as ObjectTrackingError {
            throw ToolError(Self.message(for: error, clipId: clipId))
        } catch let error as TrackingError {
            throw ToolError(Self.message(for: error, object: object))
        } catch let error as MetaModelError {
            throw ToolError(Self.message(for: error))
        }

        let out: [String: Any] = [
            "maskId": result.mask.id,
            "clipId": clipId,
            "target": result.mask.label,
            "trackedFrames": result.frames.count,
            "next": "Pass region {maskId, side: \"inside\" | \"outside\"} to apply_color or apply_effect.",
        ]
        guard let json = Self.jsonString(out) else { throw ToolError("Failed to encode result.") }
        return .ok(json)
    }

    private static func message(for error: ObjectTrackingError, clipId: String) -> String {
        switch error {
        case .clipNotFound: "Clip not found: \(clipId)"
        case .unsupportedClip: "Clip \(clipId) is not a video clip; track_object needs video footage."
        case .mediaOffline: "The media for clip \(clipId) is offline."
        case .alreadyTracking: "Clip \(clipId) is already being tracked; wait for that job to finish."
        case .emptyRange: "Clip \(clipId) uses no source frames."
        }
    }

    private static func message(for error: TrackingError, object: String) -> String {
        switch error {
        case .objectNotFound: "SAM 3.1 found no \"\(object)\" in this clip. Try a different noun phrase."
        case .tooLong(let frames): "The clip spans \(frames) source frames; SAM 3.1 tracks up to \(ObjectTracker.maxFrames). Split the clip first."
        case .invalidRange: "The clip's source range is invalid."
        case .noVideoTrack: "The clip's media has no readable video track."
        case .exportFailed(let reason): "Could not prepare the clip for tracking: \(reason)"
        case .invalidTarget: "The tracking target is invalid."
        }
    }

    private static func message(for error: MetaModelError) -> String {
        switch error {
        case .missingAPIKey: "No Meta Model API key. Add one in Settings to use track_object."
        case .http(let status, let body): "Meta Model API error \(status): \(body.prefix(300))"
        case .invalidResponse: "Meta Model API returned an unexpected response."
        case .segmentation(let error): "Could not read SAM 3.1 output: \(error)"
        case .streamFailed(let body): "SAM 3.1 request failed: \(body.prefix(300))"
        }
    }
}
