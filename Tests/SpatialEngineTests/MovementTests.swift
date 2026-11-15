import simd
import Testing
@testable import SpatialEngine

@Suite("Automatic movements")
struct MovementTests {
    @Test("The 360-degree bearing stays continuous from one ear through the rear to the other")
    func bearing360AcrossBack() {
        var point = SourcePosition(azimuth: 0, elevation: 0, distance: 0.30)
        var before = SIMD3<Double>(1, 0, 0)
        for bearing in 90...270 {
            point.azimuth360 = Double(bearing)
            #expect(point.azimuth360 == Double(bearing))
            #expect(point.direction.z <= 1e-8)
            #expect(simd_distance(before, point.direction) < 0.02)
            before = point.direction
        }
        point.azimuth360 = 360
        #expect(point.azimuth360 == 0)
        #expect(simd_distance(point.direction, SIMD3(0, 0, 1)) < 1e-8)
    }

    @Test("Live movement edits preserve phase when changing distance or speed")
    func liveMovementEdits() {
        let origin = SourcePosition(azimuth: 0, elevation: 0, distance: 0.35)
        var session = ActiveSourceMovement(pattern: .orbit, from: origin, now: 100)
        let atQuarter = session.position(now: 107.5)
        #expect(abs(atQuarter.azimuth360 - 90) < 1e-8)
        session.reference.distance = 0.80
        let farther = session.position(now: 107.5)
        #expect(farther.azimuth360 == atQuarter.azimuth360)
        #expect(abs(farther.distance - 0.8) < 1e-8)

        session.setSpeed(2, now: 107.5)
        let changedSpeed = session.position(now: 107.5)
        #expect(changedSpeed == farther)
        let later = session.position(now: 111.25)
        #expect(abs(later.azimuth360 - 180) < 1e-8)
        #expect(abs(later.distance - 0.80) < 1e-8)

        var radial = ActiveSourceMovement(pattern: .distanceSweep, from: origin, now: 100)
        let oldDelta = radial.position(now: 105).distance / radial.position(now: 109).distance
        radial.reference.distance = 0.25
        let newDelta = radial.position(now: 105).distance / radial.position(now: 109).distance
        #expect(abs(oldDelta - newDelta) < 1e-8)
    }

    @Test("Full orbit passes both ears and behind without changing radius")
    func fullOrbit() {
        let source = SourcePosition(azimuth: 0, elevation: 0, distance: 0.35)
        let orbit = SourceMovement.orbit
        let expected: [SIMD3<Double>] = [
            SIMD3(1, 0, 0), SIMD3(0, 0, -1), SIMD3(-1, 0, 0), SIMD3(0, 0, 1)
        ]
        for i in 1...4 {
            let p = orbit.position(from: source, elapsed: orbit.period * Double(i) / 4)
            #expect(simd_distance(p.direction, expected[i - 1]) < 1e-8)
            #expect(p.distance == source.distance)
        }
    }

    @Test("Rear sweep moves ear to ear across the back and returns without entering the front")
    func rearHalfCircle() {
        let source = SourcePosition(azimuth: -90, elevation: 0, distance: 0.31)
        let motion = SourceMovement.rearSweep
        let expected: [SIMD3<Double>] = [
            SIMD3(0, 0, -1), SIMD3(1, 0, 0), SIMD3(0, 0, -1), SIMD3(-1, 0, 0)
        ]
        for quarter in 1...4 {
            let at = motion.position(from: source, elapsed: motion.period * Double(quarter) / 4)
            #expect(simd_distance(at.direction, expected[quarter - 1]) < 1e-8)
            #expect(at.distance == 0.31)
        }
        for i in 0...720 {
            let at = motion.position(from: source, elapsed: motion.period * Double(i) / 720)
            #expect(at.direction.z <= 1e-8)
        }
    }

    @Test("Close rear presets stay behind the head after the entrance")
    func closeRearPresets() {
        let origin = SourcePosition(azimuth: -48, elevation: 8, distance: 0.30)
        let presets = SourceMovement.allCases.filter { $0.group == .rearClose }
        #expect(presets.count == 5)
        for preset in presets {
            for i in 0...360 {
                let p = preset.position(from: origin, elapsed: 2 + preset.period * Double(i) / 360)
                #expect(p.direction.z < -0.45)
                #expect(p.distance >= 0.24 && p.distance <= 0.42)
            }
        }
    }

    @Test("Every path eases in and crosses the loop boundary without jumping")
    func smoothPaths() {
        let origins = [
            SourcePosition(azimuth: 0, elevation: 90, distance: 0),
            SourcePosition(azimuth: 179, elevation: -76, distance: 0.18),
            SourcePosition(azimuth: -170, elevation: 33, distance: 6),
            SourcePosition(azimuth: 96, elevation: 0, distance: 0.85),
            SourcePosition(azimuth: 0, elevation: -90, distance: 0.85)
        ]
        for motion in SourceMovement.allCases {
            for origin in origins {
                #expect(motion.position(from: origin, elapsed: 0) == origin)
                var previous = origin.direction * SourcePosition.sceneRadius(origin.distance)
                for i in 1...Int((motion.period + 2) * 45) {
                    let p = motion.position(from: origin, elapsed: Double(i) / 45)
                    #expect((-90...90).contains(p.elevation))
                    #expect((0...6).contains(p.distance))
                    let current = p.direction * SourcePosition.sceneRadius(p.distance)
                    #expect(simd_distance(previous, current) < 0.055)
                    previous = current
                }
            }
        }
    }
}
