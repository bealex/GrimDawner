// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import SwiftUI

/// The two of them fighting: what the character does to this monster, and what it does back.
///
/// Every figure is the game's own arithmetic out of `records/game/combatformulas.dbr`, read at the
/// monster's own level and difficulty — change either and everything here moves. It opens on the
/// character's weapon damage, which is the floor every build stands on, and any of its attacks can be
/// read in its place.
struct MonsterInteractionView: View {
    let monster: ResolvedMonster
    let character: ResolvedCharacter
    let database: GameDatabase

    /// What the character is swinging with. Nothing is the weapon itself, which is what a build stands
    /// on before any skill is pressed.
    @State
    private var skillPath: String?
    /// Which of the monster's own attacks it is swinging back with, by record. Nothing is the one its
    /// record calls its own. Keyed by path rather than by the ability's identity, which is made afresh
    /// every time the monster is read at another level.
    @State
    private var monsterAttackPath: String?
    /// The buffs the reader says are up. The sheet counts passives and auras on its own; anything that
    /// runs out is a choice, since nothing in a save says whether it was cast.
    @State
    private var raised = Set<String>()
    /// The debuffs the reader says the monster has landed. Same story: a save says nothing about them.
    @State
    private var suffered = Set<String>()
    @State
    private var showsBuffs = false

    private var chosen: ResolvedSkill? {
        guard let skillPath else { return nil }

        return attacks.first { $0.recordPath == skillPath }
    }

    /// The attacks worth comparing: the character's own skills and whatever its gear grants, minus the
    /// ones that throw no damage of their own. A skill that only buffs has nothing to land.
    private var attacks: [ResolvedSkill] {
        var seen = Set<String>()
        return
            (character.masteries.flatMap(\.skills).filter { $0.baseLevel > 0 }
            + character.itemGrantedSkills)
            .filter { seen.insert($0.recordPath.lowercased()).inserted }
            .filter { !EncounterEngine.damage(of: $0).isEmpty }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The attacks the monster can swing back with, hardest first.
    private var monsterAttacks: [MonsterAbility] {
        monster.abilities
            .filter { ($0.role == .attack || $0.role == .special) && EncounterEngine.thrown(of: $0, of: monster) > 0 }
            .sorted { EncounterEngine.thrown(of: $0, of: monster) > EncounterEngine.thrown(of: $1, of: monster) }
    }

    private var monsterAttack: MonsterAbility? {
        monsterAttacks.first { $0.skill.recordPath == monsterAttackPath }
    }

    /// The buffs the reader has raised, in the order the character lists them.
    private var chosenBuffs: [ResolvedSkill] {
        character.optionalBuffs.filter { raised.contains($0.recordPath.lowercased()) }
    }

    /// The sheet the fight is read on: the resting one, or the one with the chosen buffs up.
    private var sheet: CharacterSheet {
        character.sheet(in: database, buffedBy: chosenBuffs)
    }

    /// Everything this monster can leave on the character.
    private var debuffs: [MonsterDebuff] {
        MonsterDebuff.all(of: monster, in: database)
    }

    /// The worst of each kind the reader says has landed, which is all the game keeps.
    private var landed: [MonsterDebuff.Kind: Double] {
        MonsterDebuff.worst(of: debuffs.filter { suffered.contains($0.id) })
    }

    private var encounter: Encounter {
        EncounterEngine(database: database)
            .encounter(
                of: sheet,
                against: monster,
                using: chosen,
                swinging: monsterAttack,
                reducing: TargetReduction.of(character),
                suffering: landed
            )
    }

    private var reductions: [TargetDebuffs.Reduction] { TargetDebuffs.of(character) }

    var body: some View {
        let fight = encounter

        VStack(alignment: .leading, spacing: 14) {
            Text(
                "\(character.name) against \(monster.title), read at monster level \(monster.level) on \(monster.difficulty.title)."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            weaponPicker

            // Side by side: the whole point is which of the two numbers is bigger.
            HStack(alignment: .top, spacing: 14) {
                blowCard(
                    title: "What you land on it",
                    subtitle: chosen?.name ?? "weapon attack",
                    blow: fight.attacking,
                    rate: fight.attackRate,
                    target: ("Kills it in", monster.health),
                    oneShots: nil
                )
                blowCard(
                    title: "What it lands on you",
                    blow: fight.defending,
                    rate: fight.monsterRate,
                    target: ("Kills you in", sheet.health),
                    oneShots: sheet.health,
                    everything: EncounterEngine(database: database).totalDamagePerSecond(
                        of: monster,
                        against: sheet,
                        reducing: TargetReduction.of(character),
                        suffering: landed
                    ),
                    accessory: AnyView(monsterPicker)
                )
            }
            debuffCard
            buffCard
        }
        .padding(16)
    }

    /// What the character is swinging with.
    private var weaponPicker: some View {
        HStack(spacing: 8) {
            Picker("Attacking with", selection: $skillPath) {
                Text("Weapon attack").tag(String?.none)
                if !attacks.isEmpty {
                    Divider()
                    ForEach(attacks) { skill in
                        Text(skill.name).tag(String?.some(skill.recordPath))
                    }
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 300)
            .help("Which of the character's attacks to read against this monster")

            buffButton
            Spacer(minLength: 8)
        }
    }

    /// One side's blow: how often it lands, what it throws, and what the other side stops.
    /// What the reader says is up, beside what it is swinging with: the sheet already counts every
    /// passive and aura, and a buff that runs out is nobody's business but the reader's.
    @ViewBuilder
    private var buffButton: some View {
        if !character.optionalBuffs.isEmpty || !debuffs.isEmpty {
            Button {
                showsBuffs = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: raised.isEmpty && suffered.isEmpty ? "sparkles" : "sparkles.rectangle.stack.fill")
                    Text(
                        raised.isEmpty && suffered.isEmpty
                            ? "Buffs and Nerfs" : "\(raised.count) up · \(suffered.count) on you"
                    )
                }
            }
            .help("Which of your timed buffs to count, and which of its debuffs have landed on you.")
            .popover(isPresented: $showsBuffs, arrowEdge: .bottom) { buffList }
        }
    }

    private var buffList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Buffs you have cast")
                .font(.headline)
            Text(
                "Nothing in a save says which of these was up, so they are yours to pick. Everything "
                    + "permanent — passives, auras, transmuters — is already counted below."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 320, alignment: .leading)

            ForEach(character.optionalBuffs) { buff in
                Toggle(
                    isOn: Binding(
                        get: { raised.contains(buff.recordPath.lowercased()) },
                        set: { isOn in
                            if isOn {
                                raised.insert(buff.recordPath.lowercased())
                            } else {
                                raised.remove(buff.recordPath.lowercased())
                            }
                        }
                    )
                ) {
                    HStack(spacing: 6) {
                        GameIcon(path: buff.iconPath, size: 18, fallbackSymbol: "sparkles")
                        Text(buff.name)
                        Text("rank \(buff.totalLevel)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }

            if !debuffs.isEmpty {
                Divider()
                Text("What it leaves on you")
                    .font(.headline)
                Text(
                    "The game keeps only the strongest of each kind, so raising two of one is the "
                        + "worse of the two and no more."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320, alignment: .leading)

                ForEach(debuffs) { debuff in
                    Toggle(
                        isOn: Binding(
                            get: { suffered.contains(debuff.id) },
                            set: { isOn in
                                if isOn { suffered.insert(debuff.id) } else { suffered.remove(debuff.id) }
                            }
                        )
                    ) {
                        HStack(spacing: 6) {
                            Text(debuff.kind.title)
                            Text(
                                debuff.kind.isPercent
                                    ? "\(Int(debuff.amount))%" : "−\(Int(debuff.amount))"
                            )
                            .foregroundStyle(Color.orange)
                            if debuff.seconds > 0 {
                                Text("\(Int(debuff.seconds))s")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(debuff.source)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }

            if !raised.isEmpty || !suffered.isEmpty {
                Divider()
                Button("Clear them all") {
                    raised.removeAll()
                    suffered.removeAll()
                }
            }
        }
        .padding(14)
        .frame(minWidth: 300)
    }

    /// What is in every figure on this tab whether or not anybody chose it.
    private var buffCard: some View {
        SectionCard(
            title: "Buffs counted",
            subtitle: "\(character.passiveBuffs.count + chosenBuffs.count) in every figure above"
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(chosenBuffs) { buff in
                    StatRow(
                        title: buff.name,
                        value: "cast",
                        valueColor: Theme.accent,
                        titleIconPath: buff.iconPath,
                        isNamed: true
                    )
                }
                ForEach(character.passiveBuffs) { buff in
                    StatRow(
                        title: buff.name,
                        value: buff.isModifier ? "modifier" : "always on",
                        titleIconPath: buff.iconPath
                    )
                }
                if character.passiveBuffs.isEmpty, chosenBuffs.isEmpty {
                    Text("Nothing on this build is permanently in effect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Which of the monster's attacks to read. A boss carries several and they are not close in what
    /// they throw, so the one its record calls its own says little on its own.
    @ViewBuilder
    private var monsterPicker: some View {
        if monsterAttacks.count > 1 {
            Picker("Swinging with", selection: $monsterAttackPath) {
                Text("Its own attack").tag(String?.none)
                Divider()
                ForEach(monsterAttacks) { ability in
                    Text("\(ability.name) — \(ability.kind)").tag(String?.some(ability.skill.recordPath))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .help("Which of this monster's attacks to read against your character")
        }
    }

    private func blowCard(
        title: String,
        subtitle: String? = nil,
        blow: Blow,
        rate: Double?,
        /// Whose health this blow is eating into, and how the row that says so is worded.
        target: (title: String, health: Double)? = nil,
        /// The health a single blow has to beat to be worth calling out, where that matters.
        oneShots: Double? = nil,
        /// What everything it throws comes to, where one attack is not the whole story.
        everything: Double? = nil,
        accessory: AnyView? = nil
    ) -> some View {
        SectionCard(title: title, subtitle: subtitle, accessory: accessory) {
            VStack(spacing: 6) {
                StatRow(
                    title: "Chance to hit",
                    value: percent(blow.hitChance),
                    valueColor: Theme.valueColor(blow.hitChance - 75)
                )
                .help("The game's own probability-to-hit equation, run on this pair's offensive and defensive ability")
                StatRow(
                    title: "Chance to crit",
                    value: percent(blow.critChance),
                    valueColor: Theme.valueColor(blow.critChance - 15)
                )
                .help(
                    "How often a swing lands in one of the game's damage bands above the plain one. A "
                        + "pairing whose hit figure never reaches 90 never crits at all. The record "
                        + "says which bands are reached but not how the roll picks between them, so "
                        + "the roll is read as even across the hit figure."
                )
                if blow.critChance > 0.05 {
                    StatRow(
                        title: "Critical damage",
                        value: span(blow.critDamageRange),
                        valueColor: oneShots.map { blow.critDamageRange.upperBound >= $0 ? .red : .primary }
                            ?? .primary,
                        range: "×\(blow.critMultiplier.formatted(.number.precision(.fractionLength(0 ... 2))))"
                    )
                }
                if blow.averageMultiplier > 1 {
                    StatRow(
                        title: "Damage multiplier",
                        value: "×\(blow.averageMultiplier.formatted(.number.precision(.fractionLength(0 ... 2))))",
                        range: "up to ×\(blow.bestMultiplier.formatted(.number.precision(.fractionLength(0 ... 2))))"
                    )
                }

                Divider()

                ForEach(blow.shares) { share in
                    StatRow(
                        title: share.type.title,
                        value: span(share.landed),
                        accents: [ Theme.Accent(word: share.type.title, color: share.type.color) ],
                        range: share.stopped > 0.5 ? "\(span(share.thrown)) thrown, \(resisted(share))" : nil
                    )
                }
                if blow.shares.isEmpty {
                    Text("Nothing the app reads — this one deals no damage the records name.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                bandRows(blow)

                Divider()

                if blow.absorbed > 0.5 {
                    StatRow(
                        title: "Damage absorption",
                        value: percent(blow.absorbed),
                        valueColor: blow.absorbed >= 99.5 ? .green : .primary,
                        range: blow.absorbed >= 99.5 ? "nothing gets through" : "of everything, after armour"
                    )
                    .help(
                        "A share of every blow swallowed whole, whatever type it is — armour absorption "
                            + "is the armour's own and stops physical only."
                    )
                }
                StatRow(title: "Landing per hit", value: span(blow.landed), valueColor: Theme.accent)
                StatRow(
                    title: "At its hardest",
                    value: whole(blow.best),
                    valueColor: oneShots.map { blow.best >= $0 ? .red : .primary } ?? .primary,
                    range: "top of the range, best band"
                )
                if let oneShots, blow.best >= oneShots {
                    StatRow(
                        title: "One shot",
                        value: "kills you outright",
                        valueColor: .red,
                        icon: "exclamationmark.triangle.fill"
                    )
                    .help("Its hardest blow is more than the whole of your health, misses aside.")
                }
                StatRow(title: "Averaged over misses and bands", value: whole(blow.expected))
                if let rate {
                    StatRow(
                        title: "Over a second",
                        value: whole(blow.expected * rate),
                        valueColor: Theme.accent,
                        range: "\(rate.formatted(.number.precision(.fractionLength(2)))) hits/s"
                    )
                }
                if let everything, everything > 0.5 {
                    StatRow(
                        title: "Everything it throws",
                        value: whole(everything),
                        valueColor: Theme.accent,
                        range: "per second, all its attacks"
                    )
                    .help(
                        "Its own attack at full rate, and every special at its stated chance once per "
                            + "the timeout its record names. The record says how often, not in what "
                            + "order, so this is an estimate."
                    )
                }
                if let rate, let kill = timeToKill(everything ?? (blow.expected * rate), of: target) {
                    StatRow(title: kill.title, value: kill.value, valueColor: kill.colour)
                }
            }
        }
    }

    /// How long the side being hit lasts at that rate, which is the figure a reader is really after.
    private func timeToKill(
        _ perSecond: Double,
        of target: (title: String, health: Double)?
    ) -> (title: String, value: String, colour: Color)? {
        guard perSecond > 0.5, let target, target.health > 0 else { return nil }

        let seconds = target.health / perSecond
        return (
            target.title,
            seconds < 60
                ? "\(seconds.formatted(.number.precision(.fractionLength(seconds < 10 ? 1 : 0))))s"
                : "\((seconds / 60).formatted(.number.precision(.fractionLength(1)))) min",
            Theme.valueColor(seconds - 20)
        )
    }

    /// Every band the pairing reaches, what a blow in it comes to, and how much of the roll it is worth.
    @ViewBuilder
    private func bandRows(_ blow: Blow) -> some View {
        if blow.bands.count > 1 {
            Divider()
            ForEach(blow.bands) { band in
                StatRow(
                    title: band.threshold > 0 ? "Past \(Int(band.threshold))" : "Under \(Int(blow.bands[1].threshold))",
                    value: span(band.damage),
                    range:
                        "×\(band.multiplier.formatted(.number.precision(.fractionLength(0 ... 2)))) · \(percent(band.share)) of hits"
                )
            }
        }
    }

    /// What the character takes off the monster, and which of it the game throws away.
    @ViewBuilder
    private var debuffCard: some View {
        let reductions = reductions

        SectionCard(title: "What you take off it", subtitle: "already counted above") {
            if reductions.isEmpty {
                Text("Nothing on this build carries one of the game's \"reduced target's…\" lines.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        "These do not add up. The game applies the largest and drops the rest, so a second "
                            + "source of one is a line that never fires. The plain -X% resistance a debuff "
                            + "leaves on an enemy is counted too, and does stack, but is not listed here: "
                            + "it is written on the debuff rather than as a line of its own."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    ForEach(reductions) { reduction in
                        ReductionView(reduction: reduction)
                    }
                }
            }
        }
    }

    private func whole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    /// A band of damage, written as one figure where both ends are the same.
    private func span(_ range: ClosedRange<Double>) -> String {
        range.upperBound - range.lowerBound < 0.5
            ? whole(range.lowerBound) : "\(whole(range.lowerBound))–\(whole(range.upperBound))"
    }

    /// What the target resists, what it resisted before anything was taken off it, and how much of an
    /// overcap it is standing on.
    ///
    /// Overcap stops nothing by itself: it is the buffer that gets spent before a reduction reaches the
    /// cap. Naming what is left says whether a build has enough of one for what it is fighting.
    private func resisted(_ share: Blow.Share) -> String {
        var words = "\(percent(share.resisted)) resisted"
        if share.resistedBefore - share.resisted > 0.5 {
            words += ", down from \(percent(share.resistedBefore))"
        }
        if share.overcap > 0.5 {
            words +=
                share.overcap - share.overcapLeft > 0.5
                ? " — \(percent(share.overcapLeft)) of \(percent(share.overcap)) overcap left"
                : " — \(percent(share.overcap)) overcap"
        }
        return words
    }

    private func percent(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0 ... 1))))%"
    }
}

/// One reduction, with every source that feeds it and what the game does with them.
private struct ReductionView: View {
    let reduction: TargetDebuffs.Reduction

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(reduction.text)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(Theme.accent)
                if reduction.isWasteful {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text(reduction.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(reduction.isWasteful ? Color.red : .primary)
                Spacer(minLength: 8)
            }

            if reduction.isWasteful {
                Text(
                    "\(reduction.sources.count) sources — only the largest applies, and "
                        + "\(reduction.unit.format(reduction.wasted)) of it is doing nothing."
                )
                .font(.caption2)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 2) {
                ForEach(reduction.sources) { source in
                    let isApplied = reduction.stacks || source.value == reduction.applied
                    StatRow(
                        title: source.name,
                        value: reduction.unit.format(source.value),
                        valueColor: isApplied ? .secondary : .red,
                        titleIconPath: source.item?.iconPath,
                        highlights: false,
                        isNamed: true
                    )
                    .opacity(isApplied ? 1 : 0.6)
                }
            }
            .padding(.leading, 6)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (reduction.isWasteful ? Color.red.opacity(0.08) : Color.primary.opacity(0.04)),
            in: .rect(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(reduction.isWasteful ? Color.red.opacity(0.45) : Theme.subtleBorder)
        )
    }
}
