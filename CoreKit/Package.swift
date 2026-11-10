// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CoreKit",
    targets: [
        .target(name: "CoreKit"),
        .executableTarget(
            name: "CoreKitTestRunner",
            dependencies: ["CoreKit"]
        ),
    ]
)
