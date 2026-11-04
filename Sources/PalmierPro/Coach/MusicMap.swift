import Foundation

/// How a part of the song feels, which sets how fast the cuts come.
enum MusicEnergy: String, Codable, Sendable, CaseIterable {
    case calm, rising, peak, fading
}

/// The song as an editor hears it: bars, parts by energy, and the drop, from the beat analysis and a loudness curve.
struct MusicMap: Equatable, Sendable {
    struct Part: Equatable, Sendable {
        let start: Double
        let end: Double
        let energy: MusicEnergy
        let bars: Int
    }

    let duration: Double
    let beatSeconds: Double
    let barSeconds: Double
    let parts: [Part]
    let drop: Double?

    static let barsPerPhrase = 4
    static let minimumBeats = 8
    static let calmBelow = 0.35
    static let peakFrom = 0.7
    static let dropJump = 0.25

    /// Nil when the song has no usable beat grid.
    static func make(analysis: BeatAnalysis, beatLoudness: [Double], duration: Double) -> MusicMap? {
        let beats = analysis.beats
        guard analysis.bpm > 0, analysis.bpm.isFinite, beats.count >= minimumBeats, beats.count == beatLoudness.count,
              !analysis.downbeats.isEmpty, duration.isFinite, duration > 0 else { return nil }
        let downbeats = analysis.downbeats.sorted().filter { $0 < duration }
        guard !downbeats.isEmpty else { return nil }

        let barLoudness = downbeats.indices.map { index -> Double in
            let start = downbeats[index], end = index + 1 < downbeats.count ? downbeats[index + 1] : duration
            let values = zip(beats, beatLoudness).filter { $0.0 >= start && $0.0 < end }.map(\.1)
            return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        }
        let low = barLoudness.min() ?? 0, high = barLoudness.max() ?? 0
        let normalized = barLoudness.map { high - low > 1e-9 ? ($0 - low) / (high - low) : 0.5 }

        var phrases: [(firstBar: Int, bars: Int, level: Double)] = []
        var bar = 0
        while bar < normalized.count {
            let remaining = normalized.count - bar
            let length = remaining < barsPerPhrase * 2 && remaining > barsPerPhrase ? remaining : min(barsPerPhrase, remaining)
            let slice = normalized[bar..<(bar + length)]
            phrases.append((bar, length, slice.reduce(0, +) / Double(length)))
            bar += length
        }
        let loudest = phrases.indices.max { phrases[$0].level < phrases[$1].level } ?? 0
        let energies = phrases.indices.map { index -> MusicEnergy in
            let level = phrases[index].level
            if level < calmBelow { return .calm }
            if level >= peakFrom { return .peak }
            return index < loudest ? .rising : .fading
        }

        var parts: [Part] = []
        var drop: Double?
        for index in phrases.indices {
            let start = index == 0 ? 0 : downbeats[phrases[index].firstBar]
            if energies[index] == .peak, drop == nil, index > 0, phrases[index].level - phrases[index - 1].level >= dropJump,
               energies[index - 1] != .peak {
                drop = start
            }
            if let last = parts.last, last.energy == energies[index] {
                parts[parts.count - 1] = Part(start: last.start, end: last.end, energy: last.energy, bars: last.bars + phrases[index].bars)
            } else {
                parts.append(Part(start: start, end: start, energy: energies[index], bars: phrases[index].bars))
            }
        }
        let closed = parts.indices.map { index in
            Part(start: parts[index].start, end: index + 1 < parts.count ? parts[index + 1].start : duration,
                 energy: parts[index].energy, bars: parts[index].bars)
        }
        let beatSeconds = 60 / analysis.bpm
        // The median gap: the beat model sometimes adds a stray downbeat just after a real one.
        let gaps = zip(downbeats.dropFirst(), downbeats).map { $0 - $1 }.sorted()
        let barSeconds = gaps.isEmpty ? beatSeconds * 4 : gaps[gaps.count / 2]
        return MusicMap(duration: duration, beatSeconds: beatSeconds, barSeconds: barSeconds, parts: closed, drop: drop)
    }

    /// The song up to the part end nearest `seconds`, keeping at least the first part. A length past the drop
    /// never ends on it, and may also end on any phrase after the drop, trimming that part there.
    func cut(nearest seconds: Double) -> MusicMap {
        guard seconds.isFinite, seconds < duration, !parts.isEmpty else { return self }
        var ends = parts.map(\.end)
        if let drop, seconds > drop {
            let phrase = barSeconds * Double(Self.barsPerPhrase)
            if phrase > 0 { ends += stride(from: drop + phrase, to: duration, by: phrase).map { $0 } }
            ends = ends.filter { $0 > drop }
        }
        guard let end = ends.min(by: { abs($0 - seconds) < abs($1 - seconds) }) else { return self }
        let kept = parts.filter { $0.start < end }.map { part in
            part.end <= end ? part
                : Part(start: part.start, end: end, energy: part.energy, bars: Int(((end - part.start) / barSeconds).rounded()))
        }
        return MusicMap(duration: end, beatSeconds: beatSeconds, barSeconds: barSeconds, parts: kept, drop: drop.flatMap { $0 < end ? $0 : nil })
    }

    /// Root-mean-square loudness from each beat to the next (the last beat runs to the end).
    static func beatLoudness(samples: [Float], sampleRate: Double, beats: [Double]) -> [Double] {
        guard sampleRate > 0 else { return beats.map { _ in 0 } }
        return beats.indices.map { index in
            let from = max(0, min(samples.count, Int((beats[index] * sampleRate).rounded())))
            let to = index + 1 < beats.count ? max(from, min(samples.count, Int((beats[index + 1] * sampleRate).rounded()))) : samples.count
            guard to > from else { return 0 }
            var sum: Double = 0
            for sample in samples[from..<to] { sum += Double(sample) * Double(sample) }
            return (sum / Double(to - from)).squareRoot()
        }
    }
}
