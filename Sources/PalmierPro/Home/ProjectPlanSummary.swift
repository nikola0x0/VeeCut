import Foundation

/// What the home screen shows about a project's edit: its plan's sections, its length and the coach's next tip.
struct ProjectPlanSummary: Sendable, Equatable {
    struct Section: Sendable, Equatable {
        let title: String
        let targetSeconds: Double
        let actualSeconds: Double
    }

    let sections: [Section]
    let durationSeconds: Double
    let plannedSeconds: Double
    let plan: EditPlan?
    let nextNudge: CoachNudge?

    /// Reads the project's active timeline from its package; call off the main actor.
    nonisolated static func read(projectURL: URL) throws -> ProjectPlanSummary {
        let data = try Data(contentsOf: projectURL.appendingPathComponent(Project.timelineFilename))
        let file = try ProjectFile.decode(data)
        let timeline = file.timelines.first { $0.id == file.activeTimelineId } ?? file.timelines[0]
        let duration = Double(timeline.totalFrames) / Double(max(timeline.fps, 1))
        guard let plan = timeline.plan else {
            return ProjectPlanSummary(sections: [], durationSeconds: duration, plannedSeconds: 0, plan: nil, nextNudge: nil)
        }
        let progress = PlanLayout.progress(plan, in: timeline)
        return ProjectPlanSummary(
            sections: zip(plan.sections, progress).map { Section(title: $0.title, targetSeconds: $0.targetSeconds, actualSeconds: $1.actualSeconds) },
            durationSeconds: duration,
            plannedSeconds: plan.sections.reduce(0) { $0 + $1.targetSeconds },
            plan: plan,
            nextNudge: CoachRules.nudges(plan: plan, timeline: timeline, beatFrames: []).first
        )
    }
}

/// Plan summaries for the home screen, re-read in the background each time a project row appears.
@MainActor @Observable
final class ProjectPlanSummaries {
    static let shared = ProjectPlanSummaries()

    private(set) var summaries: [URL: ProjectPlanSummary] = [:]

    func summary(for entry: ProjectEntry) -> ProjectPlanSummary? { summaries[entry.url] }

    /// A missing or unreadable project shows no plan rather than an error.
    func load(_ entry: ProjectEntry) async {
        let url = entry.url
        let summary = await Task.detached(priority: .utility) { try? ProjectPlanSummary.read(projectURL: url) }.value
        guard !Task.isCancelled, summary != summaries[url] else { return }
        summaries[url] = summary
    }
}
