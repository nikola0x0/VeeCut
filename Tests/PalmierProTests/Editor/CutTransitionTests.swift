import Foundation
import Testing
@testable import PalmierPro

struct CutTransitionTests {
    private func clip(_ id: String, start: Int, duration: Int = 60) -> Clip {
        Fixtures.clip(id: id, mediaRef: "media-\(id)", start: start, duration: duration)
    }

    @Test func cutsAreWhereOneClipStartsAsTheLastEnds() {
        let track = Fixtures.videoTrack(clips: [clip("a", start: 0), clip("b", start: 60), clip("c", start: 150)])
        #expect(CutTransition.cuts(on: track).map(\.frame) == [0, 60, 150])
        #expect(CutTransition.cuts(on: track).map(\.outgoingId) == [nil, "a", nil])
    }

    @Test func aZoomPunchStartsBiggerAndSettlesAroundTheCenter() throws {
        var incoming = clip("b", start: 60)
        var outgoing: Clip? = clip("a", start: 0)

        #expect(CutTransition.zoomPunch.apply(incoming: &incoming, outgoing: &outgoing, fps: 30) == nil)

        let scale = try #require(incoming.scaleTrack?.keyframes)
        #expect(scale.map(\.frame) == [0, 6])
        #expect(scale.first?.value == AnimPair(a: 1.1, b: 1.1))
        #expect(scale.last?.value == AnimPair(a: 1, b: 1))
        let start = incoming.topLeftAt(frame: 60), size = incoming.sizeAt(frame: 60)
        #expect(abs(start.x + size.width / 2 - 0.5) < 1e-9 && abs(start.y + size.height / 2 - 0.5) < 1e-9)
        #expect(outgoing == clip("a", start: 0))
    }

    @Test func aBlurRevealClearsOverItsLength() throws {
        var incoming = clip("b", start: 60)
        var outgoing: Clip?
        #expect(CutTransition.blurReveal.apply(incoming: &incoming, outgoing: &outgoing, fps: 30) == nil)
        let blur = try #require(incoming.blurKeyframeTrack?.keyframes)
        #expect(blur.map(\.frame) == [0, 12])
        #expect(blur.map(\.value) == [40, 0])
    }

    @Test func aWhipBlurSmearsBothSidesOfTheCut() throws {
        var incoming = clip("b", start: 60)
        var outgoing: Clip? = clip("a", start: 0)
        #expect(CutTransition.whipBlur.apply(incoming: &incoming, outgoing: &outgoing, fps: 30) == nil)
        #expect(try #require(outgoing?.blurKeyframeTrack?.keyframes).map(\.value) == [0, 30])
        #expect(try #require(outgoing?.blurKeyframeTrack?.keyframes).last?.frame == 59)
        #expect(try #require(incoming.blurKeyframeTrack?.keyframes).map(\.value) == [30, 0])
    }

    @Test func aDipToBlackFadesOutThenIn() {
        var incoming = clip("b", start: 60)
        var outgoing: Clip? = clip("a", start: 0)
        #expect(CutTransition.dipToBlack.apply(incoming: &incoming, outgoing: &outgoing, fps: 30) == nil)
        #expect(outgoing?.fadeOutFrames == 8)
        #expect(incoming.fadeInFrames == 8)
    }

    @Test(arguments: [CutTransition.zoomPunch, .blurReveal, .whipBlur])
    func keyframesTheUserSetAreNeverOverwritten(transition: CutTransition) {
        var incoming = clip("b", start: 60)
        incoming.scaleTrack = KeyframeTrack(keyframes: [Keyframe(frame: 0, value: AnimPair(a: 0.5, b: 0.5))])
        incoming.setBlurKeyframeTrack(KeyframeTrack(keyframes: [Keyframe(frame: 0, value: 5)]))
        let before = incoming
        var outgoing: Clip? = clip("a", start: 0)

        #expect(transition.apply(incoming: &incoming, outgoing: &outgoing, fps: 30) == .hasKeyframes)
        #expect(incoming == before)
    }

    @Test(arguments: [CutTransition.zoomPunch, .blurReveal, .whipBlur, .dipToBlack, .flash])
    func theIncomingClipRemembersItsTransition(transition: CutTransition) {
        var incoming = clip("b", start: 60)
        var outgoing: Clip? = clip("a", start: 0)
        #expect(transition.apply(incoming: &incoming, outgoing: &outgoing, fps: 30) == nil)
        #expect(incoming.cutTransition == transition)
        #expect(outgoing?.cutTransition == nil)
    }

    @Test func theTransitionSurvivesSaveAndReopen() throws {
        var saved = clip("b", start: 60)
        saved.cutTransition = .whipBlur
        let reopened = try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(saved))
        #expect(reopened.cutTransition == .whipBlur)
    }

    @Test func aClipTooShortForTheTransitionIsSkipped() {
        var incoming = clip("b", start: 60, duration: 4)
        var outgoing: Clip? = clip("a", start: 0)
        #expect(CutTransition.blurReveal.apply(incoming: &incoming, outgoing: &outgoing, fps: 30) == .tooShort)
    }
}
