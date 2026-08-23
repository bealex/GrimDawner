// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import SwiftUI

/// Both mastery trees, drawn on the game's own panels, plus whatever the gear grants.
struct SkillsTab: View {
    let character: ResolvedCharacter
    let search: QuickSearch
    @Binding
    var selected: ResolvedSkill?

    var body: some View {
        TabLayout {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(character.masteries) { mastery in
                        VStack(alignment: .leading, spacing: 6) {
                            header(mastery)
                            MasteryPanelView(mastery: mastery, search: search, selected: $selected)
                        }
                    }

                    if !character.itemGrantedSkills.isEmpty {
                        SectionCard(title: "Item-granted Skills") {
                            grantedSkills
                        }
                    }
                }
                .padding(16)
            }
        } detail: {
            if let selected {
                SkillDetailView(
                    skill: selected,
                    source: source(of: selected),
                    modifications: character.skillModifications[selected.recordPath.lowercased()] ?? []
                )
            } else {
                DetailPlaceholder(
                    title: "No skill selected",
                    hint: "Pick a skill to see what it does at its current rank."
                )
            }
        }
    }

    private func header(_ mastery: ResolvedMastery) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(mastery.name)
                .font(.headline)
            Text("Mastery \(mastery.level) / \(mastery.maxLevel)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(mastery.spentPoints) points spent")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var grantedSkills: some View {
        VStack(spacing: 6) {
            ForEach(character.itemGrantedSkills) { skill in
                Button(
                    action: { selected = skill },
                    label: {
                        HStack(spacing: 8) {
                            GameIcon(path: skill.iconPath, size: 22, fallbackSymbol: "sparkle")
                            StatRow(
                                title: skill.name,
                                value: skill.levelBreakdown,
                                valueColor: skill.bonusLevel > 0 ? .green : .primary,
                                highlights: false
                            )
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 4)
                        .contentShape(.rect)
                        .background(
                            selected?.recordPath == skill.recordPath ? Theme.accent.opacity(0.15) : .clear,
                            in: .rect(cornerRadius: 5)
                        )
                    }
                )
                .buttonStyle(.plain)
                .quickSearchText(search.emphasis(matching: [ skill.name ] + skill.stats.titles))
                .accessibilityLabel("\(skill.name), rank \(skill.levelBreakdown)")
            }
        }
    }

    /// Where a skill comes from — a mastery's name, or the gear that grants it.
    private func source(of skill: ResolvedSkill) -> String {
        let mastery = character.masteries.first { mastery in
            mastery.skills.contains { $0.recordPath == skill.recordPath }
        }
        return mastery?.name ?? "items"
    }
}
