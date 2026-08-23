// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import SwiftUI

@main
struct GrimDawnerApp: App {
    var body: some Scene {
        WindowGroup {
            // The app is a window onto a game that only has a dark one, and its artwork is lit for it.
            MainScreen.Component()
                .preferredColorScheme(.dark)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
