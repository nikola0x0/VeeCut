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
    static let maximumPacedSuggestions = 8

    /// The song to plan on, with the asset it came from.
    struct Song: Sendable {
        let map: MusicMap
        let assetId: String
    }

    @concurrent
    static func plan(
        brief: String, style: PlanStyle?, notes: [FootageNote], placed: [PlanMoment], music: MusicMap? = nil, client: any CoachModel,
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
        struct MusicPart: Encodable {
            let start: Double
            let end: Double
            let energy: MusicEnergy
            let bars: Int
        }
        struct Music: Encodable {
            let seconds: Double
            let parts: [MusicPart]
            let drop: Double?
        }
        struct Request: Encodable {
            let brief: String
            let style: String?
            let clips: [Clip]
            let alreadyPlaced: [PlanMoment]
            let music: Music?
        }
        let request = Request(
            brief: brief, style: style?.rawValue,
            clips: notes.map { Clip(assetId: $0.assetId, duration: $0.durationSeconds, speech: $0.hasSpeech, labels: $0.labels, summary: $0.summary, said: $0.transcript, moments: $0.moments) },
            alreadyPlaced: placed,
            music: music.map { map in
                Music(seconds: map.duration, parts: map.parts.map { MusicPart(start: $0.start, end: $0.end, energy: $0.energy, bars: $0.bars) }, drop: map.drop)
            }
        )
        let prompt = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        let schema = try JSONSerialization.data(withJSONObject: schemaObject)
        let text = try await client.structuredResponse(model: DescribedLook.model, instructions: instructions, parts: [.text(prompt)], schemaName: "plan", schemaJSON: schema, onThinking: onThinking)
        return try JSONDecoder().decode(RawPlan.self, from: Data(text.utf8))
    }

    /// Drops suggestions the footage can't back and malformed sections; no sections left is a failure.
    /// With a song, timing and pace come from its parts and the model only names them and picks their moments.
    @MainActor static func validated(_ raw: RawPlan, notes: [FootageNote], trackId: String, brief: String, style: PlanStyle?, music: Song? = nil) throws(CoachFailure) -> EditPlan {
        let durations = Dictionary(notes.map { ($0.assetId, $0.durationSeconds) }) { first, _ in first }
        if let music {
            let sections = music.map.parts.enumerated().map { index, part -> PlanSection in
                let drafted = raw.sections.indices.contains(index) ? raw.sections[index] : nil
                let title = drafted.flatMap { try? EditPlan.normalizedTitle($0.title) } ?? defaultTitle(for: part.energy)
                let suggestions = (drafted?.suggestions ?? []).filter { moment in
                    durations[moment.assetId].map { moment.isUsable(withinDuration: $0) } ?? false
                }
                return PlanSection(title: title, targetSeconds: part.end - part.start, hint: drafted?.hint ?? "",
                                   suggestions: Array(suggestions.prefix(maximumPacedSuggestions)), pace: part.energy)
            }
            guard !sections.isEmpty else { throw .emptyPlan }
            return EditPlan(brief: brief, style: style, trackId: trackId, sections: sections,
                            music: PlanMusic(assetId: music.assetId, beatSeconds: music.map.beatSeconds, drop: music.map.drop))
        }
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

    @MainActor private static func defaultTitle(for energy: MusicEnergy) -> String {
        switch energy {
        case .calm: L10n.string("Slow Start")
        case .rising: L10n.string("Build")
        case .peak: L10n.string("Peak")
        case .fading: L10n.string("Wind Down")
        }
    }

    private static let instructions = """
    You plan the structure of a video edit for a user who will place the clips themselves. The input is JSON: the \
    user's brief, an optional style, every clip with its duration, speech, labels, summary and moments, and the moments \
    already on the timeline. Return 3–7 ordered sections. Each has a short title, a target length in seconds, a hint \
    of at most 60 characters telling the user what to drop there, and up to 6 suggested moments. Suggest only moments \
    from the clips, using their assetId and times within the clip; you may tighten a moment's range. Section lengths \
    must fit the moments available for them and add up to the length the brief asks for (about 3 minutes when it \
    doesn't say). Prefer moments that are not already placed.

    When "music" is given, the video is cut to that song and its parts decide the timing: return exactly one section \
    per music part, in the same order (your targetSeconds is ignored). Name each section after what happens in it. \
    Match the footage to the part's energy: calm parts get wide, slow, scenic moments; rising parts get moments with \
    movement; peak parts get the most energetic moments, up to 8 short ones; fading parts get a gentle closing shot. \
    The section that starts at "drop" must open with the single strongest moment in the footage.
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
