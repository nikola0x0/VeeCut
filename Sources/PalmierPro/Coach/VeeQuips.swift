import Foundation

/// What Vee says while it plans: light jokes about the footage instead of the model's raw reasoning.
@MainActor
enum VeeQuips {
    static func lines(labels: Set<String>, hasSong: Bool = false, hasDrop: Bool = false) -> [String] {
        var lines: [String] = []
        if hasSong { lines.append(L10n.string("Counting the beats in your song\u{2026}")) }
        if hasSong, hasDrop { lines.append(L10n.string("Saving the best shot for the drop\u{2026}")) }
        if labels.contains("animal") { lines.append(L10n.string("Giving the animal its close-up\u{2026}")) }
        if labels.contains("coffee or café") || labels.contains("food") { lines.append(L10n.string("Trying not to drool on the food shots\u{2026}")) }
        if labels.contains("sunset or sunrise") { lines.append(L10n.string("Saving that sunset for the big finish\u{2026}")) }
        if labels.contains(FootageScanner.talkingLabel) { lines.append(L10n.string("Picking the takes where you didn\u{2019}t blink\u{2026}")) }
        if labels.contains("street at night") { lines.append(L10n.string("Turning up the city lights\u{2026}")) }
        return lines + [
            L10n.string("Watching your clips with popcorn\u{2026}"),
            L10n.string("Hunting for a hook that stops thumbs\u{2026}"),
            L10n.string("Arguing with myself about the order\u{2026}"),
            L10n.string("Trimming the boring bits. There were a few\u{2026}"),
            L10n.string("Counting beats on my fingers. I have no fingers\u{2026}"),
            L10n.string("Almost there. Fluffing the leaf\u{2026}"),
        ]
    }

    static func line(tick: Int, labels: Set<String>, hasSong: Bool = false, hasDrop: Bool = false) -> String {
        let lines = lines(labels: labels, hasSong: hasSong, hasDrop: hasDrop)
        return lines[abs(tick) % lines.count]
    }
}
