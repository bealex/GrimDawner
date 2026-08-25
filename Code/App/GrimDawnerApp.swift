// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import SwiftUI

@main
struct GrimDawnerApp: App {
    /// One model for the whole app: the monster window is a second scene onto the same state, and a
    /// second copy of the database would cost hundreds of megabytes.
    @State
    private var model = MainScreen.Model()

    var body: some Scene {
        WindowGroup {
            // The app is a window onto a game that only has a dark one, and its artwork is lit for it.
            MainScreen.Component(model: model)
                .preferredColorScheme(.dark)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Window("Monster", id: MonsterStatsWindow.id) {
            MonsterStatsWindow(model: model)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1180, height: 820)

        Window("Item", id: ItemDetailWindow.id) {
            ItemDetailWindow(model: model)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 760, height: 720)

        Window("Model", id: MonsterModelWindow.id) {
            MonsterModelWindow(model: model)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 720, height: 760)
    }
}
