import Foundation

/// CapCut-style editing: the main video track keeps clips end to end from zero, and drops never cut other clips.
/// Off gives Premiere-style free placement with overwrite.
@MainActor
enum MagneticTimelinePreference {
    private static let defaultsKey = "magneticTimeline"
    private(set) static var isEnabled = UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true

    static func toggle() {
        isEnabled.toggle()
        UserDefaults.standard.set(isEnabled, forKey: defaultsKey)
    }
}

enum MagneticPacking {
    /// The clips in the given order, end to end from frame zero.
    static func packed(_ clips: [Clip]) -> [Clip] {
        var cursor = 0
        return clips.map { clip in
            var clip = clip
            clip.startFrame = cursor
            cursor += clip.durationFrames
            return clip
        }
    }

    /// Where a clip whose start is dropped at `frame` lands among `clips` (in timeline order):
    /// before the first clip whose middle lies after the drop point.
    static func insertionIndex(dropFrame frame: Int, among clips: [Clip]) -> Int {
        clips.firstIndex { $0.startFrame + $0.durationFrames / 2 > frame } ?? clips.count
    }

    static func overlaps(_ clip: Clip, start: Int, end: Int) -> Bool {
        clip.startFrame < end && start < clip.endFrame
    }
}

extension EditorViewModel {
    /// The lowest visual track when it holds video: the track the magnet packs.
    var mainTrackId: String? {
        let index = zones.firstAudioIndex - 1
        guard timeline.tracks.indices.contains(index), timeline.tracks[index].type == .video else { return nil }
        return timeline.tracks[index].id
    }

    /// Each linked partner of a main-track clip, with the frame offset to keep from its anchor.
    func mainTrackLinkOffsets(mainTrackId: String) -> [String: (anchorId: String, offset: Int)] {
        guard let main = timeline.tracks.first(where: { $0.id == mainTrackId }) else { return [:] }
        var offsets: [String: (anchorId: String, offset: Int)] = [:]
        for anchor in main.clips where anchor.linkGroupId != nil {
            for partnerId in linkedPartnerIds(of: anchor.id) {
                guard let loc = findClip(id: partnerId) else { continue }
                let partner = timeline.tracks[loc.trackIndex].clips[loc.clipIndex]
                offsets[partnerId] = (anchor.id, partner.startFrame - anchor.startFrame)
            }
        }
        return offsets
    }

    /// Packs the main track in its current order and moves linked partners with their anchors,
    /// lifting any partner that would land on another clip onto a free track. Call inside a timeline swap.
    func packMainTrack(id mainTrackId: String, keeping offsets: [String: (anchorId: String, offset: Int)]) {
        guard let mainIndex = timeline.tracks.firstIndex(where: { $0.id == mainTrackId }) else { return }
        timeline.tracks[mainIndex].clips = MagneticPacking.packed(
            timeline.tracks[mainIndex].clips.sorted { $0.startFrame < $1.startFrame }
        )
        let anchorStarts = Dictionary(uniqueKeysWithValues: timeline.tracks[mainIndex].clips.map { ($0.id, $0.startFrame) })
        var synced: [(clip: Clip, trackId: String)] = []
        for (partnerId, link) in offsets {
            guard let anchorStart = anchorStarts[link.anchorId], let loc = findClip(id: partnerId) else { continue }
            let trackId = timeline.tracks[loc.trackIndex].id
            var partner = timeline.tracks[loc.trackIndex].clips.remove(at: loc.clipIndex)
            partner.startFrame = max(0, anchorStart + link.offset)
            synced.append((partner, trackId))
        }
        for item in synced.sorted(by: { $0.clip.startFrame < $1.clip.startFrame }) {
            placeWithoutOverwrite(item.clip, preferredTrackId: item.trackId)
        }
    }

    /// Puts `clip` on the preferred track if its range is free there, else on another free track of the
    /// same kind (never the packed main track), else on a new track beside it. Never trims or removes other clips.
    func placeWithoutOverwrite(_ clip: Clip, preferredTrackId: String?) {
        let mainTrackId = mainTrackId
        let start = clip.startFrame, end = clip.endFrame
        let preferredIndex = preferredTrackId.flatMap { id in timeline.tracks.firstIndex { $0.id == id } }
        func isFree(_ index: Int) -> Bool {
            timeline.tracks[index].type.isCompatible(with: clip.mediaType)
                && !timeline.tracks[index].clips.contains { MagneticPacking.overlaps($0, start: start, end: end) }
        }
        let others = timeline.tracks.indices.filter { $0 != preferredIndex && timeline.tracks[$0].id != mainTrackId }
        let candidates = (preferredIndex.map { [$0] } ?? []) + others
        let target = candidates.first(where: isFree) ?? {
            let type = preferredIndex.map { timeline.tracks[$0].type } ?? clip.mediaType
            // A new visual track goes above the preferred one, a new audio track below it.
            let requested = preferredIndex.map { type == .audio ? $0 + 1 : $0 } ?? (type == .audio ? timeline.tracks.count : 0)
            let index = partitionedInsertionIndex(for: type, requested: requested)
            timeline.tracks.insert(Track(type: type), at: index)
            return index
        }()
        timeline.tracks[target].clips.append(clip)
        sortClips(trackIndex: target)
    }
}
