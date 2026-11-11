// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CoreKit",
    products: [
        // 必须显式声明 static library product,否则 swift build 不产出 libCoreKit.a,
        // build.sh 的 -lCoreKit 只能捞到旧归档(2026-11-11 实证:增量改源后主 App 链接缺符号)
        .library(name: "CoreKit", type: .static, targets: ["CoreKit"]),
    ],
    targets: [
        .target(name: "CoreKit"),
        .executableTarget(
            name: "CoreKitTestRunner",
            dependencies: ["CoreKit"]
        ),
    ]
)
