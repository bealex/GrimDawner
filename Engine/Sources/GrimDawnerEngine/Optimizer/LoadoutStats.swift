// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// The figures a socketed component or augment can move, gathered once per fitting.
///
/// The search tries hundreds of thousands of combinations, and merging a hundred-key dictionary for
/// each one is what makes that slow. Every figure the search ranks by is linear in what the fittings
/// carry, so each one is reduced to a handful of numbers here and the search adds those instead.
///
/// Two of them are collapsed further, since their weights never move during a search: armour is stored
/// already weighted by how often its own region is struck, so the rating is a plain sum, and a
/// fitting's damage bonus is stored as the damage it adds to the chosen skill rather than as a
/// percentage per damage type.
public struct LoadoutStats: Sendable {
    public var resistance = [Double](repeating: 0, count: ResistanceKind.allCases.count)
    public var maximumResistance = [Double](repeating: 0, count: ResistanceKind.allCases.count)

    public var offensiveFlat: Double = 0
    public var offensivePercent: Double = 0
    public var cunningFlat: Double = 0
    public var cunningPercent: Double = 0

    public var defensiveFlat: Double = 0
    public var defensivePercent: Double = 0
    public var physiqueFlat: Double = 0
    public var physiquePercent: Double = 0
    public var spiritFlat: Double = 0
    public var spiritPercent: Double = 0
    public var lifeFlat: Double = 0
    public var lifePercent: Double = 0

    /// Armour already multiplied by its region's share of the hits, so a sum of these is the rating.
    public var weightedArmor: Double = 0
    public var armorPercent: Double = 0
    public var absorptionPercent: Double = 0

    public var attackSpeed: Double = 0
    public var totalSpeed: Double = 0
    /// What this adds to the chosen skill's damage, in damage rather than in percent.
    public var skillDamage: Double = 0

    public init() {}

    /// Reads one fitting's block. `armorWeight` is its region's share of the hits, or 1 where its
    /// armour lands on every region; `damageWeights` is the chosen skill's damage by type, which turns
    /// a percentage bonus into the damage it actually adds.
    public init(_ block: StatBlock, armorWeight: Double, damageWeights: [DamageType: Double]) {
        for (index, kind) in ResistanceKind.allCases.enumerated() {
            resistance[index] = StatComposition.total(feeding: kind.resistanceKey, in: block)
            maximumResistance[index] = StatComposition.total(feeding: kind.maximumKey, in: block)
        }

        offensiveFlat = block.value("characterOffensiveAbility")
        offensivePercent = block.value("characterOffensiveAbilityModifier")
        cunningFlat = block.value("characterDexterity")
        cunningPercent = block.value("characterDexterityModifier")

        defensiveFlat = block.value("characterDefensiveAbility")
        defensivePercent = block.value("characterDefensiveAbilityModifier")
        physiqueFlat = block.value("characterStrength")
        physiquePercent = block.value("characterStrengthModifier")
        spiritFlat = block.value("characterIntelligence")
        spiritPercent = block.value("characterIntelligenceModifier")
        lifeFlat = block.value("characterLife")
        lifePercent = block.value("characterLifeModifier")

        weightedArmor =
            (block.value("defensiveProtection") + block.value("defensiveBonusProtection")) * armorWeight
        armorPercent = block.value("defensiveProtectionModifier")
        absorptionPercent = block.value("defensiveAbsorptionModifier")

        attackSpeed = block.value("characterAttackSpeedModifier")
        totalSpeed = block.value("characterTotalSpeedModifier")
        skillDamage = damageWeights.reduce(0) { running, entry in
            running + entry.value * StatComposition.total(feeding: entry.key.modifierKey, in: block) / 100
        }
    }

    public static func += (total: inout LoadoutStats, added: LoadoutStats) {
        for index in total.resistance.indices {
            total.resistance[index] += added.resistance[index]
            total.maximumResistance[index] += added.maximumResistance[index]
        }
        total.offensiveFlat += added.offensiveFlat
        total.offensivePercent += added.offensivePercent
        total.cunningFlat += added.cunningFlat
        total.cunningPercent += added.cunningPercent
        total.defensiveFlat += added.defensiveFlat
        total.defensivePercent += added.defensivePercent
        total.physiqueFlat += added.physiqueFlat
        total.physiquePercent += added.physiquePercent
        total.spiritFlat += added.spiritFlat
        total.spiritPercent += added.spiritPercent
        total.lifeFlat += added.lifeFlat
        total.lifePercent += added.lifePercent
        total.weightedArmor += added.weightedArmor
        total.armorPercent += added.armorPercent
        total.absorptionPercent += added.absorptionPercent
        total.attackSpeed += added.attackSpeed
        total.totalSpeed += added.totalSpeed
        total.skillDamage += added.skillDamage
    }

    public static func + (lhs: LoadoutStats, rhs: LoadoutStats) -> LoadoutStats {
        var total = lhs
        total += rhs
        return total
    }

    /// Takes one fitting back out, which is how the search tries a socket's other options without
    /// adding up every other socket again.
    public static func -= (total: inout LoadoutStats, removed: LoadoutStats) {
        for index in total.resistance.indices {
            total.resistance[index] -= removed.resistance[index]
            total.maximumResistance[index] -= removed.maximumResistance[index]
        }
        total.offensiveFlat -= removed.offensiveFlat
        total.offensivePercent -= removed.offensivePercent
        total.cunningFlat -= removed.cunningFlat
        total.cunningPercent -= removed.cunningPercent
        total.defensiveFlat -= removed.defensiveFlat
        total.defensivePercent -= removed.defensivePercent
        total.physiqueFlat -= removed.physiqueFlat
        total.physiquePercent -= removed.physiquePercent
        total.spiritFlat -= removed.spiritFlat
        total.spiritPercent -= removed.spiritPercent
        total.lifeFlat -= removed.lifeFlat
        total.lifePercent -= removed.lifePercent
        total.weightedArmor -= removed.weightedArmor
        total.armorPercent -= removed.armorPercent
        total.absorptionPercent -= removed.absorptionPercent
        total.attackSpeed -= removed.attackSpeed
        total.totalSpeed -= removed.totalSpeed
        total.skillDamage -= removed.skillDamage
    }

    public static func - (lhs: LoadoutStats, rhs: LoadoutStats) -> LoadoutStats {
        var total = lhs
        total -= rhs
        return total
    }
}
