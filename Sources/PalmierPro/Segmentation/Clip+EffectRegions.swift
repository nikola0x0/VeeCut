import Foundation

extension Clip {
    /// Edits the effect stack for `matte`'s region, creating it on demand and dropping it when emptied.
    mutating func updateRegion(matching matte: EffectMatte, _ body: (inout [Effect]) -> Void) {
        var regions = effectRegions ?? []
        let index = regions.firstIndex { $0.matte.targetsSameRegion(as: matte) }
        var effects = index.map { regions[$0].effects } ?? []
        body(&effects)
        if let index {
            if effects.isEmpty {
                regions.remove(at: index)
            } else {
                regions[index].effects = effects
                regions[index].matte = matte
            }
        } else if !effects.isEmpty {
            regions.append(EffectRegion(matte: matte, effects: effects))
        }
        effectRegions = regions.isEmpty ? nil : regions
    }

    /// Edits one region by id, dropping it when its effect stack is emptied.
    mutating func updateRegion(id: String, _ body: (inout EffectRegion) -> Void) {
        guard var regions = effectRegions, let index = regions.firstIndex(where: { $0.id == id }) else { return }
        body(&regions[index])
        if regions[index].effects.isEmpty { regions.remove(at: index) }
        effectRegions = regions.isEmpty ? nil : regions
    }

    mutating func removeRegions(maskId: String) {
        effectRegions?.removeAll { $0.matte.maskId == maskId }
        if effectRegions?.isEmpty == true { effectRegions = nil }
    }
}
