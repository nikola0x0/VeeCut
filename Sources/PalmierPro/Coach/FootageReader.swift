import Foundation

/// Muse Spark reads small timestamped contact sheets, several clips per request, into summaries and moments.
enum FootageReader {
    static let batchSize = 8
    static let tilesPerSheet = 12
    static let parallelRequests = 3

    private struct Reply: Decodable {
        struct Clip: Decodable {
            struct Moment: Decodable { let start: Double; let end: Double; let note: String }
            let assetId: String
            let summary: String
            let moments: [Moment]
        }
        let clips: [Clip]
    }

    /// Returns the notes it read, also handing each batch over as it lands; a read note has a summary (empty when skipped).
    @concurrent
    static func read(
        _ notes: [FootageNote],
        urls: [String: URL],
        client: any CoachModel,
        onBatch: @Sendable ([FootageNote]) async -> Void = { _ in }
    ) async throws -> [FootageNote] {
        let schema = try JSONSerialization.data(withJSONObject: schemaObject)
        let batches = stride(from: 0, to: notes.count, by: batchSize).map { Array(notes[$0..<min($0 + batchSize, notes.count)]) }
        var read: [FootageNote] = []
        try await withThrowingTaskGroup(of: [FootageNote].self) { group in
            var next = batches.makeIterator()
            func startNext() {
                guard let batch = next.next() else { return }
                group.addTask { try await readBatch(batch, urls: urls, client: client, schema: schema) }
            }
            for _ in 0..<parallelRequests { startNext() }
            while let batchRead = try await group.next() {
                read += batchRead
                if !batchRead.isEmpty { await onBatch(batchRead) }
                startNext()
            }
        }
        return read
    }

    private static func readBatch(_ notes: [FootageNote], urls: [String: URL], client: any CoachModel, schema: Data) async throws -> [FootageNote] {
        try Task.checkCancellation()
        var batch: [FootageNote] = []
        var parts: [MetaInputPart] = [.text("Contact sheets for the clips below. Each tile is labeled with its source time in seconds.")]
        for note in notes {
            guard let url = urls[note.assetId],
                  let sheet = try? await OverviewRenderer.make(url: url, start: 0, end: note.durationSeconds, maxTiles: tilesPerSheet,
                                                               candidates: Double(tilesPerSheet * 3)) else { continue }
            let said = note.transcript.map { "\nsaid: \($0)" } ?? ""
            parts.append(.text("assetId=\(note.assetId) duration=\(String(format: "%.1f", note.durationSeconds))\(said)"))
            parts.append(.jpeg(sheet.jpeg))
            batch.append(note)
        }
        guard !batch.isEmpty else { return [] }
        try Task.checkCancellation()
        let text = try await client.structuredResponse(model: DescribedLook.model, instructions: instructions, parts: parts, schemaName: "footage", schemaJSON: schema)
        let clips = Dictionary(try JSONDecoder().decode(Reply.self, from: Data(text.utf8)).clips.map { ($0.assetId, $0) }) { first, _ in first }
        return batch.map { note in
            var note = note
            let clip = clips[note.assetId]
            note.summary = clip?.summary ?? ""
            let moments = (clip?.moments ?? [])
                .map { PlanMoment(assetId: note.assetId, start: $0.start, end: $0.end, note: $0.note) }
                .filter { $0.isUsable(withinDuration: note.durationSeconds) }
                .prefix(FootageScanner.maximumMoments)
            if !moments.isEmpty { note.moments = Array(moments) }
            return note
        }
    }

    private static let instructions = """
    You are a video editor's assistant reading contact sheets of a user's travel footage. For every clip, write a \
    one-sentence summary (at most 100 characters) of what it shows, and list up to 6 of its best moments. A moment is \
    1–8 seconds long; take start and end from the tile timestamps and keep them inside the clip's duration. Give each \
    moment a short note (at most 40 characters) naming what happens. When a clip has a "said:" transcript with \
    [seconds] marks, mention what is said in the summary and prefer spoken lines worth keeping as moments. Use the \
    assetId given before each sheet.
    """

    private static var schemaObject: [String: Any] {
        [
        "type": "object", "additionalProperties": false, "required": ["clips"],
        "properties": ["clips": ["type": "array", "items": [
            "type": "object", "additionalProperties": false, "required": ["assetId", "summary", "moments"],
            "properties": [
                "assetId": ["type": "string"],
                "summary": ["type": "string"],
                "moments": ["type": "array", "items": [
                    "type": "object", "additionalProperties": false, "required": ["start", "end", "note"],
                    "properties": ["start": ["type": "number"], "end": ["type": "number"], "note": ["type": "string"]],
                ]],
            ],
        ]]],
        ]
    }
}
