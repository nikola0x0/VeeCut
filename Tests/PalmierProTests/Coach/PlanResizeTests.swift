import Testing
@testable import PalmierPro

struct PlanResizeTests {
    @Test(arguments: [
        (16.0, 90.0, 0.5, 20.0),
        (16.0, 90.0, nil, 19.0),
        (16.0, 75.0, 0.5, 18.0),
        (16.0, -900.0, 0.5, 2.0),
        (16.0, -900.0, nil, 1.0),
    ] as [(Double, Double, Double?, Double)])
    func draggingABandsEdgeSetsItsLengthOnTheSongsBars(seconds: Double, dragFrames: Double, beatSeconds: Double?, expected: Double) {
        #expect(PlanLayout.resizedSeconds(from: seconds, dragFrames: dragFrames, fps: 30, beatSeconds: beatSeconds) == expected)
    }
}
