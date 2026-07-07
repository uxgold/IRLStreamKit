// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "IRLStreamKit",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "IRLStreamKit", targets: ["IRLStreamKit"]),
        .library(name: "IRLStreamKitTestSupport", targets: ["IRLStreamKitTestSupport"]),
        .library(name: "IRLTPBonding", targets: ["IRLTPBonding"]),
    ],
    dependencies: [
        // Pinned to the exact revisions Moblin resolves (upstream tracks main branches).
        .package(url: "https://github.com/eerimoq/SrtSwift", revision: "7152305fd14439dcb5e7e13a4e4009f90c3b6968"),
        .package(url: "https://github.com/eerimoq/DataChannel", revision: "85316be8ab11dd0e76e2df604d685934ab697ee7"),
        .package(url: "https://github.com/eerimoq/Rist", revision: "e60e1c53c0f60321a103e4cbf120a710912da28a"),
        .package(url: "https://github.com/eerimoq/MetalPetal", revision: "f9b78897bd4214bb097f352a1bde0a4f4a1e2ddb"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.4.1"),
        .package(url: "https://github.com/Gisman4ik/TrueTime.swift", from: "5.2.0"),
    ],
    targets: [
        .target(
            name: "IRLStreamKit",
            dependencies: [
                .product(name: "Srt", package: "SrtSwift"),
                .product(name: "DataChannel", package: "DataChannel"),
                .product(name: "Rist", package: "Rist"),
                .product(name: "MetalPetal", package: "MetalPetal"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "TrueTime", package: "TrueTime.swift"),
                "IRLTPBonding",
            ],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
            ]
        ),
        .target(
            name: "IRLStreamKitTestSupport",
            dependencies: ["IRLStreamKit"]
        ),
        // The IRLTP sans-IO SRTLA sender (Rust core), exposed via UniFFI.
        // irltp_ffiFFI is the C module the xcframework vends (built by
        // irltp/scripts/build-ios.sh); IRLTPBonding is the generated Swift API.
        .binaryTarget(
            name: "irltp_ffiFFI",
            path: "Frameworks/irltp_ffi.xcframework"
        ),
        .target(
            name: "IRLTPBonding",
            dependencies: ["irltp_ffiFFI"]
        ),
        .testTarget(
            name: "IRLStreamKitTests",
            dependencies: ["IRLStreamKit", "IRLStreamKitTestSupport", "IRLTPBonding"]
        ),
    ]
)
