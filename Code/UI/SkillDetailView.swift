// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import SwiftUI

/// Everything one skill does at the rank the character has it.
struct SkillDetailView: View {
    let skill: ResolvedSkill
    /// Where the skill comes from — a mastery name, or "items" for a granted ability.
    let source: String
    /// What the worn gear changes about this skill, one entry per item that changes it.
    var modifications: [SkillModification] = []

    @Environment(\.quickSearch)
    private var search

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !skill.description.isEmpty {
                Text(skill.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SectionCard(title: "Rank") {
                VStack(spacing: 6) {
                    StatRow(title: "Points spent", value: "\(skill.baseLevel) / \(skill.maxLevel)")
                    StatRow(
                        title: "From devotion",
                        value: "+\(skill.devotionBonus)",
                        valueColor: skill.devotionBonus > 0 ? .green : .secondary
                    )
                    StatRow(
                        title: "From items",
                        value: "+\(skill.itemBonus)",
                        valueColor: skill.itemBonus > 0 ? .green : .secondary
                    )

                    Divider().padding(.vertical, 2)

                    StatRow(
                        title: "Effective rank",
                        value: "\(skill.totalLevel) / \(skill.ultimateLevel)",
                        valueColor: skill.isOverCapped ? .green : .primary
                    )
                }
            }

            if !skill.parameters.isEmpty {
                SectionCard(title: "Parameters") {
                    VStack(spacing: 6) {
                        ForEach(skill.parameters) { parameter in
                            StatRow(title: parameter.name, value: parameter.value)
                        }
                    }
                }
            }

            SectionCard(title: "Effects", subtitle: skill.isLearned ? "at rank \(skill.totalLevel)" : "at rank 1") {
                StatBlockView(block: skill.stats)
            }

            // Gear that changes a skill nobody has spent a point on changes nothing, so it reads faded.
            ForEach(modifications) { change in
                SectionCard(title: change.itemName, subtitle: "changes this skill") {
                    HStack(alignment: .top, spacing: 10) {
                        if !change.iconPath.isEmpty {
                            GameIcon(path: change.iconPath, size: 30, fallbackSymbol: "shippingbox")
                        }
                        SkillChangesView(changes: change.changes)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .opacity(skill.isLearned ? 1 : 0.45)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            GameIcon(path: skill.iconPath, size: 48, fallbackSymbol: "sparkle")
                .saturation(skill.isLearned ? 1 : 0)

            VStack(alignment: .leading, spacing: 4) {
                Text(skill.name)
                    .font(.title3.bold())
                    .quickSearchText(search.emphasis(matching: skill.name))
                HStack(spacing: 8) {
                    if !source.isEmpty { Text(source.capitalized) }
                    Text(skill.isLearned ? "Rank \(skill.levelBreakdown)" : "Not learned")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
