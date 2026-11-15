// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SpatialDesk",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "NearFieldDVF", exclude: ["LICENSE.txt"]),
        .target(name: "SpatialEngine", dependencies: ["NearFieldDVF"], exclude: ["LICENSE-atmos-control.txt"]),
        .executableTarget(name: "SpatialDesk", dependencies: ["SpatialEngine"], resources: [.copy("Resources"), .process("Localization")]),
        .testTarget(name: "SpatialEngineTests", dependencies: ["SpatialEngine"]),
    ]
)
