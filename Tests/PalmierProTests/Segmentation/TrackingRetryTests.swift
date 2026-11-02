import Testing
@testable import PalmierPro

private func record(_ frame: Int) -> SAMFrameRecord {
    let box = SAMBox(left: 0, top: 0, right: 1, bottom: 1, sourceWidth: 2, sourceHeight: 2)
    return SAMFrameRecord(frameIndex: frame, objects: [
        SAMObjectRecord(objectID: 1, box: box, mask: SAMMaskRaster(width: 1, height: 1, bits: [1]), confidence: nil),
    ])
}

private func stream(_ frames: [Int], failingWith error: Error? = nil) -> AsyncThrowingStream<SAMFrameRecord, Error> {
    AsyncThrowingStream { continuation in
        for frame in frames { continuation.yield(record(frame)) }
        continuation.finish(throwing: error)
    }
}

@Test func aServerFailureMidStreamRetriesFromScratch() async throws {
    var calls = 0
    let objects = try await ObjectTracker.segmentedObjects(retryDelay: .zero) {
        calls += 1
        return calls == 1 ? stream([0, 1], failingWith: MetaModelError.serverFailed("x")) : stream([0, 1, 2])
    }
    #expect(calls == 2)
    #expect(objects[1]?.keys.sorted() == [0, 1, 2])
}

@Test func otherStreamFailuresAreNotRetried() async {
    var calls = 0
    await #expect(throws: MetaModelError.streamFailed("quota")) {
        try await ObjectTracker.segmentedObjects(retryDelay: .zero) {
            calls += 1
            return stream([0], failingWith: MetaModelError.streamFailed("quota"))
        }
    }
    #expect(calls == 1)
}

@Test func serverFailuresStopAfterTheLastAttempt() async {
    var calls = 0
    await #expect(throws: MetaModelError.serverFailed("x")) {
        try await ObjectTracker.segmentedObjects(retryDelay: .zero) {
            calls += 1
            return stream([], failingWith: MetaModelError.serverFailed("x"))
        }
    }
    #expect(calls == ObjectTracker.segmentAttempts)
}
