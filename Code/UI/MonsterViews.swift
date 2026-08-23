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
            // Only a skill the game itself names has anything to say about itself; the rest carry a
            // developer's file name and no text at all.
            if let title = ability.title, !ability.skill.description.isEmpty {
                Text(ability.skill.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("\(title): \(ability.skill.description)")
            }
            if !ability.skill.parameters.isEmpty {
                ForEach(ability.skill.parameters) { parameter in
                    StatRow(title: parameter.name, value: parameter.value, highlights: false)
                }
            }
            if !ability.skill.stats.hasNothingToShow {
                StatBlockView(block: ability.skill.stats, groupSpacing: 4)
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

    /// What the skill calls in. A summoned monster opens in a window of its own; a chest or a piece of
    /// scenery is named and left alone.
    @ViewBuilder
    private func summonRow(_ summon: ResolvedSummon) -> some View {
        let label = [
            summon.limit > 1 ? "\(summon.limit) ×" : nil,
            summon.name,
            summon.timeToLive > 0 ? "for \(Int(summon.timeToLive))s" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if summon.isMonster, let openMonster {
                Button(label) { openMonster(summon.recordPath) }
                    .buttonStyle(.link)
                    .font(.caption)
                    .pointerStyle(.link)
                    .help("Opens \(summon.name) in a window of its own")
            } else {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

/// One equipment slot's loot: what it can hold, and what the tables behind it produce.
struct MonsterLootView: View {
    let slot: MonsterLootSlot
    var showsHeader = true
    /// How many of a table's items are named before the rest are only counted.
    var itemLimit = 12

    var body: some View {
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
            ForEach(slot.entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if !entry.iconPath.isEmpty {
                            GameIcon(path: entry.iconPath, size: 20, fallbackSymbol: "shippingbox")
                        }
                        Text(entry.title)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(entry.share >= 1 ? "\(Int(entry.share))%" : "<1%")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    // An entry that is one item is already named by its own line; a table's contents are
                    // what says what it means.
                    if entry.name.isEmpty {
                        ForEach(entry.items.prefix(itemLimit)) { item in
                            HStack(spacing: 6) {
                                GameIcon(path: item.iconPath, size: 16, fallbackSymbol: "shippingbox")
                                Text(item.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(item.share >= 1 ? "\(Int(item.share))%" : "<1%")
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.leading, 10)
                        }
                        if entry.items.count > itemLimit {
                            Text("and \(entry.items.count - itemLimit) more")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 10)
                        }
                    }
                }
            }
        }
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
