// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import SwiftUI

/// Every number the character sheet knows, grouped the way the game groups them.
struct ParametersTab: View {
    let character: ResolvedCharacter
    let search: QuickSearch
    @Binding
    var selection: ParameterSelection?
    /// Opens a piece of gear on the inventory doll.
    let reveal: (ResolvedItem) -> Void

    @Environment(\.damageIcons)
    private var damageIcons

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
                    blockingCard
                    controlResistancesCard
                    damageCard
                    ForEach(extraGroups, id: \.group) { group in
                        catalogueCard(group.group, lines: group.lines)
                    }
                    petBonusesCard
                    setsCard
                    progressCard
                    factionsCard
                }
                .padding(16)
            }
        } detail: {
            if let selection {
                ParameterDetailView(selection: selection, character: character, reveal: reveal)
                    // The query narrows the sheet, which is what is being searched. The sidebar is the
                    // answer to a line already picked out of it, so nothing in it dims.
                    .environment(\.quickSearch, QuickSearch())
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
        let stats = sheet.contributions

        return card(title: "Offence", titles: Self.offenceTitles) {
            VStack(spacing: 6) {
                row(
                    "Offensive Ability",
                    whole(sheet.offensiveAbility),
                    key: "characterOffensiveAbility",
                    icon: "target"
                )
                row("Crit Damage", "+\(whole(sheet.critDamage))%", key: "offensiveCritDamageModifier", icon: "burst")
                row(
                    "Attacks per Second",
                    sheet.attacksPerSecond.formatted(.number.precision(.fractionLength(2))),
                    icon: "timer"
                )
                row("Attack Speed", "\(whole(sheet.attackSpeed))%", key: "characterAttackSpeedModifier", icon: "hare")
                row(
                    "Casting Speed",
                    "\(whole(sheet.castSpeed))%",
                    key: "characterSpellCastSpeedModifier",
                    icon: "wand.and.stars"
                )
                row(
                    "Movement Speed",
                    "\(whole(sheet.movementSpeed))%",
                    key: "characterRunSpeedModifier",
                    icon: "figure.run"
                )
                row(
                    "Cooldown Reduction",
                    "\(whole(sheet.cooldownReduction))%",
                    key: "skillCooldownReduction",
                    icon: "timer"
                )
                row(
                    "All Damage",
                    "+\(whole(stats.value("offensiveTotalDamageModifier")))%",
                    key: "offensiveTotalDamageModifier",
                    icon: "bolt.horizontal"
                )
                row(
                    "Life Steal",
                    percent(stats.value("offensiveLifeLeechMin")),
                    key: "offensiveLifeLeechMin",
                    icon: "drop.fill"
                )
                if stats.value("racialBonusPercentDamage") != 0 {
                    row(
                        "Damage to Race",
                        "+\(whole(stats.value("racialBonusPercentDamage")))%",
                        key: "racialBonusPercentDamage",
                        icon: "pawprint"
                    )
                }
                if stats.value("racialBonusPercentDefense") != 0 {
                    row(
                        "Reduced Damage from Race",
                        "\(whole(stats.value("racialBonusPercentDefense")))%",
                        key: "racialBonusPercentDefense",
                        icon: "pawprint"
                    )
                }
            }
        }
    }

    private static let offenceTitles = [
        "Offensive Ability", "Crit Damage", "Attack Speed", "Casting Speed", "Movement Speed",
        "Cooldown Reduction", "All Damage", "Life Steal", "Damage to Race", "Reduced Damage from Race",
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
                // Armour is the one figure the game rounds rather than truncates: 1659.8 reads as 1660
                // where a pool of 16851.5 reads as 16851.
                row("Armor Rating", whole(sheet.armor.rounded()), key: "defensiveProtection", icon: "shield.fill")
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
                row(
                    "Damage Absorption",
                    percent(sheet.contributions.value("damageAbsorptionPercent")),
                    key: "damageAbsorptionPercent",
                    icon: "shield.lefthalf.filled"
                )
                row(
                    "Energy Absorption",
                    percent(sheet.contributions.value("characterEnergyAbsorptionPercent")),
                    key: "characterEnergyAbsorptionPercent",
                    icon: "bolt.shield"
                )
                row(
                    "Healing Increased",
                    percent(sheet.contributions.value("characterHealIncreasePercent")),
                    key: "characterHealIncreasePercent",
                    icon: "cross.case"
                )
                row(
                    "Constitution",
                    percent(sheet.contributions.value("characterConstitutionModifier")),
                    key: "characterConstitutionModifier",
                    icon: "heart.text.square"
                )
            }
        }
    }

    private static let defenceTitles = [
        "Health", "Energy", "Health Regenerated", "Energy Regenerated", "Armor Rating", "Armor Absorption",
        "Defensive Ability", "Chance to Block", "Damage Absorption", "Energy Absorption",
        "Healing Increased", "Constitution",
    ]

    /// The game reports armour per hit region, so this mirrors that rather than a single number.
    private var armorCard: some View {
        let slots = EquipmentSlot.allCases.filter { $0.hitRegionChanceKey != nil }

        return card(title: "Armor by Slot", subtitle: "weighted by chance to be hit", titles: slots.map(\.title)) {
            VStack(spacing: 6) {
                ForEach(slots, id: \.self) { slot in
                    row(
                        slot.title,
                        whole((sheet.armorBySlot[slot] ?? 0).rounded()),
                        detail: "\(whole(sheet.armorHitChance[slot] ?? 0))% of hits"
                    )
                }
                if sheet.armorFromOtherSources != 0 {
                    Divider().padding(.vertical, 2)
                    row("Shared by every region", whole(sheet.armorFromOtherSources.rounded()), icon: "plus.circle")
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
            HStack(spacing: 6) {
                Text("\(whole(min(value, maximum)))%")
                    .monospacedDigit()
                    .foregroundStyle(value < 0 ? .red : .primary)
                Text(kind.title)
                    .foregroundStyle(kind.color)
                Spacer(minLength: 6)
                if value > maximum {
                    Text(Theme.overCap(value - maximum))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if let icon = damageIcons[Theme.damageToken(forStatKey: kind.resistanceKey) ?? ""] {
                    GameIcon(path: icon, size: 15, fallbackSymbol: "circle.fill")
                }
            }
            .font(.callout)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .quickSearchText(search.emphasis(matching: kind.title))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Int(value)) percent \(kind.title) resistance, cap \(Int(maximum))")
    }

    /// Blocking, dodge and deflection, as the game's own Defense panel opens.
    private var blockingCard: some View {
        let stats = sheet.contributions
        let rows: [(String, String, String)] = [
            ("Chance to Block", "defensiveBlockChance", percent(stats.value("defensiveBlockChance"))),
            ("Damage Blocked", "defensiveBlock", whole(stats.value("defensiveBlock"))),
            (
                "Shield Damage Blocked", "defensiveBlockAmountModifier",
                percent(stats.value("defensiveBlockAmountModifier"))
            ),
            (
                "Block Recovery", "characterDefensiveBlockRecoveryReduction",
                percent(stats.value("characterDefensiveBlockRecoveryReduction"))
            ),
            ("Dodge Chance", "characterDodgePercent", percent(stats.value("characterDodgePercent"))),
            (
                "Deflect Chance", "characterDeflectProjectile",
                percent(stats.value("characterDeflectProjectile"))
            ),
        ]

        return card(title: "Defence", titles: rows.map(\.0)) {
            VStack(spacing: 6) {
                ForEach(rows, id: \.0) { title, key, value in
                    row(title, value, key: key)
                }
            }
        }
    }

    /// What every pet the character has is given, in the order the game's own panel lists it.
    private var petBonusesCard: some View {
        let pets = character.petBonuses
        let overall = pets.value("characterTotalSpeedModifier")
        let rows: [(String, Double)] =
            [
                ("Life", pets.value("characterLifeModifier")),
                ("Damage", pets.value("offensiveTotalDamageModifier")),
                ("Critical Damage", pets.value("offensiveCritDamageModifier")),
                // The one modifier the game spreads over all three speeds.
                ("Attack Speed", pets.value("characterAttackSpeedModifier") + overall),
                ("Cast Speed", pets.value("characterSpellCastSpeedModifier") + overall),
                ("Run Speed", pets.value("characterRunSpeedModifier") + overall),
                ("Offensive Ability", pets.value("characterOffensiveAbility")),
                ("Defensive Ability", pets.value("characterDefensiveAbility")),
            ]
            + ResistanceKind.allCases.map { kind in
                ("\(kind.title) Resist", pets.value(kind.resistanceKey))
            }

        return card(title: "Pet Bonuses", titles: rows.map(\.0)) {
            VStack(spacing: 6) {
                ForEach(rows, id: \.0) { title, value in
                    row(
                        title,
                        "+\(whole(value))%",
                        valueColor: value > 0 ? .primary : .secondary,
                        accent: Theme.damageAccent(forStatKey: "defensive\(title)", in: title)
                    )
                }
            }
        }
    }

    private var controlResistancesCard: some View {
        let lines = StatCatalog.everyStat.filter { $0.group == .controlResistances }

        return card(title: StatGroup.controlResistances.title, titles: lines.map(\.title)) {
            VStack(spacing: 6) {
                ForEach(lines, id: \.key) { definition in
                    // These cap where every other resistance does, and the game's own window shows the
                    // capped figure: 87% stun resistance reads as 80%.
                    let raw = sheet.contributions.value(definition.key)
                    let value = min(raw, CharacterSheet.resistanceCap)
                    row(
                        definition.title,
                        definition.unit.format(value, signed: false),
                        key: definition.key,
                        valueColor: value > 0 ? .primary : .secondary,
                        detail: raw > value ? Theme.overCap(raw - value) : nil
                    )
                }
            }
        }
    }

    private var damageCard: some View {
        let types = DamageType.allCases.filter { $0 != .elemental }
            .filter { abs(sheet.damageModifiers[$0] ?? 0) >= 0.5 || sheet.flatDamage[$0] ?? 0 >= 0.5 }

        return card(title: "Damage Bonuses", titles: types.map(\.title)) {
            VStack(spacing: 6) {
                ForEach(types, id: \.self) { type in
                    Button(action: { selection = .stat(title: type.title, key: type.modifierKey) }) {
                        HStack(spacing: 8) {
                            Text(Self.damageText(
                                flat: sheet.flatDamage[type] ?? 0,
                                percent: sheet.damageModifiers[type] ?? 0
                            ))
                            .monospacedDigit()
                            Text(type.title)
                                .foregroundStyle(type.color)
                            Spacer(minLength: 6)
                            if let icon = damageIcons[Theme.damageToken(forStatKey: type.modifierKey) ?? ""] {
                                GameIcon(path: icon, size: 15, fallbackSymbol: "circle.fill")
                            } else {
                                Circle()
                                    .fill(type.color)
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .font(.callout)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .quickSearchText(search.emphasis(matching: type.title))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Plus \(Int(sheet.damageModifiers[type] ?? 0)) percent \(type.title) damage")
                }
            }
        }
    }

    /// Groups the character sheet has no card of its own for: damage over time, retaliation, utility.
    private var extraGroups: [(group: StatGroup, lines: [(definition: StatDefinition, value: Double)])] {
        StatGroup.allCases
            .filter { Self.extraGroupKinds.contains($0) }
            .map { (group: $0, lines: sheet.contributions.sheetLines(of: $0)) }
            .filter { !$0.lines.isEmpty }
    }

    private static let extraGroupKinds: Set<StatGroup> = [ .damageOverTime, .retaliation, .utility ]

    private func catalogueCard(
        _ group: StatGroup,
        lines: [(definition: StatDefinition, value: Double)]
    ) -> some View {
        card(title: group.title, titles: lines.map(\.definition.title)) {
            VStack(spacing: 6) {
                ForEach(StatBlock.merged(lines), id: \.title) { line in
                    row(
                        line.title,
                        Theme.figures(line.parts),
                        key: line.parts.first?.definition.key,
                        valueColor: Theme.valueColor(line.parts.first?.value ?? 0),
                        accent: Theme.damageAccent(forStatKey: line.parts.first?.definition.key ?? "", in: line.title)
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
                                Text(set.summary)
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Text(set.name)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(set.isComplete ? Theme.accent : .primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
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
                                highlights: false,
                                isNamed: true
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
                    Text(faction.tier)
                        .foregroundStyle(faction.isHostile ? .red : .primary)
                    Text(faction.name)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityLabel("\(faction.tier) \(faction.name), \(faction.valueText)")
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
        valueColor: Color = .primary,
        accent: Theme.Accent? = nil,
        detail: String? = nil
    ) -> some View {
        let content = StatRow(
            title: title,
            value: value,
            valueColor: valueColor,
            accents: [ accent ].compactMap { $0 },
            icon: icon,
            range: detail
        )

        // A line with no stat behind it is a line, not a dead button: disabling one would fade every
        // figure the character card, the armour breakdown and the pet panel print.
        return Group {
            if let key {
                Button(action: { selection = .stat(title: title, key: key) }) {
                    content
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private func attributeRow(_ title: String, _ attribute: CharacterSheet.Attribute, key: String) -> some View {
        Button(action: { selection = .stat(title: title, key: key) }) {
            HStack(spacing: 8) {
                Text(whole(attribute.total))
                    .monospacedDigit()
                    .fontWeight(.medium)
                Text(title)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityLabel("\(Int(attribute.total)) \(title), base \(Int(attribute.base))")
    }

    /// The game truncates the figures it prints on the character sheet rather than rounding them.
    /// "+204 & +2858%" — the flat damage a character adds and the percentage it is raised by.
    private static func damageText(flat: Double, percent: Double) -> String {
        let figures = [
            flat >= 0.5 ? "+\(Int(flat.rounded()))" : nil,
            abs(percent) >= 0.5 ? "+\(Int(percent.rounded()))%" : nil,
        ]
        .compactMap { $0 }

        return figures.isEmpty ? "—" : figures.joined(separator: " & ")
    }

    private func percent(_ value: Double) -> String { "\(whole(value))%" }

    private func whole(_ value: Double) -> String {
        value.rounded(.towardZero).formatted(.number.precision(.fractionLength(0)))
    }

    private func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
