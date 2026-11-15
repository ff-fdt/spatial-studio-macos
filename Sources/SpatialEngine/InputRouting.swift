import CoreAudio

public struct InputEndpoint: Equatable {
    public let id: String
    public let bundle: String?
    public let processes: [AudioObjectID]

    public init(id: String, bundle: String?, processes: [AudioObjectID]) {
        self.id = id
        self.bundle = bundle
        self.processes = processes
    }
}

public struct InputRoute: Equatable {
    public let id: String?
    public let including: [AudioObjectID]?
    public let excluding: [AudioObjectID]
    public let bundles: [String]

    public static func plan(for points: [StereoPoint], endpoints: [InputEndpoint]) -> [InputRoute] {
        let wanted = Set(points.compactMap(\.inputID))
        let dedicated = endpoints.filter { wanted.contains($0.id) && (!$0.processes.isEmpty || $0.bundle != nil) }
            .sorted { $0.id < $1.id }
        var routes = dedicated.map {
            InputRoute(id: $0.id, including: Array(Set($0.processes)).sorted(), excluding: [],
                       bundles: $0.bundle.map { [$0] } ?? [])
        }
        if points.contains(where: { $0.inputID == nil }) {
            let processes = Array(Set(dedicated.flatMap(\.processes))).sorted()
            let bundles = Array(Set(dedicated.compactMap(\.bundle))).sorted()
            routes.append(InputRoute(id: nil, including: nil, excluding: processes, bundles: bundles))
        }
        return routes
    }
}
