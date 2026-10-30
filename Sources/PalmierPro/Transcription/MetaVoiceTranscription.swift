import AVFoundation
import Foundation

/// Transcription through Meta Muse Voice for languages on-device recognition doesn't cover.
/// Long audio is split at quiet moments; each piece is uploaded as WAV and its timed events read back as a stream.
enum MetaVoiceTranscription {
    static let model = "muse-voice-transcribe-1.0"
    static let endpoint = MetaModelClient.baseURL.appending(path: "asr/transcribe")
    static let sampleRate = 24_000
    /// 80 ms of 24 kHz mono 16-bit PCM; the unit piece boundaries and levels are measured in.
    static let frameSamples = 1_920
    /// Well under the endpoint's 10-minute and 32 MB limits, and short enough to run pieces in parallel.
    static let pieceSeconds = 60.0
    /// How far a piece boundary may move to land on the quietest frame.
    static let boundarySearchSeconds = 3.0
    static let maxParallelSessions = 4
    static let pieceAttempts = 3
    /// Caps open sessions across every clip being transcribed, not per clip.
    private static let sessionGate = AsyncSemaphore(value: maxParallelSessions)

    /// Muse Voice's languages, by ISO 639 code, with the English names its handshake expects.
    static let languageNames: [String: String] = [
        "ar": "Arabic", "bn": "Bengali", "de": "German", "en": "English", "es": "Spanish", "fr": "French",
        "he": "Hebrew", "hi": "Hindi", "id": "Indonesian", "it": "Italian", "ja": "Japanese", "kn": "Kannada",
        "ko": "Korean", "mr": "Marathi", "ms": "Malay", "nl": "Dutch", "pl": "Polish", "pt": "Portuguese",
        "ta": "Tamil", "te": "Telugu", "th": "Thai", "tl": "Tagalog", "tr": "Turkish", "vi": "Vietnamese",
        "zh": "Mandarin Chinese",
    ]

    static var locales: [Locale] { languageNames.keys.sorted().map { Locale(identifier: $0) } }

    static func languageName(for locale: Locale) -> String? {
        locale.language.languageCode.flatMap { languageNames[$0.identifier] }
    }

    @concurrent
    static func transcribe(fileURL: URL, locale: Locale) async throws -> TranscriptionResult {
        guard let language = languageName(for: locale) else {
            throw TranscriptionError.unsupportedLocale(locale.identifier(.bcp47))
        }
        let apiKey = try await MetaModelClient.configured().apiKey
        let samples = try readSamples(fileURL)
        let pieces = pieceRanges(sampleCount: samples.count, levels: frameLevels(samples))
        Log.transcription.notice("meta voice transcribe language=\(language) pieces=\(pieces.count)")

        var phrases: [Phrase] = []
        try await withThrowingTaskGroup(of: [Phrase].self) { group in
            var next = pieces.makeIterator()
            func startNext() {
                guard let range = next.next() else { return }
                let piece = Array(samples[range])
                let offset = Double(range.lowerBound) / Double(sampleRate)
                group.addTask { try await transcribeGated(piece, offset: offset, language: language, apiKey: apiKey) }
            }
            for _ in 0..<maxParallelSessions { startNext() }
            while let piecePhrases = try await group.next() {
                phrases += piecePhrases
                startNext()
            }
        }
        phrases.sort { $0.segment.start < $1.segment.start }
        return TranscriptionResult(
            text: phrases.map(\.segment.text).joined(separator: " "),
            language: locale.language.languageCode?.identifier,
            words: phrases.flatMap(\.words),
            segments: phrases.map(\.segment)
        )
    }

    struct Phrase: Sendable {
        let segment: TranscriptionSegment
        let words: [TranscriptionWord]
    }

    /// When each word of a partial transcript had been heard, in milliseconds of audio.
    struct PartialHeard: Equatable {
        let wordCount: Int
        let ms: Double
    }

    /// Times the final phrase's words by when they first showed up in partial transcripts, so pauses stay pauses.
    /// Falls back to spreading by length when the final text has a different word count than the partials.
    static func timedWords(_ text: String, partials: [PartialHeard], startMs: Double, endMs: Double, offset: Double) -> [TranscriptionWord] {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty, endMs > startMs else { return [] }
        guard let last = partials.last, last.wordCount == tokens.count else {
            return words(in: text, from: offset + startMs / 1000, to: offset + endMs / 1000)
        }
        var previousEnd = startMs
        return tokens.enumerated().map { index, token in
            let heard = partials.first { $0.wordCount > index }?.ms ?? endMs
            let end = min(max(heard, previousEnd), endMs)
            let start = max(previousEnd, end - spokenMs(token))
            previousEnd = end
            return TranscriptionWord(text: token, start: offset + start / 1000, end: offset + end / 1000)
        }
    }

    /// A rough spoken length for a word, so a word heard after a pause doesn't stretch back across it.
    private static func spokenMs(_ token: String) -> Double {
        min(max(Double(token.count) * 70, 150), 900)
    }

    /// Piece ranges of about `pieceSeconds`, each boundary moved to the quietest 80 ms frame nearby.
    static func pieceRanges(sampleCount: Int, levels: [Double]) -> [Range<Int>] {
        guard sampleCount > 0 else { return [] }
        let pieceFrames = Int(pieceSeconds * Double(sampleRate)) / frameSamples
        let searchFrames = Int(boundarySearchSeconds * Double(sampleRate)) / frameSamples
        var boundaries: [Int] = []
        var target = pieceFrames
        while target + searchFrames < levels.count {
            let window = (target - searchFrames)...(target + searchFrames)
            let quietest = window.min { levels[$0] < levels[$1] } ?? target
            boundaries.append(quietest * frameSamples)
            target = quietest + pieceFrames
        }
        let starts = [0] + boundaries
        let ends = boundaries + [sampleCount]
        return zip(starts, ends).map { $0..<$1 }
    }

    /// Mean absolute level of each 80 ms frame.
    static func frameLevels(_ samples: [Int16]) -> [Double] {
        stride(from: 0, to: samples.count, by: frameSamples).map { start in
            let frame = samples[start..<min(start + frameSamples, samples.count)]
            return frame.reduce(0.0) { $0 + abs(Double($1)) } / Double(frame.count)
        }
    }

    /// Word timings spread across a phrase in proportion to each word's length; Muse Voice times phrases, not words.
    static func words(in text: String, from start: Double, to end: Double) -> [TranscriptionWord] {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let total = tokens.reduce(0) { $0 + $1.count }
        guard total > 0, end > start else { return [] }
        var cursor = start
        return tokens.map { token in
            let length = (end - start) * Double(token.count) / Double(total)
            defer { cursor += length }
            return TranscriptionWord(text: token, start: cursor, end: cursor + length)
        }
    }

    /// Decodes any audio file to 24 kHz mono 16-bit samples.
    private static func readSamples(_ url: URL) throws -> [Int16] {
        let file = try AVAudioFile(forReading: url)
        guard let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(sampleRate), channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: file.processingFormat, to: output) else {
            throw TranscriptionError.decodeFailed
        }
        let inputCapacity: AVAudioFrameCount = 32_768
        let outputCapacity = AVAudioFrameCount(Double(inputCapacity) * Double(sampleRate) / file.processingFormat.sampleRate) + 1_024
        var samples: [Int16] = []
        samples.reserveCapacity(Int(Double(file.length) * Double(sampleRate) / file.processingFormat.sampleRate))
        var reachedEnd = false
        while true {
            try Task.checkCancellation()
            guard let buffer = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: outputCapacity) else { throw TranscriptionError.decodeFailed }
            var readError: Error?
            let status = converter.convert(to: buffer, error: nil) { _, inputStatus in
                guard !reachedEnd, file.framePosition < file.length,
                      let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: inputCapacity) else {
                    reachedEnd = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try file.read(into: input)
                } catch {
                    readError = error
                }
                guard input.frameLength > 0 else {
                    reachedEnd = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return input
            }
            if let readError { throw TranscriptionError.audioExtractionFailed(readError.localizedDescription) }
            if let channel = buffer.int16ChannelData, buffer.frameLength > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
            }
            if status == .endOfStream || status == .error || buffer.frameLength == 0 { break }
        }
        return samples
    }

    /// Transcribes a piece once a session is free, retrying a refused or failed one.
    private static func transcribeGated(_ samples: [Int16], offset: Double, language: String, apiKey: String) async throws -> [Phrase] {
        var attempt = 1
        while true {
            try await sessionGate.wait()
            do {
                let phrases = try await transcribePiece(samples, offset: offset, language: language, apiKey: apiKey)
                await sessionGate.signal()
                return phrases
            } catch {
                await sessionGate.signal()
                try Task.checkCancellation()
                guard attempt < pieceAttempts else { throw error }
                Log.transcription.warning("meta voice piece retry offset=\(offset) attempt=\(attempt) error=\(error.localizedDescription)")
                try await Task.sleep(for: .seconds(attempt))
                attempt += 1
            }
        }
    }

    /// Uploads one piece and reads its events as they arrive; phrases come back in source time.
    private static func transcribePiece(_ samples: [Int16], offset: Double, language: String, apiKey: String) async throws -> [Phrase] {
        let boundary = "veecut-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let settings = try JSONSerialization.data(withJSONObject: [
            "model": model, "audioEncoding": "WAV", "mode": "ENDPOINTING", "language": language,
        ])
        request.httpBody = multipartBody(settings: settings, wav: wav(samples), boundary: boundary)

        let bytes = try await AgentHTTP.bytes(for: request) { status, body in
            TranscriptionError.analysisFailed("Muse Voice error \(status): \(body.prefix(300))")
        }
        var accumulator = PhraseAccumulator(offset: offset)
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:"),
                  let event = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(5).utf8)) as? [String: Any] else { continue }
            try accumulator.consume(event)
        }
        return accumulator.phrases
    }

    /// Builds phrases from Muse Voice events: partial transcripts time the words, `speechComplete` closes a phrase.
    struct PhraseAccumulator {
        let offset: Double
        private(set) var phrases: [Phrase] = []
        private var speechStartMs: Double?
        private var partials: [PartialHeard] = []
        private var lastEndMs = 0.0

        init(offset: Double) {
            self.offset = offset
        }

        mutating func consume(_ event: [String: Any]) throws {
            guard let type = event["type"] as? String else { return }
            let ms = (event["audioProcessedMs"] as? NSNumber)?.doubleValue
            switch type {
            case "speechStart":
                speechStartMs = ms
            case "transcript":
                let count = MetaVoiceTranscription.spokenText(event["transcript"] as? String ?? "").split(whereSeparator: \.isWhitespace).count
                if let ms, count > (partials.last?.wordCount ?? 0) { partials.append(PartialHeard(wordCount: count, ms: ms)) }
            case "speechComplete":
                let transcript = MetaVoiceTranscription.spokenText(event["transcript"] as? String ?? "")
                let endMs = ms ?? lastEndMs
                let startMs = speechStartMs ?? max(lastEndMs, min(partials.first?.ms ?? endMs, endMs))
                let words = timedWords(transcript, partials: partials, startMs: startMs, endMs: endMs, offset: offset)
                if let first = words.first?.start, let last = words.last?.end {
                    phrases.append(Phrase(segment: TranscriptionSegment(text: transcript, start: first, end: last), words: words))
                }
                lastEndMs = endMs
                speechStartMs = nil
                partials = []
            case "error":
                throw TranscriptionError.analysisFailed(event["message"] as? String ?? "Muse Voice error")
            default:
                return
            }
        }
    }

    /// The transcript without Muse Voice's control tokens, such as `<|speaker_A|>`.
    static func spokenText(_ transcript: String) -> String {
        transcript.replacing(/<\|[^|]*\|>/, with: "")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// 16-bit mono PCM at `sampleRate` in a WAV container; arm64 samples are already little-endian.
    static func wav(_ samples: [Int16]) -> Data {
        let dataBytes = samples.count * 2
        var data = Data(capacity: 44 + dataBytes)
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + dataBytes))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(dataBytes))
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }

    private static func multipartBody(settings: Data, wav: Data, boundary: String) -> Data {
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"request\"\r\nContent-Type: application/json\r\n\r\n".utf8))
        body.append(settings)
        body.append(Data("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"piece.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}
