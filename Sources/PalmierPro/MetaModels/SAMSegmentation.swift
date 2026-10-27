import Foundation

/// Half-open pixel bounds in the source media's displayed size.
struct SAMBox: Sendable, Equatable {
    let left: Int
    let top: Int
    let right: Int
    let bottom: Int
    let sourceWidth: Int
    let sourceHeight: Int
}

/// Box-local binary mask; the raster stretches over its object's box.
struct SAMMaskRaster: Sendable, Equatable {
    let width: Int
    let height: Int
    let bits: [UInt8]
}

struct SAMObjectRecord: Sendable, Equatable {
    let objectID: Int
    let box: SAMBox
    let mask: SAMMaskRaster
    let confidence: Double?
    /// The `!`-prefixed one-bit payload as received, kept so masks persist without re-encoding.
    var maskPayload: String = ""
}

struct SAMFrameRecord: Sendable, Equatable {
    let frameIndex: Int
    let objects: [SAMObjectRecord]
}

enum SAMOutputError: Error, Equatable {
    case malformedLine(String)
    case invalidBox
    case invalidMask(SAMMaskCodecError)
}

enum SAMOutputParser {
    /// Parses one `<Nf>`-prefixed output line. Returns nil for non-record text.
    static func parseLine(_ line: String) throws(SAMOutputError) -> SAMFrameRecord? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<"), let headerEnd = trimmed.firstIndex(of: ">") else { return nil }
        let header = trimmed[trimmed.index(after: trimmed.startIndex)..<headerEnd]
        guard let frameDigits = header.split(separator: ";", maxSplits: 1).first,
              frameDigits.hasSuffix("f"),
              let frameIndex = Int(frameDigits.dropLast()), frameIndex >= 0 else { return nil }

        var objects: [SAMObjectRecord] = []
        var rest = trimmed[trimmed.index(after: headerEnd)...]
        while !rest.isEmpty {
            if rest.first == "," { rest = rest.dropFirst() }
            let digits = rest.prefix { $0.isASCII && $0.isNumber }
            guard let objectID = Int(digits) else { throw .malformedLine(line) }
            rest = rest.dropFirst(digits.count)
            var tokens: [Substring: [Substring: Substring]] = [:]
            while rest.hasPrefix("<|"), let close = rest.range(of: "|>") {
                let body = rest[rest.index(rest.startIndex, offsetBy: 2)..<close.lowerBound]
                let parts = body.split(separator: ";")
                if let name = parts.first {
                    tokens[name] = Dictionary(parts.dropFirst().compactMap { field in
                        guard let equals = field.firstIndex(of: "=") else { return nil }
                        return (field[..<equals], field[field.index(after: equals)...])
                    }, uniquingKeysWith: { _, last in last })
                }
                rest = rest[close.upperBound...]
            }
            guard let boxFields = tokens["box"], let maskFields = tokens["mask"] else { throw .malformedLine(line) }
            objects.append(try record(objectID: objectID, box: boxFields, mask: maskFields))
        }
        return SAMFrameRecord(frameIndex: frameIndex, objects: objects)
    }

    private static func record(
        objectID: Int,
        box fields: [Substring: Substring],
        mask maskFields: [Substring: Substring]
    ) throws(SAMOutputError) -> SAMObjectRecord {
        func integer(_ key: Substring) -> Int? { fields[key].flatMap { Int($0) } }
        guard let x1 = integer("x1"), let y1 = integer("y1"), let x2 = integer("x2"), let y2 = integer("y2"),
              let width = integer("w"), let height = integer("h"),
              width > 0, height > 0, x1 >= 0, y1 >= 0, x2 >= x1, y2 >= y1, x2 < width, y2 < height
        else { throw .invalidBox }
        let box = SAMBox(left: x1, top: y1, right: x2 + 1, bottom: y2 + 1, sourceWidth: width, sourceHeight: height)

        guard let data = maskFields["data"] else { throw .invalidMask(.unsupportedEncoding) }
        let parts = data.split(separator: ",", maxSplits: 2)
        guard parts.count == 3, let rows = Int(parts[0]), let columns = Int(parts[1]) else {
            throw .invalidMask(.invalidDimensions)
        }
        let bits: [UInt8]
        do {
            bits = try SAMMaskCodec.decodeOneBit(String(parts[2]), width: columns, height: rows)
        } catch {
            throw .invalidMask(error)
        }
        let confidence = (maskFields["c"] ?? fields["c"]).flatMap { Double($0) }.flatMap { $0.isFinite ? $0 : nil }
        return SAMObjectRecord(
            objectID: objectID,
            box: box,
            mask: SAMMaskRaster(width: columns, height: rows, bits: bits),
            confidence: confidence,
            maskPayload: String(parts[2])
        )
    }
}

/// A point or box that marks one object on one frame, in source pixels.
struct SAMObjectPrompt: Sendable, Equatable {
    struct Point: Sendable, Equatable {
        let x: Int
        let y: Int
        let isPositive: Bool
    }

    let objectID: Int
    let frameIndex: Int
    var points: [Point] = []
    var box: SAMBox?
}

enum SAMPromptBuilder {
    /// Builds the `input_text` grammar for point and box prompts, grouped by frame.
    static func text(for prompts: [SAMObjectPrompt], sourceWidth: Int, sourceHeight: Int) -> String {
        let size = "w=\(sourceWidth);h=\(sourceHeight)"
        let byFrame = Dictionary(grouping: prompts, by: \.frameIndex).sorted { $0.key < $1.key }
        return byFrame.map { frame, framePrompts in
            "<\(frame)f>" + framePrompts.map { prompt in
                var tokens = "\(prompt.objectID)"
                if let box = prompt.box {
                    tokens += "<|box;x1=\(box.left);y1=\(box.top);x2=\(box.right - 1);y2=\(box.bottom - 1);\(size)|>"
                }
                for point in prompt.points {
                    tokens += "\(point.isPositive ? "" : "-")<|point;x=\(point.x);y=\(point.y);\(size)|>"
                }
                return tokens
            }.joined(separator: ",")
        }.joined()
    }
}
