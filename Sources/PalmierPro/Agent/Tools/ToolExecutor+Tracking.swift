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

    private static let smoothSkinAllowedKeys: Set<String> = ["clipId", "maskId", "smoothing", "blemishes"]

    func smoothSkin(_ editor: EditorViewModel, _ args: [String: Any]) async throws -> ToolResult {
        try validateUnknownKeys(args, allowed: Self.smoothSkinAllowedKeys, path: "smooth_skin")
        let clipId = try args.requireString("clipId")
        guard let clip = editor.clipFor(id: clipId) else { throw ToolError("Clip not found: \(clipId)") }
        guard clip.mediaType == .video else { throw ToolError("smooth_skin needs a video clip; \(clipId) is a \(clip.mediaType.rawValue) clip.") }
        let person = args["maskId"] as? String
        if args["maskId"] != nil {
            guard let person, let mask = editor.trackedMask(id: person), mask.mediaRef == clip.mediaRef else {
                throw ToolError("smooth_skin.maskId must be a person or face tracked in \(clipId)'s footage (from track_object).")
            }
        }
        func level(_ key: String, default value: Double) throws -> Double {
            guard let raw = args[key] else { return value }
            guard let number = raw as? Double, number.isFinite, (0...1).contains(number) else {
                throw ToolError("smooth_skin.\(key) must be a number from 0 to 1.")
            }
            return number
        }
        let smoothing = try level("smoothing", default: EditorViewModel.smoothSkinDefaults.smoothing)
        let blemishes = try level("blemishes", default: EditorViewModel.smoothSkinDefaults.blemishes)

        let reused = editor.trackedFace(clipId: clipId, person: person) != nil
        let face: TrackedMask
        do {
            face = try await editor.findFace(clipId: clipId, person: person)
        } catch let error as ObjectTrackingError {
            throw ToolError(Self.message(for: error, clipId: clipId))
        } catch let error as TrackingError {
            throw ToolError(Self.message(for: error, object: "face"))
        } catch let error as MetaModelError {
            throw ToolError(Self.message(for: error))
        } catch let error as SmoothSkinFailure {
            throw ToolError("smooth_skin failed: \(error).")
        }
        guard editor.clipFor(id: clipId) != nil, editor.trackedMask(id: face.id) != nil else {
            throw ToolError("smooth_skin: the clip or face was removed while the face was being found; nothing changed.")
        }

        let snapshot = timelineSnapshot(editor)
        editor.applySmoothSkin(clipId: clipId, faceId: face.id, smoothing: smoothing, blemishes: blemishes)
        return mutationResult(editor, since: snapshot, touched: [clipId], extra: [
            "faceMaskId": face.id,
            "faceLabel": face.label,
            "foundNewFace": !reused,
            "smoothing": smoothing,
            "blemishes": blemishes,
        ])
    }

    private static let followObjectAllowedKeys: Set<String> = ["clipId", "maskId", "subjectClipId", "placement"]

    func followObject(_ editor: EditorViewModel, _ args: [String: Any]) throws -> ToolResult {
        try validateUnknownKeys(args, allowed: Self.followObjectAllowedKeys, path: "follow_object")
        let clipId = try args.requireString("clipId")
        let maskId = try args.requireString("maskId")
        guard let mask = editor.trackedMask(id: maskId) else {
            throw ToolError("follow_object: unknown maskId '\(maskId)'. Call track_object first.")
        }
        guard let follower = editor.clipFor(id: clipId) else { throw ToolError("Clip not found: \(clipId)") }

        let placement = try followPlacement(args, path: "follow_object") ?? .keepOffset
        let subjectClipId = try subjectClipId(
            editor, args, mask: mask, path: "follow_object",
            overlapping: (follower.startFrame..<follower.endFrame, excluding: clipId)
        )

        let snapshot = timelineSnapshot(editor)
        let subject = CanvasSubject(clipId: subjectClipId, maskId: maskId)
        switch editor.followSubject(clipId: clipId, subject: subject, placement: placement, actionName: "Follow Object (Agent)") {
        case .failure(let failure):
            throw ToolError(Self.message(for: failure, clipId: clipId))
        case .success(let follow):
            let frames = follow.track.keyframes.map { $0.frame + follower.startFrame }
            return mutationResult(editor, since: snapshot, touched: [clipId], extra: [
                "maskId": maskId,
                "subjectClipId": subjectClipId,
                "placement": placement.rawValue,
                "positionKeyframes": frames.count,
                "followsFromFrame": frames.first ?? follower.startFrame,
                "followsThroughFrame": frames.last ?? follower.startFrame,
            ])
        }
    }

    private static let addStickerAllowedKeys: Set<String> = ["description", "maskId", "subjectClipId", "placement", "startFrame"]

    func addSticker(_ editor: EditorViewModel, _ args: [String: Any]) async throws -> ToolResult {
        try validateUnknownKeys(args, allowed: Self.addStickerAllowedKeys, path: "add_sticker")
        let description = try args.requireString("description").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty, description.count <= EditorViewModel.stickerDescriptionLimit else {
            throw ToolError("add_sticker.description must be 1–\(EditorViewModel.stickerDescriptionLimit) characters.")
        }
        let placement = try followPlacement(args, path: "add_sticker")
        var subject: CanvasSubject?
        if let rawMask = args["maskId"] {
            guard let maskId = rawMask as? String, let mask = editor.trackedMask(id: maskId) else {
                throw ToolError("add_sticker: unknown maskId '\(rawMask)'. Call track_object first.")
            }
            subject = CanvasSubject(clipId: try subjectClipId(editor, args, mask: mask, path: "add_sticker"), maskId: maskId)
        } else if args["subjectClipId"] != nil || placement != nil {
            throw ToolError("add_sticker: subjectClipId and placement need maskId.")
        }
        var startFrame: Int?
        if let raw = args["startFrame"] {
            guard subject == nil else { throw ToolError("add_sticker.startFrame applies only without maskId; a following sticker spans the object's frames.") }
            guard !isJSONBoolean(raw), let frame = raw as? Int, frame >= 0 else {
                throw ToolError("add_sticker.startFrame must be a non-negative integer.")
            }
            startFrame = frame
        }

        let snapshot = timelineSnapshot(editor)
        let receipt: StickerReceipt
        do {
            receipt = try await editor.addSticker(
                description: description, subject: subject, placement: placement,
                startFrame: startFrame, actionName: "Add Sticker (Agent)"
            )
        } catch let failure as StickerFailure {
            throw ToolError(Self.message(for: failure))
        }
        var extra: [String: Any] = ["mediaRef": receipt.assetId, "follows": subject != nil && receipt.followFailure == nil]
        var notes: [String] = []
        if let failure = receipt.followFailure {
            notes.append("Placed but not following: \(Self.message(for: failure, clipId: receipt.clipId))")
        }
        if let subject { extra["subjectClipId"] = subject.clipId }
        return mutationResult(editor, since: snapshot, touched: [receipt.clipId], extra: extra, notes: notes)
    }

    private static func message(for failure: StickerFailure) -> String {
        switch failure {
        case .noProject: "No saved project is open; save the project first."
        case .emptyDescription: "The description must be 1–\(EditorViewModel.stickerDescriptionLimit) characters."
        case .missingAPIKey: "No Meta Model API key. Add one in Settings to use add_sticker."
        case .contentPolicy: "Meta's content policy blocked that sticker. Describe it differently."
        case .nothingToCutOut: "Muse Image's drawing couldn't be cut out of its background. Try again or reword it."
        case .subject(let failure): message(for: failure, clipId: "the sticker")
        case .failed(let detail): "Muse Image failed: \(detail.prefix(300))"
        }
    }

    func followPlacement(_ args: [String: Any], path: String) throws -> SubjectFollowPlacement? {
        guard let raw = args["placement"] else { return nil }
        guard let name = raw as? String, let placement = SubjectFollowPlacement(rawValue: name) else {
            let names = SubjectFollowPlacement.allCases.map(\.rawValue).joined(separator: ", ")
            throw ToolError("\(path).placement must be one of: \(names).")
        }
        return placement
    }

    /// The video clip a tracked object rides in: `subjectClipId` when given, else the only clip using its footage
    /// (that overlaps `overlapping`, when given).
    func subjectClipId(
        _ editor: EditorViewModel,
        _ args: [String: Any],
        mask: TrackedMask,
        path: String,
        overlapping: (frames: Range<Int>, excluding: String)? = nil
    ) throws -> String {
        if let raw = args["subjectClipId"] {
            guard let id = raw as? String, let clip = editor.clipFor(id: id), clip.mediaType == .video, clip.mediaRef == mask.mediaRef else {
                throw ToolError("\(path).subjectClipId must be a video clip using the footage \(mask.id) was tracked in.")
            }
            return id
        }
        let candidates = editor.timeline.tracks.flatMap(\.clips).filter { clip in
            guard clip.mediaType == .video, clip.mediaRef == mask.mediaRef else { return false }
            guard let overlapping else { return true }
            return clip.id != overlapping.excluding
                && clip.startFrame < overlapping.frames.upperBound && overlapping.frames.lowerBound < clip.endFrame
        }
        guard let only = candidates.first, candidates.count == 1 else {
            let scope = overlapping.map { " overlapping \($0.excluding)" } ?? ""
            throw ToolError(candidates.isEmpty
                ? "\(path): no clip using the footage \(mask.id) was tracked in is on the timeline\(scope)."
                : "\(path): several clips use that footage\(scope); pass subjectClipId, one of \(candidates.map(\.id).joined(separator: ", ")).")
        }
        return only.id
    }

    private static func message(for failure: SubjectFollowFailure, clipId: String) -> String {
        switch failure {
        case .clipNotFound: "Clip not found: \(clipId)"
        case .notVisual: "Clip \(clipId) is audio; only text, image and video clips can follow an object."
        case .sameClip: "Clip \(clipId) is the clip the object was tracked in; it can't follow itself."
        case .maskNotLoaded: "The object's tracking data isn't loaded. Call track_object again."
        case .noOverlap: "Clip \(clipId) doesn't overlap the object's clip on the timeline."
        case .subjectAbsent: "The object doesn't show while clip \(clipId) plays."
        }
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
        case .contentPolicy: "Meta's content policy blocked the request."
        }
    }
}
