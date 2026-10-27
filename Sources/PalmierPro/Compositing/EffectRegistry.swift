import CoreImage
import Foundation

struct EffectParamSpec: Sendable {
    let key: String
    let label: String
    let range: ClosedRange<Double>
    let defaultValue: Double
    let unit: String
}

/// Numeric/string param values resolved for one frame
struct ResolvedEffectParams: Sendable {
    let values: [String: Double]
    let strings: [String: String]
    var frame: Int = 0   // timeline frame, for effects that animate (e.g. grain)
    var spatialScale: Double = 1

    func value(_ key: String) -> Double { values[key] ?? 0 }
    func string(_ key: String) -> String? { strings[key] }
}

struct EffectDescriptor: Identifiable, Sendable {
    let id: String
    let displayName: String
    let category: String
    let params: [EffectParamSpec]
    let linearizes: Bool
    /// True for effects carrying a file resource (LUT) — drives the inspector row.
    let resourceKey: String?
    let apply: @Sendable (CIImage, ResolvedEffectParams, CGRect) -> CIImage

    init(id: String, displayName: String, category: String,
         params: [EffectParamSpec], linearizes: Bool = false, resourceKey: String? = nil,
         apply: @escaping @Sendable (CIImage, ResolvedEffectParams, CGRect) -> CIImage) {
        self.id = id
        self.displayName = displayName
        self.category = category
        self.params = params
        self.linearizes = linearizes
        self.resourceKey = resourceKey
        self.apply = apply
    }

    /// Default Effect instance for "Add Effect".
    func makeEffect() -> Effect {
        Effect(type: id, params: params.reduce(into: [:]) {
            $0[$1.key] = EffectParam(value: $1.defaultValue)
        })
    }

    func resolve(
        _ effect: Effect,
        atOffset offset: Int,
        spatialScale: Double = 1
    ) -> ResolvedEffectParams {
        var values: [String: Double] = [:]
        for spec in params {
            let raw = effect.params[spec.key]?.resolved(at: offset, default: spec.defaultValue)
                ?? spec.defaultValue
            values[spec.key] = min(spec.range.upperBound, max(spec.range.lowerBound, raw))
        }
        let strings = effect.params.compactMapValues(\.string)
        return ResolvedEffectParams(
            values: values,
            strings: strings,
            frame: offset,
            spatialScale: spatialScale
        )
    }

    /// Full application incl. optional linear-light wrapping.
    func render(
        _ image: CIImage,
        effect: Effect,
        atOffset offset: Int,
        spatialScale: Double = 1
    ) -> CIImage {
        let params = resolve(effect, atOffset: offset, spatialScale: spatialScale)
        let extent = image.extent
        var working = image
        if linearizes {
            working = working.applyingFilter("CISRGBToneCurveToLinear")
        }
        working = apply(working, params, extent)
        if linearizes {
            working = working.applyingFilter("CILinearToSRGBToneCurve")
        }
        return working
    }
}

enum EffectRegistry {

    static let all: [EffectDescriptor] = color + wheels + hueCurves + lut + curves + detail + blur + stylize + key

    private static let color: [EffectDescriptor] = [
        EffectDescriptor(
            id: "color.exposure", displayName: L10n.key("Exposure"), category: "Color",
            params: [EffectParamSpec(key: "ev", label: L10n.key("Exposure"), range: -3...3,
                                     defaultValue: 0, unit: "")],
            linearizes: true,
            apply: { image, p, _ in
                image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: p.value("ev")])
            }
        ),
        EffectDescriptor(
            id: "color.contrast", displayName: L10n.key("Contrast"), category: "Color",
            params: [EffectParamSpec(key: "amount", label: L10n.key("Contrast"), range: 0.5...1.5,
                                     defaultValue: 1, unit: "")],
            apply: { image, p, _ in
                image.applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: p.value("amount"),
                ])
            }
        ),
        EffectDescriptor(
            id: "color.saturation", displayName: L10n.key("Saturation"), category: "Color",
            params: [EffectParamSpec(key: "amount", label: L10n.key("Saturation"), range: 0...2,
                                     defaultValue: 1, unit: "")],
            apply: { image, p, _ in
                image.applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: p.value("amount"),
                ])
            }
        ),
        EffectDescriptor(
            id: "color.temperature", displayName: L10n.key("Temperature & Tint"), category: "Color",
            params: [
                EffectParamSpec(key: "temperature", label: L10n.key("Temperature"), range: 2000...11000,
                                defaultValue: 6500, unit: "K"),
                EffectParamSpec(key: "tint", label: L10n.key("Tint"), range: -100...100,
                                defaultValue: 0, unit: ""),
            ],
            apply: { image, p, _ in
                image.applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: p.value("temperature"), y: p.value("tint")),
                    "inputTargetNeutral": CIVector(x: 6500, y: 0),
                ])
            }
        ),
        EffectDescriptor(
            id: "color.highlightsShadows", displayName: L10n.key("Highlights & Shadows"), category: "Color",
            params: [
                EffectParamSpec(key: "highlights", label: L10n.key("Highlights"), range: -1...1,
                                defaultValue: 0, unit: ""),
                EffectParamSpec(key: "shadows", label: L10n.key("Shadows"), range: -1...1,
                                defaultValue: 0, unit: ""),
            ],
            apply: { image, p, _ in
                HighlightsShadowsKernel.apply(image, highlights: p.value("highlights"),
                                              shadows: p.value("shadows"))
            }
        ),
        EffectDescriptor(
            id: "color.blacksWhites", displayName: L10n.key("Levels"), category: "Color",
            params: [
                EffectParamSpec(key: "blacks", label: L10n.key("Blacks"), range: -1...1, defaultValue: 0, unit: ""),
                EffectParamSpec(key: "whites", label: L10n.key("Whites"), range: -1...1, defaultValue: 0, unit: ""),
            ],
            apply: { image, p, _ in
                LevelsKernel.apply(image, blacks: p.value("blacks"), whites: p.value("whites"))
            }
        ),
        EffectDescriptor(
            id: "color.vibrance", displayName: L10n.key("Vibrance"), category: "Color",
            params: [EffectParamSpec(key: "amount", label: L10n.key("Vibrance"), range: -1...1, defaultValue: 0, unit: "")],
            apply: { image, p, _ in
                image.applyingFilter("CIVibrance", parameters: ["inputAmount": p.value("amount")])
            }
        ),
    ]

    private static let wheels: [EffectDescriptor] = [
        EffectDescriptor(
            id: "color.wheels", displayName: L10n.key("Color Wheels"), category: "Color",
            params: [
                EffectParamSpec(key: "lift_x", label: L10n.key("Lift"), range: -1...1, defaultValue: 0, unit: ""),
                EffectParamSpec(key: "lift_y", label: L10n.key("Lift"), range: -1...1, defaultValue: 0, unit: ""),
                EffectParamSpec(key: "lift_m", label: L10n.key("Lift"), range: -0.5...0.5, defaultValue: 0, unit: ""),
                EffectParamSpec(key: "gamma_x", label: L10n.key("Gamma"), range: -1...1, defaultValue: 0, unit: ""),
                EffectParamSpec(key: "gamma_y", label: L10n.key("Gamma"), range: -1...1, defaultValue: 0, unit: ""),
                EffectParamSpec(key: "gamma_m", label: L10n.key("Gamma"), range: 0.5...2, defaultValue: 1, unit: ""),
                EffectParamSpec(key: "gain_x", label: L10n.key("Gain"), range: -1...1, defaultValue: 0, unit: ""),
                EffectParamSpec(key: "gain_y", label: L10n.key("Gain"), range: -1...1, defaultValue: 0, unit: ""),
                EffectParamSpec(key: "gain_m", label: L10n.key("Gain"), range: 0.5...1.5, defaultValue: 1, unit: ""),
            ],
            apply: { image, p, _ in
                WheelsKernel.apply(image, params: p)
            }
        ),
    ]

    private static let hueCurves: [EffectDescriptor] = [
        EffectDescriptor(
            id: "color.hueCurves", displayName: L10n.key("Hue Curves"), category: "Color",
            params: [],
            apply: { image, p, _ in
                guard let json = p.string("curves"), let curves = HueCurves(json: json) else { return image }
                return HueCurveKernel.apply(image, curves: curves)
            }
        ),
    ]

    private static let lut: [EffectDescriptor] = [
        EffectDescriptor(
            id: "color.lut", displayName: L10n.key("LUT"), category: "Color",
            params: [EffectParamSpec(key: "intensity", label: L10n.key("Intensity"), range: 0...1,
                                     defaultValue: 1, unit: "")],
            resourceKey: "path",
            apply: { image, p, _ in
                guard let path = p.string("path"), let cube = LUTLoader.load(path: path) else { return image }
                return LUTTetraKernel.apply(image, cube: cube, key: path, intensity: p.value("intensity"))
            }
        ),
    ]

    private static let curves: [EffectDescriptor] = [
        EffectDescriptor(
            id: "color.curves", displayName: L10n.key("Curves"), category: "Color",
            params: [],
            apply: { image, p, _ in
                guard let json = p.string("curve"), let curve = GradeCurve(json: json) else { return image }
                return GradeCurveKernel.apply(image, curve: curve)
            }
        ),
    ]

    private static let blur: [EffectDescriptor] = [
        EffectDescriptor(
            id: "blur.gaussian", displayName: L10n.key("Gaussian Blur"), category: "Blur & Sharpen",
            params: [EffectParamSpec(key: "radius", label: L10n.key("Radius"), range: 0...100,
                                     defaultValue: 8, unit: "px")],
            apply: { image, p, extent in
                let radius = p.value("radius") * p.spatialScale
                guard radius > 0 else { return image }
                return image.premultiplyingAlpha()
                    .clampedToExtent()
                    .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                    .cropped(to: extent)
                    .unpremultiplyingAlpha()
            }
        ),
        EffectDescriptor(
            id: "blur.sharpen", displayName: L10n.key("Sharpen"), category: "Blur & Sharpen",
            params: [EffectParamSpec(key: "amount", label: L10n.key("Sharpness"), range: 0...2,
                                     defaultValue: 0.4, unit: "")],
            apply: { image, p, extent in
                image.clampedToExtent()
                    .applyingFilter("CISharpenLuminance", parameters: [
                        kCIInputSharpnessKey: p.value("amount"),
                    ])
                    .cropped(to: extent)
            }
        ),
        EffectDescriptor(
            id: "blur.noiseReduction", displayName: L10n.key("Noise Reduction"), category: "Blur & Sharpen",
            params: [EffectParamSpec(key: "amount", label: L10n.key("Noise Reduction"), range: 0...1,
                                     defaultValue: 0, unit: "")],
            apply: { image, p, _ in
                let amount = p.value("amount")
                guard amount > 0 else { return image }
                return image.applyingFilter("CINoiseReduction", parameters: [
                    "inputNoiseLevel": amount * 0.1,
                    "inputSharpness": 0.4,
                ])
            }
        ),
        EffectDescriptor(
            id: "blur.motion", displayName: L10n.key("Motion Blur"), category: "Blur & Sharpen",
            params: [
                EffectParamSpec(key: "radius", label: L10n.key("Motion Blur"), range: 0...100,
                                defaultValue: 0, unit: "px"),
                EffectParamSpec(key: "angle", label: L10n.key("Angle"), range: -180...180,
                                defaultValue: 0, unit: "°"),
            ],
            apply: { image, p, extent in
                let radius = p.value("radius")
                guard radius > 0 else { return image }
                return image.clampedToExtent()
                    .applyingFilter("CIMotionBlur", parameters: [
                        kCIInputRadiusKey: radius,
                        kCIInputAngleKey: p.value("angle") * .pi / 180,
                    ])
                    .cropped(to: extent)
            }
        ),
    ]

    private static let stylize: [EffectDescriptor] = [
        EffectDescriptor(
            id: "stylize.invert", displayName: L10n.key("Invert"), category: "Stylize",
            params: [],
            apply: { image, _, _ in
                return image.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: -1, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: -1, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: -1, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0),
                ])
            }
        ),
        EffectDescriptor(
            id: "stylize.grain", displayName: L10n.key("Film Grain"), category: "Stylize",
            params: [
                EffectParamSpec(key: "amount", label: L10n.key("Amount"), range: 0...1, defaultValue: 0, unit: ""),
                EffectParamSpec(key: "size", label: L10n.key("Size"), range: 0.5...4, defaultValue: 1.5, unit: ""),
            ],
            apply: { image, p, _ in
                GrainKernel.apply(image, amount: p.value("amount"), size: p.value("size"), frame: p.frame)
            }
        ),
        EffectDescriptor(
            id: "stylize.vignette", displayName: L10n.key("Vignette"), category: "Stylize",
            params: [
                EffectParamSpec(key: "amount", label: L10n.key("Amount"), range: -1...1, defaultValue: 0, unit: ""),
                EffectParamSpec(key: "midpoint", label: L10n.key("Midpoint"), range: 0...1, defaultValue: 0.5, unit: ""),
                EffectParamSpec(key: "roundness", label: L10n.key("Roundness"), range: -1...1, defaultValue: 0, unit: ""),
                EffectParamSpec(key: "feather", label: L10n.key("Feather"), range: 0...1, defaultValue: 0.5, unit: ""),
            ],
            apply: { image, p, extent in
                VignetteKernel.apply(image, extent: extent, amount: p.value("amount"),
                                     midpoint: p.value("midpoint"), roundness: p.value("roundness"),
                                     feather: p.value("feather"))
            }
        ),
        EffectDescriptor(
            id: "stylize.glow", displayName: L10n.key("Glow"), category: "Stylize",
            params: [
                EffectParamSpec(key: "intensity", label: L10n.key("Glow"), range: 0...1, defaultValue: 0, unit: ""),
                EffectParamSpec(key: "radius", label: L10n.key("Radius"), range: 0...100, defaultValue: 20, unit: "px"),
                EffectParamSpec(key: "threshold", label: L10n.key("Threshold"), range: 0...1, defaultValue: 0.6, unit: ""),
                EffectParamSpec(key: "warmth", label: L10n.key("Warmth"), range: 0...1, defaultValue: 0, unit: ""),
            ],
            apply: { image, p, extent in
                GlowKernel.apply(image, extent: extent, intensity: p.value("intensity"),
                                 radius: p.value("radius"), threshold: p.value("threshold"),
                                 warmth: p.value("warmth"))
            }
        ),
    ]

    private static let detail: [EffectDescriptor] = [
        EffectDescriptor(
            id: "detail.clarity", displayName: L10n.key("Clarity & Haze"), category: "Detail",
            params: [
                EffectParamSpec(key: "clarity", label: L10n.key("Clarity"), range: -1...1, defaultValue: 0, unit: ""),
                EffectParamSpec(key: "dehaze", label: L10n.key("Dehaze"), range: -1...1, defaultValue: 0, unit: ""),
            ],
            apply: { image, p, extent in
                ClarityKernel.apply(image, extent: extent, clarity: p.value("clarity"), dehaze: p.value("dehaze"))
            }
        ),
    ]

    private static let key: [EffectDescriptor] = [
        EffectDescriptor(
            id: "key.chroma", displayName: L10n.key("Chroma Key"), category: "Key",
            params: [
                EffectParamSpec(key: "keyHue", label: L10n.key("Key Hue"), range: 0...1, defaultValue: 0.333, unit: ""),
                EffectParamSpec(key: "tolerance", label: L10n.key("Tolerance"), range: 0...1, defaultValue: 0, unit: ""),
                EffectParamSpec(key: "softness", label: L10n.key("Softness"), range: 0...1, defaultValue: 0.1, unit: ""),
                EffectParamSpec(key: "spill", label: L10n.key("Spill"), range: 0...1, defaultValue: 0.5, unit: ""),
            ],
            apply: { image, p, _ in
                ChromaKeyKernel.apply(image, keyHue: p.value("keyHue"), tolerance: p.value("tolerance"),
                                      softness: p.value("softness"), spill: p.value("spill"))
            }
        ),
    ]

    static let byId: [String: EffectDescriptor] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    static func descriptor(id: String) -> EffectDescriptor? { byId[id] }

    /// Canonical order the always-on adjustment sections insert their effects in.
    static let canonicalOrder: [String] = [
        "color.exposure", "color.contrast", "color.highlightsShadows", "color.blacksWhites",
        "color.temperature", "color.vibrance", "color.saturation", "color.wheels", "color.curves",
        "color.hueCurves", "color.lut", "detail.clarity", "key.chroma", "blur.gaussian", "blur.sharpen",
        "blur.noiseReduction", "blur.motion", "stylize.invert", "stylize.grain", "stylize.vignette",
        "stylize.glow",
    ]

    static func insertIndex(_ effects: [Effect], for id: String) -> Int {
        let rank = canonicalOrder.firstIndex(of: id) ?? Int.max
        return effects.firstIndex { (canonicalOrder.firstIndex(of: $0.type) ?? Int.max) > rank } ?? effects.count
    }
}
