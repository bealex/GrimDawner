// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import SwiftUI

/// What the character takes away from whatever it is fighting, and which of it is wasted.
///
/// Most bonuses add up. These do not: the game applies the **largest** of them and ignores the rest, so
/// a build carrying two sources of the same one is paying for a line that never fires. Every source is
/// named, never summed: naming them is the whole point — a wasted line is only obvious once
/// you can see which two pieces carry it.
///
/// The reductions listed are the ones a record aims at whatever is being hit, under an `offensive…`
/// key. The third kind — the plain `-X% <type> Resistance` a debuff leaves on a target, which does
/// stack — is written as a negative resistance **on the debuff the skill applies**, under the same key
/// the character's own resistance uses. Reading it off the character would list the character's own
/// gear as though it were aimed at the enemy, so it is left out.
enum TargetDebuffs {
    /// One of the game's reductions, with everything the character has that feeds it.
    struct Reduction: Identifiable {
        let title: String
        /// What the figure means — a flat subtraction, or a share of what is there.
        let unit: StatUnit
        let sources: [StatSources.Entry]
        /// Whether the game stacks these or takes the largest and drops the rest.
        let stacks: Bool

        var id: String { title }

        /// What actually applies: everything where the game stacks them, the largest where it does not.
        var applied: Double {
            stacks ? sources.reduce(0) { $0 + $1.value } : sources.map(\.value).max() ?? 0
        }

        /// What is paid for and never fires.
        var wasted: Double {
            guard !stacks else { return 0 }

            return sources.reduce(0) { $0 + $1.value } - applied
        }

        /// A build carrying two of a reduction that does not stack has a line doing nothing.
        var isWasteful: Bool { !stacks && sources.count > 1 }

        var text: String { unit.format(applied) }
    }

    /// Everything the character brings to a fight that takes something off the other side.
    static func of(_ character: ResolvedCharacter) -> [Reduction] {
        var found = [Reduction]()

        func add(_ title: String, _ unit: StatUnit, stacks: Bool = false, keys: [String]) {
            let sources = keys.flatMap { StatSources.contributors(to: $0, in: character) }
                .filter { $0.value != 0 }
                .sorted { abs($0.value) > abs($1.value) }
            guard !sources.isEmpty else { return }

            found.append(Reduction(title: title, unit: unit, sources: sources, stacks: stacks))
        }

        add("Reduced target's damage", .percent, keys: [ "offensiveTotalDamageReductionPercentMin" ])
        add("Reduced target's Offensive Ability", .flat, keys: [ "offensiveSlowOffensiveReductionMin" ])
        add("Reduced target's Defensive Ability", .flat, keys: [ "offensiveSlowDefensiveReductionMin" ])

        // The two reductions aimed at resistance. A skill that names one family and a ring that names
        // everything are one reduction as far as the game is concerned, so both feed the same line.
        add(
            "% Reduced target's resistances",
            .percent,
            keys: [ "offensiveTotalResistanceReductionPercentMin" ]
                + DamageType.allCases.map { "offensive\($0.rawValue)ResistanceReductionPercentMin" }
        )
        add(
            "Reduced target's resistances",
            .flat,
            keys: [ "offensiveTotalResistanceReductionAbsoluteMin" ]
                + DamageType.allCases.map { "offensive\($0.rawValue)ResistanceReductionAbsoluteMin" }
        )

        return found
    }
}
