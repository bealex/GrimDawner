// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import SwiftUI

/// The awakened item an epic piece becomes, and where to find it.
struct ItemUpgrade: Sendable {
    let name: String
    let path: String
}

/// Everything one item carries: its parts, the stats each grants, and the skills it confers.
struct ItemDetailView: View {
    let item: ResolvedItem
    /// The directory lists items no character owns, so there is no roll to show — only the band.
    var showsRolls = true
    /// The character wearing this, as far as its skill lines need. Absent in the directory, where
    /// there is no character for a skill to belong to or a point to have been spent on.
    var wearer: SkillContext?
    /// Opens one of the character's own skills on its mastery panel, when there is a panel to open.
    var revealSkill: ((String) -> Void)?
    /// What the Ashes of Awakening turn this item into, for the directory that can go and show it.
    var upgrade: ItemUpgrade?
    var selectItem: ((String) -> Void)?
    /// Every level the game writes this item at, for the directory that lets you read any of them.
    /// Who sells this and at what standing, for the augments a faction stocks.
    var vendor: (faction: String, standing: String)?
    var tiers: [CataloguedItem] = []
    var tierPath: String?
    var selectTier: ((String) -> Void)?

    @Environment(\.quickSearch)
    private var search

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                GameIcon(path: item.iconPath, size: 64, fallbackSymbol: "shippingbox")
                    .itemQualityBadge(item.qualityMarkPath, size: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName)
                        .font(.title3.bold())
                        .foregroundStyle(item.rarity.color)
                        .quickSearchText(search.emphasis(matching: item.displayName))
                    HStack(spacing: 8) {
                        Text(item.rarity.title)
                        if item.itemLevel > 0 { Text("Item Level \(item.itemLevel)") }
                        if item.levelRequirement > 0 { Text("Requires Level \(item.levelRequirement)") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            if !item.requirements.isEmpty {
                SectionCard(title: "Requirements") {
                    VStack(spacing: 6) {
                        ForEach(item.requirements.sorted(by: { $0.key < $1.key }), id: \.key) { name, value in
                            StatRow(title: name, value: value.formatted(.number.precision(.fractionLength(0))))
                        }
                    }
                }
            }

            if let vendor, !vendor.faction.isEmpty {
                SectionCard(title: "Sold by") {
                    StatRow(title: vendor.faction, value: vendor.standing, valueColor: Theme.accent)
                }
            }

            if tiers.count > 1, let selectTier {
                Picker("Level", selection: Binding(get: { tierPath ?? tiers[0].path }, set: selectTier)) {
                    ForEach(tiers) { tier in
                        Text(tier.levelRequirement > 0 ? "Level \(tier.levelRequirement)" : "Any level")
                            .tag(tier.path)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .help("Which level tier of this item to read")
            }

            if let upgrade {
                SectionCard(title: "Ashes of Awakening") {
                    Button {
                        selectItem?(upgrade.path)
                    } label: {
                        StatRow(title: "Awakens into \(upgrade.name)", value: "", icon: "arrow.up.forward.square")
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectItem == nil)
                    .help("Show \(upgrade.name)")
                }
            }

            SectionCard(title: "Total Bonuses") {
                StatBlockView(
                    block: item.stats,
                    lowest: item.statsLowest,
                    highest: item.statsHighest,
                    showsRolls: showsRolls
                )
            }

            // A relic, a component or a proc weapon carries its skill on the base record itself.
            if let base = item.parts.first(where: { $0.kind == .base }), !base.grantedSkills.isEmpty {
                SectionCard(title: "Granted Skills") {
                    grantedSkills(base.grantedSkills)
                }
            }

            ForEach(item.parts.filter { $0.kind != .base }) { part in
                SectionCard(title: part.title, subtitle: part.subtitle, iconPath: part.iconPath) {
                    VStack(alignment: .leading, spacing: 8) {
                        // An ascendant affix has no bonuses of its own, only the skill it changes.
                        if !part.stats.hasNothingToShow || part.grantedSkills.isEmpty {
                            StatBlockView(block: part.stats)
                        }
                        grantedSkills(part.grantedSkills)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !item.flavourText.isEmpty {
                Text(item.flavourText)
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func grantedSkills(_ skills: [GrantedSkill]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(skills) { granted in
                GrantedSkillView(granted: granted, wearer: wearer, reveal: revealSkill)
            }
        }
    }
}

/// What an item's skill actually does, rather than the name of the record behind it.
struct GrantedSkillView: View {
    let granted: GrantedSkill
    /// The character reading it, when there is one. Absent in the catalogues, where no skill is
    /// anybody's own and nothing has a point spent on it.
    var wearer: SkillContext?
    var reveal: ((String) -> Void)?

    /// Whether the skill is one of the character's own, which the skill panels already show in full.
    private var isOwn: Bool { wearer?.own.contains(granted.recordPath.lowercased()) ?? false }

    /// A change to a skill the character has spent no point on changes nothing, so it reads faded.
    private var isIdle: Bool {
        guard let wearer, granted.kind == .enhanced else { return false }

        return !wearer.learned.contains(granted.recordPath.lowercased())
    }

    @Environment(\.quickSearch)
    private var search

    /// A line about one of the character's own skills opens that skill's panel; anything else — a skill
    /// of another class, or an ability the item itself grants — has no panel to open.
    private var opensPanel: Bool { isOwn && granted.kind != .granted && reveal != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                reveal?(granted.recordPath)
            } label: {
                HStack(spacing: 6) {
                    if let icon = granted.skill?.iconPath, !icon.isEmpty {
                        GameIcon(path: icon, size: 18, fallbackSymbol: granted.symbolName)
                    } else {
                        Image(systemName: granted.symbolName)
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                    }
                    Text(granted.summary)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        // A skill line says what the item does; a search for something else must not
                        // fade it out of the card.
                        .quickSearchText(search.highlight(matching: granted.title))
                    // A skill outside the character's masteries appears on no panel, so the line says
                    // whose it is instead of pointing at one.
                    if granted.kind != .granted, !isOwn, let mastery = granted.mastery {
                        Text(mastery)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if opensPanel {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!opensPanel)
            .help(opensPanel ? "Show \(granted.title) on its mastery panel" : "")

            // Only a skill the item brings into being is described here: `+N` and "Enhances" lines
            // point at a skill whose own panel says what it does.
            if granted.kind == .enhanced, let changes = granted.modifications, !changes.isEmpty {
                SkillChangesView(changes: changes)
            }

            if let skill = granted.skill, granted.kind == .granted {
                if !skill.description.isEmpty {
                    Text(skill.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !skill.parameters.isEmpty {
                    Text(skill.parameters.map { "\($0.name) \($0.value)" }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !skill.stats.hasNothingToShow {
                    StatBlockView(block: skill.stats)
                }

                SkillPetView(skill: skill)
            }
        }
        .opacity(isIdle ? 0.45 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// What an item changes about a skill: its stats, and the parameters no stat covers.
struct SkillChangesView: View {
    let changes: SkillChanges

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !changes.stats.hasNothingToShow {
                StatBlockView(block: changes.stats)
            }
            ForEach(changes.parameters) { parameter in
                StatRow(title: parameter.name, value: parameter.value)
            }
        }
    }
}

/// Renders a stat block grouped the way the character sheet groups it.
struct StatBlockView: View {
    let block: StatBlock
    /// The ends of the band each figure rolled in, when it is an item's and rolls at all.
    var lowest: StatBlock?
    var highest: StatBlock?
    /// False shows a rolled figure as its band alone, for an item nobody owns a copy of.
    var showsRolls = true
    /// How far apart the groups sit. A card small enough reads better with its lines running together.
    var groupSpacing: CGFloat = 10

    @Environment(\.damageIcons)
    private var damageIcons

    var body: some View {
        let groups = block.catalogued()

        if block.hasNothingToShow {
            Text("No bonuses")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            // The group's name is left out: what a stat is about reads from its own line, and a column
            // of headings over one or two lines each is noise.
            VStack(alignment: .leading, spacing: groupSpacing) {
                ForEach(groups, id: \.group) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(StatBlock.merged(group.lines), id: \.title) { line in
                            let bands = line.parts.compactMap { band(of: $0) }
                            let figures = Theme.figures(line.parts)
                            StatRow(
                                title: line.title,
                                value: showsRolls || bands.count != line.parts.count
                                    ? figures : bands.joined(separator: " & "),
                                valueColor: Theme.valueColor(line.parts.first?.value ?? 0),
                                accents: [
                                    Theme.damageAccent(
                                        forStatKey: line.parts.first?.definition.key ?? "",
                                        in: line.title
                                    )
                                ]
                                .compactMap { $0 },
                                iconPath: damageIcons[
                                    Theme.damageToken(forStatKey: line.parts.first?.definition.key ?? "") ?? ""
                                ],
                                range: showsRolls && !bands.isEmpty
                                    ? "[\(bands.joined(separator: " & "))]" : nil
                            )
                        }
                    }
                }

                ForEach(block.conversions, id: \.self) { conversion in
                    StatRow(
                        title: "\(conversion.source) \(Theme.convertsTo) \(conversion.target)",
                        value: "\(Int(conversion.percent))%",
                        valueColor: Theme.valueColor(conversion.percent),
                        // Both sides of a conversion name a type, and each reads in its own colour.
                        accents: [
                            Theme.damageAccent(forStatKey: "offensive\(conversion.source)", in: conversion.source),
                            Theme.damageAccent(forStatKey: "offensive\(conversion.target)", in: conversion.target),
                        ]
                        .compactMap { $0 }
                    )
                }

                if block.allSkillBonus != 0 {
                    StatRow(title: "To all skills", value: "+\(block.allSkillBonus)", valueColor: .green)
                }
            }
        }
    }
}

extension StatBlockView {
    /// The band a rolled figure can land in, as `24–36`.
    fileprivate func band(of line: (definition: StatDefinition, value: Double)) -> String? {
        guard
            let low = lowest?.value(line.definition.key),
            let high = highest?.value(line.definition.key),
            low.rounded() != high.rounded()
        else { return nil }

        let unit = line.definition.unit
        return "\(unit.format(low, signed: false))–\(unit.format(high, signed: false))"
    }
}
