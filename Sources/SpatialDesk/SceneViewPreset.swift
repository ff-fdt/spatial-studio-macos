import simd

enum SceneViewPreset: String, CaseIterable, Identifiable {
    case overview = "默认"
    case top = "俯视"
    case front = "正面"
    case left = "左侧"
    case right = "右侧"
    case back = "后面"
    case bottom = "仰视"

    var id: Self { self }
    var angles: SIMD2<Double> {
        switch self {
        case .overview: SIMD2(0, 54)
        case .top: SIMD2(0, 90)
        case .front: SIMD2(180, 0)
        case .left: SIMD2(90, 0)
        case .right: SIMD2(-90, 0)
        case .back: SIMD2(0, 0)
        case .bottom: SIMD2(0, -90)
        }
    }

    var key: String {
        switch self {
        case .overview: "0"
        case .top: "1"
        case .front: "2"
        case .left: "3"
        case .right: "4"
        case .back: "5"
        case .bottom: "6"
        }
    }
}

struct ViewRequest: Equatable {
    var preset: SceneViewPreset = .overview
    var revision = 0
}
