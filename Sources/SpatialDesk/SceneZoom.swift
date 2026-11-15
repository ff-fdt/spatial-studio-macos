enum SceneZoom {
    static let minimum = 0.40
    static let maximum = 6.0
    static let step = 1.20
    static func clamped(_ value: Double) -> Double { min(maximum, max(minimum, value)) }
}
