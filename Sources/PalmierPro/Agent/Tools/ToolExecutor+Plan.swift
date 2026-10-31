import Foundation

extension ToolExecutor {
    func getPlan(_ editor: EditorViewModel, _ args: [String: Any]) throws -> ToolResult {
        try validateUnknownKeys(args, allowed: [], path: "get_plan")
        return try planReceipt(editor)
    }

    private static let makePlanAllowedKeys: Set<String> = ["brief", "style"]

    func makePlan(_ editor: EditorViewModel, _ args: [String: Any]) async throws -> ToolResult {
        try validateUnknownKeys(args, allowed: Self.makePlanAllowedKeys, path: "make_plan")
        let brief = try args.requireString("brief").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brief.isEmpty, brief.count <= 1_000 else { throw ToolError("make_plan.brief must be 1–1000 characters.") }
        var style: PlanStyle?
        if let raw = args["style"] {
            guard let name = raw as? String, let value = PlanStyle(rawValue: name) else {
                throw ToolError("make_plan.style must be one of \(PlanStyle.allCases.map(\.rawValue).joined(separator: ", ")).")
            }
            style = value
        }
        guard editor.coachTask == nil else {
            throw ToolError("make_plan: the coach is already planning this timeline; wait for it or ask the user to cancel it.")
        }
        let planning = editor.submitBrief(brief, style: style)
        let result = await withTaskCancellationHandler {
            await planning.value
        } onCancel: {
            Task { @MainActor in editor.cancelCoach() }
        }
        switch result {
        case .success(let made):
            return try planReceipt(editor, extra: [
                "source": made.fromTemplate ? "template" : "museSpark",
                "note": made.fromTemplate ? "No Meta API key: applied the starter sections without suggestions." : "Clips stay where they are; the user places moments.",
            ])
        case .failure(let failure):
            throw ToolError(Self.message(for: failure))
        }
    }

    func editPlan(_ editor: EditorViewModel, _ args: [String: Any]) throws -> ToolResult {
        try validateUnknownKeys(args, allowed: ["operations"], path: "edit_plan")
        guard let plan = editor.timeline.plan else { throw ToolError("edit_plan: the timeline has no plan. Call make_plan first.") }
        guard let rawOperations = args["operations"] as? [Any], !rawOperations.isEmpty else {
            throw ToolError("edit_plan.operations must be a non-empty array.")
        }
        var edits: [PlanEdit] = []
        var added: [String] = []
        for (index, raw) in rawOperations.enumerated() {
            let path = "edit_plan.operations[\(index)]"
            guard let operation = raw as? [String: Any] else { throw ToolError("\(path) must be an object.") }
            let edit = try Self.planEdit(operation, path: path)
            if case .add(let section, _) = edit { added.append(section.id) }
            edits.append(edit)
            do {
                _ = try plan.applying(edits)
            } catch {
                throw ToolError("\(path): \(Self.message(for: error)) Nothing changed.")
            }
        }
        let changed = (try? plan.applying(edits)) != plan
        if let failure = editor.editPlan(edits, actionName: "Edit Plan") {
            throw ToolError("edit_plan: \(Self.message(for: failure)) Nothing changed.")
        }
        return try planReceipt(editor, extra: ["changed": changed, "addedSectionIds": added])
    }

    private static let addToSectionAllowedKeys: Set<String> = ["sectionId", "mediaRef", "startSeconds", "endSeconds"]

    func addToSection(_ editor: EditorViewModel, _ args: [String: Any]) throws -> ToolResult {
        try validateUnknownKeys(args, allowed: Self.addToSectionAllowedKeys, path: "add_to_section")
        let sectionId = try args.requireString("sectionId")
        let asset = try asset(args.requireString("mediaRef"), editor: editor)
        let start = try Self.seconds(args, "startSeconds", path: "add_to_section") ?? 0
        let end = try Self.seconds(args, "endSeconds", path: "add_to_section") ?? asset.duration
        let snapshot = timelineSnapshot(editor)
        switch editor.placeMoment(PlanMoment(assetId: asset.id, start: start, end: end, note: ""), in: sectionId) {
        case .success(let ids):
            let progress = editor.timeline.plan.flatMap { plan in
                PlanLayout.progress(plan, in: editor.timeline).first { $0.sectionId == sectionId }
            }
            return mutationResult(editor, since: snapshot, touched: ids, extra: [
                "sectionId": sectionId,
                "clipIds": ids,
                "sectionActualSeconds": progress?.actualSeconds ?? 0,
                "sectionTargetSeconds": progress?.targetSeconds ?? 0,
            ])
        case .failure(let failure):
            throw ToolError(Self.message(for: failure, sectionId: sectionId, asset: asset))
        }
    }

    private func planReceipt(_ editor: EditorViewModel, extra: [String: Any] = [:]) throws -> ToolResult {
        var out = extra
        if let plan = editor.timeline.plan {
            let progress = PlanLayout.progress(plan, in: editor.timeline)
            var planJSON: [String: Any] = [
                "brief": plan.brief,
                "trackId": plan.trackId,
                "sections": zip(plan.sections, progress).map { section, progress in
                    [
                        "sectionId": section.id,
                        "title": section.title,
                        "targetSeconds": section.targetSeconds,
                        "actualSeconds": (progress.actualSeconds * 100).rounded() / 100,
                        "filled": progress.isFilled,
                        "hint": section.hint,
                        "suggestions": section.suggestions.prefix(CoachPlanner.maximumSuggestions).map {
                            ["mediaRef": $0.assetId, "startSeconds": $0.start, "endSeconds": $0.end, "note": $0.note] as [String: Any]
                        },
                    ] as [String: Any]
                },
            ]
            if let style = plan.style { planJSON["style"] = style.rawValue }
            out["plan"] = planJSON
            out["tips"] = CoachRules.nudges(plan: plan, timeline: editor.timeline, beatFrames: editor.coachBeatFrames, musicSeconds: editor.musicSeconds)
                .map(Self.tipJSON)
        } else {
            out["plan"] = NSNull()
        }
        if let recommendation = editor.footageRecommendation {
            out["footageSummary"] = recommendation.summary
            out["ideas"] = recommendation.ideas.map {
                ["title": $0.title, "style": $0.style.rawValue, "targetSeconds": $0.targetSeconds, "pitch": $0.pitch] as [String: Any]
            }
        }
        guard let json = Self.jsonString(out) else { throw ToolError("Failed to encode result.") }
        return .ok(json)
    }

    private static func tipJSON(_ nudge: CoachNudge) -> [String: Any] {
        var tip: [String: Any] = ["tipId": nudge.id]
        if let sectionId = nudge.sectionId { tip["sectionId"] = sectionId }
        switch nudge.kind {
        case .sectionOver(_, let extra): tip["kind"] = "sectionOver"; tip["extraSeconds"] = (extra * 10).rounded() / 10
        case .offBeatCuts(_, let cuts): tip["kind"] = "offBeatCuts"; tip["cutFrames"] = cuts
        case .emptySection(_, let moments): tip["kind"] = "emptySection"; tip["suggestionCount"] = moments.count
        case .hookCandidate(_, let moment): tip["kind"] = "hookCandidate"; tip["mediaRef"] = moment.assetId; tip["startSeconds"] = moment.start; tip["endSeconds"] = moment.end
        case .fitToMusic(let seconds): tip["kind"] = "fitToMusic"; tip["songSeconds"] = seconds
        }
        return tip
    }

    private static func planEdit(_ operation: [String: Any], path: String) throws -> PlanEdit {
        guard let op = operation["op"] as? String else { throw ToolError("\(path).op is required.") }
        func sectionId() throws -> String {
            guard let id = operation["sectionId"] as? String else { throw ToolError("\(path).sectionId is required for \(op).") }
            return id
        }
        func title() throws -> String {
            guard let title = operation["title"] as? String else { throw ToolError("\(path).title is required for \(op).") }
            return title
        }
        switch op {
        case "rename":
            try validateUnknownKeys(operation, allowed: ["op", "sectionId", "title"], path: path)
            return .rename(try sectionId(), to: try title())
        case "setTarget":
            try validateUnknownKeys(operation, allowed: ["op", "sectionId", "seconds"], path: path)
            guard let seconds = try Self.seconds(operation, "seconds", path: path) else { throw ToolError("\(path).seconds is required for setTarget.") }
            return .setTarget(try sectionId(), seconds: seconds)
        case "move":
            try validateUnknownKeys(operation, allowed: ["op", "sectionId", "offset"], path: path)
            guard let offset = operation["offset"] as? Int, !(operation["offset"] is Bool) else { throw ToolError("\(path).offset must be an integer.") }
            return .move(try sectionId(), by: offset)
        case "add":
            try validateUnknownKeys(operation, allowed: ["op", "title", "seconds", "hint", "afterSectionId"], path: path)
            let hint = operation["hint"] as? String ?? ""
            guard operation["hint"] == nil || operation["hint"] is String else { throw ToolError("\(path).hint must be a string.") }
            guard operation["afterSectionId"] == nil || operation["afterSectionId"] is String else { throw ToolError("\(path).afterSectionId must be a string.") }
            let seconds = try Self.seconds(operation, "seconds", path: path) ?? 10
            return .add(PlanSection(title: try title(), targetSeconds: seconds, hint: hint), after: operation["afterSectionId"] as? String)
        case "delete":
            try validateUnknownKeys(operation, allowed: ["op", "sectionId"], path: path)
            return .delete(try sectionId())
        default:
            throw ToolError("\(path).op must be rename, setTarget, move, add or delete.")
        }
    }

    /// A finite JSON number, or nil when absent.
    private static func seconds(_ args: [String: Any], _ key: String, path: String) throws -> Double? {
        guard let raw = args[key] else { return nil }
        let value: Double? = raw is Bool ? nil : (raw as? Double) ?? (raw as? Int).map(Double.init)
        guard let value, value.isFinite else { throw ToolError("\(path).\(key) must be a finite number of seconds.") }
        return value
    }

    private static func message(for failure: PlanEditFailure) -> String {
        switch failure {
        case .noPlan: "The timeline has no plan."
        case .unknownSection: "Unknown sectionId (or a duplicate new section)."
        case .invalidTitle: "Titles must be 1–80 characters on one line."
        case .invalidTarget: "Target length must be 1–600 seconds."
        case .invalidMove: "The move goes past the first or last section."
        }
    }

    private static func message(for failure: PlanPlacementFailure, sectionId: String, asset: MediaAsset) -> String {
        switch failure {
        case .noPlan: "add_to_section: the timeline has no plan. Call make_plan first."
        case .unknownSection: "add_to_section.sectionId '\(sectionId)' is not in the plan; use get_plan."
        case .unknownAsset: "add_to_section.mediaRef must be a video or image; \(asset.id) is \(asset.type.rawValue)."
        case .invalidRange: "add_to_section: the range must lie within 0–\(asset.duration) s of \(asset.id) with endSeconds after startSeconds."
        case .rippleBlocked: "add_to_section: inserting there would break a multicam group's sync; nothing changed."
        }
    }

    private static func message(for failure: CoachFailure) -> String {
        switch failure {
        case .missingAPIKey: "make_plan needs a Meta Model API key in Settings."
        case .noFootage: "make_plan: there is no video in the project to plan from. Import footage first."
        case .emptyPlan: "make_plan: Muse Spark returned no usable sections. Try a more specific brief."
        case .cancelled: "make_plan was cancelled or the timeline changed while planning; nothing changed."
        case .service(let detail): "make_plan failed: \(detail)"
        }
    }
}
