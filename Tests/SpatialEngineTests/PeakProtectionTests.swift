import Testing
@testable import SpatialEngine

@Suite("Output gain protection")
struct PeakProtectionTests {
    @Test("Gain boost respects the stereo ceiling without shifting the sound sideways")
    func stereoPeakGuard() {
        let guardStage = PeakProtection()
        guardStage.setCeiling(0.49)
        var l: [Float] = [0.10, 1.50, 0.16, -4, 0.12]
        var r: [Float] = [0.05, -0.75, 0.08, 2, 0.06]
        l.withUnsafeMutableBufferPointer { left in
            r.withUnsafeMutableBufferPointer { right in
                guardStage.process(left.baseAddress!, right.baseAddress!, frames: left.count)
            }
        }
        #expect(l[0] == 0.10 && r[0] == 0.05)
        #expect(l.allSatisfy { abs($0) <= 0.490001 })
        #expect(r.allSatisfy { abs($0) <= 0.490001 })
        for i in l.indices {
            #expect(abs(abs(l[i]) - 2 * abs(r[i])) < 0.000001)
        }
        #expect(abs(l[1] - 0.49) < 0.000001)
        #expect(abs(l[3] + 0.49) < 0.000001)
    }
}
