// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// The computed character sheet: the numbers the game shows on its own character window.
struct CharacterSheet: Sendable {
    struct Attribute: Sendable {
        let base: Double
        let bonus: Double
        var total: Double { base + bonus }
    }

    var physique = Attribute(base: 0, bonus: 0)
    var cunning = Attribute(base: 0, bonus: 0)
    var spirit = Attribute(base: 0, bonus: 0)

    var health: Double = 0
    var energy: Double = 0
    var healthRegen: Double = 0
    var energyRegen: Double = 0

    var offensiveAbility: Double = 0
    var defensiveAbility: Double = 0

    var armor: Double = 0
    /// Where a resistance stops counting, absent anything that raises it.
    static let resistanceCap: Double = 80
    var armorAbsorption: Double = 0
    /// Armour on each hit region, as the game's character window lists it.
    var armorBySlot: [EquipmentSlot: Double] = [:]
    /// Armour from belts, jewellery and skills, which the game adds to every region.
    var armorFromOtherSources: Double = 0

    /// Resistance percentages, already including the elemental and all-resistance blanket bonuses.
    var resistances: [ResistanceKind: Double] = [:]
    var maxResistances: [ResistanceKind: Double] = [:]

    /// Percentage damage bonus by type, including the attribute-driven scaling the game applies.
    var damageModifiers: [DamageType: Double] = [:]
    /// Flat damage the character adds to what it wields, by type.
    var flatDamage: [DamageType: Double] = [:]

    /// The speeds as the game's own window prints them: the resulting percentage, not the bonus.
    var attackSpeed: Double = 0
    /// How often the character swings, at that speed.
    var attacksPerSecond: Double = 0
    var castSpeed: Double = 0
    var movementSpeed: Double = 0
    var critDamage: Double = 0
    var cooldownReduction: Double = 0

    /// Everything that fed the sheet, for the detail panels.
    var contributions = StatBlock()
}

/// Computes a character sheet from a save, its gear and its skills.
///
/// Every formula here is read from the game's own database — `records/creatures/pc/playerlevels.dbr` for
/// attribute conversions and `records/game/combatformulas.dbr` for the ability equations — rather than
/// hardcoded, so the numbers stay right across patches.
struct StatEngine {
    private struct Constants {
        let baseOffensiveAbility: Double
        let baseDefensiveAbility: Double
        let attributeIncrement: Double
        let lifePerPhysiquePoint: Double
        let lifePerCunningPoint: Double
        let lifePerSpiritPoint: Double
        let energyPerSpiritPoint: Double
        let armorAbsorption: Double
        /// What the engine lets a player's speeds run between, in percent.
        let attackSpeedRange: ClosedRange<Double>
        let castSpeedRange: ClosedRange<Double>
        let runSpeedRange: ClosedRange<Double>
    }

    /// What a point of an attribute regenerates per second before any bonus.
    ///
    /// No record states these — the shipped data carries only the 1.0/s a bare character record holds —
    /// so they are fitted to the game's own character window: 201.89 energy at 874.24 spirit and 154.20
    /// health at 1306.24 physique, both reproduced to within a hundredth. One character is one sample,
    /// and the fit only holds while every other contribution is right — a missing bonus lands here as a
    /// wrong rate. A second character that disagrees means the rate is not a flat per-point figure.
    /// Swings a second at 100% attack speed. The records name a weapon's speed class — `tagAttackSpeed
    /// Average` — but state no rate for it; this is fitted to the game's own reading of 1.84 attacks a
    /// second at 122.4%, and a weapon of another class may well swing at a different base rate.
    private static let baseAttackRate = 1.5

    private static let energyRegenPerSpirit = 0.165_60
    private static let healthRegenPerPhysique = 0.038_47

    private static let playerLevelsPath = "records/creatures/pc/playerlevels.dbr"
    private static let malePlayerPath = "records/creatures/pc/malepc01.dbr"
    private static let femalePlayerPath = "records/creatures/pc/femalepc01.dbr"
    private static let combatFormulasPath = "records/game/combatformulas.dbr"
    private static let gameEnginePath = "records/game/gameengine.dbr"

    let database: GameDatabase

    func sheet(
        for save: Gdc.SaveFile,
        contributions: StatBlock,
        bodyArmor: [EquipmentSlot: Double] = [:],
        /// What the weapon in hand does to the base attack rate, as a fraction: a wand at −0.1 is 10%
        /// slower before any bonus.
        weaponSpeed: Double = 0
    ) -> CharacterSheet {
        let constants = constants(isMale: save.header.isMale)
        var sheet = CharacterSheet()
        sheet.contributions = contributions

        applyAttributes(to: &sheet, biography: save.biography, contributions: contributions)
        applyPools(to: &sheet, biography: save.biography, contributions: contributions, constants: constants)
        applyAbilities(
            to: &sheet,
            level: Double(save.biography.level),
            contributions: contributions,
            constants: constants
        )
        applyMitigation(to: &sheet, contributions: contributions, constants: constants, bodyArmor: bodyArmor)
        applySpeeds(to: &sheet, contributions: contributions, weaponSpeed: weaponSpeed, constants: constants)

        return sheet
    }

    private func applyAttributes(to sheet: inout CharacterSheet, biography: Gdc.Biography, contributions: StatBlock) {
        sheet.physique = attribute(
            base: Double(biography.physique),
            flat: contributions.value("characterStrength"),
            percent: contributions.value("characterStrengthModifier")
        )
        sheet.cunning = attribute(
            base: Double(biography.cunning),
            flat: contributions.value("characterDexterity"),
            percent: contributions.value("characterDexterityModifier")
        )
        sheet.spirit = attribute(
            base: Double(biography.spirit),
            flat: contributions.value("characterIntelligence"),
            percent: contributions.value("characterIntelligenceModifier")
        )
    }

    private func applyPools(
        to sheet: inout CharacterSheet,
        biography: Gdc.Biography,
        contributions: StatBlock,
        constants: Constants
    ) {
        let increment = constants.attributeIncrement
        sheet.health = pool(
            stored: Double(biography.health),
            fromAttributes: sheet.physique.bonus * (constants.lifePerPhysiquePoint / increment)
                + sheet.cunning.bonus * (constants.lifePerCunningPoint / increment)
                + sheet.spirit.bonus * (constants.lifePerSpiritPoint / increment),
            flat: contributions.value("characterLife"),
            percent: contributions.value("characterLifeModifier")
        )
        sheet.energy = pool(
            stored: Double(biography.energy),
            fromAttributes: sheet.spirit.bonus * (constants.energyPerSpiritPoint / increment),
            flat: contributions.value("characterMana"),
            percent: contributions.value("characterManaModifier")
        )
        // "Percent bonuses only affect regeneration from gear and skills; not base regeneration, which
        // is based on spirit" — the game's own words for the energy line, and health reads the same way
        // against physique. The rate per point is in the executable rather than the records; see
        // `Self.regenPerPoint`.
        sheet.healthRegen =
            sheet.physique.total * Self.healthRegenPerPhysique
            + scaled(
                contributions.value("characterLifeRegen"),
                percent: contributions.value("characterLifeRegenModifier")
            )
        sheet.energyRegen =
            sheet.spirit.total * Self.energyRegenPerSpirit
            + scaled(
                contributions.value("characterManaRegen"),
                percent: contributions.value("characterManaRegenModifier")
            )
    }

    private func applyAbilities(
        to sheet: inout CharacterSheet,
        level: Double,
        contributions: StatBlock,
        constants: Constants
    ) {
        sheet.offensiveAbility = ability(
            equationKey: "offensiveAbilityEquation",
            flat: constants.baseOffensiveAbility + contributions.value("characterOffensiveAbility"),
            attribute: sheet.cunning.total,
            percent: contributions.value("characterOffensiveAbilityModifier"),
            level: level
        )
        sheet.defensiveAbility = ability(
            equationKey: "defensiveAbilityEquation",
            flat: constants.baseDefensiveAbility + contributions.value("characterDefensiveAbility"),
            attribute: sheet.physique.total,
            percent: contributions.value("characterDefensiveAbilityModifier"),
            level: level
        )
    }

    private func applyMitigation(
        to sheet: inout CharacterSheet,
        contributions: StatBlock,
        constants: Constants,
        bodyArmor: [EquipmentSlot: Double]
    ) {
        sheet.armorBySlot = bodyArmor
        // What is left once the hit regions have taken their own: armour from belts, jewellery and
        // skills, which the game's help text says lands on every region.
        sheet.armorFromOtherSources =
            contributions.value("defensiveProtection")
            + contributions.value("defensiveBonusProtection")
            - bodyArmor.values.reduce(0, +)
        sheet.armor = scaled(
            armorRating(bodyArmor: bodyArmor, global: sheet.armorFromOtherSources),
            percent: contributions.value("defensiveProtectionModifier")
        )
        // "Increases Armor Absorption by X%" scales the base share, and no share can exceed the whole hit.
        sheet.armorAbsorption = min(
            100,
            scaled(constants.armorAbsorption, percent: contributions.value("defensiveAbsorptionModifier"))
        )
        sheet.resistances = resistances(contributions)
        sheet.maxResistances = maxResistances(contributions)
        sheet.damageModifiers = damageModifiers(contributions)
        sheet.flatDamage = Dictionary(
            uniqueKeysWithValues: DamageType.allCases.map { ($0, contributions.value($0.minimumKey)) }
        )
    }

    /// The game's Armor Rating: each hit region contributes in proportion to how often it is struck.
    ///
    /// Its own help text puts it plainly — "Bonuses on skills and on non-armor pieces are added to all
    /// armor slots" — so global armour lands in every region and survives the weighting intact.
    private func armorRating(bodyArmor: [EquipmentSlot: Double], global: Double) -> Double {
        let formulas = database.record(Self.combatFormulasPath)
        var weighted: Double = 0
        var totalChance: Double = 0

        for slot in EquipmentSlot.allCases {
            guard let key = slot.hitRegionChanceKey else { continue }

            let chance = formulas?.number(key) ?? 0
            totalChance += chance
            weighted += chance * (bodyArmor[slot] ?? 0)
        }

        guard totalChance > 0 else { return bodyArmor.values.reduce(0, +) + global }

        return weighted / totalChance + global
    }

    /// The speeds the game prints: a hundred plus every bonus, the weapon's own rate folded in, and the
    /// engine's caps applied — a character with +48% movement still runs at the 135% the engine allows.
    private func applySpeeds(
        to sheet: inout CharacterSheet,
        contributions: StatBlock,
        weaponSpeed: Double,
        constants: Constants
    ) {
        let overall = contributions.value("characterTotalSpeedModifier")

        func speed(_ key: String, weapon: Double = 0, within range: ClosedRange<Double>) -> Double {
            let bonus = 100 + contributions.value(key) + overall
            return min(max(bonus * (1 + weapon), range.lowerBound), range.upperBound)
        }

        sheet.attackSpeed = speed(
            "characterAttackSpeedModifier",
            weapon: weaponSpeed,
            within: constants.attackSpeedRange
        )
        sheet.attacksPerSecond = Self.baseAttackRate * sheet.attackSpeed / 100
        sheet.castSpeed = speed("characterSpellCastSpeedModifier", within: constants.castSpeedRange)
        sheet.movementSpeed = speed("characterRunSpeedModifier", within: constants.runSpeedRange)
        sheet.critDamage = contributions.value("offensiveCritDamageModifier")
        sheet.cooldownReduction = contributions.value("skillCooldownReduction")
    }

    // MARK: - Components

    private func attribute(base: Double, flat: Double, percent: Double) -> CharacterSheet.Attribute {
        let total = (base + flat) * (1 + percent / 100)
        return CharacterSheet.Attribute(base: base, bonus: total - base)
    }

    /// The save stores the pool the character's own attribute points produce; everything else adds on top.
    private func pool(stored: Double, fromAttributes: Double, flat: Double, percent: Double) -> Double {
        (stored + fromAttributes + flat) * (1 + percent / 100)
    }

    private func scaled(_ value: Double, percent: Double) -> Double {
        value * (1 + percent / 100)
    }

    private func ability(
        equationKey: String,
        flat: Double,
        attribute: Double,
        percent: Double,
        level: Double
    ) -> Double {
        let variables: [String: Double] = [
            "offensiveAbilityDV": flat,
            "defensiveAbilityDV": flat,
            "characterLevelDV": level,
            "dexterityDV": attribute,
            "strengthDV": attribute,
            "bonusDV": 0,
            "offensiveAbilityModifierDV": percent,
            "defensiveAbilityModifierDV": percent,
        ]

        guard
            let formulas = database.record(Self.combatFormulasPath),
            case let source = formulas.text(equationKey),
            !source.isEmpty,
            let equation = try? Equation(source),
            let value = try? equation.value(variables)
        else {
            // Matches the shipped equations; only reached if the record is missing.
            return (flat + level * 12 + attribute * 0.5) * (1 + percent / 100) + 53
        }

        return value
    }

    private func resistances(_ stats: StatBlock) -> [ResistanceKind: Double] {
        let elemental = stats.value("defensiveElementalResistance")
        let everyKind = stats.value("defensiveAllResistance")

        var values = [ResistanceKind: Double]()
        for kind in ResistanceKind.allCases {
            var amount = stats.value(kind.resistanceKey)
            if kind.takesAllResistanceBonus { amount += everyKind }
            if kind.isElemental { amount += elemental }
            values[kind] = amount
        }
        return values
    }

    private func maxResistances(_ stats: StatBlock) -> [ResistanceKind: Double] {
        let everyKind = stats.value("defensiveAllMaxResist")

        var values = [ResistanceKind: Double]()
        for kind in ResistanceKind.allCases {
            values[kind] = Self.baseResistanceCap + everyKind + stats.value(kind.maximumKey)
        }
        return values
    }

    /// Percentage damage bonuses as the character window reports them.
    ///
    /// The game states that this figure excludes the bonus attributes give — Cunning to physical and
    /// pierce, Spirit to the magical types — so that scaling is deliberately left out here too.
    private func damageModifiers(_ stats: StatBlock) -> [DamageType: Double] {
        let total = stats.value("offensiveTotalDamageModifier")
        let elemental = stats.value("offensiveElementalModifier")

        var values = [DamageType: Double]()
        for type in DamageType.allCases where type != .elemental {
            var percent = stats.value(type.modifierKey) + total
            if type == .fire || type == .cold || type == .lightning { percent += elemental }

            values[type] = percent
        }
        return values
    }

    /// Every resistance caps at 80% before gear raises the cap.
    private static let baseResistanceCap: Double = 80

    // MARK: - Constants

    private func constants(isMale: Bool) -> Constants {
        let levels = database.record(Self.playerLevelsPath)
        let player = database.record(isMale ? Self.malePlayerPath : Self.femalePlayerPath)
        let engine = database.record(Self.gameEnginePath)

        return Constants(
            baseOffensiveAbility: player?.number("characterOffensiveAbility") ?? 65,
            baseDefensiveAbility: player?.number("characterDefensiveAbility") ?? 65,
            attributeIncrement: levels.map { max(1, $0.number("strengthIncrement")) } ?? 8,
            lifePerPhysiquePoint: levels?.number("lifeIncrement") ?? 20,
            lifePerCunningPoint: levels?.number("lifeIncrementDexterity") ?? 8,
            lifePerSpiritPoint: levels?.number("lifeIncrementIntelligence") ?? 12,
            energyPerSpiritPoint: levels?.number("manaIncrement") ?? 16,
            armorAbsorption: engine?.number("armorDefensiveAbsorption") ?? 70,
            attackSpeedRange: Self.range(engine, "playerAttackSpeedCap"),
            castSpeedRange: Self.range(engine, "playerSpellCastSpeedCap"),
            runSpeedRange: Self.range(engine, "playerRunSpeedCap")
        )
    }

    /// A `…CapMin` / `…CapMax` pair, which is how the engine states what it lets a player reach.
    private static func range(_ engine: ArzRecord?, _ prefix: String) -> ClosedRange<Double> {
        let lowest = engine?.number(prefix + "Min") ?? 0
        let highest = engine?.number(prefix + "Max") ?? 200
        guard lowest < highest else { return 0 ... 200 }

        return lowest ... highest
    }
}
