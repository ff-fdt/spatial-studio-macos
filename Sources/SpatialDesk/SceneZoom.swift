enum SceneZoom {
    static let minimum = 0.40
    static let maximum = 20.0
    static let earExitThreshold = 4.0
    static let initial = 1.70
    static let step = 1.20
    static func clamped(_ value: Double) -> Double { min(maximum, max(minimum, value)) }
}
