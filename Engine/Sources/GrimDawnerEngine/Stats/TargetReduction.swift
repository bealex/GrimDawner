// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// What a character takes off whatever it is fighting, before a blow is weighed against it.
///
/// The game has three of these and they are not the same thing. A share of what is there fires first,
/// then a flat subtraction, and last the plain `-X% <type> Resistance` a debuff leaves on the target.
/// Within the first two the game applies the **largest** source and drops the rest; the debuffs stack.
///
/// The debuff kind is written as a negative resistance on the record of the debuff the skill applies,
/// under the same key the character's own resistance uses — Spectral Wrath carries `defensiveAether`
/// at −39 — so it is read off the character's skills rather than off its gear, where the same key
/// means the character's own resistance instead.
public struct TargetReduction: Sendable {
    /// A share of the resistance that is there, by type. `nil` under a type means the whole-family
    /// figure applies.
    public var percent = [ResistanceKind: Double]()
    /// A flat subtraction, by type.
    public var flat = [ResistanceKind: Double]()
    /// What the character's debuffs leave on the target, by type. Already summed: these stack.
    public var debuff = [ResistanceKind: Double]()

    public init() {}

    /// What the target's resistance comes to once all three have been applied, in the game's order:
    /// the stacking debuffs, then the largest share, then the largest flat subtraction.
    ///
    /// The share follows the sign of what it is taking from. A resistance the debuffs have already
    /// driven below zero is a hole, and a share of a hole deepens it rather than filling it back in.
    public func applied(to resistance: Double, of kind: ResistanceKind) -> Double {
        let left = resistance - (debuff[kind] ?? 0)
        let share = left * (1 - (left < 0 ? -1 : 1) * (percent[kind] ?? 0) / 100)
        return share - (flat[kind] ?? 0)
    }

    public var isEmpty: Bool { percent.isEmpty && flat.isEmpty && debuff.isEmpty }

    /// Everything the character brings to a fight that takes something off the other side.
    ///
    /// The largest source of each stacking-free kind is the one that fires, so every source is read
    /// apart rather than summed — a build carrying two of the same reduction gets the better one, not
    /// both. A record naming the whole family and one naming a single type are the same reduction as
    /// far as the game is concerned, so they compete for the same slot.
    public static func of(_ character: ResolvedCharacter) -> TargetReduction {
        var reduction = TargetReduction()
        let sources = character.equippedItems.map(\.stats) + character.everySkill.map(\.stats)

        for kind in ResistanceKind.allCases {
            guard let type = kind.damageType else { continue }

            for (suffix, keyPath) in [
                ("ResistanceReductionPercentMin", \TargetReduction.percent),
                ("ResistanceReductionAbsoluteMin", \TargetReduction.flat),
            ] {
                let largest =
                    sources
                    .map { max($0.value("offensive\(type.rawValue)\(suffix)"), $0.value("offensiveTotal\(suffix)")) }
                    .max() ?? 0
                if largest > 0 { reduction[keyPath: keyPath][kind] = largest }
            }

            // A debuff writes what it takes off the target as a negative resistance, and these add up.
            let left = character.everySkill.reduce(0.0) { total, skill in
                total + min(0, skill.stats.value(kind.resistanceKey))
            }
            if left < 0 { reduction.debuff[kind] = -left }
        }
        return reduction
    }

    /// What a monster takes off the character it is fighting.
    ///
    /// Only the debuff kind: since 1.2 a monster's abilities no longer carry the `%` and flat
    /// reductions, and the unique debuffs that write a negative resistance are what is left — Ravager's
    /// Presence at −25 across most of them, Zantarin's Curse of Frailty at −30.
    public static func of(_ monster: ResolvedMonster) -> TargetReduction {
        var reduction = TargetReduction()
        for kind in ResistanceKind.allCases {
            let left = monster.abilities.reduce(0.0) { total, ability in
                total + min(0, ability.skill.stats.value(kind.resistanceKey))
            }
            if left < 0 { reduction.debuff[kind] = -left }
        }
        return reduction
    }
}
