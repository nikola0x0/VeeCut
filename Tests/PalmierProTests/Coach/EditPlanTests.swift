import Foundation
import Testing
@testable import PalmierPro

struct EditPlanTests {
    @Test func planAndMembershipSurviveSaveAndReopen() throws {
        let section = PlanSection(
            title: "Hook", targetSeconds: 8, hint: "Your best shot",
            suggestions: [PlanMoment(assetId: "media-1", start: 2, end: 6, note: "cat jumps")]
        )
        var clip = Fixtures.clip(start: 0, duration: 90)
        clip.planSectionId = section.id
        let track = Fixtures.videoTrack(clips: [clip])
        var timeline = Fixtures.timeline(tracks: [track])
        timeline.plan = EditPlan(brief: "Dalat vlog", style: .travelVlog, trackId: track.id, sections: [section], dismissedNudges: ["over:x"])
        let file = ProjectFile(timelines: [timeline], activeTimelineId: timeline.id)

        let reopened = try ProjectFile.decode(JSONEncoder().encode(file))

        #expect(reopened.timelines.first?.plan == timeline.plan)
        #expect(reopened.timelines.first?.tracks.first?.clips.first?.planSectionId == section.id)
    }

    @Test func timelinesSavedBeforePlansStillOpen() throws {
        let file = ProjectFile(timelines: [Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [Fixtures.clip(start: 0, duration: 30)])])])
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(file)) as? [String: Any])
        var timelines = try #require(json["timelines"] as? [[String: Any]])
        timelines[0].removeValue(forKey: "plan")
        json["timelines"] = timelines

        let reopened = try ProjectFile.decode(JSONSerialization.data(withJSONObject: json))

        #expect(reopened.timelines.first?.plan == nil)
        #expect(reopened.timelines.first?.tracks.first?.clips.first?.planSectionId == nil)
    }
}
