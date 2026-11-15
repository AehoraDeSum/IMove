// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IMove",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "IMove", targets: ["IMoveApp"])],
    targets: [
        .target(name: "IMoveCore"),
        .executableTarget(name: "IMoveApp", dependencies: ["IMoveCore"])
    ]
)
