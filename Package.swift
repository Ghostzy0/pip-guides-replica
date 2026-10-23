// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "PipGuides", platforms: [.macOS(.v14)], products: [
    .library(name: "GuidesCore", targets: ["GuidesCore"]),
    .executable(name: "PipGuides", targets: ["PipGuides"])
], targets: [
    .target(name: "GuidesCore"),
    .executableTarget(name: "PipGuides", dependencies: ["GuidesCore"]),
    .testTarget(name: "GuidesCoreTests", dependencies: ["GuidesCore"])
], swiftLanguageModes: [.v5])
