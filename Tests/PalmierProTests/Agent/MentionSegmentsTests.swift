import Foundation
import Testing
@testable import PalmierPro

@Suite("Mention segments")
struct MentionSegmentsTests {
    private let sky = AgentMention(displayName: "Sky", mediaRef: "m1", type: .image)
    private let sky2 = AgentMention(displayName: "Sky-2", mediaRef: "m2", type: .image)

    @Test func splitFindsWholeTokensOnly() {
        let segments = MentionSegments.split("make @Sky-2 and @Sky warm", mentions: [sky, sky2])
        #expect(segments == [.text("make "), .mention(sky2), .text(" and "), .mention(sky), .text(" warm")])
    }

    @Test(arguments: ["@Skyline", "email@Sky.com", "@Sky#2"])
    func aTokenFollowedByMoreOfAWordIsText(text: String) {
        #expect(MentionSegments.split(text, mentions: [sky]) == [.text(text)])
    }

    @Test func punctuationEndsAToken() {
        #expect(MentionSegments.split("@Sky, please", mentions: [sky]) == [.mention(sky), .text(", please")])
    }

    @Test func unregisteredTokensStayText() {
        #expect(MentionSegments.split("@Mochi", mentions: []) == [.text("@Mochi")])
    }

    @Test(arguments: ["", "plain", "@Sky", "a @Sky-2 b @Sky\n@Sky", "@@Sky @ @Sky-2."])
    func serializeRoundTripsExactly(text: String) {
        #expect(MentionSegments.serialize(MentionSegments.split(text, mentions: [sky, sky2])) == text)
    }
}
