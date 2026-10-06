// swift-tools-version: 5.9
// The iOS side of lunaway_nav: the spoken instructions. The Rust engine is
// not built here but by the package's build hook (hook/build.dart).

import PackageDescription

let package = Package(
    name: "lunaway_nav",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "lunaway-nav", targets: ["lunaway_nav"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "lunaway_nav",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
