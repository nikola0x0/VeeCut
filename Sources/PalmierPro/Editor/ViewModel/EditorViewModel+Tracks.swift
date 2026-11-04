import AppKit

/// Track-level mutations: add/remove, visibility toggles, height, sync-lock.
extension EditorViewModel {

    // MARK: - Add / remove

    @discardableResult
    func insertTrack(at index: Int, type: ClipType) -> Int {
        let clamped = partitionedInsertionIndex(for: type, requested: index)
        withTimelineSwap(actionName: "Add Track") {
            freezeTrackNumbers()
            let taken = Set(timeline.tracks.filter { $0.type == type }.compactMap(\.number))
            var track = Track(type: type)
            track.number = (1...).first { !taken.contains($0) }
            timeline.tracks.insert(track, at: clamped)
        }
        return clamped
    }

    /// "V1", "A1", "I1" label for the track at the given index: its own number once fixed, else the next free one by position.
    func timelineTrackDisplayLabel(at trackIndex: Int) -> String {
        guard timeline.tracks.indices.contains(trackIndex) else { return "" }
        return "\(timeline.tracks[trackIndex].type.trackLabelPrefix)\(trackNumbers()[trackIndex])"
    }

    /// Each track's label number. Fixed numbers stay; the rest take the smallest unused numbers in label order
    /// (visual tracks bottom up, audio top down), so no two tracks of a kind ever share one.
    private func trackNumbers() -> [Int] {
        let tracks = timeline.tracks
        var numbers = tracks.map(\.number)
        let firstAudio = zones.firstAudioIndex
        for type in Set(tracks.map(\.type)) {
            var taken = Set(tracks.filter { $0.type == type }.compactMap(\.number))
            let order = tracks.indices.filter { tracks[$0].type == type }
                .sorted { lhs, rhs in
                    let lhsAudio = lhs >= firstAudio, rhsAudio = rhs >= firstAudio
                    return type == .audio || lhsAudio || rhsAudio ? lhs < rhs : lhs > rhs
                }
            var next = 1
            for index in order where numbers[index] == nil {
                while taken.contains(next) { next += 1 }
                numbers[index] = next
                taken.insert(next)
            }
        }
        return numbers.map { $0 ?? 1 }
    }

    /// Stores every track's current label number, so moving or adding tracks doesn't renumber the others.
    private func freezeTrackNumbers() {
        let numbers = trackNumbers()
        for index in timeline.tracks.indices where timeline.tracks[index].number == nil {
            timeline.tracks[index].number = numbers[index]
        }
    }

    @discardableResult
    func setTrackName(id: String, to rawName: String?) throws -> Bool {
        let name = try TrackName.normalized(rawName)
        return applyTrackName(id: id, name: name)
    }

    @discardableResult
    private func applyTrackName(id: String, name: String?) -> Bool {
        guard let index = timeline.tracks.firstIndex(where: { $0.id == id }) else { return false }
        let previous = timeline.tracks[index].name
        guard previous != name else { return false }
        timeline.tracks[index].name = name
        registerTimelineUndo(L10n.string("Rename Track")) { vm in
            _ = vm.applyTrackName(id: id, name: previous)
        }
        return true
    }

    @discardableResult
    func selectAllClips(onTrack trackId: String) -> Bool {
        guard let track = timeline.tracks.first(where: { $0.id == trackId }),
              !track.clips.isEmpty else { return false }
        selectedGap = nil
        selectedTimelineMarkerIds = []
        selectedClipIds = Set(track.clips.map(\.id))
        return true
    }

    /// Clamp `requested` so that visual (video/image) tracks always sit above every audio track.
    func partitionedInsertionIndex(for type: ClipType, requested: Int) -> Int {
        let z = zones
        let bounded = max(0, min(requested, z.trackCount))
        switch type {
        case .video, .image, .text, .lottie, .sequence, .subtitle:
            // Visual tracks must come at or before the first audio track.
            return min(bounded, z.firstAudioIndex)
        case .audio:
            // Audio tracks must come at or after the first audio track
            return max(bounded, z.firstAudioIndex)
        }
    }

    func removeTrack(id: String) {
        removeTracks(ids: [id])
    }

    // MARK: - Reorder
    /// Instantly move the track with `id` to `targetIndex`, clamped to its track type zone. No undo.
    func reorderTrackLive(id: String, to targetIndex: Int) {
        guard let from = timeline.tracks.firstIndex(where: { $0.id == id }) else { return }
        let z = zones
        let isAudio = timeline.tracks[from].type == .audio
        let lower = isAudio ? z.firstAudioIndex : 0
        let upper = isAudio ? z.trackCount - 1 : z.firstAudioIndex - 1
        let dest = max(lower, min(upper, targetIndex))
        guard dest != from else { return }
        freezeTrackNumbers()
        let track = timeline.tracks.remove(at: from)
        timeline.tracks.insert(track, at: dest)
    }

    /// Register a single undo step for a completed live reorder.
    func commitTrackReorder(before: Timeline) {
        guard before != timeline else { return }
        registerTimelineSwap(undoState: before, redoState: timeline, actionName: "Reorder Track")
        notifyTimelineChanged()
    }

    func removeTracks(ids: [String]) {
        let set = Set(ids)
        guard timeline.tracks.contains(where: { set.contains($0.id) }) else { return }
        withTimelineSwap(actionName: set.count == 1 ? "Remove Track" : "Remove Tracks") {
            timeline.tracks.removeAll { set.contains($0.id) }
        }
    }

    func pruneEmptyTracks() {
        timeline.tracks.removeAll(where: \.clips.isEmpty)
    }

    // MARK: - Flag toggles

    func toggleTrackMute(trackIndex: Int) {
        toggleTrackFlag(trackIndex: trackIndex, keyPath: \.muted, onName: "Mute Track", offName: "Unmute Track")
    }

    func toggleTrackHidden(trackIndex: Int) {
        toggleTrackFlag(trackIndex: trackIndex, keyPath: \.hidden, onName: "Hide Track", offName: "Show Track")
    }

    func toggleTrackSyncLock(trackIndex: Int) {
        if timeline.tracks.indices.contains(trackIndex),
           timeline.tracks[trackIndex].syncLocked,
           let clip = timeline.tracks[trackIndex].clips.first(where: { $0.multicamGroupId != nil }),
           let group = multicamGroup(of: clip) {
            mediaPanelToast = MediaPanelToast(message: L10n.string("Can't unlock sync on a multicam track — \"\(group.name)\" stays aligned through it."))
            NSSound.beep()
            return
        }
        toggleTrackFlag(trackIndex: trackIndex, keyPath: \.syncLocked, onName: "Sync Lock Track", offName: "Unlock Track Sync")
    }

    /// Flip a `Bool` on a track, register a reversing undo, and publish the change.
    /// `onName` is used when the flag transitions false → true; `offName` for true → false.
    private func toggleTrackFlag(
        trackIndex: Int,
        keyPath: WritableKeyPath<Track, Bool>,
        onName: String,
        offName: String
    ) {
        guard timeline.tracks.indices.contains(trackIndex) else { return }
        let trackId = timeline.tracks[trackIndex].id
        let was = timeline.tracks[trackIndex][keyPath: keyPath]
        timeline.tracks[trackIndex][keyPath: keyPath].toggle()
        let actionName = was ? offName : onName
        registerTimelineUndo(actionName) { vm in
            guard let i = vm.timeline.tracks.firstIndex(where: { $0.id == trackId }) else { return }
            vm.timeline.tracks[i][keyPath: keyPath] = was
        }
        notifyTimelineChanged()
    }

    // MARK: - Sizing

    func setTrackHeight(trackIndex: Int, height: CGFloat) {
        guard timeline.tracks.indices.contains(trackIndex) else { return }
        let trackId = timeline.tracks[trackIndex].id
        let prev = timeline.tracks[trackIndex].displayHeight
        timeline.tracks[trackIndex].displayHeight = max(TrackSize.minHeight, min(TrackSize.maxHeight, height))
        registerTimelineUndo("Resize Track") { vm in
            guard let i = vm.timeline.tracks.firstIndex(where: { $0.id == trackId }) else { return }
            vm.setTrackHeight(trackIndex: i, height: prev)
        }
    }
}
