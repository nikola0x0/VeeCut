import Foundation

enum MetaModelError: Error, Equatable {
    case missingAPIKey
    case http(status: Int, body: String)
    case invalidResponse
    case segmentation(SAMOutputError)
    case streamFailed(String)
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
            throw .streamFailed(String(decoding: data, as: UTF8.self))
        default:
            return []
        }
    }
}
