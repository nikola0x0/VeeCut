import Foundation
import Testing
@testable import PalmierPro

struct ProjectPlanSummaryTests {
    private func package(with file: ProjectFile) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("summary-\(UUID().uuidString).veecut")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try JSONEncoder().encode(file).write(to: url.appendingPathComponent(Project.timelineFilename))
        return url
    }

    @Test func aPlannedProjectSummarizesItsSectionsAndNextTip() throws {
        var hook = Fixtures.clip(start: 0, duration: 150)
        hook.planSectionId = "s0"
        let track = Fixtures.videoTrack(id: "v1", clips: [hook])
        var timeline = Fixtures.timeline(tracks: [track])
        timeline.plan = EditPlan(brief: "trip", style: .travelVlog, trackId: "v1", sections: [
            PlanSection(id: "s0", title: "Hook", targetSeconds: 5, hint: ""),
            PlanSection(id: "s1", title: "Night", targetSeconds: 45, hint: "", suggestions: [PlanMoment(assetId: "m", start: 0, end: 2, note: "")]),
        ])
        let url = try package(with: ProjectFile(timelines: [timeline], activeTimelineId: timeline.id))
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = try #require(try ProjectPlanSummary.read(projectURL: url))

        #expect(summary.sections.map(\.title) == ["Hook", "Night"])
        #expect(summary.sections.map(\.actualSeconds) == [5, 0])
        #expect(summary.durationSeconds == 5)
        #expect(summary.plannedSeconds == 50)
        #expect(summary.nextNudge?.id == "empty:s1")
    }

    @Test func aProjectWithoutAPlanHasNoSections() throws {
        let timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [Fixtures.clip(start: 0, duration: 60)])])
        let url = try package(with: ProjectFile(timelines: [timeline], activeTimelineId: timeline.id))
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = try #require(try ProjectPlanSummary.read(projectURL: url))

        #expect(summary.sections.isEmpty)
        #expect(summary.durationSeconds == 2)
        #expect(summary.nextNudge == nil)
    }

    @Test(arguments: [
        ([], "Oct 31"),
        (["Oct 31"], "Oct 31 2"),
        (["Oct 31", "Oct 31 2"], "Oct 31 3"),
    ] as [([String], String)])
    func footageProjectsAreNamedForTheDay(existing: [String], expected: String) {
        #expect(Project.uniqueName(base: "Oct 31", existing: Set(existing)) == expected)
    }
}
