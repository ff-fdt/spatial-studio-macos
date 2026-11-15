import Darwin
import Synchronization

/// Zero-latency stereo peak guard for boosted sources. One shared gain preserves
/// relative left/right levels; a slow release prevents distortion after peaks.
final class PeakProtection: @unchecked Sendable {
    private let encodedCeiling = Atomic<UInt32>(Float(0.98).bitPattern)
    private var gain: Float = 1 // output render thread only

    func setCeiling(_ ceiling: Float) {
        encodedCeiling.store(min(0.98, max(0.001, ceiling)).bitPattern, ordering: .releasing)
    }

    func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        let ceiling = Float(bitPattern: encodedCeiling.load(ordering: .acquiring))
        let release: Float = 0.00041 // about 50 ms at 48 kHz
        for i in 0..<frames {
            let l = left[i].isFinite ? left[i] : 0
            let r = right[i].isFinite ? right[i] : 0
            let peak = max(fabsf(l), fabsf(r))
            let allowed = peak > ceiling ? ceiling / peak : 1
            gain = min(allowed, gain + (1 - gain) * release)
            left[i] = l * gain
            right[i] = r * gain
        }
    }
}
