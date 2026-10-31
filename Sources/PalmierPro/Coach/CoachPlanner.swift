import Foundation

struct RawPlan: Decodable {
    struct Section: Decodable {
        let title: String
        let targetSeconds: Double
        let hint: String
        let suggestions: [PlanMoment]
    }
    let sections: [Section]
}

/// Drafts a plan with Muse Spark from the footage notes, then keeps only what the footage can back.
enum CoachPlanner {
    static let maximumSuggestions = 6

    @concurrent
    static func plan(
        brief: String, style: PlanStyle?, notes: [FootageNote], placed: [PlanMoment], client: any CoachModel,
        onThinking: @escaping @Sendable (String) async -> Void = { _ in }
    ) async throws -> RawPlan {
        struct Clip: Encodable {
            let assetId: String
            let duration: Double
            let speech: Bool
            let labels: [String]
            let summary: String?
            let said: String?
            let moments: [PlanMoment]
        }
        struct Request: Encodable {
            let brief: String
            let style: String?
            let clips: [Clip]
            let alreadyPlaced: [PlanMoment]
        }
        let request = Request(
            brief: brief, style: style?.rawValue,
            clips: notes.map { Clip(assetId: $0.assetId, duration: $0.durationSeconds, speech: $0.hasSpeech, labels: $0.labels, summary: $0.summary, said: $0.transcript, moments: $0.moments) },
            alreadyPlaced: placed
        )
        let prompt = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        let schema = try JSONSerialization.data(withJSONObject: schemaObject)
        let text = try await client.structuredResponse(model: DescribedLook.model, instructions: instructions, parts: [.text(prompt)], schemaName: "plan", schemaJSON: schema, onThinking: onThinking)
        return try JSONDecoder().decode(RawPlan.self, from: Data(text.utf8))
    }

    /// Drops suggestions the footage can't back and malformed sections; no sections left is a failure.
    static func validated(_ raw: RawPlan, notes: [FootageNote], trackId: String, brief: String, style: PlanStyle?) throws(CoachFailure) -> EditPlan {
        let durations = Dictionary(notes.map { ($0.assetId, $0.durationSeconds) }) { first, _ in first }
        let sections = raw.sections.compactMap { section -> PlanSection? in
            guard section.targetSeconds.isFinite, section.targetSeconds > 0,
                  let title = try? EditPlan.normalizedTitle(section.title) else { return nil }
            let suggestions = section.suggestions.filter { moment in
                durations[moment.assetId].map { moment.isUsable(withinDuration: $0) } ?? false
            }
            return PlanSection(title: title, targetSeconds: section.targetSeconds, hint: section.hint, suggestions: Array(suggestions.prefix(maximumSuggestions)))
        }
        guard !sections.isEmpty else { throw .emptyPlan }
        return EditPlan(brief: brief, style: style, trackId: trackId, sections: sections)
    }

    private static let instructions = """
    You plan the structure of a video edit for a user who will place the clips themselves. The input is JSON: the \
    user's brief, an optional style, every clip with its duration, speech, labels, summary and moments, and the moments \
    already on the timeline. Return 3–7 ordered sections. Each has a short title, a target length in seconds, a hint \
    of at most 60 characters telling the user what to drop there, and up to 6 suggested moments. Suggest only moments \
    from the clips, using their assetId and times within the clip; you may tighten a moment's range. Section lengths \
    must fit the moments available for them and add up to the length the brief asks for (about 3 minutes when it \
    doesn't say). Prefer moments that are not already placed.
    """

    private static var schemaObject: [String: Any] {
        [
        "type": "object", "additionalProperties": false, "required": ["sections"],
        "properties": ["sections": ["type": "array", "items": [
            "type": "object", "additionalProperties": false, "required": ["title", "targetSeconds", "hint", "suggestions"],
            "properties": [
                "title": ["type": "string"],
                "targetSeconds": ["type": "number"],
                "hint": ["type": "string"],
                "suggestions": ["type": "array", "items": [
                    "type": "object", "additionalProperties": false, "required": ["assetId", "start", "end", "note"],
                    "properties": ["assetId": ["type": "string"], "start": ["type": "number"], "end": ["type": "number"], "note": ["type": "string"]],
                ]],
            ],
        ]]],
        ]
    }
}
