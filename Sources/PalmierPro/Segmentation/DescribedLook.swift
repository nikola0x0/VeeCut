import Foundation

enum DescribedLookError: Error, Equatable {
    case malformed
    case empty
}

/// Muse Spark's contract for turning a described look ("warm golden hour") into subject and background effects,
/// or a whole-clip grade when the clip has no subject.
/// Only effects the Subject tab can show as sliders are offered; settings are clamped to each slider's range.
@MainActor
enum DescribedLook {
    static let model = "muse-spark-1.3"
    static let maxDescriptionLength = 300

    struct Result: Equatable {
        let name: String
        let plan: LookPlan
        /// Effects or settings the model named that VeeCut does not have, as "effect" or "effect.setting".
        let skipped: [String]
    }

    static let effects: [EffectDescriptor] = EditorViewModel.subjectEffectDescriptors.filter { $0.id != "color.wheels" }

    static func instructions(hasSubject: Bool) -> String {
        let catalog = effects.map { descriptor in
            let settings = descriptor.params.map { spec in
                let unit = spec.unit.isEmpty ? "" : " \(spec.unit)"
                return "\(spec.key) \(number(spec.range.lowerBound))…\(number(spec.range.upperBound))\(unit), neutral \(number(spec.defaultValue))"
            }
            return "- \(descriptor.id): " + settings.joined(separator: "; ")
        }
        let sides = hasSubject
            ? "\"subject\" is the tracked person or object; \"background\" is everything else in the frame. Use the same grain on both sides when grain should cover the whole frame."
            : "\"frame\" is the whole clip."
        return """
        You are the colorist inside a video editor. Build the look the user describes from the effects below only.
        \(sides)
        Use exact effect ids and setting names, and values inside each range. Prefer 2–5 effects per side with subtle values.
        Higher temperature is warmer. Negative vignette amount darkens the edges. Contrast and saturation are neutral at 1.
        Give the look a short name of 1–3 words.

        Effects:
        \(catalog.joined(separator: "\n"))
        """
    }

    static func schema(hasSubject: Bool) -> [String: Any] {
        let side: [String: Any] = [
            "type": "array",
            "items": [
                "type": "object",
                "properties": [
                    "effect": ["type": "string"],
                    "settings": ["type": "object", "additionalProperties": ["type": "number"]],
                ],
                "required": ["effect", "settings"],
            ],
        ]
        let sides = sideKeys(hasSubject: hasSubject)
        var properties: [String: Any] = ["name": ["type": "string"]]
        for key in sides { properties[key] = side }
        return ["type": "object", "properties": properties, "required": ["name"] + sides]
    }

    private static func sideKeys(hasSubject: Bool) -> [String] {
        hasSubject ? ["subject", "background"] : ["frame"]
    }

    /// Validates the model's JSON against the effect registry. Unknown effects and settings are skipped and reported.
    static func parse(_ text: String, hasSubject: Bool) throws(DescribedLookError) -> Result {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else {
            throw .malformed
        }
        var skipped: [String] = []
        func side(_ key: String) throws(DescribedLookError) -> [Effect] {
            guard let entries = object[key] as? [[String: Any]] else { throw .malformed }
            var result: [Effect] = []
            for entry in entries {
                guard let type = entry["effect"] as? String else { throw .malformed }
                guard let descriptor = effects.first(where: { $0.id == type }) else {
                    skipped.append(type)
                    continue
                }
                var effect = descriptor.makeEffect()
                for (settingKey, raw) in entry["settings"] as? [String: Any] ?? [:] {
                    guard let spec = descriptor.params.first(where: { $0.key == settingKey }),
                          let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                          case let value = number.doubleValue, value.isFinite else {
                        skipped.append("\(type).\(settingKey)")
                        continue
                    }
                    effect.params[settingKey] = EffectParam(value: min(spec.range.upperBound, max(spec.range.lowerBound, value)))
                }
                result.removeAll { $0.type == type }
                result.append(effect)
            }
            return result
        }
        let plan = hasSubject
            ? LookPlan(subject: try side("subject"), background: try side("background"))
            : LookPlan(frame: try side("frame"))
        guard !plan.isEmpty else { throw .empty }
        let name = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Result(name: name, plan: plan, skipped: skipped)
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }
}
