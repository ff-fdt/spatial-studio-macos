import SpatialEngine

enum ListeningPosition: String, CaseIterable, Identifiable {
    case front = "正前方"
    case back = "正后方"
    case leftEar = "左耳边"
    case rightEar = "右耳边"
    case above = "正头顶"
    case below = "正下方"
    case inside = "脑内"

    var id: Self { self }

    func placed(from previous: SourcePosition) -> SourcePosition {
        switch self {
        case .front: return SourcePosition(azimuth: 0, elevation: 0, distance: 0.30)
        case .back: return SourcePosition(azimuth: 180, elevation: 0, distance: 0.30)
        case .leftEar: return SourcePosition(azimuth: -90, elevation: 0, distance: 0.22)
        case .rightEar: return SourcePosition(azimuth: 90, elevation: 0, distance: 0.22)
        case .above: return SourcePosition(azimuth: 0, elevation: 90, distance: 0.28)
        case .below: return SourcePosition(azimuth: 0, elevation: -90, distance: 0.28)
        case .inside:
            var center = previous
            center.distance = 0
            return center
        }
    }
}
