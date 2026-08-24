// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import GrimDawnerRender
import SwiftUI

/// The monster's own model, in a window with room to look at it.
///
/// It follows the selection, as the stats window does, so picking another monster turns this one into
/// that one. The view fills the window, whatever size it is dragged to.
struct MonsterModelWindow: View {
    static let id = "monster-model"

    let model: MainScreen.Model

    var body: some View {
        Group {
            if let monster = model.selectedMonster, !monster.meshPath.isEmpty, model.modelRenderer != nil {
                MonsterModelPane(monster: monster, renderer: model.modelRenderer, database: model.records)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(monster.name)
                    .navigationSubtitle(subtitle(monster))
            } else {
                DetailPlaceholder(
                    title: "No model to show",
                    hint: "Pick a monster in the Monsters tab; the ones with a model open here."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 360, minHeight: 360)
    }

    private func subtitle(_ monster: ResolvedMonster) -> String {
        [ monster.rank.title, monster.race, "drag to turn, scroll to move in" ]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
