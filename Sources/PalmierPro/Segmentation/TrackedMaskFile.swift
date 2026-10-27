import Foundation

/// `masks/<id>.samtrack`: one SAM output line per frame for a single tracked object.
enum TrackedMaskFile {
    static let directoryName = "masks"

    static func fileName(maskId: String) -> String { "\(maskId).samtrack" }

    static func encode(_ frames: [Int: MaskFrame]) -> Data {
        let lines = frames.sorted { $0.key < $1.key }.map { index, frame in
            let box = frame.box
            return "<\(index)f>1<|box;x1=\(box.left);y1=\(box.top);x2=\(box.right - 1);y2=\(box.bottom - 1);"
                + "w=\(box.sourceWidth);h=\(box.sourceHeight)|><|mask;x=0;y=0;data=\(frame.height),\(frame.width),\(frame.payload)|>"
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    static func decode(_ data: Data) throws(SAMOutputError) -> [Int: MaskFrame] {
        var frames: [Int: MaskFrame] = [:]
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            guard let record = try SAMOutputParser.parseLine(String(line)), let object = record.objects.first else { continue }
            frames[record.frameIndex] = MaskFrame(object)
        }
        return frames
    }
}
