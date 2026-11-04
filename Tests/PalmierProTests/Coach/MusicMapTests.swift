import Testing
@testable import PalmierPro

struct MusicMapTests {
    /// 120 bpm, 4/4: a beat every 0.5 s, a bar every 2 s.
    private func analysis(bars: Int, bpm: Double = 120) -> BeatAnalysis {
        let beats = (0..<(bars * 4)).map { Double($0) * 0.5 }
        return BeatAnalysis(bpm: bpm, beats: beats, downbeats: stride(from: 0, to: beats.count, by: 4).map { beats[$0] })
    }

    /// Four quiet bars, four building bars, eight loud bars.
    private var buildThenDrop: MusicMap? {
        let bars: [Double] = [0.1, 0.1, 0.1, 0.1, 0.3, 0.4, 0.5, 0.6] + Array(repeating: 1, count: 8)
        return MusicMap.make(analysis: analysis(bars: 16), beatLoudness: bars.flatMap { Array(repeating: $0, count: 4) }, duration: 32)
    }

    @Test func aBuildThenDropMakesCalmRisingPeakParts() throws {
        let map = try #require(buildThenDrop)
        #expect(map.parts.map(\.energy) == [.calm, .rising, .peak])
        #expect(map.parts.map(\.bars) == [4, 4, 8])
        #expect(map.beatSeconds == 0.5)
        #expect(map.barSeconds == 2)
    }

    @Test func theDropIsWhereThePeakStarts() throws {
        #expect(try #require(buildThenDrop).drop == 16)
    }

    @Test func partsStartOnDownbeats() throws {
        let map = try #require(buildThenDrop)
        #expect(map.parts.map(\.start) == [0, 8, 16])
        #expect(map.parts.map(\.end) == [8, 16, 32])
    }

    @Test func strayDownbeatsDontShortenTheBar() throws {
        let clean = analysis(bars: 16)
        let noisy = BeatAnalysis(bpm: clean.bpm, beats: clean.beats, downbeats: (clean.downbeats + [8.1, 16.1, 25.1]).sorted())
        let map = try #require(MusicMap.make(analysis: noisy, beatLoudness: Array(repeating: 0.5, count: clean.beats.count), duration: 32))
        #expect(map.barSeconds == 2)
    }

    @Test func aSongWithoutABeatHasNoMap() {
        #expect(MusicMap.make(analysis: BeatAnalysis(bpm: 0, beats: [], downbeats: []), beatLoudness: [], duration: 30) == nil)
    }

    @Test func aShortSongIsOnePartWithoutADrop() throws {
        let map = try #require(MusicMap.make(analysis: analysis(bars: 3), beatLoudness: Array(repeating: 0.5, count: 12), duration: 6))
        #expect(map.parts.count == 1)
        #expect(map.drop == nil)
    }

    @Test(arguments: [(20.0, 24.0, 3), (10.0, 8.0, 1), (3.0, 8.0, 1), (100.0, 32.0, 3)])
    /// A length past the drop never ends on it: the drop stays in the cut.
    func aSongIsCutAtThePartEndNearestTheLength(seconds: Double, end: Double, parts: Int) {
        let song = MusicMap(duration: 32, beatSeconds: 0.5, barSeconds: 2, parts: [
            .init(start: 0, end: 8, energy: .calm, bars: 4),
            .init(start: 8, end: 16, energy: .rising, bars: 4),
            .init(start: 16, end: 32, energy: .peak, bars: 8),
        ], drop: 16)

        let cut = song.cut(nearest: seconds)

        #expect(cut.duration == end)
        #expect(cut.parts.count == parts)
        #expect(cut.parts.last?.end == end)
        #expect(cut.drop == (end > 16 ? 16 : nil))
    }

    @Test func aLongPartAfterTheDropIsCutAtThePhraseNearestTheLength() {
        let song = MusicMap(duration: 80, beatSeconds: 0.5, barSeconds: 2, parts: [
            .init(start: 0, end: 8, energy: .calm, bars: 4),
            .init(start: 8, end: 16, energy: .rising, bars: 4),
            .init(start: 16, end: 80, energy: .peak, bars: 32),
        ], drop: 16)

        let cut = song.cut(nearest: 30)

        #expect(cut.duration == 32)
        #expect(cut.parts.last == .init(start: 16, end: 32, energy: .peak, bars: 8))
        #expect(cut.drop == 16)
    }

    @Test func loudnessIsMeasuredBetweenBeats() {
        let quiet = [Float](repeating: 0, count: 100)
        let loud = [Float](repeating: 1, count: 100)
        let loudness = MusicMap.beatLoudness(samples: quiet + loud, sampleRate: 100, beats: [0, 1])
        #expect(loudness == [0, 1])
    }
}
