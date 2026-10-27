// Copyright (c) Meta Platforms, Inc. and affiliates. All Rights Reserved.
// Swift port of the one-bit mask codec from meta-sam-parser 0.1.0.
// Licensed under the SAM License (ThirdPartyLicenses/SAM-LICENSE.txt), not GPLv3.

import Foundation

enum SAMMaskCodecError: Error, Equatable {
    case unsupportedEncoding
    case invalidCharacter
    case missingLengthPrefix
    case lengthMismatch
    case outOfRangeGroup
    case truncated
    case invalidCodingState
    case invalidDimensions
}

enum SAMMaskCodec {
    /// Decodes a `!`-prefixed one-bit payload into a row-major raster of 0/1 values.
    static func decodeOneBit(_ payload: String, width: Int, height: Int) throws(SAMMaskCodecError) -> [UInt8] {
        guard width > 0, height > 0, width <= 1 << 15, height <= 1 << 15 else { throw .invalidDimensions }
        guard payload.first == "!" else { throw .unsupportedEncoding }
        var decoder = try RangeDecoder(bytes: try Base85.unpack(payload.dropFirst()))
        var model = ContextModel(width: width, height: height)
        var output = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = model.contextOffset(x: x, y: y)
                let zero = Int(model.counts[offset])
                let one = Int(model.counts[offset + 1])
                let bit: UInt8 = try decoder.frequency(total: zero + one) < zero ? 0 : 1
                if bit == 0 {
                    try decoder.decode(cumulative: 0, frequency: zero)
                } else {
                    try decoder.decode(cumulative: zero, frequency: one)
                }
                model.record(bit, x: x, y: y, offset: offset)
                output[y * width + x] = bit
            }
        }
        return output
    }

    /// Encodes a row-major 0/1 raster as a `!`-prefixed one-bit payload.
    static func encodeOneBit(_ raster: [UInt8], width: Int, height: Int) throws(SAMMaskCodecError) -> String {
        guard width > 0, height > 0, raster.count == width * height else { throw .invalidDimensions }
        var encoder = RangeEncoder()
        var model = ContextModel(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = model.contextOffset(x: x, y: y)
                let zero = Int(model.counts[offset])
                let one = Int(model.counts[offset + 1])
                let bit: UInt8 = raster[y * width + x] == 0 ? 0 : 1
                if bit == 0 {
                    encoder.encode(cumulative: 0, frequency: zero, total: zero + one)
                } else {
                    encoder.encode(cumulative: zero, frequency: one, total: zero + one)
                }
                model.record(bit, x: x, y: y, offset: offset)
            }
        }
        return "!" + (try Base85.pack(encoder.finish()))
    }
}

private struct ContextModel {
    private static let padding = 2
    private static let increment: UInt16 = 14
    private static let countLimit = 4096
    private static let contextCount = 1 << 12

    var counts = [UInt16](repeating: 1, count: contextCount * 2)
    private var padded: [UInt8]
    private let paddedWidth: Int

    init(width: Int, height: Int) {
        paddedWidth = width + 2 * Self.padding
        padded = [UInt8](repeating: 0, count: paddedWidth * (height + Self.padding))
    }

    private func position(x: Int, y: Int) -> Int {
        (y + Self.padding) * paddedWidth + Self.padding + x
    }

    func contextOffset(x: Int, y: Int) -> Int {
        let p = position(x: x, y: y)
        let prior = p - paddedWidth
        let earlier = p - 2 * paddedWidth
        let r = padded
        let context = Int(r[p - 1])
            | Int(r[p - 2]) << 1
            | Int(r[prior - 2]) << 2
            | Int(r[prior - 1]) << 3
            | Int(r[prior]) << 4
            | Int(r[prior + 1]) << 5
            | Int(r[prior + 2]) << 6
            | Int(r[earlier - 2]) << 7
            | Int(r[earlier - 1]) << 8
            | Int(r[earlier]) << 9
            | Int(r[earlier + 1]) << 10
            | Int(r[earlier + 2]) << 11
        return context << 1
    }

    mutating func record(_ bit: UInt8, x: Int, y: Int, offset: Int) {
        padded[position(x: x, y: y)] = bit
        counts[offset + Int(bit)] &+= Self.increment
        if Int(counts[offset]) + Int(counts[offset + 1]) >= Self.countLimit {
            counts[offset] = max(counts[offset] >> 1, 1)
            counts[offset + 1] = max(counts[offset + 1] >> 1, 1)
        }
    }
}

private let rangeTop: UInt32 = 1 << 24
private let rangeBottom: UInt32 = 1 << 16

private struct RangeEncoder {
    private var low: UInt32 = 0
    private var range: UInt32 = .max
    private var output: [UInt8] = []

    mutating func encode(cumulative: Int, frequency: Int, total: Int) {
        let scaled = range / UInt32(total)
        low = low &+ scaled &* UInt32(cumulative)
        range = scaled &* UInt32(frequency)
        while true {
            if (low ^ (low &+ range)) < rangeTop {
            } else if range < rangeBottom {
                range = (0 &- low) & (rangeBottom - 1)
            } else {
                break
            }
            output.append(UInt8(low >> 24))
            low = low << 8
            range = range << 8
        }
    }

    mutating func finish() -> [UInt8] {
        for _ in 0..<4 {
            output.append(UInt8(low >> 24))
            low = low << 8
        }
        return output
    }
}

private struct RangeDecoder {
    private let bytes: [UInt8]
    private var position = 0
    private var low: UInt32 = 0
    private var range: UInt32 = .max
    private var code: UInt32 = 0
    private var scaled: UInt32 = 0

    init(bytes: [UInt8]) throws(SAMMaskCodecError) {
        guard bytes.count >= 4 else { throw .truncated }
        self.bytes = bytes
        for _ in 0..<4 { code = (code << 8) | UInt32(try read()) }
    }

    mutating func frequency(total: Int) throws(SAMMaskCodecError) -> Int {
        scaled = range / UInt32(total)
        guard scaled > 0 else { throw .invalidCodingState }
        let value = Int((code &- low) / scaled)
        return min(value, total - 1)
    }

    mutating func decode(cumulative: Int, frequency: Int) throws(SAMMaskCodecError) {
        low = low &+ scaled &* UInt32(cumulative)
        range = scaled &* UInt32(frequency)
        while true {
            if (low ^ (low &+ range)) < rangeTop {
            } else if range < rangeBottom {
                range = (0 &- low) & (rangeBottom - 1)
            } else {
                break
            }
            code = (code << 8) | UInt32(try read())
            low = low << 8
            range = range << 8
        }
    }

    private mutating func read() throws(SAMMaskCodecError) -> UInt8 {
        guard position < bytes.count else { throw .truncated }
        defer { position += 1 }
        return bytes[position]
    }
}

private enum Base85 {
    static let radix = 85
    static let prefixLength = 5
    static let alphabet: [UInt8] = (0x21..<0x7F).compactMap { code in
        let character = UInt8(code)
        return Array("\"\\,;<>|".utf8).contains(character) ? nil : character
    }
    static let values: [Int] = {
        var table = [Int](repeating: -1, count: 128)
        for (index, character) in alphabet.enumerated() where index < radix { table[Int(character)] = index }
        return table
    }()

    static func digit(_ character: UInt8) throws(SAMMaskCodecError) -> UInt64 {
        guard character < 128, values[Int(character)] >= 0 else { throw .invalidCharacter }
        return UInt64(values[Int(character)])
    }

    static func unpack(_ payload: Substring) throws(SAMMaskCodecError) -> [UInt8] {
        let characters = Array(payload.utf8)
        guard characters.count >= prefixLength else { throw .missingLengthPrefix }
        var length = 0
        for character in characters[..<prefixLength] { length = length * radix + Int(try digit(character)) }
        let remainder = length % 4
        guard characters.count == prefixLength + (length / 4) * 5 + (remainder == 0 ? 0 : remainder + 1) else {
            throw .lengthMismatch
        }
        var output = [UInt8](repeating: 0, count: length)
        var source = prefixLength
        var destination = 0
        while destination < length - remainder {
            var value: UInt64 = 0
            for index in 0..<5 { value = value * UInt64(radix) + (try digit(characters[source + index])) }
            guard value <= UInt64(UInt32.max) else { throw .outOfRangeGroup }
            for index in 0..<4 { output[destination + index] = UInt8((value >> UInt64(24 - index * 8)) & 0xFF) }
            source += 5
            destination += 4
        }
        if remainder > 0 {
            var value: UInt64 = 0
            for index in 0..<5 {
                let digitValue = index < remainder + 1 ? try digit(characters[source + index]) : UInt64(radix - 1)
                value = value * UInt64(radix) + digitValue
            }
            guard value <= UInt64(UInt32.max) else { throw .outOfRangeGroup }
            for index in 0..<remainder { output[destination + index] = UInt8((value >> UInt64(24 - index * 8)) & 0xFF) }
        }
        return output
    }

    static func pack(_ input: [UInt8]) throws(SAMMaskCodecError) -> String {
        var remaining = input.count
        var prefix = [UInt8](repeating: 0, count: prefixLength)
        for index in stride(from: prefixLength - 1, through: 0, by: -1) {
            prefix[index] = alphabet[remaining % radix]
            remaining /= radix
        }
        guard remaining == 0 else { throw .lengthMismatch }
        var output = prefix
        let full = input.count - input.count % 4
        var offset = 0
        func digits(_ value: UInt32) -> [UInt8] {
            var value = value
            var result = [UInt8](repeating: 0, count: 5)
            for index in stride(from: 4, through: 0, by: -1) {
                result[index] = alphabet[Int(value % UInt32(radix))]
                value /= UInt32(radix)
            }
            return result
        }
        while offset < full {
            let value = UInt32(input[offset]) << 24 | UInt32(input[offset + 1]) << 16
                | UInt32(input[offset + 2]) << 8 | UInt32(input[offset + 3])
            output += digits(value)
            offset += 4
        }
        let remainder = input.count - offset
        if remainder > 0 {
            var value: UInt32 = 0
            for index in 0..<4 { value = value << 8 | UInt32(index < remainder ? input[offset + index] : 0) }
            output += digits(value).prefix(remainder + 1)
        }
        return String(decoding: output, as: UTF8.self)
    }
}
