import CoreGraphics
import Foundation
import Testing
@testable import PalmierPro

@Suite("Subject follow path")
struct SubjectFollowPathTests {
    private func samples(_ points: [(Int, Double, Double)]) -> [SubjectFollowPath.Sample] {
        points.map { SubjectFollowPath.Sample(offset: $0.0, topLeft: CGPoint(x: $0.1, y: $0.2)) }
    }

    @Test func steadyMotionReducesToItsEnds() throws {
        let points: [(Int, Double, Double)] = (0...60).map { ($0, Double($0) * 0.01, 0.3) }
        let track = try #require(SubjectFollowPath.track(samples(points)))
        #expect(track.keyframes.map(\.frame) == [0, 60])
        #expect(track.keyframes.allSatisfy { $0.interpolationOut == .linear })
    }

    @Test func aTurnKeepsTheTurningFrame() throws {
        let points: [(Int, Double, Double)] = (0...40).map { frame in
            let x: Double = frame <= 20 ? Double(frame) * 0.01 : 0.2 - Double(frame - 20) * 0.01
            return (frame, x, 0.5)
        }
        let track = try #require(SubjectFollowPath.track(samples(points)))
        #expect(track.keyframes.contains { abs($0.frame - 20) <= SubjectFollowPath.smoothingRadius })
    }

    @Test func jitterSmallerThanTheToleranceIsNotKeyed() throws {
        let points: [(Int, Double, Double)] = (0...30).map { frame in
            let jitter: Double = frame.isMultiple(of: 2) ? 0.001 : -0.001
            return (frame, 0.4 + jitter, 0.4)
        }
        let track = try #require(SubjectFollowPath.track(samples(points)))
        #expect(track.keyframes.count == 2)
    }
}

@Suite("Subject follow")
@MainActor
struct SubjectFollowTests {
    private let undoManager = UndoManager()

    private func editor(_ tracks: [Track]) -> EditorViewModel {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: tracks)
        editor.undo.attach(undoManager)
        return editor
    }

    private func movingMask(in editor: EditorViewModel) -> TrackedMask {
        Fixtures.movingTrackedMask(in: editor)
    }

    private func textClip(start: Int = 0, duration: Int = 30) -> Clip {
        var clip = Fixtures.clip(id: "text", mediaRef: "", mediaType: .text, start: start, duration: duration)
        clip.transform = Transform(topLeft: (0.1, 0.1), width: 0.2, height: 0.1)
        return clip
    }

    private func center(of clip: Clip, at frame: Int) -> CGPoint {
        let topLeft = clip.topLeftAt(frame: frame), size = clip.sizeAt(frame: frame)
        return CGPoint(x: topLeft.x + size.width / 2, y: topLeft.y + size.height / 2)
    }

    @Test func followerKeepsItsOffsetFromTheSubject() throws {
        let editor = editor([Fixtures.videoTrack(clips: [textClip()]), Fixtures.videoTrack(clips: [Fixtures.clip(id: "video", start: 0, duration: 30)])])
        let mask = movingMask(in: editor)
        let subject = CanvasSubject(clipId: "video", maskId: mask.id)
        let before = try #require(editor.clipFor(id: "text"))
        let video = try #require(editor.clipFor(id: "video"))
        let startBox = try #require(editor.subjectBox(of: mask.id, in: video, at: 0))
        let startOffset = center(of: before, at: 0).x - startBox.midX

        #expect(try editor.followSubject(clipId: "text", subject: subject).get().track.keyframes.count >= 2)

        let followed = try #require(editor.clipFor(id: "text"))
        for frame in [5, 15, 25] {
            let subjectX = try #require(editor.subjectBox(of: mask.id, in: video, at: frame)).midX
            #expect(abs(center(of: followed, at: frame).x - subjectX - startOffset) < 0.005)
        }
    }

    @Test func followingIsOneUndoStep() throws {
        let editor = editor([Fixtures.videoTrack(clips: [textClip()]), Fixtures.videoTrack(clips: [Fixtures.clip(id: "video", start: 0, duration: 30)])])
        let mask = movingMask(in: editor)
        _ = try editor.followSubject(clipId: "text", subject: CanvasSubject(clipId: "video", maskId: mask.id)).get()

        undoManager.undo()

        #expect(editor.clipFor(id: "text")?.positionTrack == nil)
        #expect(!undoManager.canUndo)
    }

    @Test func labelSpansTheSubjectsFramesAboveItsBox() throws {
        let editor = editor([Fixtures.videoTrack(clips: [Fixtures.clip(id: "video", start: 0, duration: 60)])])
        let mask = movingMask(in: editor)

        let id = try editor.addFollowingLabel(for: CanvasSubject(clipId: "video", maskId: mask.id)).get()

        let label = try #require(editor.clipFor(id: id))
        let video = try #require(editor.clipFor(id: "video"))
        #expect(label.textContent == "Cat")
        #expect(label.startFrame == 0 && label.durationFrames == 30)
        let box = try #require(editor.subjectBox(of: mask.id, in: video, at: 10))
        #expect(label.topLeftAt(frame: 10).y + label.sizeAt(frame: 10).height <= box.minY)
        #expect(label.positionTrack != nil)
    }

    @Test(arguments: [
        (Fixtures.clip(id: "text", mediaType: .audio, start: 0, duration: 30), SubjectFollowFailure.notVisual),
        (Fixtures.clip(id: "text", mediaRef: "", mediaType: .text, start: 40, duration: 10), SubjectFollowFailure.noOverlap),
    ])
    func refusesFollowersItCannotKey(follower: Clip, failure: SubjectFollowFailure) {
        let editor = editor([Fixtures.videoTrack(clips: [follower]), Fixtures.videoTrack(clips: [Fixtures.clip(id: "video", start: 0, duration: 30)])])
        let mask = movingMask(in: editor)

        let result = editor.followSubject(clipId: "text", subject: CanvasSubject(clipId: "video", maskId: mask.id))

        #expect(result == .failure(failure))
        #expect(!undoManager.canUndo)
    }
}

@Suite("Subject follow offset")
@MainActor
struct SubjectFollowOffsetTests {
    private let undoManager = UndoManager()

    private func followingEditor() throws -> (EditorViewModel, TrackedMask) {
        var text = Fixtures.clip(id: "text", mediaRef: "", mediaType: .text, start: 0, duration: 30)
        text.transform = Transform(topLeft: (0.1, 0.1), width: 0.2, height: 0.1)
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [text]), Fixtures.videoTrack(clips: [Fixtures.clip(id: "video", start: 0, duration: 30)])])
        editor.undo.attach(undoManager)
        let mask = Fixtures.movingTrackedMask(in: editor)
        _ = try editor.followSubject(clipId: "text", subject: CanvasSubject(clipId: "video", maskId: mask.id)).get()
        return (editor, mask)
    }

    @Test func movingAFollowingClipOnceShiftsItsWholePath() throws {
        let (editor, _) = try followingEditor()
        let before = try #require(editor.clipFor(id: "text"))
        editor.seekToFrame(10)
        let at10 = before.topLeftAt(frame: 10)

        editor.commitTransform(clipId: "text", newTransform: Transform(topLeft: (at10.x + 0.05, at10.y - 0.02), width: 0.2, height: 0.1))

        let after = try #require(editor.clipFor(id: "text"))
        #expect(after.positionTrack?.keyframes.count == before.positionTrack?.keyframes.count)
        for frame in [0, 20, 29] {
            #expect(abs(after.topLeftAt(frame: frame).x - before.topLeftAt(frame: frame).x - 0.05) < 1e-9)
            #expect(abs(after.topLeftAt(frame: frame).y - before.topLeftAt(frame: frame).y + 0.02) < 1e-9)
        }
        #expect(after.subjectFollow?.clipId == "video")
    }

    @Test func positionFieldsShiftTheWholePathToo() throws {
        let (editor, _) = try followingEditor()
        let before = try #require(editor.clipFor(id: "text"))
        editor.seekToFrame(5)

        editor.commitPositions(clipIds: ["text"], setX: before.topLeftAt(frame: 5).x + 0.1, setY: nil)

        let after = try #require(editor.clipFor(id: "text"))
        #expect(abs(after.topLeftAt(frame: 25).x - before.topLeftAt(frame: 25).x - 0.1) < 1e-9)
    }

    @Test func stoppingFollowingDropsTheLinkAndPath() throws {
        let (editor, _) = try followingEditor()
        editor.stopFollowing(clipId: "text")
        let clip = try #require(editor.clipFor(id: "text"))
        #expect(clip.subjectFollow == nil && clip.positionTrack == nil)
    }
}

@Suite("Subject follow spot")
@MainActor
struct SubjectFollowSpotTests {
    private let undoManager = UndoManager()

    /// A 64×48 subject whose box stays anchored at x = 8 and widens by 1 px per frame from 16 px, present on frames 0…29.
    private func stretchingMask(in editor: EditorViewModel) -> TrackedMask {
        let mask = TrackedMask(id: UUID().uuidString, mediaRef: "media-1", label: "Cat", sourceFPS: 30, sourceWidth: 64, sourceHeight: 48)
        let frames = Dictionary(uniqueKeysWithValues: (0..<30).map { index in
            let box = SAMBox(left: 8, top: 16, right: 24 + index, bottom: 32, sourceWidth: 64, sourceHeight: 48)
            return (index, MaskFrame(SAMObjectRecord(objectID: 1, box: box, mask: SAMMaskRaster(width: 1, height: 1, bits: [1]), confidence: nil)))
        })
        editor.registerTrackedMask(mask, frames: frames, file: Data())
        return mask
    }

    private func setUp() -> (EditorViewModel, TrackedMask) {
        var text = Fixtures.clip(id: "text", mediaRef: "", mediaType: .text, start: 0, duration: 30)
        text.transform = Transform(topLeft: (0, 0), width: 0.1, height: 0.05)
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [text]), Fixtures.videoTrack(clips: [Fixtures.clip(id: "video", start: 0, duration: 30)])])
        editor.undo.attach(undoManager)
        return (editor, stretchingMask(in: editor))
    }

    private func center(_ editor: EditorViewModel, at frame: Int) throws -> CGPoint {
        let clip = try #require(editor.clipFor(id: "text"))
        let topLeft = clip.topLeftAt(frame: frame), size = clip.sizeAt(frame: frame)
        return CGPoint(x: topLeft.x + size.width / 2, y: topLeft.y + size.height / 2)
    }

    private func box(_ editor: EditorViewModel, _ mask: TrackedMask, at frame: Int) throws -> CGRect {
        let video = try #require(editor.clipFor(id: "video"))
        return try #require(editor.subjectBox(of: mask.id, in: video, at: frame))
    }

    @Test func followerKeepsItsSpotOfAStretchingBox() throws {
        let (editor, mask) = setUp()
        let start = try box(editor, mask, at: 0)
        editor.commitTransform(clipId: "text", newTransform: Transform(center: (start.maxX, start.midY), width: 0.1, height: 0.05))
        _ = try editor.followSubject(clipId: "text", subject: CanvasSubject(clipId: "video", maskId: mask.id)).get()

        for frame in [10, 20, 29] {
            let stretched = try box(editor, mask, at: frame)
            #expect(abs(try center(editor, at: frame).x - stretched.maxX) < 0.01)
        }
    }

    @Test func draggingAtAnyFrameResetsTheSpotForTheWholeClip() throws {
        let (editor, mask) = setUp()
        _ = try editor.followSubject(clipId: "text", subject: CanvasSubject(clipId: "video", maskId: mask.id), placement: .center).get()
        editor.seekToFrame(20)
        let at20 = try box(editor, mask, at: 20)

        editor.commitTransform(clipId: "text", newTransform: Transform(center: (at20.minX, at20.minY), width: 0.1, height: 0.05))

        let link = try #require(editor.clipFor(id: "text")?.subjectFollow)
        #expect(abs(link.anchorX) < 0.02 && abs(link.anchorY) < 0.02)
        let at5 = try box(editor, mask, at: 5)
        #expect(abs(try center(editor, at: 5).x - at5.minX) < 0.01)
        #expect(abs(try center(editor, at: 5).y - at5.minY) < 0.01)
    }

    @Test func pickingAGridSpotMovesTheClipToThatSpotOfTheBox() throws {
        let (editor, mask) = setUp()
        _ = try editor.followSubject(clipId: "text", subject: CanvasSubject(clipId: "video", maskId: mask.id), placement: .center).get()

        editor.setFollowAnchor(clipId: "text", anchor: CGPoint(x: 0.5, y: 0))

        for frame in [0, 15, 29] {
            let current = try box(editor, mask, at: frame)
            #expect(abs(try center(editor, at: frame).x - current.midX) < 0.01)
            #expect(abs(try center(editor, at: frame).y - current.minY) < 0.01)
        }
        undoManager.undo()
        #expect(abs((editor.clipFor(id: "text")?.subjectFollow?.anchorY ?? -1) - 0.5) < 1e-9)
    }
}


@Test func followLinkSurvivesSaveAndReopen() throws {
    var clip = Fixtures.clip(id: "sticker", mediaRef: "art", mediaType: .image, start: 0, duration: 30)
    clip.subjectFollow = SubjectFollowLink(clipId: "video", maskId: "mask", anchorX: 0.5, anchorY: -0.1)
    clip.positionTrack = KeyframeTrack(keyframes: [Keyframe(frame: 0, value: AnimPair(a: 0.2, b: 0.3), interpolationOut: .linear)])

    let reopened = try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(clip))

    #expect(reopened.subjectFollow == clip.subjectFollow)
    #expect(reopened.positionTrack == clip.positionTrack)
}
