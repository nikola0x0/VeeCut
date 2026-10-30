import AVFoundation
import Foundation
import Testing
@testable import PalmierPro

@Test func shortAudioIsOnePiece() {
    let frames = 20 * MetaVoiceTranscription.sampleRate / MetaVoiceTranscription.frameSamples
    let ranges = MetaVoiceTranscription.pieceRanges(sampleCount: frames * MetaVoiceTranscription.frameSamples, levels: Array(repeating: 1, count: frames))
    #expect(ranges == [0..<(frames * MetaVoiceTranscription.frameSamples)])
}

@Test func longAudioSplitsAtTheQuietestNearbyFrame() throws {
    let frameRate = MetaVoiceTranscription.sampleRate / MetaVoiceTranscription.frameSamples
    let frames = Int(MetaVoiceTranscription.pieceSeconds * 2.2) * frameRate
    var levels = Array(repeating: 500.0, count: frames)
    let quiet = (Int(MetaVoiceTranscription.pieceSeconds) + 1) * frameRate
    levels[quiet] = 0
    let ranges = MetaVoiceTranscription.pieceRanges(sampleCount: frames * MetaVoiceTranscription.frameSamples, levels: levels)
    let first = try #require(ranges.first)
    #expect(first == 0..<(quiet * MetaVoiceTranscription.frameSamples))
    #expect(ranges.last?.upperBound == frames * MetaVoiceTranscription.frameSamples)
    #expect(zip(ranges, ranges.dropFirst()).allSatisfy { $0.upperBound == $1.lowerBound })
}

@Test func emptyAudioHasNoPieces() {
    #expect(MetaVoiceTranscription.pieceRanges(sampleCount: 0, levels: []).isEmpty)
}

@Test func wordsAreTimedByWhenTheyWereHeardSoPausesStayPauses() throws {
    let partials = [
        MetaVoiceTranscription.PartialHeard(wordCount: 1, ms: 600),
        MetaVoiceTranscription.PartialHeard(wordCount: 2, ms: 900),
        MetaVoiceTranscription.PartialHeard(wordCount: 3, ms: 4_000),
    ]
    let words = MetaVoiceTranscription.timedWords("Xin chào, Mochi.", partials: partials, startMs: 0, endMs: 4_300, offset: 10)
    #expect(words.map(\.text) == ["Xin", "chào,", "Mochi."])
    #expect(words.map(\.end) == [10.6, 10.9, 14.0])
    #expect(try #require(words[2].start) > 13)
}

@Test func mismatchedPartialsFallBackToSpreadingByLength() {
    let words = MetaVoiceTranscription.timedWords("Xin chào bạn", partials: [.init(wordCount: 2, ms: 500)], startMs: 2_000, endMs: 5_000, offset: 0)
    #expect(words.first?.start == 2 && abs((words.last?.end ?? 0) - 5) < 1e-9)
}

@Test func wordTimesSpreadAcrossThePhraseByLength() {
    let words = MetaVoiceTranscription.words(in: "Xin chào bạn", from: 2, to: 5)
    #expect(words.map(\.text) == ["Xin", "chào", "bạn"])
    #expect(words.first?.start == 2)
    #expect(abs((words.last?.end ?? 0) - 5) < 1e-9)
    #expect(abs((words[1].end ?? 0) - (words[1].start ?? 0) - 1.2) < 1e-9)
}

@Test(arguments: [("vi", "Vietnamese"), ("vi-VN", "Vietnamese"), ("zh-Hans", "Mandarin Chinese"), ("en-US", "English")])
func museVoiceLanguagesUseTheirEnglishNames(identifier: String, name: String) {
    #expect(MetaVoiceTranscription.languageName(for: Locale(identifier: identifier)) == name)
}

@Test func languagesMuseVoiceDoesNotKnowAreRejected() async {
    #expect(MetaVoiceTranscription.languageName(for: Locale(identifier: "sw")) == nil)
    await #expect(throws: TranscriptionError.self) {
        try await Transcription.transcribe(fileURL: URL(fileURLWithPath: "/dev/null"), preferredLocale: Locale(identifier: "sw"))
    }
}

@Test func vietnameseIsOfferedForCaptions() async {
    let languages = await Transcription.supportedLocales().compactMap { $0.language.languageCode?.identifier }
    #expect(languages.contains("vi"))
}

/// Opt in with VEECUT_LIVE_MUSE=1 and MODEL_API_KEY. Speaks Vietnamese with the system voice and transcribes it.
@Suite("Live — Muse Voice", .enabled(if: ProcessInfo.processInfo.environment["VEECUT_LIVE_MUSE"] == "1"))
struct LiveMetaVoiceTranscriptionTests {
    @Test func transcribesVietnameseKeepingPausesBetweenWords() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let audio = directory.appendingPathComponent("vi.aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Linh", "-o", audio.path, "Xin chào các bạn. [[slnc 2500]] Hôm nay mình đi Đà Lạt."]
        try say.run()
        say.waitUntilExit()

        let result = try await Transcription.transcribe(fileURL: audio, preferredLocale: Locale(identifier: "vi"))
        #expect(result.text.localizedCaseInsensitiveContains("Đà Lạt"))
        let hom = try #require(result.words.firstIndex { $0.text.localizedCaseInsensitiveContains("Hôm") })
        #expect(try #require(result.words[hom].start) - (result.words[hom - 1].end ?? 0) > 1, "the pause stays between the phrases")
        #expect(result.segments.allSatisfy { $0.end > $0.start })
        #expect(result.language == "vi")
    }
}

@Test func theAgentCanAskForVietnameseCaptions() async throws {
    let locale = try #require(try await ToolExecutor.parseLocale(["language": "vi"], path: "add_captions"))
    #expect(locale.language.languageCode?.identifier == "vi")
}

@Test func eventStreamPhrasesKeepThePauseBetweenThem() throws {
    var accumulator = MetaVoiceTranscription.PhraseAccumulator(offset: 30)
    let events: [[String: Any]] = [
        ["type": "speechStart", "audioProcessedMs": 0],
        ["type": "transcript", "audioProcessedMs": 700, "transcript": "Xin"],
        ["type": "transcript", "audioProcessedMs": 1_100, "transcript": "Xin chào"],
        ["type": "speechComplete", "audioProcessedMs": 1_300, "transcript": "Xin chào"],
        ["type": "audioProgress", "audioProcessedMs": 2_000],
        ["type": "speechStart", "audioProcessedMs": 3_500],
        ["type": "transcript", "audioProcessedMs": 4_200, "transcript": "<|speaker_A|> Đà Lạt"],
        ["type": "speechComplete", "audioProcessedMs": 4_400, "transcript": "<|speaker_A|>  Đà Lạt"],
    ]
    for event in events { try accumulator.consume(event) }

    #expect(accumulator.phrases.map(\.segment.text) == ["Xin chào", "Đà Lạt"])
    let second = try #require(accumulator.phrases.last?.segment)
    #expect(second.start >= 33.5 && second.end <= 34.4 + 1e-9)
}

@Test func errorEventFailsThePiece() {
    var accumulator = MetaVoiceTranscription.PhraseAccumulator(offset: 0)
    #expect(throws: TranscriptionError.self) {
        try accumulator.consume(["type": "error", "message": "budget exceeded"])
    }
}

@Test func wavHeaderDescribes24kHzMono16Bit() {
    let wav = MetaVoiceTranscription.wav([0, 1, -1, 2])
    #expect(wav.count == 44 + 8)
    #expect(String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF")
    #expect(wav[22] == 1 && wav[34] == 16)
    #expect(wav.subdata(in: 24..<28).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } == 24_000)
}
