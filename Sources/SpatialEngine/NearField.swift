import Darwin
import NearFieldDVF
import Synchronization

struct EarShelf: Sendable, Equatable {
    var b0: SIMD2<Float> = SIMD2(repeating: 1)
    var b1: SIMD2<Float> = .zero
    var a1: SIMD2<Float> = .zero

    static let identity = EarShelf()

    /// Approximate the distance-to-reference DVF ratio with a per-ear shelf.
    /// Use the spatial point's center; stereo points have a small angular spread.
    static func proximity(to point: SourcePosition, strength: Float) -> EarShelf {
        let reference: Float = 0.85
        let dist = Float(point.distance)
        guard dist.isFinite, (0..<reference).contains(dist), strength > 0 else { return .identity }
        let angleLeft = acosf(Float(min(1, max(-1, -point.direction.x)))) * 180 / .pi
        let angles = SIMD2(angleLeft, 180 - angleLeft)
        var lowDB = SIMD2<Float>.zero
        var highDB = SIMD2<Float>.zero
        var frequency = SIMD2<Float>.zero

        for ear in 0..<2 {
            var low: Float = 0, high: Float = 0, fc: Float = 0
            var refLow: Float = 0, refHigh: Float = 0, refFC: Float = 0
            ss_dvf_shelf(angles[ear], max(0.15, dist), &low, &high, &fc)
            ss_dvf_shelf(angles[ear], reference, &refLow, &refHigh, &refFC)
            guard low.isFinite, high.isFinite, fc.isFinite, refLow.isFinite, refHigh.isFinite else { return .identity }
            lowDB[ear] = (low - refLow) * strength
            highDB[ear] = (low + high - refLow - refHigh) * strength
            frequency[ear] = min(4_000, max(180, fc))
        }

        // Common gain is removed before applying the relative ear cues so this
        // stage never boosts a band above unity gain.
        let peak = max(0, lowDB.x, lowDB.y, highDB.x, highDB.y)
        var result = EarShelf()
        for ear in 0..<2 {
            let low = powf(10, max(-9, lowDB[ear] - peak) / 20)
            let high = powf(10, max(-9, highDB[ear] - peak) / 20)
            let g = tanf(.pi * frequency[ear] / 48_000)
            result.b0[ear] = (high + low * g) / (1 + g)
            result.b1[ear] = (low * g - high) / (1 + g)
            result.a1[ear] = (g - 1) / (g + 1)
        }
        return result
    }
}

/// Main writer, one realtime reader. A torn update is ignored until the next buffer.
final class NearFieldStage: @unchecked Sendable {
    private let revision = Atomic<UInt64>(0)
    private let b0 = Atomic<UInt64>(NearFieldStage.pack(SIMD2(repeating: Float(1))))
    private let b1 = Atomic<UInt64>(0)
    private let a1 = Atomic<UInt64>(0)
    private var published = EarShelf.identity  // control thread
    private var seen: UInt64 = 0                // render thread below
    private var current = EarShelf.identity
    private var target = EarShelf.identity
    private var x1 = SIMD2<Float>.zero
    private var y1 = SIMD2<Float>.zero
    private var started = false

    func update(_ value: EarShelf) {
        guard value != published else { return }
        published = value
        let old = revision.load(ordering: .sequentiallyConsistent)
        revision.store(old &+ 1, ordering: .sequentiallyConsistent)
        b0.store(Self.pack(value.b0), ordering: .sequentiallyConsistent)
        b1.store(Self.pack(value.b1), ordering: .sequentiallyConsistent)
        a1.store(Self.pack(value.a1), ordering: .sequentiallyConsistent)
        revision.store(old &+ 2, ordering: .sequentiallyConsistent)
    }

    func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        let version = revision.load(ordering: .sequentiallyConsistent)
        if version != seen, version & 1 == 0 {
            let next = EarShelf(b0: Self.unpack(b0.load(ordering: .sequentiallyConsistent)),
                                b1: Self.unpack(b1.load(ordering: .sequentiallyConsistent)),
                                a1: Self.unpack(a1.load(ordering: .sequentiallyConsistent)))
            if revision.load(ordering: .sequentiallyConsistent) == version {
                seen = version
                target = next
            }
        }
        if !started {
            current = target
            started = true
        }
        if target == .identity, current == .identity { return }
        let smoothing: Float = 0.0025
        for i in 0..<frames {
            current.b0 += (target.b0 - current.b0) * smoothing
            current.b1 += (target.b1 - current.b1) * smoothing
            current.a1 += (target.a1 - current.a1) * smoothing
            let input = SIMD2(left[i], right[i])
            let output = current.b0 * input + current.b1 * x1 - current.a1 * y1
            x1 = input
            // Avoid very small feedback values after long silent sections.
            y1 = SIMD2(abs(output.x) > 1e-20 ? output.x : 0, abs(output.y) > 1e-20 ? output.y : 0)
            left[i] = output.x
            right[i] = output.y
        }

        if target == .identity,
           abs(current.b0.x - 1) < 0.00001, abs(current.b0.y - 1) < 0.00001,
           abs(current.b1.x) < 0.00001, abs(current.b1.y) < 0.00001,
           abs(current.a1.x) < 0.00001, abs(current.a1.y) < 0.00001 {
            current = .identity
            x1 = .zero
            y1 = .zero
        }
    }

    private static func pack(_ value: SIMD2<Float>) -> UInt64 {
        UInt64(value.x.bitPattern) | (UInt64(value.y.bitPattern) << 32)
    }

    private static func unpack(_ value: UInt64) -> SIMD2<Float> {
        SIMD2(Float(bitPattern: UInt32(truncatingIfNeeded: value)), Float(bitPattern: UInt32(value >> 32)))
    }
}
