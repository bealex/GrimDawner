// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import SwiftUI

/// A monster's whole account — its sheet, its attacks and its loot — in a window of its own.
///
/// The sidebar shows what fits a sidebar; this is everything, and it reads the same selection, so
/// picking another monster in the main window moves this one with it.
struct MonsterStatsWindow: View {
    static let id = "monster-stats"

    let model: MainScreen.Model

    private enum Tab: String, CaseIterable, Identifiable {
        case stats = "Stats"
        case attacks = "Attacks"
        case loot = "Loot"
        case model = "Model"

        var id: String { rawValue }
    }

    @Environment(\.openWindow)
    private var openWindow
    @State
    private var tab: Tab = .stats
    /// The window filters its own rows, and starts on the first keystroke as the main window does.
    @State
    private var search = ""

    var body: some View {
        Group {
            if let monster = model.selectedMonster {
                content(monster)
            } else {
                DetailPlaceholder(title: "No monster selected", hint: "Pick one in the Monsters tab and it opens here.")
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .environment(\.textures, model.textures)
        .environment(\.damageIcons, model.damageIcons)
        .environment(\.quickSearch, QuickSearch(search))
        .background(TypeToSearch(text: $search).frame(width: 0, height: 0))
        .overlay(alignment: .top) {
            if !search.isEmpty { SearchOverlay(text: $search) }
        }
        .animation(.easeOut(duration: 0.15), value: search.isEmpty)
    }

    private func content(_ monster: ResolvedMonster) -> some View {
        VStack(spacing: 0) {
            header(monster)
            Divider()
            // A scroll view gives its content all the height it asks for, and a model view asks for
            // none — so the model sits in the pane itself and only the reading tabs scroll.
            if tab == .model {
                self.model(monster)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    switch tab {
                        case .attacks: abilities(monster)
                        case .loot: loot(monster)
                        default: MonsterSheetView(monster: monster, search: QuickSearch(search))
                    }
                }
            }
        }
        .navigationTitle(monster.name)
    }

    private func header(_ monster: ResolvedMonster) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(monster.name)
                    .font(.headline)
                    .foregroundStyle(monster.rank.color)
                    .lineLimit(1)
                Text(subtitle(monster))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Picker("Showing", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)

            Spacer(minLength: 8)

            MonsterLevelField(
                range: monster.levelRange,
                level: model.monsterLevel,
                setLevel: { model.selectMonster(path: monster.path, level: $0) },
                difficulty: model.monsterDifficulty,
                setDifficulty: {
                    model.selectMonster(path: monster.path, level: model.monsterLevel, difficulty: $0)
                }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func subtitle(_ monster: ResolvedMonster) -> String {
        [
            monster.rank.title,
            monster.difficulty.title,
            monster.race.isEmpty ? nil : monster.race,
            monster.nemesisOf.isEmpty ? nil : "the \(monster.nemesisOf)' nemesis",
            monster.faction.isEmpty ? nil : "\(monster.faction) faction pack",
            monster.experience > 0 ? "\(Int(monster.experience)) XP" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    /// Attacks down one column and passives down the other: a boss has a dozen of each, and one column
    /// of two dozen boxes reads as a scroll rather than as two kinds of thing.
    private func abilities(_ monster: ResolvedMonster) -> some View {
        let query = QuickSearch(search)
        let matching = monster.abilities.filter {
            !query.isActive || query.matches([ $0.title, $0.kind, $0.role.title ].compactMap { $0 })
        }
        let attacks = matching.filter { $0.role != .passive }
        let passives = matching.filter { $0.role == .passive }

        return HStack(alignment: .top, spacing: 14) {
            column("Attacks", subtitle: "at level \(monster.level)", abilities: attacks)
            column("Passives", subtitle: "always in effect", abilities: passives)
        }
        .padding(16)
    }

    @ViewBuilder
    private func column(_ title: String, subtitle: String, abilities: [MonsterAbility]) -> some View {
        if abilities.isEmpty {
            Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
        } else {
            SectionCard(title: title, subtitle: subtitle) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(abilities) { ability in
                        MonsterAbilityView(ability: ability)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private func model(_ monster: ResolvedMonster) -> some View {
        if monster.meshPath.isEmpty || self.model.modelRenderer == nil {
            Text("This one has no model to draw.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            MonsterModelPane(monster: monster, renderer: self.model.modelRenderer, database: self.model.records)
                .help("Drag to turn the model, scroll to move in")
        }
    }

    /// A summoned creature reads in this same window, which is what it is for.
    private func openMonster(_ path: String) {
        model.selectMonster(path: path, level: model.monsterLevel)
    }

    private func loot(_ monster: ResolvedMonster) -> some View {
        let query = QuickSearch(search)
        let slots = monster.loot.filter { slot in
            guard !search.isEmpty else { return true }

            return slot.entries.contains { entry in
                query.matches([ entry.title ] + entry.items.map(\.name))
            }
        }

        return VStack(alignment: .leading, spacing: 14) {
            if slots.isEmpty {
                Text(monster.loot.isEmpty ? "This one drops nothing." : "Nothing here matches the search.")
                    .foregroundStyle(.secondary)
            }
            ForEach(slots) { slot in
                SectionCard(title: slot.slot, subtitle: "\(Int(slot.chance))% carried") {
                    MonsterLootView(slot: slot, showsHeader: false, itemLimit: 60)
                }
            }
        }
        .padding(16)
    }
}
