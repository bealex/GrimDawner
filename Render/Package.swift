// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrimDawnerRender",
    platforms: [ .macOS(.v15) ],
    products: [
        .library(name: "GrimDawnerRender", targets: [ "GrimDawnerRender" ]),
        .executable(name: "render-monsters", targets: [ "render-monsters" ]),
    ],
    dependencies: [
        .package(path: "../Mesh"),
        .package(path: "../Engine"),
    ],
    targets: [
        .target(
            name: "GrimDawnerRender",
            dependencies: [
                .product(name: "GrimDawnerMesh", package: "Mesh"),
                .product(name: "GrimDawnerEngine", package: "Engine"),
            ]
        ),
        .executableTarget(
            name: "render-monsters",
            dependencies: [
                "GrimDawnerRender",
                .product(name: "GrimDawnerEngine", package: "Engine"),
            ]
        ),
        .testTarget(
            name: "GrimDawnerRenderTests",
            dependencies: [
                "GrimDawnerRender",
                .product(name: "GrimDawnerMesh", package: "Mesh"),
                .product(name: "GrimDawnerEngine", package: "Engine"),
            ]
        ),
    ]
)
