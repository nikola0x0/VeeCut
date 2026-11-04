import Testing
@testable import PalmierPro

struct VoiceLevelTests {
    @Test(arguments: [
        ([Float](repeating: 0, count: 64), 0.0),
        ([Float](repeating: 1, count: 64), 1.0),
        ([Float](repeating: 0.0032, count: 64), 0.0),
        ([Float](repeating: 0.056, count: 64), 0.5),
    ] as [([Float], Double)])
    func theLevelMapsLoudnessFromSilenceToFullScale(samples: [Float], expected: Double) {
        #expect(abs(VoiceLevel.level(of: samples) - expected) < 0.02)
    }

    @Test func noSamplesIsSilence() {
        #expect(VoiceLevel.level(of: []) == 0)
    }

    @Test func theMeterHoldsTheLatestLevelUntilReset() {
        let meter = VoiceLevel()
        meter.record([Float](repeating: 1, count: 64))
        #expect(meter.value == 1)
        meter.reset()
        #expect(meter.value == 0)
    }
}
