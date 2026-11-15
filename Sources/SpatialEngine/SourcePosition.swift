import Foundation
import simd

/// Right, up, and front are positive X, Y, and Z.
public struct SourcePosition: Equatable, Sendable, Codable {
    public var azimuth: Double
    public var elevation: Double
    public var distance: Double

    public init(azimuth: Double = 25, elevation: Double = 12, distance: Double = 0.85) {
        self.azimuth = azimuth
        self.elevation = elevation
        self.distance = distance
    }

    /// Compass-style bearing with the display seam in front of the listener.
    public var azimuth360: Double {
        get {
            let angle = azimuth.truncatingRemainder(dividingBy: 360)
            return angle < 0 ? angle + 360 : angle == 0 ? 0 : angle
        }
        set {
            let angle = newValue.truncatingRemainder(dividingBy: 360)
            if angle > 180 { azimuth = angle - 360 }
            else if angle < -180 { azimuth = angle + 360 }
            else { azimuth = angle }
        }
    }

    public var direction: SIMD3<Double> {
        if elevation == 90 { return SIMD3(0, 1, 0) }
        if elevation == -90 { return SIMD3(0, -1, 0) }
        let a = azimuth * .pi / 180
        let e = elevation * .pi / 180
        return SIMD3(sin(a) * cos(e), sin(e), cos(a) * cos(e))
    }

    public init(direction: SIMD3<Double>, distance: Double, poleAzimuth: Double = 0) {
        let horizontal = hypot(direction.x, direction.z)
        self.init(
            azimuth: horizontal < 1e-8 ? poleAzimuth : atan2(direction.x, direction.z) * 180 / .pi,
            elevation: atan2(direction.y, horizontal) * 180 / .pi,
            distance: distance
        )
    }

    /// Narrow the pair continuously as it approaches either pole so both
    /// channels reach the directly overhead/below position together.
    public func stereoPair(halfWidth: Double) -> [SourcePosition] {
        guard halfWidth != 0, abs(elevation) < 90 else { return [self, self] }
        let a = azimuth * .pi / 180
        let offset = halfWidth * cos(elevation * .pi / 180) * .pi / 180
        let tangent = SIMD3(cos(a), 0, -sin(a))
        return [-1.0, 1.0].map {
            SourcePosition(direction: direction * cos(offset) + tangent * sin(offset) * $0,
                           distance: distance, poleAzimuth: azimuth)
        }
    }
}

public enum StereoChannel: String, CaseIterable, Codable, Sendable, Identifiable {
    case left, right, stereo
    public var id: Self { self }
    public var includesLeft: Bool { self != .right }
    public var includesRight: Bool { self != .left }
}

public struct StereoPoint: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var position: SourcePosition
    public var channel: StereoChannel
    public var inputID: String?
    public var gain: Float

    public init(position: SourcePosition, channel: StereoChannel, gain: Float = -3, inputID: String? = nil) {
        id = UUID()
        self.position = position
        self.channel = channel
        self.inputID = inputID
        self.gain = gain
    }
}

extension SourcePosition {
    public static func sceneRadius(_ metres: Double) -> Double {
        if metres <= 0.35 { return 0.30 * max(metres, 0) / 0.35 }
        return min(1, 0.30 + 0.70 * log(metres / 0.35) / log(6 / 0.35))
    }

    private static func distance(forRadius r: Double) -> Double {
        if r <= 0.30 { return min(0.35, max(0, r) / 0.30 * 0.35) }
        return 0.35 * exp((min(r, 1) - 0.30) / 0.70 * log(6 / 0.35))
    }

    public init(scenePoint: SIMD3<Double>) {
        let radius = simd_length(scenePoint)
        self.init(direction: scenePoint, distance: Self.distance(forRadius: radius))
    }

    /// Translate in the camera plane frozen at mouse-down. Retain its original
    /// depth, even if the point visually passes in front of or behind the head.
    public func dragged(right: SIMD3<Double>, up: SIMD3<Double>,
                        horizontal: Double, vertical: Double) -> SourcePosition {
        let face = simd_cross(right, up)
        let initial = direction * Self.sceneRadius(distance)
        let first = SIMD2(simd_dot(initial, right), simd_dot(initial, up))
        var screen = first + SIMD2(horizontal, vertical)
        let r = simd_length(screen)
        let depth = simd_dot(initial, face)
        let maxScreenRadius = sqrt(max(0, 1 - depth * depth))
        if r > maxScreenRadius, r > 0 { screen *= maxScreenRadius / r }
        let vector = right * screen.x + up * screen.y + face * depth
        let length = simd_length(vector)
        if length < 1e-8 {
            return SourcePosition(azimuth: azimuth, elevation: elevation, distance: 0)
        }
        return SourcePosition(direction: vector / length, distance: Self.distance(forRadius: length), poleAzimuth: azimuth)
    }
}
