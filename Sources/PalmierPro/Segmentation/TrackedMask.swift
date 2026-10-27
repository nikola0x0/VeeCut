import Foundation

/// One SAM-tracked object in a source video. Immutable: refining creates a new mask.
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
}

/// Limits a region's effects to the inside (or outside) of a tracked mask.
struct EffectMatte: Codable, Sendable, Equatable {
    var maskId: String
    var invert: Bool = false
    /// Edge softness in source pixels.
    var feather: Double = 0

    func targetsSameRegion(as other: EffectMatte) -> Bool {
        maskId == other.maskId && invert == other.invert
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
