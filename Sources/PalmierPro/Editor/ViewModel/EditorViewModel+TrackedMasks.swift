import Foundation

/// Tracked SAM masks: in-memory registry, save snapshot, and restore on open.
extension EditorViewModel {

    func trackedMask(id: String) -> TrackedMask? {
        trackedMasks.first { $0.id == id }
    }

    func referencedMaskIds() -> Set<String> {
        Set(timelines.flatMap { timeline in
            timeline.tracks.flatMap { track in
                track.clips.flatMap { $0.effectRegions?.map(\.matte.maskId) ?? [] }
            }
        })
    }

    /// Masks referenced by an effect; unreferenced tracking results are not persisted.
    func savedTrackedMasks() -> [TrackedMask]? {
        let referenced = referencedMaskIds()
        let saved = trackedMasks.filter { referenced.contains($0.id) && trackedMaskFiles[$0.id] != nil }
        return saved.isEmpty ? nil : saved
    }

    func trackedMaskFileSnapshot() -> [(name: String, data: Data)] {
        (savedTrackedMasks() ?? []).compactMap { mask in
            trackedMaskFiles[mask.id].map { (name: TrackedMaskFile.fileName(maskId: mask.id), data: $0) }
        }
    }

    func registerTrackedMask(_ mask: TrackedMask, frames: [Int: MaskFrame], file: Data) {
        MatteStore.shared.install(mask, frames: frames)
        trackedMasks.removeAll { $0.id == mask.id }
        trackedMasks.append(mask)
        trackedMaskFiles[mask.id] = file
    }

    /// Decodes saved mask files off-main, then makes them available to the renderer.
    func restoreTrackedMasks(files: [String: Data]) {
        let masks = trackedMasks.filter { files[$0.id] != nil }
        guard !masks.isEmpty else { return }
        Task {
            let decoded = await Self.decodeMaskFiles(masks: masks, files: files)
            for (mask, frames) in decoded where self.trackedMask(id: mask.id) != nil {
                self.registerTrackedMask(mask, frames: frames, file: files[mask.id]!)
            }
            self.notifyTimelineChanged()
        }
    }

    func releaseTrackedMasks() {
        MatteStore.shared.remove(maskIds: trackedMasks.map(\.id))
    }

    @concurrent
    private static func decodeMaskFiles(
        masks: [TrackedMask],
        files: [String: Data]
    ) async -> [(TrackedMask, [Int: MaskFrame])] {
        masks.compactMap { mask in
            guard let data = files[mask.id] else { return nil }
            do {
                return (mask, try TrackedMaskFile.decode(data))
            } catch {
                Log.project.error("tracked mask decode failed mask=\(mask.id) error=\(String(describing: error))")
                return nil
            }
        }
    }
}
