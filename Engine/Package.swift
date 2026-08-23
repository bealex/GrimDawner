// swift-tools-version: 6.0
//
// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import PackageDescription

/// Everything the app knows that is not a view: the save reader, the game database, the resolvers and
/// the stat engine. Kept apart so its tests run on their own, without an app to host them.
let package = Package(
    name: "GrimDawnerEngine",
    platforms: [ .macOS(.v15) ],
    products: [
        .library(name: "GrimDawnerEngine", targets: [ "GrimDawnerEngine" ]),
    ],
    targets: [
        .target(name: "GrimDawnerEngine"),
        .testTarget(name: "GrimDawnerEngineTests", dependencies: [ "GrimDawnerEngine" ]),
    ]
)
