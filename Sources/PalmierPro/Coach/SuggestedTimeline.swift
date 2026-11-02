import Foundation

/// A suggestion drawn where it would land if kept; never part of the edit until then.
struct GhostClip: Equatable, Identifiable {
    let sectionId: String
    let index: Int
    let moment: PlanMoment
    let startFrame: Int
    let durationFrames: Int

    var id: String { "\(sectionId):\(index)" }
    var endFrame: Int { startFrame + durationFrames }
}

/// Lays each section's suggestions where Keep All would insert them, until the section reaches its target.
enum SuggestedTimeline {
    static let keptTolerance = 0.1

    /// `durationFrames` is the placed length of a moment, or nil when it can't be placed.
    /// With `beatSeconds` (the plan's song is on the timeline), paced sections become beat-length cuts.
    static func ghosts(plan: EditPlan, timeline: Timeline, beatSeconds: Double? = nil, beatFrames: [Int] = [], durationFrames: (PlanMoment) -> Int?) -> [GhostClip] {
        let fps = Double(max(timeline.fps, 1))
        let planClips = timeline.tracks.first { $0.id == plan.trackId }?.clips ?? []
        var ghosts: [GhostClip] = []
        var inserted = 0
        var sectionStart = 0.0
        for (sectionIndex, section) in plan.sections.enumerated() {
            defer { sectionStart += max(section.targetSeconds, 0) }
            let members = planClips.filter { $0.planSectionId == section.id }
            guard let insertion = PlanLayout.insertionFrame(for: section.id, plan: plan, timeline: timeline) else { continue }
            var cursor = insertion + inserted
            var room = Int((max(section.targetSeconds, 0) * fps).rounded()) - members.reduce(0) { $0 + $1.durationFrames }
            var added = 0
            let moments: [PlanMoment] = if let beatSeconds, let pace = section.pace {
                PacedCuts.framed(
                    PacedCuts.moments(from: section.suggestions, cutSeconds: PacedCuts.cutSeconds(for: pace, beatSeconds: beatSeconds),
                                      beatSeconds: beatSeconds, filling: max(section.targetSeconds, 0), leftoverFirst: sectionIndex == 0),
                    startSeconds: sectionStart, fps: fps, beatFrames: beatFrames, snapWithin: Int(beatSeconds * fps / 2)
                )
            } else {
                section.suggestions
            }
            for (index, moment) in moments.enumerated() {
                guard room > 0 || (members.isEmpty && added == 0) else { break }
                let isKept = members.contains {
                    $0.mediaRef == moment.assetId && abs(Double($0.trimStartFrame) / fps - moment.start) < keptTolerance
                }
                guard !isKept, let duration = durationFrames(moment) else { continue }
                ghosts.append(GhostClip(sectionId: section.id, index: index, moment: moment, startFrame: cursor, durationFrames: duration))
                cursor += duration
                room -= duration
                inserted += duration
                added += 1
            }
        }
        return ghosts
    }
}
