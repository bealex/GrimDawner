// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// What a monster leaves on the character it hits, beyond taking resistance off it.
///
/// Most of these are written under keys the stat catalogue does not carry — they are aimed at whoever
/// is struck rather than describing the creature — so they are read off the ability's own record.
/// Nothing in a save says whether one is on, so which of them to count is a reader's to choose.
public struct MonsterDebuff: Identifiable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        /// The game's Sundered: the character takes this much more damage from everything.
        case sunder
        /// Flat Defensive Ability off the character, so the monster hits and crits it more often.
        case defensiveAbility
        /// Flat Offensive Ability off the character, so the character hits less often.
        case offensiveAbility
        /// A share off everything the character deals.
        case damageDealt

        /// The keys an ability writes it under, in the order they are preferred.
        var keys: [String] {
            switch self {
                case .sunder: [ "offensiveSlowDamageMultMin" ]
                case .defensiveAbility: [ "offensiveSlowDefensiveAbilityMin", "offensiveSlowDefensiveReductionMin" ]
                case .offensiveAbility: [ "offensiveSlowOffensiveAbilityMin", "offensiveSlowOffensiveReductionMin" ]
                case .damageDealt: [ "offensiveTotalDamageReductionPercentMin" ]
            }
        }

        var durationKey: String? {
            switch self {
                case .sunder: "offensiveSlowDamageMultDurationMin"
                case .defensiveAbility: "offensiveSlowDefensiveAbilityDurationMin"
                case .offensiveAbility: "offensiveSlowOffensiveAbilityDurationMin"
                case .damageDealt: "offensiveTotalDamageReductionPercentDurationMin"
            }
        }

        public var title: String {
            switch self {
                case .sunder: "Sundered"
                case .defensiveAbility: "Defensive Ability down"
                case .offensiveAbility: "Offensive Ability down"
                case .damageDealt: "Damage down"
            }
        }

        public var isPercent: Bool { self != .defensiveAbility && self != .offensiveAbility }
    }

    public let kind: Kind
    /// The attack that leaves it, as the monster's own record names it.
    public let source: String
    public let amount: Double
    /// How long it stays, in seconds. Zero where the record states none.
    public let seconds: Double

    public var id: String { "\(kind.rawValue)|\(source)" }

    /// Everything a monster can leave on a character, one entry per attack that leaves one.
    ///
    /// The game stacks none of these: only the strongest of each kind is in effect, which the patch
    /// notes say outright for Sundered. So a reader raising two of a kind still only feels the worse.
    public static func all(of monster: ResolvedMonster, in database: GameDatabase) -> [MonsterDebuff] {
        var found = [MonsterDebuff]()
        for ability in monster.abilities {
            guard let record = database.record(ability.skill.recordPath) else { continue }

            let rank = max(ability.skill.baseLevel, 1)
            for kind in Kind.allCases {
                guard
                    case let amount = kind.keys.compactMap({ level(record, $0, at: rank) }).first(where: { $0 > 0 }),
                    let amount
                else { continue }

                found.append(MonsterDebuff(
                    kind: kind,
                    source: ability.name,
                    amount: amount,
                    seconds: kind.durationKey.flatMap { level(record, $0, at: rank) } ?? 0
                ))
            }
        }
        return found.sorted {
            $0.kind.rawValue == $1.kind.rawValue ? $0.amount > $1.amount : $0.kind.rawValue < $1.kind.rawValue
        }
    }

    /// The worst of each kind among those a reader has raised, which is all the game has in effect.
    public static func worst(of raised: [MonsterDebuff]) -> [Kind: Double] {
        var strongest = [Kind: Double]()
        for debuff in raised {
            strongest[debuff.kind] = max(strongest[debuff.kind] ?? 0, debuff.amount)
        }
        return strongest
    }

    private static func level(_ record: ArzRecord, _ key: String, at rank: Int) -> Double? {
        let numbers = record[key]?.numbers ?? []
        guard !numbers.isEmpty else { return nil }

        return numbers[min(max(rank - 1, 0), numbers.count - 1)]
    }
}
