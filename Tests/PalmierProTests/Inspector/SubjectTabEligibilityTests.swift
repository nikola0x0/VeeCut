import Testing
@testable import PalmierPro

@Suite("Subject tab eligibility")
struct SubjectTabEligibilityTests {
    private let video = Fixtures.clip(id: "video", start: 0, duration: 30)
    private let audio = Fixtures.clip(id: "audio", mediaType: .audio, start: 0, duration: 30)
    private let other = Fixtures.clip(id: "other", start: 30, duration: 30)

    private func selection(_ ids: Set<String>) -> InspectorClipSelection {
        let timeline = Fixtures.timeline(tracks: [
            Fixtures.videoTrack(clips: [video, other]),
            Fixtures.audioTrack(clips: [audio]),
        ])
        return InspectorClipSelection.resolve(timeline: timeline, selectedIds: ids)
    }

    @Test func aVideoClipWithItsLinkedAudioCountsAsOneClip() {
        let clip = selection(["video", "audio"]).singleVideoClip { $0 == "video" ? ["audio"] : [] }
        #expect(clip?.id == "video")
    }

    @Test func unrelatedAudioOrASecondVideoHidesTheTab() {
        #expect(selection(["video", "audio"]).singleVideoClip { _ in [] } == nil)
        #expect(selection(["video", "other"]).singleVideoClip { _ in [] } == nil)
    }
}
