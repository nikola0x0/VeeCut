import CoreImage
import Foundation
import Testing
@testable import PalmierPro

@Suite("SkinSmoothingKernel")
struct SkinSmoothingKernelTests {
    private let ctx = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    private let n = 96
    private static let skin: SIMD3<Float> = [0.85, 0.65, 0.53]
    private static let gray: SIMD3<Float> = [0.55, 0.55, 0.55]

    /// Pore-sized ±0.04 texture in 2×2 blocks over a flat color.
    private static func textured(_ color: SIMD3<Float>, _ x: Int, _ y: Int) -> SIMD3<Float> {
        color + ((x / 2 + y / 2) % 2 == 0 ? 0.04 : -0.04)
    }

    private func image(_ color: (Int, Int) -> SIMD3<Float>) -> CIImage {
        var px = [Float](repeating: 1, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let c = color(x, y), i = (y * n + x) * 4
                px[i] = c.x; px[i + 1] = c.y; px[i + 2] = c.z
            }
        }
        let data = px.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(bitmapData: data, bytesPerRow: n * 16, size: CGSize(width: n, height: n), format: .RGBAf, colorSpace: nil)
    }

    private func pixels(_ image: CIImage) -> [SIMD3<Float>] {
        var px = [Float](repeating: 0, count: n * n * 4)
        ctx.render(image, toBitmap: &px, rowBytes: n * 16, bounds: CGRect(x: 0, y: 0, width: n, height: n), format: .RGBAf, colorSpace: nil)
        return stride(from: 0, to: px.count, by: 4).map { SIMD3(px[$0], px[$0 + 1], px[$0 + 2]) }
    }

    private func smoothed(_ img: CIImage, amount: Double = 1, blemishes: Double = 0) -> [SIMD3<Float>] {
        pixels(SkinSmoothingKernel.apply(img, extent: img.extent, amount: amount, blemishes: blemishes))
    }

    /// Spread of green over the interior rows, away from the borders.
    private func spread(_ px: [SIMD3<Float>]) -> Float {
        let values = (16..<(n - 16)).flatMap { y in (16..<(n - 16)).map { px[y * n + $0].y } }
        let mean = values.reduce(0, +) / Float(values.count)
        return (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(values.count)).squareRoot()
    }

    @Test func zeroAmountLeavesTheImageUntouched() {
        let img = image { Self.textured(Self.skin, $0, $1) }
        #expect(pixels(img) == smoothed(img, amount: 0))
    }

    @Test func reducesSkinTextureButKeepsSomeOfIt() {
        let img = image { Self.textured(Self.skin, $0, $1) }
        let before = spread(pixels(img)), after = spread(smoothed(img))
        #expect(after < before * 0.75)
        #expect(after > before * 0.2)
    }

    @Test func doesNotBrightenOrDrainTheSkin() {
        let img = image { Self.textured(Self.skin, $0, $1) }
        let before = Self.mean(pixels(img)), after = Self.mean(smoothed(img, blemishes: 1))
        #expect(abs(after.x - before.x) < 0.003 && abs(after.z - before.z) < 0.003)
    }

    @Test func leavesNonSkinTextureAlone() {
        let img = image { Self.textured(Self.gray, $0, $1) }
        let before = pixels(img), after = smoothed(img)
        #expect(zip(before, after).allSatisfy { abs($0.y - $1.y) < 0.005 })
    }

    @Test func keepsAStrongEdgeLikeABrowSharp() {
        let brow: SIMD3<Float> = [0.22, 0.15, 0.12]
        let img = image { x, y in (n / 2 - 2..<n / 2 + 2).contains(y) ? brow : Self.textured(Self.skin, x, y) }
        let after = smoothed(img)
        #expect(abs(after[(n / 2) * n + n / 2].y - brow.y) < 0.08)
    }

    @Test func blemishesTakeTheColorOfTheSkinAroundThemButKeepTheirBrightness() {
        let pimple = Self.skin + SIMD3<Float>(0.05, -0.02, -0.01)
        let img = image { x, y in abs(x - n / 2) < 3 && abs(y - n / 2) < 3 ? pimple : Self.skin }
        let center = Self.ycc(pixels(SkinSmoothingKernel.apply(img, extent: img.extent, amount: 0, blemishes: 1))[(n / 2) * n + n / 2])
        #expect(abs(center.z - Self.ycc(Self.skin).z) < abs(Self.ycc(pimple).z - Self.ycc(Self.skin).z) * 0.4)
        #expect(abs(center.x - Self.ycc(pimple).x) < 0.005)
    }

    @Test func blemishRemovalKeepsALargeRedAreaLikeLips() {
        let lips: SIMD3<Float> = [0.75, 0.42, 0.42]
        let img = image { x, y in abs(y - n / 2) < 20 ? lips : Self.skin }
        let center = pixels(SkinSmoothingKernel.apply(img, extent: img.extent, amount: 0, blemishes: 1))[(n / 2) * n + n / 2]
        #expect(abs(center.x - lips.x) < 0.01 && abs(center.y - lips.y) < 0.01)
    }

    /// Luma, Cb and Cr (BT.601).
    private static func ycc(_ c: SIMD3<Float>) -> SIMD3<Float> {
        [0.299 * c.x + 0.587 * c.y + 0.114 * c.z,
         0.5 - 0.168736 * c.x - 0.331264 * c.y + 0.5 * c.z,
         0.5 + 0.5 * c.x - 0.418688 * c.y - 0.081312 * c.z]
    }

    private static func mean(_ px: [SIMD3<Float>]) -> SIMD3<Float> {
        ycc(px.reduce(SIMD3<Float>(), +) / Float(px.count))
    }
}
