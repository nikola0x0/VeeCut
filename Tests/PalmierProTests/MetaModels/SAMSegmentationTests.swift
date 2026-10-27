import Testing
@testable import PalmierPro

private func raster(width: Int, height: Int, _ isSet: (Int, Int) -> Bool) -> [UInt8] {
    (0..<height).flatMap { y in (0..<width).map { x in isSet(x, y) ? 1 : 0 } }
}

@Test(arguments: [(1, 1), (3, 2), (17, 9), (64, 48), (101, 46)])
func oneBitMaskRoundTrips(width: Int, height: Int) throws {
    let bits = raster(width: width, height: height) { x, y in (x * 7 + y * 3) % 5 < 2 || x == y }
    let payload = try SAMMaskCodec.encodeOneBit(bits, width: width, height: height)
    #expect(payload.first == "!")
    #expect(try SAMMaskCodec.decodeOneBit(payload, width: width, height: height) == bits)
}

@Test func oneBitDecodeRejectsLosslessAndCorruptPayloads() throws {
    #expect(throws: SAMMaskCodecError.unsupportedEncoding) {
        try SAMMaskCodec.decodeOneBit("~00000", width: 2, height: 2)
    }
    let payload = try SAMMaskCodec.encodeOneBit([1, 0, 0, 1], width: 2, height: 2)
    #expect(throws: SAMMaskCodecError.lengthMismatch) {
        try SAMMaskCodec.decodeOneBit(String(payload.dropLast()), width: 2, height: 2)
    }
    #expect(throws: SAMMaskCodecError.invalidDimensions) {
        try SAMMaskCodec.decodeOneBit(payload, width: 0, height: 2)
    }
}

@Test func parserReadsMultiObjectFrameWithHalfOpenBoxes() throws {
    let first = raster(width: 4, height: 3) { x, _ in x < 2 }
    let second = raster(width: 2, height: 2) { _, _ in true }
    let a = try SAMMaskCodec.encodeOneBit(first, width: 4, height: 3)
    let b = try SAMMaskCodec.encodeOneBit(second, width: 2, height: 2)
    let line = "<12f>3<|box;x1=10;y1=20;x2=49;y2=59;w=1920;h=1080;c=0.9|><|mask;x=0;y=0;data=3,4,\(a)|>,"
        + "7<|box;x1=0;y1=0;x2=1;y2=1;w=1920;h=1080|><|mask;x=0;y=0;c=0.5;data=2,2,\(b)|>"

    let frame = try #require(try SAMOutputParser.parseLine(line))

    #expect(frame.frameIndex == 12)
    #expect(frame.objects.map(\.objectID) == [3, 7])
    #expect(frame.objects[0].box == SAMBox(left: 10, top: 20, right: 50, bottom: 60, sourceWidth: 1920, sourceHeight: 1080))
    #expect(frame.objects[0].mask == SAMMaskRaster(width: 4, height: 3, bits: first))
    #expect(frame.objects[0].confidence == 0.9)
    #expect(frame.objects[1].confidence == 0.5)
}

@Test(arguments: ["", "plain text", "<abc>1<|box|>"])
func parserIgnoresNonRecordLines(line: String) throws {
    #expect(try SAMOutputParser.parseLine(line) == nil)
}

@Test func parserRejectsBoxOutsideSource() throws {
    let mask = try SAMMaskCodec.encodeOneBit([1], width: 1, height: 1)
    let line = "<0f>1<|box;x1=0;y1=0;x2=1920;y2=10;w=1920;h=1080|><|mask;x=0;y=0;data=1,1,\(mask)|>"
    #expect(throws: SAMOutputError.invalidBox) { try SAMOutputParser.parseLine(line) }
}

@Test func promptBuilderGroupsObjectsByFrameWithInclusiveBoxes() {
    let box = SAMBox(left: 444, top: 626, right: 676, bottom: 850, sourceWidth: 1800, sourceHeight: 1200)
    let text = SAMPromptBuilder.text(for: [
        SAMObjectPrompt(objectID: 1, frameIndex: 30, points: [.init(x: 585, y: 366, isPositive: true)]),
        SAMObjectPrompt(objectID: 2, frameIndex: 0, points: [.init(x: 5, y: 6, isPositive: false)], box: box),
        SAMObjectPrompt(objectID: 3, frameIndex: 30, points: [.init(x: 1, y: 2, isPositive: true)]),
    ], sourceWidth: 1800, sourceHeight: 1200)

    #expect(text == "<0f>2<|box;x1=444;y1=626;x2=675;y2=849;w=1800;h=1200|>-<|point;x=5;y=6;w=1800;h=1200|>"
        + "<30f>1<|point;x=585;y=366;w=1800;h=1200|>,3<|point;x=1;y=2;w=1800;h=1200|>")
}

@Test func streamEventsYieldFramesFromDeltasAndIgnoreOtherEvents() throws {
    let mask = try SAMMaskCodec.encodeOneBit([1], width: 1, height: 1)
    let line = "<4f>1<|box;x1=0;y1=0;x2=0;y2=0;w=8;h=8|><|mask;x=0;y=0;data=1,1,\(mask)|>"
    let delta = #"data: {"type":"response.output_text.delta","delta":"\#(line)\n"}"#

    #expect(try SAMStreamEvents.frames(fromEventLine: delta).map(\.frameIndex) == [4])
    #expect(try SAMStreamEvents.frames(fromEventLine: "event: response.output_text.delta").isEmpty)
    #expect(try SAMStreamEvents.frames(fromEventLine: #"data: {"type":"response.completed"}"#).isEmpty)
    #expect(try SAMStreamEvents.frames(fromEventLine: "data: [DONE]").isEmpty)
}

@Test func streamEventsSurfaceFailures() {
    #expect(throws: MetaModelError.self) {
        try SAMStreamEvents.frames(fromEventLine: #"data: {"type":"error","message":"quota"}"#)
    }
}
