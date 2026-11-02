import Foundation

/// Turns a section's moments into cuts a whole number of beats long, taking turns across the moments.
enum PacedCuts {
    static func beats(for energy: MusicEnergy) -> Int {
        switch energy {
        case .calm: 8
        case .rising, .fading: 4
        case .peak: 2
        }
    }

    static func cutSeconds(for energy: MusicEnergy, beatSeconds: Double) -> Double {
        Double(beats(for: energy)) * beatSeconds
    }

    /// Each turn takes a moment's next piece: the cut length, or the whole beats left when less remains. When every moment
    /// is used up the moments are reused, so the section fills exactly and the next section starts on its downbeat.
    /// The leftover part of a beat goes on the last cut with room, or the first with room when `leftoverFirst` (the song's pickup).
    static func moments(from moments: [PlanMoment], cutSeconds: Double, beatSeconds: Double, filling: Double, leftoverFirst: Bool = false) -> [PlanMoment] {
        guard beatSeconds > 0, beatSeconds.isFinite, cutSeconds >= beatSeconds, filling.isFinite, filling > 0 else { return [] }
        let tolerance = 1e-6
        let target = (filling / beatSeconds + tolerance).rounded(.down) * beatSeconds
        let starts = moments.map(\.start)
        var offsets = starts
        var cuts: [(source: Int, moment: PlanMoment)] = []
        var filled = 0.0
        while filled < target - tolerance {
            var tookPiece = false
            for index in moments.indices where filled < target - tolerance {
                let remaining = moments[index].end - offsets[index]
                let wholeBeats = (remaining / beatSeconds + tolerance).rounded(.down) * beatSeconds
                let piece = min(cutSeconds, wholeBeats, target - filled)
                guard piece >= beatSeconds - tolerance else { continue }
                cuts.append((index, PlanMoment(assetId: moments[index].assetId, start: offsets[index], end: offsets[index] + piece, note: moments[index].note)))
                offsets[index] += piece
                filled += piece
                tookPiece = true
            }
            if !tookPiece {
                guard offsets != starts else { break }
                offsets = starts
            }
        }
        let leftover = filling - filled
        if leftover > tolerance, leftover < beatSeconds {
            for slot in leftoverFirst ? Array(cuts.indices) : cuts.indices.reversed() {
                let source = moments[cuts[slot].source]
                let cut = cuts[slot].moment
                if cut.end + leftover <= source.end + tolerance {
                    cuts[slot].moment.end += leftover
                } else if cut.start - leftover >= source.start - tolerance {
                    cuts[slot].moment.start -= leftover
                } else {
                    continue
                }
                break
            }
        }
        return cuts.map(\.moment)
    }

    /// Sizes each cut to the frames between its song-time boundaries, moved onto the song's nearest detected beat when one
    /// is within `snapWithin` frames, so frame rounding and tempo drift never pull a cut off the beat.
    /// Lengths sit half a frame past the whole frame count because placement truncates seconds to frames.
    static func framed(_ cuts: [PlanMoment], startSeconds: Double, fps: Double, beatFrames: [Int] = [], snapWithin: Int = 0) -> [PlanMoment] {
        guard fps > 0, fps.isFinite, startSeconds.isFinite else { return cuts }
        let beats = beatFrames.sorted()
        var elapsed = startSeconds
        var from = Int((elapsed * fps).rounded())
        return cuts.map { cut in
            elapsed += cut.end - cut.start
            let onGrid = Int((elapsed * fps).rounded())
            let beat = nearest(to: onGrid, in: beats).flatMap { abs($0 - onGrid) <= snapWithin && $0 > from ? $0 : nil }
            let to = max(beat ?? onGrid, from + 1)
            let length = (Double(to - from) + 0.5) / fps
            from = to
            var framed = cut
            let growth = length - (cut.end - cut.start)
            if growth > 0, cut.start - growth >= 0 {
                framed.start -= growth
            } else {
                framed.end = cut.start + length
            }
            return framed
        }
    }

    private static func nearest(to frame: Int, in sorted: [Int]) -> Int? {
        guard !sorted.isEmpty else { return nil }
        var low = 0, high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid] < frame { low = mid + 1 } else { high = mid }
        }
        let candidates = [low - 1, low].filter(sorted.indices.contains).map { sorted[$0] }
        return candidates.min { abs($0 - frame) < abs($1 - frame) }
    }
}
