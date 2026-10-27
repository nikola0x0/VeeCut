import Foundation
import Testing
@testable import PalmierPro

@Suite("Described looks")
@MainActor
struct DescribedLookTests {
    @Test func parsesBothSidesIntoRegistryEffects() throws {
        let result = try DescribedLook.parse("""
        {"name": "Golden Hour", "subject": [{"effect": "color.exposure", "settings": {"ev": 0.4}}],
         "background": [{"effect": "color.temperature", "settings": {"temperature": 7400}}]}
        """, hasSubject: true)
        #expect(result.name == "Golden Hour")
        #expect(result.plan.subject.map(\.type) == ["color.exposure"])
        #expect(result.plan.subject.first?.params["ev"]?.value == 0.4)
        let temperature = try #require(result.plan.background.first)
        #expect(temperature.params["temperature"]?.value == 7400)
        #expect(temperature.params["tint"]?.value == 0)
        #expect(result.skipped.isEmpty)
    }

    @Test func clampsSettingsToTheSliderRange() throws {
        let result = try DescribedLook.parse("""
        {"name": "x", "subject": [{"effect": "color.exposure", "settings": {"ev": 40}}], "background": []}
        """, hasSubject: true)
        #expect(result.plan.subject.first?.params["ev"]?.value == 3)
    }

    @Test func skipsAndReportsWhatVeeCutDoesNotHave() throws {
        let result = try DescribedLook.parse("""
        {"name": "x", "subject": [
            {"effect": "color.exposure", "settings": {"exposure": 0.2, "ev": 0.1}},
            {"effect": "key.chroma", "settings": {"tolerance": 0.5}},
            {"effect": "color.contrast", "settings": {"amount": true}}
        ], "background": []}
        """, hasSubject: true)
        #expect(result.plan.subject.map(\.type) == ["color.exposure", "color.contrast"])
        #expect(result.plan.subject.last?.params["amount"]?.value == 1)
        #expect(Set(result.skipped) == ["color.exposure.exposure", "key.chroma", "color.contrast.amount"])
    }

    @Test func aRepeatedEffectKeepsTheLastSettings() throws {
        let result = try DescribedLook.parse("""
        {"name": "x", "subject": [], "background": [
            {"effect": "blur.gaussian", "settings": {"radius": 4}},
            {"effect": "blur.gaussian", "settings": {"radius": 9}}
        ]}
        """, hasSubject: true)
        #expect(result.plan.background.count == 1)
        #expect(result.plan.background.first?.params["radius"]?.value == 9)
    }

    @Test(arguments: ["not json", #"{"name": "x", "subject": {}}"#, #"{"name": "x", "subject": [{"settings": {}}], "background": []}"#])
    func rejectsMalformedAnswers(_ text: String) {
        #expect(throws: DescribedLookError.malformed) { try DescribedLook.parse(text, hasSubject: true) }
    }

    @Test func rejectsALookWithNothingApplicable() {
        #expect(throws: DescribedLookError.empty) {
            try DescribedLook.parse(#"{"name": "x", "subject": [{"effect": "made.up", "settings": {}}], "background": []}"#, hasSubject: true)
        }
    }

    @Test func catalogOffersOnlySliderEffects() {
        let instructions = DescribedLook.instructions(hasSubject: true)
        #expect(instructions.contains("- color.temperature: temperature 2000…11000 K, neutral 6500; tint -100…100, neutral 0"))
        #expect(!instructions.contains("key.chroma"))
        #expect(!instructions.contains("color.wheels"))
        #expect(!instructions.contains("color.lut"))
    }

    @Test func aClipWithoutASubjectGetsAWholeFrameLook() throws {
        let result = try DescribedLook.parse(#"{"name": "Teal", "frame": [{"effect": "color.saturation", "settings": {"amount": 0.7}}]}"#, hasSubject: false)
        #expect(result.plan.frame.map(\.type) == ["color.saturation"])
        #expect(result.plan.subject.isEmpty && result.plan.background.isEmpty)
        #expect(DescribedLook.schema(hasSubject: false)["required"] as? [String] == ["name", "frame"])
        #expect(!DescribedLook.instructions(hasSubject: false).contains("background"))
    }

    @Test func aWholeFrameAnswerWithoutFrameIsMalformed() {
        #expect(throws: DescribedLookError.malformed) {
            try DescribedLook.parse(#"{"name": "x", "subject": [], "background": []}"#, hasSubject: false)
        }
    }
}
