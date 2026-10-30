import CoreImage
import Foundation

/// Smooths skin texture and evens out blemishes while edges (eyes, brows, lips, hair) stay sharp.
/// Kernel: `Metal/SkinSmoothing.metal`.
enum SkinSmoothingKernel {
    private static let energyKernel = CIKernelLoader.colorKernel("SkinSmoothing", "skinDetailEnergy")
    private static let smoothKernel = CIKernelLoader.colorKernel("SkinSmoothing", "smoothSkin")
    private static let skinWeightKernel = CIKernelLoader.colorKernel("SkinSmoothing", "skinWeighted")

    /// Texture scale as a fraction of the frame's long side, so preview and export match.
    static let radiusFraction = 0.006
    /// Blemishes are judged against the tone of the skin this many texture radii around them.
    static let surroundScale = 2.2
    /// The wide blurs run on a copy downscaled until the texture radius is this many pixels.
    static let workingRadius = 4.0
    /// The fine-grain blur keeps more resolution so pores stay crisp.
    static let finestWorkingRadius = 2.0

    static func apply(_ image: CIImage, extent: CGRect, amount: Double, blemishes: Double = 0) -> CIImage {
        guard let energyKernel, let smoothKernel, let skinWeightKernel, amount > 0 || blemishes > 0, extent.width > 0, extent.height > 0 else { return image }
        let radius = max(2, max(extent.width, extent.height) * radiusFraction)
        let scale = min(1, workingRadius / radius)
        let base = lowPass(image, radius: radius, scale: scale, extent: extent)
        let fineRadius = max(0.75, radius / 5)
        let fine = lowPass(image, radius: fineRadius, scale: min(1, finestWorkingRadius / fineRadius), extent: extent)
        guard let detail = energyKernel.apply(extent: extent, arguments: [image, base]),
              let skin = skinWeightKernel.apply(extent: extent, arguments: [image]) else { return image }
        let energy = lowPass(detail, radius: radius, scale: scale, extent: extent)
        let skinAround = lowPass(skin, radius: radius * surroundScale, scale: scale, extent: extent)
        let arguments: [Any] = [image, base, fine, energy, skinAround, Float(min(max(amount, 0), 1)), Float(min(max(blemishes, 0), 1))]
        return smoothKernel.apply(extent: extent, arguments: arguments) ?? image
    }

    /// A Gaussian blur computed at `scale` and resampled back; exact enough for these smooth layers and far cheaper.
    private static func lowPass(_ image: CIImage, radius: Double, scale: Double, extent: CGRect) -> CIImage {
        let down = CGAffineTransform(translationX: -extent.minX, y: -extent.minY).scaledBy(x: scale, y: scale)
        let small = image.transformed(by: down, highQualityDownsample: true)
        return small.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius * scale])
            .samplingLinear()
            .transformed(by: down.inverted())
            .cropped(to: extent)
    }
}
