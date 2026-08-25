// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import SwiftUI

/// The two of them fighting: what the character does to this monster, and what it does back.
///
/// Every figure is the game's own arithmetic out of `records/game/combatformulas.dbr`, read at the
/// monster's own level and difficulty — change either and everything here moves. What it does not model
/// is a particular skill: this is the character's weapon damage against this monster's defences, which
/// is the floor every build stands on.
struct MonsterInteractionView: View {
    let monster: ResolvedMonster
    let character: ResolvedCharacter
    let database: GameDatabase

    private var encounter: Encounter {
        EncounterEngine(database: database).encounter(of: character.sheet, against: monster)
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

            blowCard(title: "What you land on it", subtitle: "per swing", blow: fight.attacking, rate: fight.attackRate)
            blowCard(title: "What it lands on you", subtitle: "per swing", blow: fight.defending, rate: nil)
            debuffCard
        }
        .padding(16)
    }

    /// One side's blow: how often it lands, what it throws, and what the other side stops.
    private func blowCard(title: String, subtitle: String, blow: Blow, rate: Double?) -> some View {
        SectionCard(title: title, subtitle: subtitle) {
            VStack(spacing: 6) {
                StatRow(
                    title: "Chance to hit",
                    value: percent(blow.hitChance),
                    valueColor: Theme.valueColor(blow.hitChance - 75)
                )
                .help("The game's own probability-to-hit equation, run on this pair's offensive and defensive ability")
                if blow.bestMultiplier > 1 {
                    StatRow(
                        title: "Best damage band",
                        value: "×\(blow.bestMultiplier.formatted(.number.precision(.fractionLength(0 ... 2))))",
                        range: "past \(Int(blow.bands.last?.threshold ?? 0))"
                    )
                    .help(
                        "The game states six bands a blow can land in, by how far the hit figure clears "
                            + "each threshold. This is the highest this pairing reaches — how often it "
                            + "is rolled is the game's own business and is not guessed at here."
                    )
                }

                Divider()

                ForEach(blow.shares) { share in
                    StatRow(
                        title: share.type.title,
                        value: whole(share.landed),
                        accents: [ Theme.Accent(word: share.type.title, color: share.type.color) ],
                        range: share.stopped > 0.5
                            ? "\(whole(share.thrown)) thrown, \(percent(share.resisted)) resisted" : nil
                    )
                }
                if blow.shares.isEmpty {
                    Text("Nothing the app reads — this one deals no damage the records name.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                StatRow(title: "Landing per hit", value: whole(blow.landed), valueColor: Theme.accent)
                if blow.bestMultiplier > 1 {
                    StatRow(title: "In the best band", value: whole(blow.best))
                }
                StatRow(title: "Averaged over misses", value: whole(blow.expected))
                if let rate {
                    StatRow(
                        title: "Over a second",
                        value: whole(blow.expected * rate),
                        valueColor: Theme.accent,
                        range: "\(rate.formatted(.number.precision(.fractionLength(2)))) hits/s"
                    )
                }
            }
        }
    }

    /// What the character takes off the monster, and which of it the game throws away.
    @ViewBuilder
    private var debuffCard: some View {
        let reductions = reductions

        SectionCard(title: "What you take off it", subtitle: "before any of the above") {
            if reductions.isEmpty {
                Text(
                    "Nothing on this build carries one of the game's \"reduced target's…\" lines. The "
                        + "plain -X% resistance a debuff leaves on an enemy is not counted here: the game "
                        + "writes it under the same key as your own resistance, so it cannot be told apart."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        "These do not add up. The game applies the largest and drops the rest, so a second "
                            + "source of one is a line that never fires."
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
                        highlights: false
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
