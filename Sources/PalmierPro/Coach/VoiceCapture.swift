import AVFoundation

/// Records the microphone to a unique temporary file between `start` and `stop`; the caller deletes the file.
actor VoiceCapture {
    enum Failure: Error { case microphoneDenied, notRecording }

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
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { buffer, _ in writer.write(buffer) }
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
