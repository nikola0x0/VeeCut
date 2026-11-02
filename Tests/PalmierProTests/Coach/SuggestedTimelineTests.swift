import Foundation
import Testing
@testable import PalmierPro

@Suite("Suggested timeline")
@MainActor
struct SuggestedTimelineTests {
    private let undoManager = UndoManager()

    private func moment(_ start: Double, _ end: Double, asset: String = "cat") -> PlanMoment {
        PlanMoment(assetId: asset, start: start, end: end, note: "")
    }

    private func plan(_ sections: [(Double, [PlanMoment])], trackId: String = "v1") -> EditPlan {
        EditPlan(brief: "", style: nil, trackId: trackId, sections: sections.enumerated().map { index, section in
            var plan = PlanSection(id: "s\(index)", title: "S\(index)", targetSeconds: section.0, hint: "")
            plan.suggestions = section.1
            return plan
        })
    }

    private func member(_ id: String, start: Int, duration: Int, trimStart: Int = 0) -> Clip {
        var clip = Fixtures.clip(id: id, mediaRef: "cat", start: start, duration: duration, trimStart: trimStart)
        clip.planSectionId = "s0"
        return clip
    }

    private func editor(plan: EditPlan, clips: [Clip] = []) -> EditorViewModel {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(id: "v1", clips: clips)])
        editor.timeline.plan = plan
        let asset = MediaAsset(id: "cat", url: URL(fileURLWithPath: "/tmp/cat.mov"), type: .video, name: "cat", duration: 20)
        asset.hasAudio = false
        editor.mediaAssets.append(asset)
        editor.undo.attach(undoManager)
        return editor
    }

    private let catOnly: (PlanMoment) -> Int? = { $0.assetId == "cat" ? Int(($0.end - $0.start) * 30) : nil }

    private func undoActions() -> Int {
        var count = 0
        while undoManager.canUndo { undoManager.undo(); count += 1 }
        return count
    }

    @Test func ghostsFollowPlacedClipsAndStopAtTheTarget() {
        let timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(id: "v1", clips: [member("a", start: 0, duration: 60)])])
        let plan = plan([(5, [moment(2, 4), moment(4, 6), moment(6, 8)])])

        let ghosts = SuggestedTimeline.ghosts(plan: plan, timeline: timeline, durationFrames: catOnly)

        #expect(ghosts.map(\.startFrame) == [60, 120])
        #expect(ghosts.map(\.durationFrames) == [60, 60])
    }

    @Test func ghostsOnAnEmptyTimelineStartAtZero() {
        let plan = plan([(3, [moment(0, 2)]), (2, [moment(5, 7)])], trackId: "gone")

        let ghosts = SuggestedTimeline.ghosts(plan: plan, timeline: Fixtures.timeline(), durationFrames: catOnly)

        #expect(ghosts.map(\.startFrame) == [0, 60])
        #expect(ghosts.map(\.sectionId) == ["s0", "s1"])
    }

    private func pacedPlan() -> EditPlan {
        var plan = plan([(4, [moment(0, 4), moment(10, 14)])])
        plan.sections[0].pace = .peak
        plan.music = PlanMusic(assetId: "song", beatSeconds: 0.5, drop: nil)
        return plan
    }

    @Test func pacedGhostsLandOnTheBeat() {
        let ghosts = SuggestedTimeline.ghosts(plan: pacedPlan(), timeline: Fixtures.timeline(), beatSeconds: 0.5, durationFrames: catOnly)

        #expect(ghosts.map(\.startFrame) == [0, 30, 60, 90])
        #expect(ghosts.map(\.durationFrames) == [30, 30, 30, 30])
    }

    @Test func pacedGhostsStayOnABeatThatIsNotAWholeNumberOfFrames() {
        var plan = plan([(13.6, [moment(0, 30)])])
        plan.sections[0].pace = .peak
        plan.music = PlanMusic(assetId: "song", beatSeconds: 0.68, drop: nil)

        let ghosts = SuggestedTimeline.ghosts(plan: plan, timeline: Fixtures.timeline(), beatSeconds: 0.68, durationFrames: catOnly)

        #expect(ghosts.map(\.startFrame) == (0..<10).map { Int((Double($0) * 1.36 * 30).rounded()) })
    }

    @Test func pacedGhostsFollowTheSongsDetectedBeats() {
        let ghosts = SuggestedTimeline.ghosts(plan: pacedPlan(), timeline: Fixtures.timeline(), beatSeconds: 0.5, beatFrames: [0, 31, 62, 89, 120], durationFrames: catOnly)

        #expect(ghosts.map(\.startFrame) == [0, 31, 62, 89])
    }

    @Test func withoutTheSongGhostsUseWholeMoments() {
        let ghosts = SuggestedTimeline.ghosts(plan: pacedPlan(), timeline: Fixtures.timeline(), beatSeconds: nil, durationFrames: catOnly)

        #expect(ghosts.map(\.moment) == [moment(0, 4)])
    }

    @Test func keptMomentsAreNotSuggestedAgain() {
        let timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(id: "v1", clips: [member("a", start: 0, duration: 60, trimStart: 60)])])
        let plan = plan([(5, [moment(2, 4), moment(4, 6)])])

        let ghosts = SuggestedTimeline.ghosts(plan: plan, timeline: timeline, durationFrames: catOnly)

        #expect(ghosts.map(\.moment) == [moment(4, 6)])
        #expect(ghosts.first?.startFrame == 60)
    }

    @Test func suggestionsForMissingAssetsAreSkipped() {
        let plan = plan([(5, [moment(0, 2, asset: "gone"), moment(0, 2)])])

        let ghosts = SuggestedTimeline.ghosts(plan: plan, timeline: Fixtures.timeline(), durationFrames: catOnly)

        #expect(ghosts.map(\.moment.assetId) == ["cat"])
        #expect(ghosts.first?.startFrame == 0)
    }

    @Test func aSectionWithNoGhostsDoesNotPushLaterGhosts() {
        let plan = plan([(10, [moment(0, 2, asset: "gone")]), (5, [moment(0, 2)])])

        let ghosts = SuggestedTimeline.ghosts(plan: plan, timeline: Fixtures.timeline(), durationFrames: catOnly)

        #expect(ghosts.map(\.startFrame) == [0])
    }

    @Test func suggestionsPastTheEndOfTheirClipAreNotShown() {
        let editor = editor(plan: plan([(5, [moment(18, 25), moment(0, 2)])]))

        #expect(editor.suggestedGhosts.map(\.moment) == [moment(0, 2)])
    }

    @Test func keepingAGhostPlacesItInItsSectionInOneUndoStep() throws {
        let editor = editor(plan: plan([(5, [moment(2, 4)])]))
        let ghost = try #require(editor.suggestedGhosts.first)

        editor.keepSuggestion(ghost)

        let clips = editor.timeline.tracks.flatMap(\.clips)
        #expect(clips.map(\.planSectionId) == ["s0"])
        #expect(clips.first?.trimStartFrame == 60)
        #expect(editor.suggestedGhosts.isEmpty)
        #expect(undoActions() == 1)
        #expect(editor.timeline.tracks.flatMap(\.clips).isEmpty)
    }

    @Test func keepAllLeavesOutInvalidSuggestionsAndKeepsTheRestInOneStep() {
        let editor = editor(plan: plan([(5, [moment(0, 2), moment(3, 5)]), (5, [moment(18, 25)])]))
        editor.showsSuggestedTimeline = true

        editor.keepAllSuggestions()

        let clips = editor.timeline.tracks.flatMap(\.clips)
        #expect(clips.count == 2)
        #expect(Set(clips.compactMap(\.planSectionId)) == ["s0"])
        #expect(editor.mediaPanelToast == nil)
        #expect(!editor.showsSuggestedTimeline)
        #expect(undoActions() == 1)
        #expect(editor.timeline.tracks.flatMap(\.clips).isEmpty)
    }

    @Test func suggestionsShowOnlyOnTheTimelineTheyWereMadeFor() {
        let editor = editor(plan: plan([(5, [moment(0, 2)])]))
        editor.activeTimelineId = "a"
        editor.showsSuggestedTimeline = true

        editor.activeTimelineId = "b"
        #expect(!editor.showsSuggestedTimeline)

        editor.activeTimelineId = "a"
        #expect(editor.showsSuggestedTimeline)
    }

    @Test func keepAllWithNothingToKeepAddsNoUndo() {
        let editor = editor(plan: plan([(5, [])]))

        editor.keepAllSuggestions()

        #expect(!undoManager.canUndo)
    }
}
