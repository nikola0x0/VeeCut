import CoreGraphics
import Foundation
import ImageIO
import Testing
import Synchronization
import UniformTypeIdentifiers
@testable import PalmierPro

enum StickerFixtures {
    /// PNG bytes of a red disc on white, the kind of flat-background drawing Muse Image returns.
    @concurrent
    static func discOnWhite(size: Int = 256, drawsDisc: Bool = true) async throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        if drawsDisc {
            context.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1))
            let inset = CGFloat(size) / 4
            context.fillEllipse(in: CGRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2))
        }
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// A staged transparent sticker PNG, as the sticker maker hands back.
    @concurrent
    static func staged(width: Int = 40, height: Int = 20) async throws -> StickerImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0.8, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let url = FileManager.default.temporaryDirectory.appending(path: "sticker-test-\(UUID().uuidString).png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return StickerImage(stagedURL: url, width: width, height: height)
    }

    @concurrent
    static func makePackage() async throws -> (root: URL, package: URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "stickers-\(UUID().uuidString)", directoryHint: .isDirectory)
        let package = root.appending(path: "Stickers.veecut", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: package.appending(path: Project.mediaDirectoryName, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        return (root, package)
    }

    @concurrent
    static func remove(_ url: URL) async {
        try? FileManager.default.removeItem(at: url)
    }

    @concurrent
    static func fileExists(_ url: URL) async -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

@Suite("Sticker cut-out")
struct StickerCutOutTests {
    @Test func liftsTheDrawingOffItsFlatBackgroundWithTransparency() async throws {
        let image = try StickerMaker.cutOut(try await StickerFixtures.discOnWhite())
        defer { try? FileManager.default.removeItem(at: image.stagedURL) }

        #expect(image.width < 256 && image.height < 256)
        let source = try #require(CGImageSourceCreateWithURL(image.stagedURL as CFURL, nil))
        let cgImage = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(cgImage.alphaInfo != .none && cgImage.alphaInfo != .noneSkipLast && cgImage.alphaInfo != .noneSkipFirst)
    }
}

@Suite("Stickers", .serialized)
@MainActor
struct StickerTests {
    private let undoManager = UndoManager()

    private func editor(package: URL, tracks: [Track] = [Fixtures.videoTrack(clips: [Fixtures.clip(id: "video", start: 0, duration: 60)])]) -> EditorViewModel {
        let editor = EditorViewModel()
        editor.projectURL = package
        editor.timeline = Fixtures.timeline(tracks: tracks)
        editor.undo.attach(undoManager)
        editor.stickerImageSource = { _ in try await StickerFixtures.staged() }
        return editor
    }

    @Test func stickerWithoutASubjectSitsCenteredAtThePlayheadInOneUndoStep() async throws {
        let (root, package) = try await StickerFixtures.makePackage()
        let editor = editor(package: package)
        editor.seekToFrame(12)

        let receipt = try await editor.addSticker(description: "crown", subject: nil)

        let clip = try #require(editor.clipFor(id: receipt.clipId))
        #expect(clip.mediaType == .image && clip.startFrame == 12)
        #expect(abs(clip.transform.centerX - 0.5) < 0.0001 && abs(clip.transform.height - EditorViewModel.stickerHeight) < 0.0001)
        #expect(clip.positionTrack == nil)
        let asset = try #require(editor.mediaAssets.first { $0.id == receipt.assetId })
        #expect(asset.url.path.hasPrefix(package.path))
        #expect(await StickerFixtures.fileExists(asset.url))

        undoManager.undo()
        #expect(editor.clipFor(id: receipt.clipId) == nil)
        #expect(!editor.mediaAssets.contains { $0.id == receipt.assetId })
        #expect(!undoManager.canUndo)
        await StickerFixtures.remove(root)
    }

    @Test func stickerOnASubjectSpansItsFramesAndSitsOnItsTopEdge() async throws {
        let (root, package) = try await StickerFixtures.makePackage()
        let editor = editor(package: package)
        let mask = Fixtures.movingTrackedMask(in: editor)
        let subject = CanvasSubject(clipId: "video", maskId: mask.id)

        let receipt = try await editor.addSticker(description: "crown", subject: subject)

        #expect(receipt.followFailure == nil)
        let clip = try #require(editor.clipFor(id: receipt.clipId))
        let video = try #require(editor.clipFor(id: "video"))
        #expect(clip.startFrame == 0 && clip.durationFrames == 30)
        for frame in [0, 15, 29] {
            let box = try #require(editor.subjectBox(of: mask.id, in: video, at: frame))
            let topLeft = clip.topLeftAt(frame: frame), size = clip.sizeAt(frame: frame)
            #expect(abs(topLeft.x + size.width / 2 - box.midX) < 0.005)
            #expect(abs(topLeft.y + size.height - box.minY) < 0.005)
            #expect(abs(size.width - box.width * EditorViewModel.stickerSubjectWidth) < 0.005)
        }
        editor.releaseTrackedMasks()
        await StickerFixtures.remove(root)
    }

    @Test func aStickerOnASubjectAtTheTopOfTheFrameStaysAtLeastHalfInView() {
        let editor = EditorViewModel()

        let layout = editor.stickerLayout(imageWidth: 100, imageHeight: 100, on: CGRect(x: 0.3, y: 0.02, width: 0.4, height: 0.5))

        #expect(abs(layout.centerY) < 0.0001)
    }

    @Test func fullFrameStickerCanFollowAnObjectInTheVideoUnderIt() async throws {
        let (root, package) = try await StickerFixtures.makePackage()
        let editor = editor(package: package)
        let mask = Fixtures.movingTrackedMask(in: editor)
        editor.seekToFrame(5)

        let receipt = try await editor.addSticker(description: "crown", subject: nil)

        #expect(editor.followableSubjects(for: receipt.clipId).map(\.mask.id) == [mask.id])
        editor.releaseTrackedMasks()
        await StickerFixtures.remove(root)
    }

    @Test func subjectThatNeverShowsFailsBeforeDrawing() async throws {
        let (root, package) = try await StickerFixtures.makePackage()
        let editor = editor(package: package)
        let mask = Fixtures.trackedMask(in: editor, presentAt: [])
        let drew = Mutex(false)
        editor.stickerImageSource = { _ in
            drew.withLock { $0 = true }
            return try await StickerFixtures.staged()
        }

        await #expect(throws: StickerFailure.subject(.subjectAbsent)) {
            try await editor.addSticker(description: "crown", subject: CanvasSubject(clipId: "video", maskId: mask.id))
        }
        #expect(!drew.withLock { $0 })
        #expect(!undoManager.canUndo)
        editor.releaseTrackedMasks()
        await StickerFixtures.remove(root)
    }
}

/// Opt in with VEECUT_LIVE_MUSE=1 and MODEL_API_KEY. Draws one sticker with Muse Image ($0.01) and cuts it out.
@Suite("Live — Muse Image sticker", .enabled(if: ProcessInfo.processInfo.environment["VEECUT_LIVE_MUSE"] == "1"))
struct LiveStickerTests {
    @Test func drawsAndCutsOutASticker() async throws {
        let key = try #require(ProcessInfo.processInfo.environment["MODEL_API_KEY"])
        let image = try await StickerMaker.make("cartoon golden crown", client: MetaModelClient(apiKey: key))
        defer { try? FileManager.default.removeItem(at: image.stagedURL) }
        #expect(image.width > 100 && image.height > 100)
    }
}

@Suite("Sticker flat background")
struct StickerFlatBackgroundTests {
    @Test func clearsTheBackgroundAroundTheDrawingAndCropsToIt() async throws {
        let image = try StickerMaker.clearingFlatBackground(try await StickerFixtures.discOnWhite(size: 256))
        #expect(abs(image.extent.width - 128) <= 2 && abs(image.extent.height - 128) <= 2)
    }

    @Test func anImageThatIsAllBackgroundHasNothingToCutOut() async throws {
        let blank = try await StickerFixtures.discOnWhite(drawsDisc: false)
        #expect(throws: StickerError.nothingToCutOut) { try StickerMaker.clearingFlatBackground(blank) }
    }
}
