// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrimDawnerMesh",
    platforms: [ .macOS(.v15) ],
    products: [ .library(name: "GrimDawnerMesh", targets: [ "GrimDawnerMesh" ]) ],
    targets: [
        .target(name: "GrimDawnerMesh"),
        .testTarget(name: "GrimDawnerMeshTests", dependencies: [ "GrimDawnerMesh" ]),
    ]
)
