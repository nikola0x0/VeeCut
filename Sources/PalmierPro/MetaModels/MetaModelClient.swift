import Foundation

enum MetaModelError: Error, Equatable {
    case missingAPIKey
    case http(status: Int, body: String)
    case invalidResponse
    case segmentation(SAMOutputError)
    case streamFailed(String)
    /// Meta's server failed mid-response; the same request may succeed when retried.
    case serverFailed(String)
    /// Muse Image refused the prompt under Meta's content policy.
    case contentPolicy
}

enum MetaInputPart: Sendable {
    case text(String)
    case jpeg(Data)

    var content: [String: String] {
        switch self {
        case .text(let text): ["type": "input_text", "text": text]
        case .jpeg(let data): ["type": "input_image", "image_url": "data:image/jpeg;base64,\(data.base64EncodedString())"]
        }
    }
}

struct MetaModelClient: Sendable {
    static let baseURL = URL(string: "https://api.meta.ai/v1")!

    let apiKey: String

    static func configured() async throws(MetaModelError) -> MetaModelClient {
        let key = await AgentProvider.meta.loadAPIKey()
        guard !key.isEmpty else { throw .missingAPIKey }
        return MetaModelClient(apiKey: key)
    }

    private func request(_ path: String) -> URLRequest {
        var request = URLRequest(url: Self.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Uploads a local media file for reuse across segmentation requests and returns its file ID.
    func uploadFile(at fileURL: URL, mimeType: String) async throws -> String {
        let boundary = "veecut-\(UUID().uuidString)"
        var request = request("files")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let body = try await Self.multipartBody(fileURL: fileURL, mimeType: mimeType, boundary: boundary)
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: body)
        try? FileManager.default.removeItem(at: body)
        try Self.validate(response, data: data)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String else { throw MetaModelError.invalidResponse }
        return id
    }

    /// Streams SAM 3.1 frames for point/box prompts on an uploaded video.
    func segmentVideo(fileID: String, prompt: String) -> AsyncThrowingStream<SAMFrameRecord, Error> {
        segment(media: ["type": "input_video", "file_id": fileID], prompt: prompt)
    }

    /// Streams SAM 3.1 results for an image given as a URL or base64 data URL.
    func segmentImage(imageURL: String, prompt: String) -> AsyncThrowingStream<SAMFrameRecord, Error> {
        segment(media: ["type": "input_image", "image_url": imageURL], prompt: prompt)
    }

    private func segment(media: [String: String], prompt: String) -> AsyncThrowingStream<SAMFrameRecord, Error> {
        var request = request("responses")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "model": "sam-3.1",
            "stream": true,
            "metadata": ["mask_encoding": "one_bit", "include_confidence": "true"],
            "input": [[
                "type": "message",
                "role": "user",
                "content": [["type": "input_text", "text": prompt], media],
            ]],
        ]
        let preparedRequest = Result { () throws -> URLRequest in
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            return request
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let bytes = try await AgentHTTP.bytes(for: try preparedRequest.get()) { status, body in
                        MetaModelError.http(status: status, body: body)
                    }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        for frame in try SAMStreamEvents.frames(fromEventLine: line) { continuation.yield(frame) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// One non-streaming `/responses` call whose text output must match the JSON schema. Returns that text.
    @concurrent
    func structuredResponse(
        model: String,
        instructions: String,
        prompt: String,
        schemaName: String,
        schemaJSON: Data
    ) async throws -> String {
        try await structuredResponse(model: model, instructions: instructions, parts: [.text(prompt)], schemaName: schemaName, schemaJSON: schemaJSON)
    }

    /// The same call with interleaved text and JPEG parts in the user message.
    @concurrent
    func structuredResponse(
        model: String,
        instructions: String,
        parts: [MetaInputPart],
        schemaName: String,
        schemaJSON: Data
    ) async throws -> String {
        let schema = try JSONSerialization.jsonObject(with: schemaJSON)
        var request = request("responses")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "instructions": instructions,
            "input": [["type": "message", "role": "user", "content": parts.map(\.content)]],
            "text": ["format": ["type": "json_schema", "name": schemaName, "schema": schema]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response, data: data)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = object["output"] as? [[String: Any]] else { throw MetaModelError.invalidResponse }
        let text = output
            .filter { $0["type"] as? String == "message" }
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .compactMap { $0["type"] as? String == "output_text" ? $0["text"] as? String : nil }
            .joined()
        guard !text.isEmpty else { throw MetaModelError.invalidResponse }
        return text
    }

    /// The structured call streamed, handing over the model's thinking summary as it arrives.
    @concurrent
    func structuredResponse(
        model: String,
        instructions: String,
        parts: [MetaInputPart],
        schemaName: String,
        schemaJSON: Data,
        onThinking: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        let schema = try JSONSerialization.jsonObject(with: schemaJSON)
        var request = request("responses")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "reasoning": ["summary": "auto"],
            "instructions": instructions,
            "input": [["type": "message", "role": "user", "content": parts.map(\.content)]],
            "text": ["format": ["type": "json_schema", "name": schemaName, "schema": schema]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let bytes = try await AgentHTTP.bytes(for: request) { status, body in MetaModelError.http(status: status, body: body) }
        var text = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            switch MetaResponseStream.event(fromLine: line) {
            case .thinking(let delta): await onThinking(delta)
            case .text(let delta): text += delta
            case .failed(let message): throw MetaModelError.streamFailed(message)
            case nil: break
            }
        }
        guard !text.isEmpty else { throw MetaModelError.invalidResponse }
        return text
    }

    static let imageModel = "muse-image-1.0"
    static let imageAttempts = 3

    /// One Muse Image generation as PNG bytes. Retries the 503s Meta marks as retryable.
    @concurrent
    func generateImage(prompt: String, size: String) async throws -> Data {
        var request = request("images/generations")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": Self.imageModel, "prompt": prompt, "n": 1, "size": size,
            "output_format": "png", "reasoning_strength": "low",
        ] as [String: Any])
        var attempt = 1
        while true {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 503, attempt < Self.imageAttempts {
                try await Task.sleep(for: .seconds(attempt))
                attempt += 1
                continue
            }
            if status == 400, String(decoding: data, as: UTF8.self).contains("content_policy_violation") {
                throw MetaModelError.contentPolicy
            }
            try Self.validate(response, data: data)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let first = (object["data"] as? [[String: Any]])?.first,
                  let base64 = first["b64_json"] as? String,
                  let png = Data(base64Encoded: base64) else { throw MetaModelError.invalidResponse }
            return png
        }
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw MetaModelError.invalidResponse }
        guard http.statusCode < 400 else {
            throw MetaModelError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
    }

    @concurrent
    private static func multipartBody(fileURL: URL, mimeType: String, boundary: String) async throws -> URL {
        let bodyURL = FileManager.default.temporaryDirectory.appending(path: "\(boundary).multipart")
        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: bodyURL)
        defer { try? output.close() }
        let head = "--\(boundary)\r\nContent-Disposition: form-data; name=\"purpose\"\r\n\r\nuser_data\r\n"
            + "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n"
            + "Content-Type: \(mimeType)\r\n\r\n"
        try output.write(contentsOf: Data(head.utf8))
        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
        try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        return bodyURL
    }
}

/// Turns one server-sent event line into SAM frames; each delta carries whole output lines.
enum SAMStreamEvents {
    static func frames(fromEventLine eventLine: String) throws(MetaModelError) -> [SAMFrameRecord] {
        guard eventLine.hasPrefix("data:") else { return [] }
        let payload = eventLine.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = event["type"] as? String else { return [] }
        switch type {
        case "response.output_text.delta":
            guard let delta = event["delta"] as? String else { throw .invalidResponse }
            var frames: [SAMFrameRecord] = []
            for line in delta.split(whereSeparator: \.isNewline) {
                do {
                    if let frame = try SAMOutputParser.parseLine(String(line)) { frames.append(frame) }
                } catch {
                    throw .segmentation(error)
                }
            }
            return frames
        case "error", "response.failed":
            let body = String(decoding: data, as: UTF8.self)
            let code = event["code"] as? String
                ?? ((event["response"] as? [String: Any])?["error"] as? [String: Any])?["code"] as? String
            throw code == "server_error" ? .serverFailed(body) : .streamFailed(body)
        default:
            return []
        }
    }
}
