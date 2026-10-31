import Foundation

/// One coaching moment; `id` names the situation so a dismissal never brings it back.
struct CoachNudge: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case sectionOver(sectionId: String, extraSeconds: Double)
        case offBeatCuts(sectionId: String, cutFrames: [Int])
        case emptySection(sectionId: String, moments: [PlanMoment])
        case hookCandidate(sectionId: String, moment: PlanMoment)
        case fitToMusic(seconds: Double)
    }

    let id: String
    let kind: Kind

    var sectionId: String? {
        switch kind {
        case .sectionOver(let id, _), .offBeatCuts(let id, _), .emptySection(let id, _), .hookCandidate(let id, _): id
        case .fitToMusic: nil
        }
    }
}

/// Finds coaching moments in the plan, most useful first: a song that doesn't fit, over-long sections, cuts just off the beat, empty sections, the hook.
enum CoachRules {
    static let overMarginSeconds = 3.0
    static let overMarginFraction = 0.15
    static let beatToleranceSeconds = 0.25
    static let onBeatFrames = 2
    static let musicMarginSeconds = 5.0
    static let musicMarginFraction = 0.1

    static func nudges(plan: EditPlan, timeline: Timeline, beatFrames: [Int], musicSeconds: Double? = nil) -> [CoachNudge] {
        let fps = Double(max(timeline.fps, 1))
        let progress = PlanLayout.progress(plan, in: timeline)
        let clips = timeline.tracks.first { $0.id == plan.trackId }?.clips.sorted { $0.startFrame < $1.startFrame } ?? []
        let beats = beatFrames.sorted()
        var fit: [CoachNudge] = [], over: [CoachNudge] = [], offBeat: [CoachNudge] = [], empty: [CoachNudge] = [], hook: [CoachNudge] = []
        let planned = plan.sections.reduce(0) { $0 + $1.targetSeconds }
        if let musicSeconds, musicSeconds.isFinite, musicSeconds >= 1,
           abs(planned - musicSeconds) > max(musicMarginSeconds, musicSeconds * musicMarginFraction) {
            let seconds = musicSeconds.rounded()
            fit.append(CoachNudge(id: "fit:\(Int(seconds))", kind: .fitToMusic(seconds: seconds)))
        }

        for (index, section) in plan.sections.enumerated() {
            let actual = progress[index].actualSeconds
            if actual > section.targetSeconds + max(overMarginSeconds, section.targetSeconds * overMarginFraction) {
                over.append(CoachNudge(id: "over:\(section.id)", kind: .sectionOver(sectionId: section.id, extraSeconds: actual - section.targetSeconds)))
            }
            let cuts = clips.filter { $0.planSectionId == section.id }.dropFirst().map(\.startFrame)
            let offCuts = cuts.filter { cut in
                guard let distance = nearestDistance(to: cut, in: beats) else { return false }
                return distance > onBeatFrames && Double(distance) <= beatToleranceSeconds * fps
            }
            if !offCuts.isEmpty {
                offBeat.append(CoachNudge(id: "beats:\(section.id)", kind: .offBeatCuts(sectionId: section.id, cutFrames: offCuts)))
            }
            guard progress[index].frames == nil, section.targetSeconds > 0, let first = section.suggestions.first else { continue }
            if index == 0 {
                hook.append(CoachNudge(id: "hook:\(section.id)", kind: .hookCandidate(sectionId: section.id, moment: first)))
            } else {
                empty.append(CoachNudge(id: "empty:\(section.id)", kind: .emptySection(sectionId: section.id, moments: section.suggestions)))
            }
        }
        return (fit + over + offBeat + empty + hook).filter { !plan.dismissedNudges.contains($0.id) }
    }

    /// The beat nearest to `frame`, for snapping.
    static func nearestBeat(to frame: Int, in sortedBeats: [Int]) -> Int? {
        sortedBeats.min { abs($0 - frame) < abs($1 - frame) }
    }

    private static func nearestDistance(to frame: Int, in sortedBeats: [Int]) -> Int? {
        nearestBeat(to: frame, in: sortedBeats).map { abs($0 - frame) }
    }
}
