// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import SwiftUI

/// Every number the character sheet knows, grouped the way the game groups them.
struct ParametersTab: View {
    let character: ResolvedCharacter
    let search: QuickSearch
    @Binding
    var selection: ParameterSelection?
    /// Opens a piece of gear on the inventory doll.
    let reveal: (ResolvedItem) -> Void

    var body: some View {
        TabLayout {
            ScrollView {
                MasonryLayout {
                    identityCard
                    attributesCard
                    offenceCard
                    defenceCard
                    armorCard
                    resistancesCard
                    controlResistancesCard
                    damageCard
                    ForEach(extraGroups, id: \.group) { group in
                        catalogueCard(group.group, lines: group.lines)
                    }
                    setsCard
                    progressCard
                    factionsCard
                }
                .padding(16)
            }
        } detail: {
            if let selection {
                ParameterDetailView(selection: selection, character: character, reveal: reveal)
            } else {
                DetailPlaceholder(
                    title: "No stat selected",
                    hint: "Click a number to see every item, skill and constellation behind it."
                )
            }
        }
    }

    private var sheet: CharacterSheet { character.sheet }

    // MARK: - Cards

    private var identityCard: some View {
        card(title: character.name, subtitle: character.isHardcore ? "Hardcore" : nil, titles: Self.identityTitles) {
            VStack(spacing: 6) {
                row("Class", character.className, icon: "person.crop.circle")
                row("Level", "\(character.level)", icon: "chevron.up.circle")
                row("Difficulty", character.difficulty.title, icon: "flame")
                row("Completed", character.greatestDifficulty.title, icon: "checkmark.seal")
                row("Iron Bits", character.save.info.iron.formatted(.number), icon: "circle.hexagongrid")
                row("Played", character.playTime.hoursAndMinutes, icon: "clock")
                row(
                    "Devotion",
                    "\(character.devotionPointsUsed) / \(character.save.biography.totalDevotionUnlocked)",
                    icon: "star"
                )
            }
        }
    }

    private static let identityTitles = [
        "Class", "Level", "Difficulty", "Completed", "Iron Bits", "Played", "Devotion",
    ]

    private var attributesCard: some View {
        card(title: "Attributes", titles: [ "Physique", "Cunning", "Spirit", "Unspent" ]) {
            VStack(spacing: 6) {
                attributeRow("Physique", sheet.physique, key: "characterStrength")
                attributeRow("Cunning", sheet.cunning, key: "characterDexterity")
                attributeRow("Spirit", sheet.spirit, key: "characterIntelligence")

                Divider().padding(.vertical, 2)

                row(
                    "Unspent attribute points",
                    "\(character.save.biography.attributePoints)",
                    valueColor: character.save.biography.attributePoints > 0 ? .orange : .secondary
                )
                row(
                    "Unspent skill points",
                    "\(character.save.biography.skillPoints)",
                    valueColor: character.save.biography.skillPoints > 0 ? .orange : .secondary
                )
            }
        }
    }

    private var offenceCard: some View {
        card(title: "Offence", titles: Self.offenceTitles) {
            VStack(spacing: 6) {
                row(
                    "Offensive Ability",
                    whole(sheet.offensiveAbility),
                    key: "characterOffensiveAbility",
                    icon: "target"
                )
                row("Crit Damage", "+\(whole(sheet.critDamage))%", key: "offensiveCritDamageModifier", icon: "burst")
                row("Attack Speed", "+\(whole(sheet.attackSpeed))%", key: "characterAttackSpeedModifier", icon: "hare")
                row(
                    "Casting Speed",
                    "+\(whole(sheet.castSpeed))%",
                    key: "characterSpellCastSpeedModifier",
                    icon: "wand.and.stars"
                )
                row(
                    "Movement Speed",
                    "+\(whole(sheet.movementSpeed))%",
                    key: "characterRunSpeedModifier",
                    icon: "figure.run"
                )
                row(
                    "Cooldown Reduction",
                    "\(whole(sheet.cooldownReduction))%",
                    key: "skillCooldownReduction",
                    icon: "timer"
                )
            }
        }
    }

    private static let offenceTitles = [
        "Offensive Ability", "Crit Damage", "Attack Speed", "Casting Speed", "Movement Speed",
        "Cooldown Reduction",
    ]

    private var defenceCard: some View {
        card(title: "Defence", titles: Self.defenceTitles) {
            VStack(spacing: 6) {
                row("Health", whole(sheet.health), key: "characterLife", icon: "heart.fill")
                row("Energy", whole(sheet.energy), key: "characterMana", icon: "bolt.fill")
                row(
                    "Health Regenerated",
                    "\(oneDecimal(sheet.healthRegen))/s",
                    key: "characterLifeRegen",
                    icon: "arrow.clockwise.heart"
                )
                row(
                    "Energy Regenerated",
                    "\(oneDecimal(sheet.energyRegen))/s",
                    key: "characterManaRegen",
                    icon: "bolt.badge.clock"
                )
                row("Armor Rating", whole(sheet.armor), key: "defensiveProtection", icon: "shield.fill")
                row(
                    "Armor Absorption",
                    "\(whole(sheet.armorAbsorption))%",
                    key: "defensiveAbsorptionModifier",
                    icon: "shield.lefthalf.filled"
                )
                row(
                    "Defensive Ability",
                    whole(sheet.defensiveAbility),
                    key: "characterDefensiveAbility",
                    icon: "figure.fencing"
                )
                row(
                    "Chance to Block",
                    "\(whole(sheet.contributions.value("defensiveBlockChance")))%",
                    key: "defensiveBlockChance",
                    icon: "shield"
                )
            }
        }
    }

    private static let defenceTitles = [
        "Health", "Energy", "Health Regenerated", "Energy Regenerated", "Armor Rating", "Armor Absorption",
        "Defensive Ability", "Chance to Block",
    ]

    /// The game reports armour per hit region, so this mirrors that rather than a single number.
    private var armorCard: some View {
        let slots = EquipmentSlot.allCases.filter { $0.hitRegionChanceKey != nil }

        return card(title: "Armor by Slot", subtitle: "weighted by chance to be hit", titles: slots.map(\.title)) {
            VStack(spacing: 6) {
                ForEach(slots, id: \.self) { slot in
                    row(
                        slot.title,
                        whole(sheet.armorBySlot[slot] ?? 0),
                        valueColor: (sheet.armorBySlot[slot] ?? 0) > 0 ? .primary : .secondary
                    )
                }
                if sheet.armorFromOtherSources != 0 {
                    Divider().padding(.vertical, 2)
                    row("Added to every slot", whole(sheet.armorFromOtherSources), icon: "plus.circle")
                }
            }
        }
    }

    private var resistancesCard: some View {
        card(title: "Resistances", titles: ResistanceKind.allCases.map(\.title)) {
            VStack(spacing: 8) {
                ForEach(ResistanceKind.allCases, id: \.self) { kind in
                    resistanceRow(kind)
                }
            }
        }
    }

    private func resistanceRow(_ kind: ResistanceKind) -> some View {
        let value = sheet.resistances[kind] ?? 0
        let maximum = sheet.maxResistances[kind] ?? 80

        return Button(action: { selection = .stat(title: kind.title, key: kind.resistanceKey) }) {
            VStack(spacing: 3) {
                HStack {
                    Text(kind.title)
                        .foregroundStyle(.secondary)
                    Text("\(whole(min(value, maximum)))%")
                        .monospacedDigit()
                        .foregroundStyle(value < 0 ? .red : .primary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    if value > maximum {
                        Text("over \(whole(value - maximum))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                MeterBar(value: max(value, 0), maximum: maximum, tint: kind.color)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .quickSearchText(search.emphasis(matching: kind.title))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.title) resistance \(Int(value)) percent, cap \(Int(maximum))")
    }

    private var controlResistancesCard: some View {
        let lines = StatCatalog.everyStat.filter { $0.group == .controlResistances }

        return card(title: StatGroup.controlResistances.title, titles: lines.map(\.title)) {
            VStack(spacing: 6) {
                ForEach(lines, id: \.key) { definition in
                    let value = sheet.contributions.value(definition.key)
                    row(
                        definition.title,
                        definition.unit.format(value, signed: false),
                        key: definition.key,
                        valueColor: value > 0 ? .primary : .secondary
                    )
                }
            }
        }
    }

    private var damageCard: some View {
        let types = DamageType.allCases.filter { $0 != .elemental }
            .filter { abs(sheet.damageModifiers[$0] ?? 0) >= 0.5 }

        return card(title: "Damage Bonuses", subtitle: "percent", titles: types.map(\.title)) {
            VStack(spacing: 6) {
                ForEach(types, id: \.self) { type in
                    Button(action: { selection = .stat(title: type.title, key: type.modifierKey) }) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(type.color)
                                .frame(width: 8, height: 8)
                            Text(type.title)
                                .foregroundStyle(.secondary)
                            Text("+\(whole(sheet.damageModifiers[type] ?? 0))%")
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.callout)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .quickSearchText(search.emphasis(matching: type.title))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(type.title) damage plus \(Int(sheet.damageModifiers[type] ?? 0)) percent")
                }
            }
        }
    }

    /// Groups the character sheet has no card of its own for: damage over time, retaliation, utility.
    private var extraGroups: [(group: StatGroup, lines: [(definition: StatDefinition, value: Double)])] {
        sheet.contributions.catalogued().filter { Self.extraGroupKinds.contains($0.group) }
    }

    private static let extraGroupKinds: Set<StatGroup> = [ .damageOverTime, .retaliation, .utility ]

    private func catalogueCard(
        _ group: StatGroup,
        lines: [(definition: StatDefinition, value: Double)]
    ) -> some View {
        card(title: group.title, titles: lines.map(\.definition.title)) {
            VStack(spacing: 6) {
                ForEach(lines, id: \.definition.key) { line in
                    row(
                        line.definition.title,
                        line.definition.unit.format(line.value),
                        key: line.definition.key,
                        valueColor: Theme.valueColor(line.value)
                    )
                }
            }
        }
    }

    /// What the worn set pieces grant on top of the items themselves.
    @ViewBuilder
    private var setsCard: some View {
        if !character.sets.isEmpty {
            card(title: "Item Sets", titles: character.sets.map(\.name)) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(character.sets) { set in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(set.name)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(set.isComplete ? Theme.accent : .primary)
                                Text(set.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }

                            if set.bonuses.hasNothingToShow, set.grantedSkills.isEmpty {
                                Text("Nothing yet at this many pieces")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                StatBlockView(block: set.bonuses)
                                ForEach(set.grantedSkills) { granted in
                                    Text(granted.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var progressCard: some View {
        card(title: "Record", titles: Self.recordTitles) {
            VStack(spacing: 6) {
                row("Kills", character.save.stats.kills.formatted(.number))
                row("Hero kills", character.save.stats.heroKills.formatted(.number))
                row("Champion kills", character.save.stats.championKills.formatted(.number))
                row(
                    "Deaths",
                    character.save.stats.deaths.formatted(.number),
                    valueColor: character.save.stats.deaths > 0 ? .orange : .secondary
                )
                row("Shrines restored", "\(character.save.stats.shrinesRestored)")
                row("Lore notes", "\(character.save.stats.loreNotesCollected)")
                row("Greatest hit", whole(Double(character.save.stats.greatestDamageInflicted)))
            }
        }
    }

    private static let recordTitles = [
        "Kills", "Hero kills", "Champion kills", "Deaths", "Shrines restored", "Lore notes", "Greatest hit",
    ]

    private var factionsCard: some View {
        card(
            title: "Factions",
            subtitle: "\(character.reputations.count) reputations",
            titles: character.factions.map(\.name)
        ) {
            VStack(spacing: 8) {
                ForEach(character.reputations) { faction in
                    reputationRow(faction)
                }

                if !character.hostilityGroups.isEmpty {
                    Divider()
                        .padding(.top, 4)

                    Text("At war with")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(character.hostilityGroups) { faction in
                        HStack(spacing: 8) {
                            GameIcon(path: faction.iconPath, size: 18, fallbackSymbol: "burst")
                            StatRow(
                                title: faction.name,
                                value: faction.tier,
                                valueColor: faction.isHostile ? .red : .secondary,
                                highlights: false
                            )
                        }
                        .quickSearchText(search.emphasis(matching: faction.name))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(faction.name): \(faction.tier)")
                    }
                }
            }
        }
    }

    private func reputationRow(_ faction: ResolvedFaction) -> some View {
        HStack(spacing: 8) {
            GameIcon(path: faction.iconPath, size: 24, fallbackSymbol: "flag")

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(faction.name)
                        .foregroundStyle(.secondary)
                    Text(faction.tier)
                        .foregroundStyle(faction.isHostile ? .red : .primary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.callout)

                HStack(spacing: 6) {
                    MeterBar(value: faction.progress, maximum: 1, tint: faction.isHostile ? .red : Theme.accent)
                    Text(faction.isAtCap ? "max" : faction.valueText)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
        }
        .quickSearchText(search.emphasis(matching: faction.name, faction.tier))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(faction.name): \(faction.tier), \(faction.valueText)")
    }

    // MARK: - Pieces

    private func card(
        title: String,
        subtitle: String? = nil,
        titles: [String],
        @ViewBuilder content: () -> some View
    ) -> some View {
        SectionCard(title: title, subtitle: subtitle, content: content)
            .quickSearchText(search.fade(unless: search.matches([ title ] + titles)))
    }

    private func row(
        _ title: String,
        _ value: String,
        key: String? = nil,
        icon: String? = nil,
        valueColor: Color = .primary
    ) -> some View {
        Button(action: { selection = key.map { .stat(title: title, key: $0) } }) {
            StatRow(title: title, value: value, valueColor: valueColor, icon: icon)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(key == nil)
    }

    private func attributeRow(_ title: String, _ attribute: CharacterSheet.Attribute, key: String) -> some View {
        Button(action: { selection = .stat(title: title, key: key) }) {
            HStack(spacing: 8) {
                Text(title)
                    .foregroundStyle(.secondary)
                Text(whole(attribute.total))
                    .monospacedDigit()
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if attribute.bonus != 0 {
                    Text("(+\(whole(attribute.bonus)))")
                        .monospacedDigit()
                        .font(.caption)
                        .foregroundStyle(Theme.valueColor(attribute.bonus))
                }
            }
            .font(.callout)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .quickSearchText(search.emphasis(matching: title))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(Int(attribute.total)), base \(Int(attribute.base))")
    }

    /// The game truncates the figures it prints on the character sheet rather than rounding them.
    private func whole(_ value: Double) -> String {
        value.rounded(.towardZero).formatted(.number.precision(.fractionLength(0)))
    }

    private func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
