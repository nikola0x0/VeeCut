import Foundation

extension ToolExecutor {
    /// Stable machine ids for the object bar's preset looks.
    nonisolated static let lookIdsByLook: [(id: String, look: SubjectLook)] = [
        ("pop_subject", .popSubject), ("crisp_subject", .crispSubject),
        ("darken_background", .darkenBackground), ("blur_background", .blurBackground), ("color_pop", .colorPop),
        ("vlog_pop", .vlogPop), ("cinematic", .cinematic), ("moody", .moody), ("golden_hour", .goldenHour),
        ("teal_orange", .tealOrange), ("noir", .noir), ("vintage_film", .vintageFilm), ("dreamy", .dreamy), ("crisp", .crisp),
    ]
    nonisolated static var lookIds: [String] { lookIdsByLook.map(\.id) }

    private static let applyLookAllowedKeys: Set<String> = ["clipId", "look", "maskId"]

    func applyLook(_ editor: EditorViewModel, _ args: [String: Any]) throws -> ToolResult {
        try validateUnknownKeys(args, allowed: Self.applyLookAllowedKeys, path: "apply_look")
        let clipId = try args.requireString("clipId")
        let lookId = try args.requireString("look")
        guard let look = Self.lookIdsByLook.first(where: { $0.id == lookId })?.look else {
            throw ToolError("apply_look: unknown look '\(lookId)'. Use one of: \(Self.lookIds.joined(separator: ", ")).")
        }
        guard let clip = editor.clipFor(id: clipId) else { throw ToolError("Clip not found: \(clipId)") }
        guard clip.mediaType == .video else { throw ToolError("apply_look needs a video clip; \(clipId) is a \(clip.mediaType.rawValue) clip.") }

        let maskId = args["maskId"] as? String
        if args["maskId"] != nil {
            guard let maskId, let mask = editor.trackedMask(id: maskId), mask.mediaRef == clip.mediaRef else {
                throw ToolError("apply_look: unknown maskId for \(clipId)'s footage. Call track_object on this clip first.")
            }
        }
        if maskId == nil, look.placement != .both {
            throw ToolError("apply_look: \(lookId) needs maskId — call track_object first to choose what it applies to.")
        }

        let snapshot = timelineSnapshot(editor)
        editor.applySubjectLook(look, clipId: clipId, maskId: maskId)
        let placement = switch (look.placement, maskId) {
        case (.subject, _): "subject"
        case (.background, _): "background"
        case (.both, nil): "wholeClip"
        case (.both, _): "subjectAndBackground"
        }
        var extra: [String: Any] = ["look": lookId, "placement": placement]
        if let maskId { extra["maskId"] = maskId }
        if look.placement != .subject, maskId != nil,
           let background = editor.clipFor(id: clipId)?.effectRegions?.first(where: { $0.matte.invert }) {
            extra["keptSharp"] = background.matte.maskIds
        }
        return mutationResult(editor, since: snapshot, touched: [clipId], extra: extra)
    }
}
