import Testing
@testable import PalmierPro

@Test func onlyTheFlagThatSilencesATrackDimsIt() {
    var audio = Fixtures.audioTrack()
    var video = Fixtures.videoTrack()
    audio.hidden = true
    video.muted = true
    #expect(!audio.isSilencedOrHidden && !video.isSilencedOrHidden)
    audio.muted = true
    video.hidden = true
    #expect(audio.isSilencedOrHidden && video.isSilencedOrHidden)
}
