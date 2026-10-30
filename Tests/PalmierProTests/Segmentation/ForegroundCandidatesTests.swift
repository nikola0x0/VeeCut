import AVFoundation
import Foundation
import Testing
@testable import PalmierPro

/// A 6×6 map: label 1 fills the left 2×6 column, label 2 a 2×2 square at the bottom right.
private let labels: [UInt8] = [
    1, 1, 0, 0, 0, 0,
    1, 1, 0, 0, 0, 0,
    1, 1, 0, 0, 0, 0,
    1, 1, 0, 0, 0, 0,
    1, 1, 0, 0, 2, 2,
    1, 1, 0, 0, 2, 2,
]

@Test func candidatesGetTheirBoxAndThreeInteriorPointsSpreadTopToBottom() throws {
    let candidates = ForegroundCandidates.analyze(labels: labels, width: 6, height: 6)
    #expect(candidates.instances.map(\.label) == [1, 2])
    let tall = try #require(candidates.instances.first)
    #expect(tall.box == CGRect(x: 0, y: 0, width: 2.0 / 6, height: 1))
    #expect(tall.points.count == ForegroundCandidates.pointCount)
    #expect(tall.points.allSatisfy { candidates.instance(at: $0)?.label == 1 })
    #expect(tall.points.map(\.y) == tall.points.map(\.y).sorted())
    #expect(Set(tall.points.map(\.y)).count == 3)
}

@Test(arguments: [
    (CGPoint(x: 0.1, y: 0.5), 1), (CGPoint(x: 0.75, y: 0.75), 2), (CGPoint(x: 0.5, y: 0.2), nil),
    (CGPoint(x: 1, y: 0.5), nil), (CGPoint(x: -0.1, y: 0.5), nil), (CGPoint(x: .nan, y: 0.5), nil),
] as [(CGPoint, UInt8?)])
func hoverFindsTheInstanceUnderASourcePoint(point: CGPoint, label: UInt8?) {
    #expect(ForegroundCandidates.analyze(labels: labels, width: 6, height: 6).instance(at: point)?.label == label)
}

@Test func shapesCoveringMostOfTheFrameAreNotOffered() {
    var map = [UInt8](repeating: 1, count: 36)
    map[35] = 2
    let candidates = ForegroundCandidates.analyze(labels: map, width: 6, height: 6)
    #expect(candidates.instances.map(\.label) == [2])
    #expect(candidates.instance(at: CGPoint(x: 0.1, y: 0.1)) == nil)
}

@Test func aMalformedLabelMapHasNoCandidates() {
    #expect(ForegroundCandidates.analyze(labels: [1, 1], width: 6, height: 6).instances.isEmpty)
}

@Test func visionAnalyzesADecodedSourceFrame() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
    defer { try? FileManager.default.removeItem(at: url) }
    try await writeSolidVideo(to: url, frames: 10, timescale: 30, frameDuration: 1)
    let candidates = try await ForegroundCandidates.detect(url: url, sourceSeconds: 0.1, tint: .init(r: 0, g: 0, b: 0, a: 0))
    #expect(candidates.instances.isEmpty)
}

@Suite("Vision hover target")
@MainActor
struct ForegroundHoverTargetTests {
    private func editor() -> EditorViewModel {
        let editor = EditorViewModel()
        editor.importMediaAsset(MediaAsset(id: "media-1", url: URL(fileURLWithPath: "/tmp/dog.mov"), type: .video, name: "Dog", duration: 5))
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [Fixtures.clip(id: "clip", start: 0, duration: 60, trimStart: 30)])])
        editor.currentFrame = 15
        return editor
    }

    @Test func thePickToolAnalyzesThePausedFrameUnderThePlayhead() {
        let editor = editor()
        #expect(editor.foregroundDetectionTarget == nil)
        editor.toggleCanvasSelection(.subject)
        #expect(editor.foregroundDetectionTarget == ForegroundDetectionTarget(clipId: "clip", url: URL(fileURLWithPath: "/tmp/dog.mov"), sourceSeconds: 1.5))
    }

    @Test func playbackBrushAndEmptyFramesAnalyzeNothing() {
        let editor = editor()
        editor.toggleCanvasSelection(.brush)
        #expect(editor.foregroundDetectionTarget == nil)
        editor.toggleCanvasSelection(.subject)
        editor.play()
        #expect(editor.foregroundDetectionTarget == nil)
        editor.pause()
        editor.currentFrame = 90
        #expect(editor.foregroundDetectionTarget == nil)
    }
}
