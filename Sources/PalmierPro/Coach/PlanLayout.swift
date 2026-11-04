import Foundation

struct SectionProgress: Equatable {
    let sectionId: String
    let actualSeconds: Double
    let targetSeconds: Double
    let frames: Range<Int>?

    var isFilled: Bool { actualSeconds >= targetSeconds * 0.9 }
}

/// Where a section sits on the timeline: `placed` spans its clips, `slot` adds the target time still missing.
struct SectionBand: Equatable {
    let sectionId: String
    let placed: Range<Int>?
    let slot: Range<Int>
}

/// Plan progress derived from the timeline; only clips on the plan's track count.
enum PlanLayout {
    static func progress(_ plan: EditPlan, in timeline: Timeline) -> [SectionProgress] {
        let fps = Double(max(timeline.fps, 1))
        let clips = planClips(plan, in: timeline)
        return plan.sections.map { section in
            let members = clips.filter { $0.planSectionId == section.id }
            let frames = members.isEmpty ? nil : members.map(\.startFrame).min()!..<members.map(\.endFrame).max()!
            let actual = Double(members.reduce(0) { $0 + $1.durationFrames }) / fps
            return SectionProgress(sectionId: section.id, actualSeconds: actual, targetSeconds: section.targetSeconds, frames: frames)
        }
    }

    /// The end of the section, or of the nearest earlier filled section when it is empty.
    static func insertionFrame(for sectionId: String, plan: EditPlan, timeline: Timeline) -> Int? {
        guard let index = plan.sections.firstIndex(where: { $0.id == sectionId }) else { return nil }
        let progress = progress(plan, in: timeline)
        return progress[...index].reversed().lazy.compactMap(\.frames?.upperBound).first ?? 0
    }

    /// Assigns each plan-track clip to the section whose cumulative target window holds its midpoint.
    static func membership(byPosition plan: EditPlan, timeline: Timeline) -> [String: String] {
        guard let last = plan.sections.last else { return [:] }
        let fps = Double(max(timeline.fps, 1))
        var windowEnds: [Double] = []
        var total = 0.0
        for section in plan.sections {
            total += max(section.targetSeconds, 0)
            windowEnds.append(total)
        }
        var membership: [String: String] = [:]
        for clip in planClips(plan, in: timeline) {
            let midpoint = (Double(clip.startFrame) + Double(clip.durationFrames) / 2) / fps
            let index = windowEnds.firstIndex { midpoint < $0 }
            membership[clip.id] = index.map { plan.sections[$0].id } ?? last.id
        }
        return membership
    }

    static let barBeats = 4.0

    /// A section's new length after dragging its band's trailing edge: whole bars when cut to a song, else whole
    /// seconds, never shorter than one bar or one second.
    static func resizedSeconds(from seconds: Double, dragFrames: Double, fps: Int, beatSeconds: Double?) -> Double {
        let step = beatSeconds.map { $0 * barBeats }.flatMap { $0 > 0 && $0.isFinite ? $0 : nil } ?? 1
        let proposed = seconds + dragFrames / Double(max(fps, 1))
        guard proposed.isFinite else { return seconds }
        return max(step, (proposed / step).rounded() * step)
    }

    /// Bands in timeline frames; a slot never runs into a later section's clips.
    static func bands(_ plan: EditPlan, in timeline: Timeline, progress: [SectionProgress]? = nil) -> [SectionBand] {
        let fps = Double(max(timeline.fps, 1))
        let progress = progress ?? self.progress(plan, in: timeline)
        var cursor = 0
        var bands: [SectionBand] = []
        for (index, section) in progress.enumerated() {
            let start = section.frames?.lowerBound ?? cursor
            let targetFrames = Int((max(section.targetSeconds, 0) * fps).rounded())
            let nextPlaced = progress[(index + 1)...].lazy.compactMap(\.frames?.lowerBound).first { $0 >= start }
            var end = max(section.frames?.upperBound ?? start, start + targetFrames)
            if let nextPlaced { end = max(section.frames?.upperBound ?? start, min(end, nextPlaced)) }
            bands.append(SectionBand(sectionId: section.sectionId, placed: section.frames, slot: start..<end))
            cursor = max(cursor, end)
        }
        return bands
    }

    private static func planClips(_ plan: EditPlan, in timeline: Timeline) -> [Clip] {
        timeline.tracks.first { $0.id == plan.trackId }?.clips.sorted { $0.startFrame < $1.startFrame } ?? []
    }
}
