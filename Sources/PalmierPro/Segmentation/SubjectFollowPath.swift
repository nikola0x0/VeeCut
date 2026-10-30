import CoreGraphics

/// Turns per-frame follower positions into a compact linear position track.
enum SubjectFollowPath {
    /// Canvas fraction the reduced path may stray from the smoothed one; about 2 px on a 1080p frame.
    static let tolerance = 0.002
    /// Frames on each side averaged to steady SAM's frame-to-frame box jitter.
    static let smoothingRadius = 2

    struct Sample: Equatable {
        /// Clip-relative frame.
        let offset: Int
        let topLeft: CGPoint
    }

    static func track(_ samples: [Sample]) -> KeyframeTrack<AnimPair>? {
        let sorted = samples.sorted { $0.offset < $1.offset }
        guard !sorted.isEmpty else { return nil }
        let smoothed = smooth(sorted)
        let kept = reduce(smoothed)
        return KeyframeTrack(keyframes: kept.map {
            Keyframe(frame: $0.offset, value: AnimPair(a: $0.topLeft.x, b: $0.topLeft.y), interpolationOut: .linear)
        })
    }

    /// Averages each sample with neighbors at most `smoothingRadius` frames away, as many on each side
    /// so motion at the path's ends isn't pulled inward.
    static func smooth(_ samples: [Sample]) -> [Sample] {
        samples.indices.map { index in
            let offset = samples[index].offset
            var before = 0, after = 0
            while index - before > 0, offset - samples[index - before - 1].offset <= smoothingRadius { before += 1 }
            while index + after < samples.count - 1, samples[index + after + 1].offset - offset <= smoothingRadius { after += 1 }
            let reach = min(before, after)
            let window = samples[(index - reach)...(index + reach)]
            let count = Double(window.count)
            return Sample(
                offset: offset,
                topLeft: CGPoint(x: window.reduce(0) { $0 + $1.topLeft.x } / count,
                                 y: window.reduce(0) { $0 + $1.topLeft.y } / count)
            )
        }
    }

    /// Ramer–Douglas–Peucker over time: keeps the samples linear interpolation can't reproduce within `tolerance`.
    static func reduce(_ samples: [Sample]) -> [Sample] {
        guard samples.count > 2 else { return samples }
        var keep = [Bool](repeating: false, count: samples.count)
        keep[0] = true
        keep[samples.count - 1] = true
        var spans = [(0, samples.count - 1)]
        while let (start, end) = spans.popLast() {
            guard end - start > 1 else { continue }
            let a = samples[start], b = samples[end]
            var worst = start, worstError = 0.0
            for index in (start + 1)..<end {
                let t = Double(samples[index].offset - a.offset) / Double(b.offset - a.offset)
                let x = a.topLeft.x + (b.topLeft.x - a.topLeft.x) * t
                let y = a.topLeft.y + (b.topLeft.y - a.topLeft.y) * t
                let error = max(abs(samples[index].topLeft.x - x), abs(samples[index].topLeft.y - y))
                if error > worstError { worst = index; worstError = error }
            }
            guard worstError > tolerance else { continue }
            keep[worst] = true
            spans.append((start, worst))
            spans.append((worst, end))
        }
        return samples.indices.filter { keep[$0] }.map { samples[$0] }
    }
}
