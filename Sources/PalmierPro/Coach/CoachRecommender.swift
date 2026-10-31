import Foundation

struct PlanIdea: Codable, Sendable, Equatable, Hashable {
    var title: String
    var style: PlanStyle
    var targetSeconds: Double
    var pitch: String

    var brief: String { "\(title): \(pitch) (about \(Int(targetSeconds.rounded())) seconds)" }
}

/// Muse Spark's read of the footage as a whole and what it would make from it; `assetIds` are the clips it saw.
struct FootageRecommendation: Codable, Sendable, Equatable {
    var summary: String
    var ideas: [PlanIdea]
    var assetIds: [String]
}

enum CoachRecommender {
    static let maximumIdeas = 3

    private struct Reply: Decodable {
        struct Idea: Decodable { let title: String; let style: String; let targetSeconds: Double; let pitch: String }
        let summary: String
        let ideas: [Idea]
    }

    @concurrent
    static func recommend(_ notes: [FootageNote], client: any CoachModel) async throws -> FootageRecommendation {
        struct Clip: Encodable { let assetId: String; let duration: Double; let speech: Bool; let labels: [String]; let summary: String?; let said: String? }
        let clips = notes.map { Clip(assetId: $0.assetId, duration: $0.durationSeconds, speech: $0.hasSpeech, labels: $0.labels, summary: $0.summary, said: $0.transcript) }
        let prompt = String(decoding: try JSONEncoder().encode(clips), as: UTF8.self)
        let schema = try JSONSerialization.data(withJSONObject: schemaObject)
        let text = try await client.structuredResponse(model: DescribedLook.model, instructions: instructions, parts: [.text(prompt)], schemaName: "ideas", schemaJSON: schema)
        return validated(try JSONDecoder().decode(Reply.self, from: Data(text.utf8)), assetIds: notes.map(\.assetId).sorted())
    }

    /// Keeps ideas with a known style, a 5–600 s length and a title; at most three.
    private static func validated(_ reply: Reply, assetIds: [String]) -> FootageRecommendation {
        let ideas = reply.ideas.compactMap { idea -> PlanIdea? in
            guard let style = PlanStyle(rawValue: idea.style), idea.targetSeconds.isFinite, (5...600).contains(idea.targetSeconds),
                  let title = try? EditPlan.normalizedTitle(idea.title) else { return nil }
            return PlanIdea(title: title, style: style, targetSeconds: idea.targetSeconds, pitch: idea.pitch)
        }
        return FootageRecommendation(summary: reply.summary, ideas: Array(ideas.prefix(maximumIdeas)), assetIds: assetIds)
    }

    private static let instructions = """
    You are an editor looking at a user's raw footage before they say what they want. The input is JSON: every clip \
    with its duration, whether someone talks, scene labels and a one-line summary. Write one friendly sentence (at most \
    140 characters) saying what the footage is about as a whole, naming the place or occasion when it is clear. Then \
    propose 3 different videos to make from it, each with a short title (at most 40 characters), a style \
    (travelVlog, reel, cinematicRecap or talkingHead), a target length in seconds that the footage can fill, and a \
    one-line pitch (at most 120 characters). Make the ideas genuinely different in format and length.
    """

    private static var schemaObject: [String: Any] {
        [
            "type": "object", "additionalProperties": false, "required": ["summary", "ideas"],
            "properties": [
                "summary": ["type": "string"],
                "ideas": ["type": "array", "items": [
                    "type": "object", "additionalProperties": false, "required": ["title", "style", "targetSeconds", "pitch"],
                    "properties": [
                        "title": ["type": "string"],
                        "style": ["type": "string", "enum": PlanStyle.allCases.map(\.rawValue)],
                        "targetSeconds": ["type": "number"],
                        "pitch": ["type": "string"],
                    ],
                ]],
            ],
        ]
    }
}
