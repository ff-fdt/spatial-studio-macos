import simd

enum SceneViewPreset: String, CaseIterable, Identifiable {
    case overview = "默认"
    case top = "俯视"
    case front = "正视"
    case left = "左视"
    case right = "右视"
    case back = "后视"
    case bottom = "仰视"
    case closeLeftEar = "左耳特写"
    case closeRightEar = "右耳特写"

    var id: Self { self }
    var angles: SIMD2<Double> {
        switch self {
        case .overview: SIMD2(135, 30)
        case .top: SIMD2(0, 90)
        case .front: SIMD2(180, 0)
        case .left, .closeLeftEar: SIMD2(90, 0)
        case .right, .closeRightEar: SIMD2(-90, 0)
        case .back: SIMD2(0, 0)
        case .bottom: SIMD2(0, -90)
        }
    }

    var earSide: Double? {
        switch self {
        case .closeLeftEar: -1
        case .closeRightEar: 1
        default: nil
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
        case .closeLeftEar: "7"
        case .closeRightEar: "8"
        }
    }
}

struct ViewRequest: Equatable {
    var preset: SceneViewPreset = .overview
    var revision = 0
}
