import Foundation
import simd

public enum SourceMovement: String, CaseIterable, Sendable, Identifiable {
    case orbit = "水平环绕"
    case reverseOrbit = "反向水平环绕"
    case tiltedOrbit = "斜向环绕"
    case earSweep = "前半圈往返"
    case rearSweep = "后半圈往返"
    case overheadSweep = "头顶半圈往返"
    case frontRearSweep = "前后往返"
    case verticalSweep = "上下往返"
    case leftEarSweep = "左耳小范围往返"
    case rightEarSweep = "右耳小范围往返"
    case distanceSweep = "靠近与远离"
    case napeSweep = "后脑横扫"
    case rearCrownSweep = "后头顶横扫"
    case napeToCrown = "后脑到后头顶"
    case napeDepth = "后脑远近"
    case rearCrownLoop = "后头顶小圈"

    public enum Group: String, CaseIterable, Identifiable {
        case rearClose = "后脑与后头顶"
        case orbit = "环绕"
        case sweep = "往返"
        case distance = "距离"
        public var id: Self { self }
    }

    public var id: Self { self }

    public var group: Group {
        switch self {
        case .orbit, .reverseOrbit, .tiltedOrbit: .orbit
        case .distanceSweep: .distance
        case .napeSweep, .rearCrownSweep, .napeToCrown, .napeDepth, .rearCrownLoop: .rearClose
        default: .sweep
        }
    }

    public var period: Double {
        switch self {
        case .orbit, .reverseOrbit: 30
        case .tiltedOrbit: 36
        case .earSweep: 18
        case .rearSweep: 20
        case .overheadSweep: 24
        case .frontRearSweep: 22
        case .verticalSweep: 20
        case .leftEarSweep, .rightEarSweep: 12
        case .distanceSweep, .napeDepth: 14
        case .napeSweep: 16
        case .rearCrownSweep, .napeToCrown: 18
        case .rearCrownLoop: 22
        }
    }

    public func reference(from origin: SourcePosition) -> SourcePosition {
        let distance = origin.distance < 0.12 ? 0.36 : origin.distance
        var reference = origin
        switch self {
        case .earSweep: reference.distance = min(0.48, max(0.24, distance))
        case .rearSweep: reference.distance = min(0.46, max(0.28, distance))
        case .frontRearSweep, .overheadSweep: reference.distance = min(0.65, max(0.28, distance))
        case .leftEarSweep, .rightEarSweep: reference.distance = min(0.45, max(0.23, distance))
        case .distanceSweep: reference.distance = 0.38
        case .napeSweep: reference = SourcePosition(azimuth: 180, elevation: 8, distance: 0.29)
        case .rearCrownSweep: reference = SourcePosition(azimuth: 180, elevation: 46, distance: 0.33)
        case .napeToCrown: reference = SourcePosition(azimuth: 180, elevation: 29, distance: 0.31)
        case .napeDepth: reference = SourcePosition(azimuth: 180, elevation: 10, distance: 0.33)
        case .rearCrownLoop: reference = SourcePosition(azimuth: 180, elevation: 47, distance: 0.34)
        default: reference.distance = distance
        }
        return reference
    }

    public func position(from origin: SourcePosition, elapsed: Double) -> SourcePosition {
        let time = max(0, elapsed)
        if time == 0 { return origin }
        let phase = time.truncatingRemainder(dividingBy: period) / period * 2 * .pi
        let target = self.target(from: origin, phase: phase)
        if time >= 2 { return target }
        let entry = self.target(from: origin, phase: 0)

        let t = min(1, time / 2)
        let blend = t * t * (3 - 2 * t)
        let distance = origin.distance + (target.distance - origin.distance) * blend
        if self == .overheadSweep {
            // Rotate via the prescribed entry direction so an antipodal start
            // keeps the same swing plane throughout the entrance.
            let first = rotation(from: origin.direction, to: entry.direction, fraction: blend).act(origin.direction)
            let direction = rotation(from: entry.direction, to: target.direction, fraction: blend).act(first)
            return SourcePosition(direction: direction, distance: distance, poleAzimuth: origin.azimuth)
        }
        let change = wrap(entry.azimuth - origin.azimuth) + wrap(target.azimuth - entry.azimuth)
        return SourcePosition(azimuth: wrap(origin.azimuth + change * blend),
                              elevation: origin.elevation + (target.elevation - origin.elevation) * blend,
                              distance: distance)
    }

    private func target(from origin: SourcePosition, phase: Double) -> SourcePosition {
        var target = reference(from: origin)
        switch self {
        case .orbit, .reverseOrbit:
            let direction: Double = self == .orbit ? 1 : -1
            target.azimuth = wrap(origin.azimuth + direction * phase * 180 / .pi)
            target.elevation = min(55, max(-55, origin.elevation))
        case .tiltedOrbit:
            target.azimuth = wrap(origin.azimuth + phase * 180 / .pi)
            target.elevation = min(40, max(-40, origin.elevation)) + 26 * sin(phase)
        case .earSweep:
            let entry = asin(min(1, max(-1, origin.azimuth / 90)))
            target.azimuth = 90 * sin(phase + entry)
            target.elevation = 0
        case .rearSweep:
            let rearAngle = wrap(origin.azimuth - 180)
            let entry = asin(min(1, max(-1, rearAngle / 90)))
            target.azimuth = wrap(180 + 90 * sin(phase + entry))
            target.elevation = min(18, max(-18, origin.elevation))
        case .overheadSweep:
            let entry = asin(min(1, max(-1, origin.direction.x)))
            let theta = .pi / 2 * sin(phase + entry)
            target = SourcePosition(direction: SIMD3(sin(theta), cos(theta), 0),
                                    distance: target.distance, poleAzimuth: origin.azimuth)
        case .frontRearSweep:
            let side: Double = origin.azimuth < 0 ? -1 : 1
            let entry = asin(min(1, max(-1, abs(origin.azimuth) / 90 - 1)))
            target.azimuth = side * (90 + 90 * sin(phase + entry))
            target.elevation = min(24, max(-24, origin.elevation))
        case .verticalSweep:
            let entry = asin(min(1, max(-1, origin.elevation / 60)))
            target.elevation = 60 * sin(phase + entry)
        case .leftEarSweep, .rightEarSweep:
            let side: Double = self == .leftEarSweep ? -90 : 90
            target.azimuth = side + 15 * sin(phase)
            target.elevation = 9 * sin(phase + .pi / 2)
        case .distanceSweep:
            let distance = origin.distance < 0.12 ? 0.36 : origin.distance
            let entry = acos(min(1, max(-1, (distance - 0.38) / 0.16)))
            target.distance = 0.38 + 0.16 * cos(phase + entry)
        case .napeSweep:
            target.azimuth = wrap(180 + 33 * sin(phase))
        case .rearCrownSweep:
            target.azimuth = wrap(180 + 38 * sin(phase))
        case .napeToCrown:
            target.elevation += 23 * sin(phase)
        case .napeDepth:
            target.distance += 0.085 * sin(phase)
        case .rearCrownLoop:
            target.azimuth = wrap(180 + 26 * sin(phase))
            target.elevation += 12 * cos(phase)
        }

        return target
    }

    private func rotation(from start: SIMD3<Double>, to end: SIMD3<Double>, fraction: Double) -> simd_quatd {
        let dot = min(1, max(-1, simd_dot(start, end)))
        let cross = simd_cross(start, end)
        let fallback = abs(start.x) < 0.9 ? SIMD3<Double>(1, 0, 0) : SIMD3(0, 0, 1)
        let axis = simd_length_squared(cross) < 1e-10 ? simd_normalize(simd_cross(start, fallback))
                                                    : simd_normalize(cross)
        return simd_quatd(angle: acos(dot) * fraction, axis: axis)
    }

    private func wrap(_ degrees: Double) -> Double {
        var result = degrees.truncatingRemainder(dividingBy: 360)
        if result > 180 { result -= 360 }
        if result < -180 { result += 360 }
        return result
    }
}

/// Changing a trajectory's reference or playback rate never resets its clock.
public struct ActiveSourceMovement {
    public let pattern: SourceMovement
    public var reference: SourcePosition
    public private(set) var speed: Double = 1
    private let original: SourcePosition
    private let initialReference: SourcePosition
    private var clockAnchor: Double
    private var elapsedAtAnchor = 0.0

    public init(pattern: SourceMovement, from origin: SourcePosition, now: Double) {
        self.pattern = pattern
        original = origin
        initialReference = pattern.reference(from: origin)
        reference = initialReference
        clockAnchor = now
    }

    public mutating func setSpeed(_ rate: Double, now: Double) {
        elapsedAtAnchor = elapsed(now: now)
        clockAnchor = now
        speed = min(2, max(0.25, rate))
    }

    public func position(now: Double) -> SourcePosition {
        var result = pattern.position(from: original, elapsed: elapsed(now: now))
        result.azimuth360 = result.azimuth + reference.azimuth - initialReference.azimuth
        result.elevation = min(90, max(-90, result.elevation + reference.elevation - initialReference.elevation))
        result.distance = min(6, max(0, result.distance * reference.distance / max(0.025, initialReference.distance)))
        return result
    }

    public mutating func setInstantaneousDistance(_ distance: Double, now: Double) {
        let measured = pattern.position(from: original, elapsed: elapsed(now: now)).distance
        reference.distance = min(6, max(0, distance * initialReference.distance / max(0.025, measured)))
    }

    private func elapsed(now: Double) -> Double {
        elapsedAtAnchor + max(0, now - clockAnchor) * speed
    }
}
