// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// The computed character sheet: the numbers the game shows on its own character window.
public struct CharacterSheet: Sendable {
    public struct Attribute: Sendable {
        public let base: Double
        public let bonus: Double
        public var total: Double { base + bonus }
    }

    public var physique = Attribute(base: 0, bonus: 0)
    public var cunning = Attribute(base: 0, bonus: 0)
    public var spirit = Attribute(base: 0, bonus: 0)

    public var health: Double = 0
    public var energy: Double = 0
    public var healthRegen: Double = 0
    public var energyRegen: Double = 0

    public var offensiveAbility: Double = 0
    public var defensiveAbility: Double = 0

    public var armor: Double = 0
    /// Where a resistance stops counting, absent anything that raises it.
    public static let resistanceCap: Double = 80
    public var armorAbsorption: Double = 0
    /// Armour on each hit region, as the game's own popup lists it: the piece worn there plus the
    /// armour every region shares, raised by the percentage bonus.
    public var armorBySlot: [EquipmentSlot: Double] = [:]
    /// The share of that which comes from belts, jewellery and skills rather than from the piece.
    public var armorFromOtherSources: Double = 0
    /// How often each region is the one struck, as the percentages the game's own popup prints.
    public var armorHitChance: [EquipmentSlot: Double] = [:]

    /// Resistance percentages, already including the elemental and all-resistance blanket bonuses.
    public var resistances: [ResistanceKind: Double] = [:]
    public var maxResistances: [ResistanceKind: Double] = [:]

    /// Percentage damage bonus by type, as the game's own panel prints it: the blanket bonuses folded
    /// in, the attribute-driven scaling excluded.
    public var damageModifiers: [DamageType: Double] = [:]
    /// Flat damage the character adds to what it wields, by type.
    public var flatDamage: [DamageType: Double] = [:]
    /// The same, as the band the game rolls it in.
    ///
    /// The game writes a flat bonus as a minimum with no maximum and a range as both, and the two keys
    /// are summed apart, so a build whose flat bonuses outweigh its ranged ones has a maximum below its
    /// minimum. The floor is the honest figure of the two, so the top never reads under it.
    public var flatDamageRange: [DamageType: ClosedRange<Double>] = [:]

    /// The speeds as the game's own window prints them: the resulting percentage, not the bonus.
    public var attackSpeed: Double = 0
    /// How often the character swings, at that speed.
    public var attacksPerSecond: Double = 0
    public var castSpeed: Double = 0
    public var movementSpeed: Double = 0
    public var critDamage: Double = 0
    public var cooldownReduction: Double = 0

    /// Everything that fed the sheet, for the detail panels.
    public var contributions = StatBlock()
}

/// Computes a character sheet from a save, its gear and its skills.
///
/// Every formula here is read from the game's own database — `records/creatures/pc/playerlevels.dbr` for
/// attribute conversions and `records/game/combatformulas.dbr` for the ability equations — rather than
/// hardcoded, so the numbers stay right across patches.
public struct StatEngine {
    private struct Constants {
        public let baseOffensiveAbility: Double
        public let baseDefensiveAbility: Double
        public let attributeIncrement: Double
        public let lifePerPhysiquePoint: Double
        public let lifePerCunningPoint: Double
        public let lifePerSpiritPoint: Double
        public let energyPerSpiritPoint: Double
        public let armorAbsorption: Double
        /// Where every resistance caps before gear raises the cap, which the engine record states per
        /// difficulty and writes the same in all three.
        public let resistanceCap: Double
        /// What the engine lets a player's speeds run between, in percent.
        public let attackSpeedRange: ClosedRange<Double>
        public let castSpeedRange: ClosedRange<Double>
        public let runSpeedRange: ClosedRange<Double>
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

    public let database: GameDatabase

    public func sheet(
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
        let bonus = contributions.value("defensiveProtectionModifier")
        // What is left once the hit regions have taken their own: armour from belts, jewellery and
        // skills, which the game's help text says lands on every region.
        let shared =
            contributions.value("defensiveProtection")
            + contributions.value("defensiveBonusProtection")
            - bodyArmor.values.reduce(0, +)
        sheet.armorHitChance = hitChances()
        sheet.armorFromOtherSources = scaled(shared, percent: bonus)
        // Each region reads as the window prints it: the piece worn there, the shared armour, and the
        // percentage bonus over both.
        sheet.armorBySlot = Dictionary(uniqueKeysWithValues: sheet.armorHitChance.keys.map {
            ($0, scaled((bodyArmor[$0] ?? 0) + shared, percent: bonus))
        })
        sheet.armor = scaled(armorRating(bodyArmor: bodyArmor, global: shared), percent: bonus)
        // "Increases Armor Absorption by X%" scales the base share, and no share can exceed the whole hit.
        sheet.armorAbsorption = min(
            100,
            scaled(constants.armorAbsorption, percent: contributions.value("defensiveAbsorptionModifier"))
        )
        sheet.resistances = resistances(contributions)
        sheet.maxResistances = maxResistances(contributions, cap: constants.resistanceCap)
        sheet.damageModifiers = damageModifiers(contributions)
        sheet.flatDamage = Dictionary(uniqueKeysWithValues: DamageType.allCases.map {
            ($0, StatComposition.total(feeding: $0.minimumKey, in: contributions))
        })
        sheet.flatDamageRange = Dictionary(uniqueKeysWithValues: DamageType.allCases.map { type in
            let low = StatComposition.total(feeding: type.minimumKey, in: contributions)
            let high = StatComposition.total(feeding: type.maximumKey, in: contributions)
            return (type, low ... max(low, high))
        })
    }

    /// The game's Armor Rating: each hit region contributes in proportion to how often it is struck.
    ///
    /// Its own help text puts it plainly — "Bonuses on skills and on non-armor pieces are added to all
    /// armor slots" — so global armour lands in every region and survives the weighting intact.
    private func armorRating(bodyArmor: [EquipmentSlot: Double], global: Double) -> Double {
        let chances = hitChances()
        let total = chances.values.reduce(0, +)

        guard total > 0 else { return bodyArmor.values.reduce(0, +) + global }

        let weighted = chances.reduce(0) { $0 + $1.value * (bodyArmor[$1.key] ?? 0) }
        return weighted / total + global
    }

    /// How often each hit region is the one struck, normalised to percentages.
    private func hitChances() -> [EquipmentSlot: Double] {
        let formulas = database.record(Self.combatFormulasPath)
        var chances = [EquipmentSlot: Double]()

        for slot in EquipmentSlot.allCases {
            guard let key = slot.hitRegionChanceKey else { continue }

            chances[slot] = formulas?.number(key) ?? 0
        }

        let total = chances.values.reduce(0, +)
        guard total > 0 else { return chances }

        return chances.mapValues { $0 * 100 / total }
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
        CombatFormulas(database: database).ability(
            equationKey: equationKey,
            flat: flat,
            attribute: attribute,
            percent: percent,
            level: level
        )
    }

    private func resistances(_ stats: StatBlock) -> [ResistanceKind: Double] {
        Dictionary(uniqueKeysWithValues: ResistanceKind.allCases.map {
            ($0, StatComposition.total(feeding: $0.resistanceKey, in: stats))
        })
    }

    private func maxResistances(_ stats: StatBlock, cap: Double) -> [ResistanceKind: Double] {
        Dictionary(uniqueKeysWithValues: ResistanceKind.allCases.map {
            ($0, cap + StatComposition.total(feeding: $0.maximumKey, in: stats))
        })
    }

    /// Percentage damage bonuses as the character window reports them.
    ///
    /// The game states that this figure excludes the bonus attributes give — Cunning to physical and
    /// pierce, Spirit to the magical types — so that scaling is deliberately left out here too.
    private func damageModifiers(_ stats: StatBlock) -> [DamageType: Double] {
        Dictionary(
            uniqueKeysWithValues: DamageType.allCases.filter { $0 != .elemental }
                .map { ($0, StatComposition.total(feeding: $0.modifierKey, in: stats)) }
        )
    }

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
            resistanceCap: engine.map { max($0.number("playerDefenseCap"), 1) } ?? 80,
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
