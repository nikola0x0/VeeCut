import AVFoundation

/// Records the microphone to a unique temporary file between `start` and `stop`; the caller deletes the file.
actor VoiceCapture {
    enum Failure: Error { case microphoneDenied, notRecording }

    /// The live microphone level, readable from the UI without hopping onto the actor.
    nonisolated let level = VoiceLevel()

    private var engine: AVAudioEngine?
    private var writer: TapWriter?

    func start() async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw Failure.microphoneDenied }
        stopEngine()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("veecut-voice-\(UUID().uuidString).caf")
        let writer = TapWriter(file: try AVAudioFile(forWriting: url, settings: format.settings), url: url)
        let level = level
        level.reset()
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { buffer, _ in
            writer.write(buffer)
            if let samples = buffer.floatChannelData?[0] {
                level.record(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
            }
        }
        try engine.start()
        self.engine = engine
        self.writer = writer
    }

    func stop() throws -> URL {
        guard let writer else { throw Failure.notRecording }
        stopEngine()
        return writer.finish()
    }

    private func stopEngine() {
        level.reset()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        writer = nil
    }
}

/// The audio tap writes from the render thread; the lock orders those writes against `finish`.
private final class TapWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    let url: URL

    init(file: AVAudioFile, url: URL) {
        self.file = file
        self.url = url
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { try? file?.write(from: buffer) }
    }

    func finish() -> URL {
        lock.withLock { file = nil }
        return url
    }
}

/// Loudness of the latest buffer from 0 (−50 dB or quieter) to 1 (full scale); the lock orders tap writes against UI reads.
final class VoiceLevel: @unchecked Sendable {
    private static let floorDecibels: Float = -50
    private let lock = NSLock()
    private var latest = 0.0

    var value: Double { lock.withLock { latest } }

    func record(_ samples: some Collection<Float>) {
        let level = Self.level(of: samples)
        lock.withLock { latest = level }
    }

    func reset() {
        lock.withLock { latest = 0 }
    }

    static func level(of samples: some Collection<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        let meanSquare = samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)
        guard meanSquare > 0 else { return 0 }
        let decibels = 10 * log10(meanSquare)
        return Double(min(max((decibels - floorDecibels) / -floorDecibels, 0), 1))
    }
}
