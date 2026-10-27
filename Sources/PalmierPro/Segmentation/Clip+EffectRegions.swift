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
}
