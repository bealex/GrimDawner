// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// What a set of fittings is worth, in the figures a plan is judged on.
///
/// The resistances are arrays in `ResistanceKind.allCases` order rather than dictionaries: the search
/// reads them hundreds of thousands of times and a dictionary allocates on every one.
public struct LoadoutFigures: Sendable {
    public var resistance = [Double](repeating: 0, count: ResistanceKind.allCases.count)
    public var maximumResistance = [Double](repeating: 0, count: ResistanceKind.allCases.count)
    public var offensiveAbility: Double = 0
    public var defensiveAbility: Double = 0
    public var armor: Double = 0
    public var armorAbsorption: Double = 0
    public var health: Double = 0
    /// Attack speed as a percentage, which is what the skill's damage a second scales by.
    public var attackSpeed: Double = 0
    /// The chosen skill's damage before a target's own defences, raised by the character's modifiers.
    public var skillDamage: Double = 0

    public func resistance(_ kind: ResistanceKind) -> Double {
        resistance[ResistanceKind.allCases.firstIndex(of: kind) ?? 0]
    }

    public func maximumResistance(_ kind: ResistanceKind) -> Double {
        maximumResistance[ResistanceKind.allCases.firstIndex(of: kind) ?? 0]
    }
}

/// Ranks a set of fittings, quickly enough for a search that tries hundreds of thousands of them.
///
/// It evaluates the game's own equations, read once here rather than per call, over the reduced figures
/// `LoadoutStats` carries. **Nothing it produces is ever displayed**: a finished plan is rebuilt through
/// `CharacterBuilder` like any other character, and the sheet the app shows comes from there. This only
/// decides which plans are worth rebuilding, so it is pinned to the builder by a test rather than
/// trusted to agree with it on its own.
public struct LoadoutEvaluator: Sendable {
    /// The character with none of the fittings in, which every combination is added to.
    public let base: LoadoutStats
    /// The chosen skill's own damage, before any modifier — the constant part of its output.
    public let flatSkillDamage: Double

    private let level: Double
    private let baseCunning: Double
    private let basePhysique: Double
    private let baseSpirit: Double
    private let storedHealth: Double
    /// What a point of each attribute is worth in health, as `playerlevels.dbr` states it.
    private let lifePerPhysique: Double
    private let lifePerCunning: Double
    private let lifePerSpirit: Double
    private let baseOffensiveAbility: Double
    private let baseDefensiveAbility: Double
    private let baseAbsorption: Double
    private let weaponSpeed: Double
    private let attackSpeedRange: ClosedRange<Double>
    private let offensiveEquation: Equation?
    private let defensiveEquation: Equation?
    /// What the character is worth as it stands, which every score is read against so that figures in
    /// different units can be added up at all. Written once, at the end of `init`.
    private var reference: LoadoutFigures

    public init(
        database: GameDatabase,
        save: Gdc.SaveFile,
        base: LoadoutStats,
        worn: LoadoutStats,
        flatSkillDamage: Double,
        weaponSpeed: Double
    ) {
        let player = database.record(
            save.header.isMale ? "records/creatures/pc/malepc01.dbr" : "records/creatures/pc/femalepc01.dbr"
        )
        let engine = database.record("records/game/gameengine.dbr")
        let formulas = database.record("records/game/combatformulas.dbr")
        let levels = database.record("records/creatures/pc/playerlevels.dbr")
        let increment = levels.map { max(1, $0.number("strengthIncrement")) } ?? 8

        self.base = base
        self.flatSkillDamage = flatSkillDamage
        self.weaponSpeed = weaponSpeed
        level = Double(save.biography.level)
        baseCunning = Double(save.biography.cunning)
        basePhysique = Double(save.biography.physique)
        baseSpirit = Double(save.biography.spirit)
        storedHealth = Double(save.biography.health)
        lifePerPhysique = (levels?.number("lifeIncrement") ?? 20) / increment
        lifePerCunning = (levels?.number("lifeIncrementDexterity") ?? 8) / increment
        lifePerSpirit = (levels?.number("lifeIncrementIntelligence") ?? 12) / increment
        baseOffensiveAbility = player?.number("characterOffensiveAbility") ?? 65
        baseDefensiveAbility = player?.number("characterDefensiveAbility") ?? 65
        baseAbsorption = engine?.number("armorDefensiveAbsorption") ?? 70
        attackSpeedRange = Self.range(engine, "playerAttackSpeedCap")
        offensiveEquation = formulas.flatMap { try? Equation($0.text("offensiveAbilityEquation")) }
        defensiveEquation = formulas.flatMap { try? Equation($0.text("defensiveAbilityEquation")) }

        // Read once, with what the character wears now, so a score says how much better a plan is than
        // the fittings already in the sockets. Empty first: nothing may call an instance method until
        // every stored property has a value.
        reference = LoadoutFigures()
        reference = figures(worn)
    }

    /// What the character comes to with these fittings added.
    public func figures(_ added: LoadoutStats) -> LoadoutFigures {
        figures(absolute: base + added)
    }

    /// The same, given the character and its fittings already added up — which is what the search
    /// carries, so it never builds the sum twice.
    public func figures(absolute stats: LoadoutStats) -> LoadoutFigures {
        var figures = LoadoutFigures()

        for index in figures.resistance.indices {
            figures.resistance[index] = stats.resistance[index]
            figures.maximumResistance[index] = Self.baseResistanceCap + stats.maximumResistance[index]
        }
        figures.offensiveAbility = ability(
            offensiveEquation,
            names: Self.offensiveNames,
            flat: baseOffensiveAbility + stats.offensiveFlat,
            attribute: (baseCunning + stats.cunningFlat) * (1 + stats.cunningPercent / 100),
            percent: stats.offensivePercent
        )
        figures.defensiveAbility = ability(
            defensiveEquation,
            names: Self.defensiveNames,
            flat: baseDefensiveAbility + stats.defensiveFlat,
            attribute: (basePhysique + stats.physiqueFlat) * (1 + stats.physiquePercent / 100),
            percent: stats.defensivePercent
        )
        figures.armor = stats.weightedArmor * (1 + stats.armorPercent / 100)
        figures.armorAbsorption = min(100, baseAbsorption * (1 + stats.absorptionPercent / 100))
        figures.health = health(stats)
        figures.attackSpeed = attackSpeed(modifier: stats.attackSpeed, overall: stats.totalSpeed)
        figures.skillDamage = flatSkillDamage + stats.skillDamage
        return figures
    }

    /// The resistances a plan has to reach, by `ResistanceKind.allCases` position. A resistance the
    /// target leaves out reads as zero, which nothing can fall short of.
    public func wanted(for target: LoadoutTarget) -> [Double] {
        ResistanceKind.allCases.map { kind in
            guard target.required.contains(kind) else { return 0 }

            return reference.maximumResistance(kind) + target.overcap
        }
    }

    /// Everything still short of the target, for saying so.
    public func shortfalls(_ figures: LoadoutFigures, wanted: [Double]) -> [ResistanceKind: Double] {
        var short = [ResistanceKind: Double]()
        for (index, kind) in ResistanceKind.allCases.enumerated() where figures.resistance[index] < wanted[index] {
            short[kind] = wanted[index] - figures.resistance[index]
        }
        return short
    }

    /// The search's inner loop: what one socket's option scores on top of everything already chosen,
    /// less what it is charged for falling short.
    ///
    /// The two are kept apart rather than added because this runs hundreds of thousands of times, and
    /// building the sum would allocate its arrays on every one of them. Only the figures the goal reads
    /// are worked out, since each ability costs an equation.
    public func penalisedScore(
        _ chosen: LoadoutStats,
        plus option: LoadoutStats,
        goal: LoadoutGoal,
        wanted: [Double],
        prices: [Double],
        wantedAbility: Double = 0,
        abilityPrice: Double = 0
    ) -> Double {
        var value = 0.0

        if goal != .defence {
            var attack = ratio(
                ability(
                    offensiveEquation,
                    names: Self.offensiveNames,
                    flat: baseOffensiveAbility + chosen.offensiveFlat + option.offensiveFlat,
                    attribute: (baseCunning + chosen.cunningFlat + option.cunningFlat)
                        * (1 + (chosen.cunningPercent + option.cunningPercent) / 100),
                    percent: chosen.offensivePercent + option.offensivePercent
                ),
                reference.offensiveAbility
            )
            if flatSkillDamage > 0 {
                let speed = attackSpeed(
                    modifier: chosen.attackSpeed + option.attackSpeed,
                    overall: chosen.totalSpeed + option.totalSpeed
                )
                attack += ratio(
                    (flatSkillDamage + chosen.skillDamage + option.skillDamage) * speed,
                    reference.skillDamage * reference.attackSpeed
                )
            } else {
                attack *= 2
            }
            value += goal == .balanced ? attack / 2 : attack
        }
        if goal != .attack {
            let armor =
                (chosen.weightedArmor + option.weightedArmor)
                * (1 + (chosen.armorPercent + option.armorPercent) / 100)
            let defensiveAbility = ability(
                defensiveEquation,
                names: Self.defensiveNames,
                flat: baseDefensiveAbility + chosen.defensiveFlat + option.defensiveFlat,
                attribute: (basePhysique + chosen.physiqueFlat + option.physiqueFlat)
                    * (1 + (chosen.physiquePercent + option.physiquePercent) / 100),
                percent: chosen.defensivePercent + option.defensivePercent
            )
            if wantedAbility > defensiveAbility {
                value -= (wantedAbility - defensiveAbility) * abilityPrice
            }
            let defence =
                ratio(defensiveAbility, reference.defensiveAbility)
                + ratio(armor, reference.armor)
                + ratio(
                    min(100, baseAbsorption * (1 + (chosen.absorptionPercent + option.absorptionPercent) / 100)),
                    reference.armorAbsorption
                )
                + ratio(
                    health(
                        physiqueFlat: chosen.physiqueFlat + option.physiqueFlat,
                        physiquePercent: chosen.physiquePercent + option.physiquePercent,
                        cunningFlat: chosen.cunningFlat + option.cunningFlat,
                        cunningPercent: chosen.cunningPercent + option.cunningPercent,
                        spiritFlat: chosen.spiritFlat + option.spiritFlat,
                        spiritPercent: chosen.spiritPercent + option.spiritPercent,
                        lifeFlat: chosen.lifeFlat + option.lifeFlat,
                        lifePercent: chosen.lifePercent + option.lifePercent
                    ),
                    reference.health
                )
            value += goal == .balanced ? defence / 2 : defence
        }

        for index in wanted.indices where wanted[index] > 0 {
            let short = wanted[index] - chosen.resistance[index] - option.resistance[index]
            if short > 0 { value -= short * prices[index] }
        }
        return value
    }

    /// What the goal is worth, as a multiple of what the character has now, so figures in percent,
    /// in points and in damage can be weighed against one another at all.
    public func score(_ figures: LoadoutFigures, goal: LoadoutGoal) -> Double {
        var value = 0.0
        if goal != .defence {
            var attack = ratio(figures.offensiveAbility, reference.offensiveAbility)
            if flatSkillDamage > 0 {
                attack += ratio(
                    figures.skillDamage * figures.attackSpeed,
                    reference.skillDamage * reference.attackSpeed
                )
            } else {
                attack *= 2
            }
            value += goal == .balanced ? attack / 2 : attack
        }
        if goal != .attack {
            let defence =
                ratio(figures.defensiveAbility, reference.defensiveAbility)
                + ratio(figures.armor, reference.armor)
                + ratio(figures.armorAbsorption, reference.armorAbsorption)
                + ratio(figures.health, reference.health)
            value += goal == .balanced ? defence / 2 : defence
        }
        return value
    }

    /// The character as it stands, for reading a plan against.
    public var current: LoadoutFigures { reference }

    // MARK: - The game's own arithmetic

    /// The equations' own variable names, already folded to lower case: the evaluator hands them
    /// straight to `Equation` hundreds of thousands of times and will not fold them each time.
    private typealias Names = (flat: String, attribute: String, percent: String)
    private static let offensiveNames: Names = (
        "offensiveabilitydv", "dexteritydv", "offensiveabilitymodifierdv"
    )
    private static let defensiveNames: Names = (
        "defensiveabilitydv", "strengthdv", "defensiveabilitymodifierdv"
    )

    /// Health as the sheet reads it: what the character's own points bought, what its attribute
    /// bonuses add on top, and the flat and percentage bonuses over both.
    private func health(_ stats: LoadoutStats) -> Double {
        health(
            physiqueFlat: stats.physiqueFlat,
            physiquePercent: stats.physiquePercent,
            cunningFlat: stats.cunningFlat,
            cunningPercent: stats.cunningPercent,
            spiritFlat: stats.spiritFlat,
            spiritPercent: stats.spiritPercent,
            lifeFlat: stats.lifeFlat,
            lifePercent: stats.lifePercent
        )
    }

    /// The same, taken apart, so the search's inner loop never builds the sum of two stat blocks
    /// just to read one figure off it.
    private func health(
        physiqueFlat: Double,
        physiquePercent: Double,
        cunningFlat: Double,
        cunningPercent: Double,
        spiritFlat: Double,
        spiritPercent: Double,
        lifeFlat: Double,
        lifePercent: Double
    ) -> Double {
        let fromAttributes =
            bonus(base: basePhysique, flat: physiqueFlat, percent: physiquePercent) * lifePerPhysique
            + bonus(base: baseCunning, flat: cunningFlat, percent: cunningPercent) * lifePerCunning
            + bonus(base: baseSpirit, flat: spiritFlat, percent: spiritPercent) * lifePerSpirit

        return (storedHealth + fromAttributes + lifeFlat) * (1 + lifePercent / 100)
    }

    /// What an attribute gains over the points the character itself spent.
    private func bonus(base: Double, flat: Double, percent: Double) -> Double {
        (base + flat) * (1 + percent / 100) - base
    }

    private func attackSpeed(modifier: Double, overall: Double) -> Double {
        min(
            max((100 + modifier + overall) * (1 + weaponSpeed), attackSpeedRange.lowerBound),
            attackSpeedRange.upperBound
        )
    }

    private func ratio(_ value: Double, _ against: Double) -> Double {
        against > 0 ? value / against : 0
    }

    private func ability(
        _ equation: Equation?,
        names: Names,
        flat: Double,
        attribute: Double,
        percent: Double
    ) -> Double {
        guard
            let equation,
            let value = try? equation.value(lowercased: [
                names.flat: flat,
                names.attribute: attribute,
                names.percent: percent,
                "characterleveldv": level,
                "bonusdv": 0,
            ])
        else { return (flat + level * 12 + attribute * 0.5) * (1 + percent / 100) + 53 }

        return value
    }

    /// Every resistance caps at 80 before gear raises the cap, as the sheet reads it.
    private static let baseResistanceCap: Double = 80

    private static func range(_ engine: ArzRecord?, _ prefix: String) -> ClosedRange<Double> {
        let lowest = engine?.number(prefix + "Min") ?? 0
        let highest = engine?.number(prefix + "Max") ?? 200
        guard lowest < highest else { return 0 ... 200 }

        return lowest ... highest
    }
}
