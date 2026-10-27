import Foundation

/// One subject in a source video: an object SAM tracked, or a static area the user drew.
/// Immutable apart from its label: refining creates a new mask.
struct TrackedMask: Codable, Sendable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var mediaRef: String
    var label: String
    /// Frame rate SAM indexed frames at; maps source seconds to SAM frame indices.
    var sourceFPS: Double
    /// Source time of SAM frame 0 (the start of the excerpt sent for tracking).
    var sourceStartSeconds: Double = 0
    /// Display-oriented pixel size SAM coordinates refer to.
    var sourceWidth: Int
    var sourceHeight: Int
    /// A drawn area's closed outline in display-oriented source coordinates, 0…1 from the top left.
    /// Nil for SAM-tracked masks.
    var area: [CGPoint]?

    /// Drawn areas rasterize at this square size; the renderer scales it to the source.
    static let areaRasterSize = 2048

    static func drawnArea(outline: [CGPoint], mediaRef: String, label: String) -> TrackedMask {
        TrackedMask(mediaRef: mediaRef, label: label, sourceFPS: 0,
                    sourceWidth: areaRasterSize, sourceHeight: areaRasterSize, area: outline)
    }

    var isDrawnArea: Bool { area != nil }
}

/// Limits a region's effects to the inside (or outside) of a tracked mask.
struct EffectMatte: Codable, Sendable, Equatable {
    var maskId: String
    /// More subjects covered together with `maskId`; an inverted matte keeps all of them out.
    var additionalMaskIds: [String]?
    var invert: Bool = false
    /// Edge softness in source pixels.
    var feather: Double = 0

    static let featherRange: ClosedRange<Double> = 0...50

    init(maskIds: [String], invert: Bool = false, feather: Double = 0) {
        precondition(!maskIds.isEmpty)
        maskId = maskIds[0]
        additionalMaskIds = maskIds.count > 1 ? Array(maskIds.dropFirst()) : nil
        self.invert = invert
        self.feather = feather
    }

    init(maskId: String, invert: Bool = false, feather: Double = 0) {
        self.init(maskIds: [maskId], invert: invert, feather: feather)
    }

    var maskIds: [String] { [maskId] + (additionalMaskIds ?? []) }

    /// A clip has one background (inverted) region shared by all subjects, and one inside region per subject.
    func targetsSameRegion(as other: EffectMatte) -> Bool {
        invert == other.invert && (invert || maskId == other.maskId)
    }

    /// Joining an existing region: a background gains the new subjects, everything else takes the new settings.
    func merged(into existing: EffectMatte) -> EffectMatte {
        guard invert, existing.invert else { return self }
        var ids = existing.maskIds
        for id in maskIds where !ids.contains(id) { ids.append(id) }
        return EffectMatte(maskIds: ids, invert: true, feather: feather)
    }

    /// Without `maskId`; nil when nothing would be left.
    func removing(_ maskId: String) -> EffectMatte? {
        let ids = maskIds.filter { $0 != maskId }
        guard !ids.isEmpty else { return nil }
        return EffectMatte(maskIds: ids, invert: invert, feather: feather)
    }
}

/// An effect stack applied only within a matte, after the clip's whole-frame effects.
struct EffectRegion: Codable, Sendable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var matte: EffectMatte
    var effects: [Effect]
}

/// Per-frame box-local mask, packed one bit per pixel, row-major from the top row.
struct MaskFrame: Sendable, Equatable {
    let box: SAMBox
    let width: Int
    let height: Int
    let packedBits: [UInt8]
    let payload: String

    init(_ object: SAMObjectRecord) {
        box = object.box
        width = object.mask.width
        height = object.mask.height
        payload = object.maskPayload.isEmpty
            ? (try? SAMMaskCodec.encodeOneBit(object.mask.bits, width: width, height: height)) ?? ""
            : object.maskPayload
        var packed = [UInt8](repeating: 0, count: (object.mask.bits.count + 7) / 8)
        for (index, bit) in object.mask.bits.enumerated() where bit != 0 {
            packed[index >> 3] |= 0x80 >> UInt8(index & 7)
        }
        packedBits = packed
    }

    /// 8-bit coverage raster (0 or 255), one byte per pixel.
    func coverage() -> Data {
        var bytes = Data(count: width * height)
        bytes.withUnsafeMutableBytes { buffer in
            for index in 0..<(width * height) where packedBits[index >> 3] & (0x80 >> UInt8(index & 7)) != 0 {
                buffer[index] = 255
            }
        }
        return bytes
    }
}
