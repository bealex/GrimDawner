// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import GrimDawnerRender
import SwiftUI

/// One monster read at a level: what it is, what it can do, and what it leaves behind.
///
/// Its full stat sheet does not fit a sidebar, so that opens in a window of its own.
struct MonsterDetailView: View {
    let monster: ResolvedMonster
    let level: Int
    let mode: MonsterMode
    let setLevel: (Int) -> Void
    let setMode: (MonsterMode) -> Void
    /// Draws the game's own model, when the game folder is open.
    var renderer: ModelRenderer?
    /// The records behind the gear a human is drawn from.
    var database: GameDatabase?

    @Environment(\.quickSearch)
    private var search
    @Environment(\.openWindow)
    private var openWindow
    /// Reads a summoned creature in place of this one, which is what clicking one is for.
    var openMonster: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if !monster.meshPath.isEmpty, renderer != nil {
                // Played rather than left in the bind pose: the first animation is the combat stance,
                // and a creature standing ready reads far better than one with its arms hanging.
                MonsterModelView(
                    monster: monster,
                    renderer: renderer,
                    database: database,
                    animation: monster.animations.first
                )
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: Theme.cardCornerRadius))
                .help("The game's own model — drag to turn it, scroll to move in")
            }
            levelControl
            summaryCard
            if !monster.attacks.isEmpty {
                SectionCard(title: "Attacks", subtitle: "at level \(monster.level)") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(monster.attacks) { ability in
                            MonsterAbilityView(ability: ability, openMonster: openMonster)
                        }
                    }
                }
            }
            if !monster.passives.isEmpty {
                SectionCard(title: "Passives", subtitle: "always in effect") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(monster.passives) { ability in
                            MonsterAbilityView(ability: ability, openMonster: openMonster)
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(monster.title)
                .font(.title3.bold())
                .foregroundStyle(monster.rank.color)
                .quickSearchText(search.emphasis(matching: monster.title))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        [
            monster.rank.title,
            monster.race.isEmpty ? nil : monster.race,
            monster.nemesisOf.isEmpty ? nil : "the \(monster.nemesisOf)' nemesis",
            monster.experience > 0 ? "\(Int(monster.experience)) XP" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var levelControl: some View {
        HStack(spacing: 10) {
            MonsterLevelField(range: monster.levelRange, level: level, setLevel: setLevel, mode: mode, setMode: setMode)

            Button("All Stats…") { openWindow(id: MonsterStatsWindow.id) }
                .help("Opens this monster's whole sheet, its attacks and its loot in a window of its own")
        }
    }

    private var summaryCard: some View {
        SectionCard(title: "At a glance") {
            VStack(spacing: 6) {
                StatRow(
                    title: "Health",
                    value: whole(monster.health),
                    icon: "heart.fill",
                    range: monster.cancelsAscendantMode ? "outside ascendant mode" : nil
                )
                .help(
                    monster.cancelsAscendantMode
                        ? "This one carries a skill that cancels the game's ascendant-mode adjustment, so "
                            + "neither counts here."
                        : ""
                )
                StatRow(title: "Energy", value: whole(monster.energy), icon: "bolt.fill")
                StatRow(title: "Offensive Ability", value: whole(monster.offensiveAbility), icon: "target")
                StatRow(title: "Defensive Ability", value: whole(monster.defensiveAbility), icon: "figure.fencing")
                StatRow(title: "Armor", value: whole(monster.armor), icon: "shield.fill")
            }
        }
    }

    private func whole(_ value: Double) -> String {
        value.rounded().formatted(.number.precision(.fractionLength(0)))
    }
}
