import Foundation

/// What Vee offers for the one selected video clip.
enum VeeSuggestions {
    /// `canCutPauses`: the clip has its linked audio and this build can analyze speech.
    static func kinds(for clip: Clip, note: FootageNote?, canCutPauses: Bool, offBeatSectionId: String?) -> [VeeAction.Kind] {
        guard clip.mediaType == .video else { return [] }
        var kinds: [VeeAction.Kind] = []
        if note?.wantsTranscript == true {
            let smoothed = clip.effectRegions?.contains { $0.effects.contains { $0.type == EditorViewModel.smoothSkinEffect } } == true
            if !smoothed { kinds.append(.smoothSkin(clipId: clip.id)) }
            kinds.append(.addCaptions(clipId: clip.id))
            if canCutPauses { kinds.append(.cutPauses(clipId: clip.id)) }
        }
        if let offBeatSectionId { kinds.append(.snapToBeat(sectionId: offBeatSectionId)) }
        return kinds
    }
}
