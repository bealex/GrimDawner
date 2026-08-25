// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import SwiftUI

/// The level a monster is read at, which every figure it has depends on.
struct MonsterLevelField: View {
    let range: ClosedRange<Int>
    let level: Int
    let setLevel: (Int) -> Void
    var difficulty: Difficulty?
    var setDifficulty: ((Difficulty) -> Void)?

    @State
    private var text = ""

    var body: some View {
        HStack(spacing: 4) {
            Text("Level")
                .foregroundStyle(.secondary)
            TextField("Level", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 54)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .onSubmit { commit() }
            Stepper("Level", value: Binding(get: { level }, set: setLevel), in: range)
                .labelsHidden()

            if let difficulty, let setDifficulty {
                Picker("Difficulty", selection: Binding(get: { difficulty }, set: setDifficulty)) {
                    ForEach(Difficulty.allCases, id: \.self) { difficulty in
                        Text(difficulty.title).tag(difficulty)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .help("A monster on Ultimate carries several times the health it does on Normal")
            }
        }
        .font(.callout)
        .help("Monsters scale with where they are met: everything here is read at this level")
        .onChange(of: level, initial: true) { _, level in text = "\(level)" }
    }

    /// A typed level only counts once it is entered, and only inside the range the monster is met in.
    private func commit() {
        guard
            let typed = Int(text.trimmingCharacters(in: .whitespaces))
        else {
            text = "\(level)"
            return
        }

        setLevel(min(max(typed, range.lowerBound), range.upperBound))
    }
}

/// One of a monster's skills: what it is, how it reaches, what it carries and what it calls in.
struct MonsterAbilityView: View {
    let ability: MonsterAbility
    /// Opens a summoned creature in a window of its own, since a pet is a monster like any other.
    var openMonster: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            // Most of a monster's skills carry a developer's file name and no text; the ones the game
            // does describe say it here, named or not.
            if !ability.skill.description.isEmpty {
                Text(ability.skill.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("\(ability.title ?? ability.kind): \(ability.skill.description)")
            }
            if !ability.skill.parameters.isEmpty {
                ForEach(ability.skill.parameters) { parameter in
                    StatRow(title: parameter.name, value: parameter.value, highlights: false)
                }
            }
            if !ability.skill.stats.hasNothingToShow {
                StatBlockView(block: ability.skill.stats)
            }
            if let summon = ability.skill.summon {
                summonRow(summon)
            }
        }
        // One monster carries a dozen of these, and a run of stat lines with nothing between them reads
        // as one long list rather than as several skills.
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.subtleBorder))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                if let title = ability.title {
                    Text(title)
                        .font(.callout.weight(.medium))
                }
                Text(detail)
                    .font(ability.title == nil ? .callout : .caption2)
                    .foregroundStyle(ability.title == nil ? .primary : .secondary)
            }
            Spacer(minLength: 4)
            Text("rank \(ability.skill.totalLevel)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    /// What kind of thing it is, how it reaches and how often — the line that stands in for a name.
    ///
    /// The slot and the record's class often say the same thing, and "Passive · Passive bonus" says it
    /// twice, so the slot is named only where it adds something.
    private var detail: String {
        let slot: String? =
            switch ability.role {
                case .attack: "Auto attack"
                case .special: "Special attack"
                case .onDeath: "On death"
                case .passive: nil
            }

        return [
            slot,
            ability.kind,
            ability.range.map(Self.rangeTitle),
            ability.cooldown.flatMap { $0 > 0 ? "every \(Int($0))s" : nil },
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    /// What the skill calls in, and what the thing it calls in is worth.
    ///
    /// A summon named and left at that says nothing about the fight it makes: what matters is the pet's
    /// own sheet and the abilities it brings, which are read here rather than in a window somewhere else.
    @ViewBuilder
    private func summonRow(_ summon: ResolvedSummon) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(summon.limit > 1 ? "\(summon.limit) × \(summon.name)" : summon.name)
                    .font(.caption.weight(.semibold))
                if let subtitle = SummonView.subtitle(of: summon) {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            SummonView(summon: summon, openMonster: openMonster)
                .padding(.leading, 16)
        }
    }

    /// The record words a range as one token — `ShortRange` — which reads badly as it stands.
    private static func rangeTitle(_ range: String) -> String {
        switch range {
            case "ShortRange": "close up"
            case "MediumRange": "mid range"
            case "LongRange": "at range"
            case "AnyRange": "any range"
            default: range
        }
    }
}

/// One equipment slot's loot, drawn as the chain of rolls that reaches each item.
///
/// The game rolls a slot, then an entry of that slot, then an item of the table the entry names. Each of
/// those is one roll for the whole group under it, so each is drawn as one figure against a rule spanning
/// everything that rides on it: the eye can see at a glance which lines are decided together and which
/// are separate draws. The figure on the right is the chain multiplied out — the chance of actually
/// walking away with that item.
///
/// Only what is worth naming is listed. A monster's tables are mostly the game's ordinary drops — white
/// and blue gear generated by the thousand — and printing those buries the two lines a reader came for.
struct MonsterLootView: View {
    let slot: MonsterLootSlot
    var showsHeader = true
    /// How many of a table's items are named before the rest are only counted.
    var itemLimit = 12
    /// Whether to list the ordinary drops too, which are most of what a table holds.
    var showsOrdinary = false

    /// What counts as worth naming: what a monster is actually hunted for. The epics are left out with
    /// the ordinary drops — most of the game's gear is epic, and a table full of it says nothing about
    /// which monster you are looking at.
    private static let notable: Set<ItemRarity> = [
        .rare, .legendary, .quest, .relic, .component, .lore, .augment,
    ]

    /// One entry of the slot with the items of it that are worth naming. An entry that is one item
    /// rather than a table stands as its own leaf.
    private struct Group: Identifiable {
        let entry: MonsterLootEntry
        let items: [MonsterLootEntry.Item]

        var id: UUID { entry.id }
    }

    private var groups: [Group] {
        slot.entries.compactMap { entry in
            guard entry.name.isEmpty else { return Group(entry: entry, items: []) }

            let items = entry.items
                .filter { showsOrdinary || Self.notable.contains($0.rarity) }
                .prefix(itemLimit)
            return items.isEmpty ? nil : Group(entry: entry, items: Array(items))
        }
    }

    var body: some View {
        let groups = groups

        VStack(alignment: .leading, spacing: 6) {
            if showsHeader {
                HStack {
                    Text(slot.slot)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(slot.chance))% carried")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }

            if groups.isEmpty {
                Text(showsOrdinary ? "Nothing" : "Nothing beyond the game's ordinary drops")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                // One roll decides the whole slot, so its figure brackets every group under it.
                HStack(alignment: .center, spacing: 0) {
                    chance(slot.chance)
                    rule
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(groups) { group in
                            self.group(group)
                        }
                    }
                }
            }
        }
    }

    /// One entry: its own roll, bracketing whichever items that entry's table can produce.
    private func group(_ group: Group) -> some View {
        HStack(alignment: .center, spacing: 0) {
            chance(group.entry.share)
            rule
            VStack(alignment: .leading, spacing: 2) {
                if group.items.isEmpty {
                    leaf(
                        name: group.entry.title,
                        iconPath: group.entry.iconPath,
                        rarity: .common,
                        reached: reached(entry: group.entry.share, table: nil)
                    )
                } else {
                    ForEach(group.items) { item in
                        HStack(alignment: .center, spacing: 0) {
                            chance(item.share)
                            rule
                            leaf(
                                name: item.name,
                                iconPath: item.iconPath,
                                rarity: item.rarity,
                                reached: reached(entry: group.entry.share, table: item.share)
                            )
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The item itself, with the whole chain multiplied out beside it.
    private func leaf(name: String, iconPath: String, rarity: ItemRarity, reached: String) -> some View {
        HStack(spacing: 6) {
            if !iconPath.isEmpty {
                GameIcon(path: iconPath, size: 18, fallbackSymbol: "shippingbox")
            }
            Text(name)
                .font(.caption)
                .foregroundStyle(rarity.color)
                .lineLimit(1)

            Text(" ")
                .frame(maxWidth: .infinity)
                .overlay(alignment: .center) {
                    Rectangle()
                        .fill(.tertiary)
                        .frame(height: 1)
                        .opacity(0.35)
                        .padding(.horizontal, 6)
                }

            Text(reached)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 6)
    }

    /// One roll of the chain, in the column its depth gives it.
    private func chance(_ value: Double) -> some View {
        Text(value >= 1 ? "\(Int(value.rounded()))%" : "<1%")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 46, alignment: .trailing)
    }

    /// The line down the side of a group, as tall as everything the roll beside it decides.
    private var rule: some View {
        Rectangle()
            .fill(Theme.accent.opacity(0.45))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .padding(.leading, 8)
    }

    /// The chance of actually walking away with it: every roll of the chain multiplied together.
    private func reached(entry: Double, table: Double?) -> String {
        let chance = slot.chance / 100 * entry / 100 * (table ?? 100) / 100 * 100
        guard chance >= 0.01 else { return "<0.01%" }

        return chance.formatted(.number.precision(.significantDigits(1 ... 4))) + "%"
    }
}

/// A monster's stat sheet, grouped as the character's own is.
struct MonsterSheetView: View {
    let monster: ResolvedMonster
    let search: QuickSearch

    @Environment(\.damageIcons)
    private var damageIcons

    var body: some View {
        MasonryLayout {
            headlineCard
            resistancesCard
            ForEach(groups, id: \.group) { group in
                card(group.group.title, lines: group.lines)
            }
        }
        .padding(16)
    }

    /// Everything the record carries, minus the resistances the card above prints in full.
    private var groups: [(group: StatGroup, lines: [(definition: StatDefinition, value: Double)])] {
        StatGroup.allCases
            .filter { $0 != .resistances }
            .map { (group: $0, lines: monster.stats.sheetLines(of: $0).filter { matches($0.definition.title) }) }
            .filter { !$0.lines.isEmpty }
    }

    private func matches(_ title: String) -> Bool { !search.isActive || search.matches(title) }

    private var headlineCard: some View {
        let rows: [(String, String, String)] = [
            ("Physique", whole(monster.physique), "figure.strengthtraining.traditional"),
            ("Cunning", whole(monster.cunning), "scope"),
            ("Spirit", whole(monster.spirit), "sparkles"),
            ("Health", whole(monster.health), "heart.fill"),
            ("Energy", whole(monster.energy), "bolt.fill"),
            ("Offensive Ability", whole(monster.offensiveAbility), "target"),
            ("Defensive Ability", whole(monster.defensiveAbility), "figure.fencing"),
            ("Armor", whole(monster.armor), "shield.fill"),
            ("Experience", whole(monster.experience), "star"),
        ]
        .filter { matches($0.0) }

        return Group {
            if !rows.isEmpty {
                SectionCard(title: "In a fight", subtitle: "at level \(monster.level)") {
                    VStack(spacing: 6) {
                        ForEach(rows, id: \.0) { title, value, icon in
                            StatRow(title: title, value: value, icon: icon)
                        }
                    }
                }
            }
        }
    }

    private var resistancesCard: some View {
        let kinds = ResistanceKind.allCases.filter { matches($0.title) }

        return Group {
            if !kinds.isEmpty {
                SectionCard(title: "Resistances", subtitle: "no cap applies to a monster") {
                    VStack(spacing: 6) {
                        ForEach(kinds, id: \.self) { kind in
                            StatRow(
                                title: kind.title,
                                value: "\(Int((monster.resistances[kind] ?? 0).rounded()))%",
                                accents: [ Theme.Accent(word: kind.title, color: kind.color) ],
                                iconPath: damageIcons[Theme.damageToken(forStatKey: kind.resistanceKey) ?? ""]
                            )
                        }
                    }
                }
            }
        }
    }

    private func card(_ title: String, lines: [(definition: StatDefinition, value: Double)]) -> some View {
        SectionCard(title: title) {
            VStack(spacing: 6) {
                ForEach(StatBlock.merged(lines), id: \.title) { line in
                    StatRow(
                        title: line.title,
                        value: Theme.figures(line.parts),
                        accents: [
                            Theme.damageAccent(forStatKey: line.parts[0].definition.key, in: line.title)
                        ]
                        .compactMap { $0 },
                        iconPath: damageIcons[Theme.damageToken(forStatKey: line.parts[0].definition.key) ?? ""]
                    )
                }
            }
        }
    }

    private func whole(_ value: Double) -> String {
        value.rounded().formatted(.number.precision(.fractionLength(0)))
    }
}
