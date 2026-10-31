import Foundation
import Testing
@testable import PalmierPro

@Suite("Footage scanner")
@MainActor
struct FootageScannerTests {
    private func input(_ id: String, key: String = "k", duration: Double = 30) -> ScanInput {
        ScanInput(assetId: id, url: URL(fileURLWithPath: "/tmp/\(id).mov"), fileKey: key, durationSeconds: duration)
    }

    private nonisolated static func hit(_ asset: String, shot: Double, score: Float) -> VisualSearch.Hit {
        VisualSearch.Hit(assetID: asset, time: shot + 0.5, shotStart: shot, shotEnd: shot + 2, score: score)
    }

    private func note(_ id: String, labels: [String], speech: Bool = false, duration: Double = 60) -> FootageNote {
        FootageNote(assetId: id, fileKey: "k", durationSeconds: duration, hasSpeech: speech, labels: labels, summary: nil, moments: [])
    }

    @Test func labelsComeFromHitsAboveTheScoreFloor() async {
        let notes = await FootageScanner.scan([input("a")], search: { label in
            switch label {
            case "food": [VisualSearch.Hit(assetID: "a", time: 1, shotStart: 0, shotEnd: 2, score: 0.2)]
            case "animal": [VisualSearch.Hit(assetID: "a", time: 1, shotStart: 0, shotEnd: 2, score: 0.11)]
            default: []
            }
        }, speech: { _ in true })

        #expect(notes.count == 1)
        #expect(notes[0].labels == ["food"])
        #expect(notes[0].hasSpeech)
        #expect(notes[0].fileKey == "k")
    }

    @Test func momentsAreTheBestShotsCappedAtSix() async {
        let notes = await FootageScanner.scan([input("a")], search: { label in
            switch label {
            case "food": (0..<5).map { Self.hit("a", shot: Double($0 * 3), score: 0.25 + Float($0) * 0.01) }
            case "market or shop": (0..<5).map { Self.hit("a", shot: 20 + Double($0 * 3), score: 0.2 + Float($0) * 0.01) } + [Self.hit("a", shot: 12, score: 0.5)]
            default: []
            }
        }, speech: { _ in false })

        let moments = notes[0].moments
        #expect(moments.count == 6)
        #expect(moments.first == PlanMoment(assetId: "a", start: 12, end: 14, note: "market or shop"))
        #expect(Set(moments.map(\.start)).count == 6)
        #expect(moments.last == PlanMoment(assetId: "a", start: 32, end: 34, note: "market or shop"))
    }

    @Test func overviewNamesTopLabelsAndSpeech() {
        let notes = [
            note("1", labels: ["coffee or café", "food"], speech: true),
            note("2", labels: ["coffee or café"]),
            note("3", labels: ["animal", "street at night"]),
            note("4", labels: ["street at night", "beach or water"]),
            note("5", labels: ["street at night", "food"], speech: true),
        ]
        #expect(FootageScanner.overview(notes) == "5 clips — night streets, food, cafés, and animals · 2 with talking")
    }

    @Test func overviewFallsBackWithoutLabels() {
        let notes = [note("1", labels: [], speech: true, duration: 600), note("2", labels: [], duration: 480)]
        #expect(FootageScanner.overview(notes) == "2 clips, 18 min · 1 with talking")
    }

    @Test func staleNotesAreRescannedWhenTheFileChanges() {
        let notes = ["a": note("a", labels: ["food"]), "b": note("b", labels: ["food"]), "c": note("c", labels: [])]
        let inputs = [input("a"), input("b", key: "changed"), input("c"), input("d")]

        #expect(FootageScanner.inputsNeedingScan(inputs, notes: notes, labelsAvailable: true).map(\.assetId) == ["b", "c", "d"])
        #expect(FootageScanner.inputsNeedingScan(inputs, notes: notes, labelsAvailable: false).map(\.assetId) == ["b", "d"])
    }
}
