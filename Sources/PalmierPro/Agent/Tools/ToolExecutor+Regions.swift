import Foundation

extension ToolExecutor {
    struct RegionInput: Decodable {
        let maskId: String
        let side: String?
        let feather: Double?
    }

    /// Validates a region against the target clips before any mutation.
    func resolveRegion(_ input: RegionInput?, clipIds: [String], editor: EditorViewModel, path: String) throws -> EffectMatte? {
        guard let input else { return nil }
        guard let mask = editor.trackedMask(id: input.maskId) else {
            throw ToolError("\(path).region: unknown maskId '\(input.maskId)'. Call track_object first.")
        }
        let invert: Bool
        switch input.side ?? "inside" {
        case "inside": invert = false
        case "outside": invert = true
        case let other: throw ToolError("\(path).region.side must be 'inside' or 'outside', got '\(other)'.")
        }
        let feather = input.feather ?? 0
        guard feather.isFinite, EffectMatte.featherRange.contains(feather) else {
            throw ToolError("\(path).region.feather must be between 0 and 50.")
        }
        for id in clipIds {
            guard let clip = editor.clipFor(id: id), clip.mediaRef == mask.mediaRef else {
                throw ToolError("\(path).region: mask '\(mask.id)' tracks media \(mask.mediaRef); clip \(id) uses different media.")
            }
        }
        return EffectMatte(maskId: mask.id, invert: invert, feather: feather)
    }
}
