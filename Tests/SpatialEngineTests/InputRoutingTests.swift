import Testing
@testable import SpatialEngine

@Suite("Audio input routing")
struct InputRoutingTests {
    @Test("Two app inputs get independent routes and are excluded from the system mix")
    func splitApplicationsFromSystem() throws {
        let music = InputEndpoint(id: "music", bundle: "app.music", processes: [25, 20])
        let web = InputEndpoint(id: "web", bundle: "app.web", processes: [29])
        let other = InputEndpoint(id: "other", bundle: "app.other", processes: [99])
        let points = [
            StereoPoint(position: .init(), channel: .stereo, inputID: music.id),
            StereoPoint(position: .init(), channel: .stereo, inputID: web.id),
            StereoPoint(position: .init(), channel: .stereo)
        ]
        let plan = InputRoute.plan(for: points, endpoints: [other, web, music])
        #expect(plan.map(\.id) == ["music", "web", nil])
        #expect(plan[0].including == [20, 25])
        #expect(plan[1].including == [29])
        let system = try #require(plan.last)
        #expect(system.including == nil)
        #expect(system.excluding == [20, 25, 29])
        #expect(system.bundles == ["app.music", "app.web"])
    }

    @Test("Multiple stereo points reuse the same input and turning off the last system point does not capture other apps")
    func sharedInput() throws {
        let app = InputEndpoint(id: "music", bundle: "app.music", processes: [20])
        let points = [-48.0, 48.0].map {
            StereoPoint(position: .init(azimuth: $0), channel: .stereo, inputID: app.id)
        }
        let plan = InputRoute.plan(for: points, endpoints: [app])
        #expect(plan.count == 1)
        #expect(plan.first?.id == app.id)
        var bothSystem = points
        for index in bothSystem.indices { bothSystem[index].inputID = nil }
        let system = InputRoute.plan(for: bothSystem, endpoints: [app])
        #expect(system.count == 1)
        #expect(system[0].including == nil)
        #expect(system[0].excludedNothing)
    }
}

private extension InputRoute {
    var excludedNothing: Bool { excluding.isEmpty && bundles.isEmpty }
}
