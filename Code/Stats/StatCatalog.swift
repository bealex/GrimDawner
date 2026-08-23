// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// Where a stat belongs on the character sheet.
enum StatGroup: Int, CaseIterable, Sendable {
    case attributes
    case defence
    case resistances
    case controlResistances
    case offence
    case damage
    case damageOverTime
    case retaliation
    case utility

    var title: String {
        switch self {
            case .attributes: "Attributes"
            case .defence: "Defence"
            case .resistances: "Resistances"
            case .controlResistances: "Control Resistances"
            case .offence: "Offence"
            case .damage: "Damage"
            case .damageOverTime: "Damage over Time"
            case .retaliation: "Retaliation"
            case .utility: "Utility"
        }
    }
}

/// How a stat's numbers read.
enum StatUnit: Sendable {
    case flat
    case percent
    case perSecond
    case seconds
    case level

    func format(_ value: Double, signed: Bool = true) -> String {
        let rounded = (value * 100).rounded() / 100
        let magnitude = abs(rounded)
        let decimals = magnitude < 10 && rounded != rounded.rounded() ? 1 : 0
        let sign = signed && rounded > 0 ? "+" : ""
        let number = String(format: "%\(sign).\(decimals)f", rounded)

        return switch self {
            case .flat: number
            case .percent: number + "%"
            case .perSecond: number + "/s"
            case .seconds: number + "s"
            case .level: number
        }
    }
}

/// One stat the app knows how to read out of a `.dbr` record and show.
struct StatDefinition: Sendable {
    let key: String
    let title: String
    let group: StatGroup
    let unit: StatUnit
    /// Sort weight inside the group; equal weights fall back to the catalogue's declaration order.
    let order: Int

    init(_ key: String, _ title: String, _ group: StatGroup, _ unit: StatUnit = .flat, order: Int = 0) {
        self.key = key
        self.title = title
        self.group = group
        self.unit = unit
        self.order = order
    }
}

/// Every `.dbr` stat field the app reads, in the order it presents them.
///
/// The catalogue is deliberately explicit rather than derived from the record: a `.dbr` carries hundreds of
/// engine-internal fields, and only these carry meaning on a character sheet.
enum StatCatalog {
    static let everyStat: [StatDefinition] =
        attributes + defence + resistances
        + controlResistances + offence + damage + damageOverTime + retaliation + utility

    private static let byKey: [String: StatDefinition] = Dictionary(
        everyStat.map { ($0.key, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    static func definition(for key: String) -> StatDefinition? { byKey[key] }

    // MARK: - Groups

    private static let attributes: [StatDefinition] = [
        StatDefinition("characterStrength", "Physique", .attributes, .flat, order: 0),
        StatDefinition("characterStrengthModifier", "Physique", .attributes, .percent, order: 1),
        StatDefinition("characterDexterity", "Cunning", .attributes, .flat, order: 2),
        StatDefinition("characterDexterityModifier", "Cunning", .attributes, .percent, order: 3),
        StatDefinition("characterIntelligence", "Spirit", .attributes, .flat, order: 4),
        StatDefinition("characterIntelligenceModifier", "Spirit", .attributes, .percent, order: 5),
    ]

    private static let defence: [StatDefinition] = [
        StatDefinition("characterLife", "Health", .defence, .flat, order: 0),
        StatDefinition("characterLifeModifier", "Health", .defence, .percent, order: 1),
        StatDefinition("characterLifeRegen", "Health Regenerated", .defence, .perSecond, order: 2),
        StatDefinition("characterLifeRegenModifier", "Health Regeneration", .defence, .percent, order: 3),
        StatDefinition("characterMana", "Energy", .defence, .flat, order: 4),
        StatDefinition("characterManaModifier", "Energy", .defence, .percent, order: 5),
        StatDefinition("characterManaRegen", "Energy Regenerated", .defence, .perSecond, order: 6),
        StatDefinition("characterManaRegenModifier", "Energy Regeneration", .defence, .percent, order: 7),
        StatDefinition("defensiveProtection", "Armor", .defence, .flat, order: 8),
        StatDefinition("defensiveBonusProtection", "Armor", .defence, .flat, order: 8),
        StatDefinition("defensiveProtectionModifier", "Armor", .defence, .percent, order: 9),
        StatDefinition("defensiveAbsorptionModifier", "Armor Absorption", .defence, .percent, order: 10),
        StatDefinition("damageAbsorptionPercent", "Damage Absorption", .defence, .percent, order: 11),
        StatDefinition("characterDefensiveAbility", "Defensive Ability", .defence, .flat, order: 11),
        StatDefinition("characterDefensiveAbilityModifier", "Defensive Ability", .defence, .percent, order: 12),
        StatDefinition("defensiveBlock", "Shield Block", .defence, .flat, order: 13),
        StatDefinition("defensiveBlockChance", "Shield Block Chance", .defence, .percent, order: 14),
        StatDefinition("defensiveBlockAmountModifier", "Shield Damage Blocked", .defence, .percent, order: 15),
        StatDefinition("blockRecoveryTime", "Block Recovery", .defence, .seconds, order: 16),
        StatDefinition("characterDodgePercent", "Chance to Avoid Melee Attacks", .defence, .percent, order: 17),
        StatDefinition("characterDeflectProjectile", "Chance to Avoid Projectiles", .defence, .percent, order: 18),
        StatDefinition("defensivePhysical", "Physical Resistance", .defence, .percent, order: 19),
        StatDefinition("characterEnergyAbsorptionPercent", "Energy Absorption", .defence, .percent, order: 20),
        StatDefinition("characterHealIncreasePercent", "Healing Effects Increased", .defence, .percent, order: 21),
        StatDefinition("characterConstitutionModifier", "Constitution Bonus", .defence, .percent, order: 22),
    ]

    private static let resistances: [StatDefinition] = [
        StatDefinition("defensiveFire", "Fire Resistance", .resistances, .percent, order: 0),
        StatDefinition("defensiveCold", "Cold Resistance", .resistances, .percent, order: 1),
        StatDefinition("defensiveLightning", "Lightning Resistance", .resistances, .percent, order: 2),
        StatDefinition("defensiveElementalResistance", "Elemental Resistance", .resistances, .percent, order: 3),
        StatDefinition("defensivePoison", "Poison & Acid Resistance", .resistances, .percent, order: 4),
        StatDefinition("defensiveLife", "Vitality Resistance", .resistances, .percent, order: 5),
        StatDefinition("defensiveAether", "Aether Resistance", .resistances, .percent, order: 6),
        StatDefinition("defensiveChaos", "Chaos Resistance", .resistances, .percent, order: 7),
        StatDefinition("defensivePierce", "Pierce Resistance", .resistances, .percent, order: 8),
        StatDefinition("defensiveBleeding", "Bleeding Resistance", .resistances, .percent, order: 9),
        StatDefinition("defensiveAllResistance", "All Resistances", .resistances, .percent, order: 10),
        StatDefinition("defensiveFireMaxResist", "Max Fire Resistance", .resistances, .percent, order: 11),
        StatDefinition("defensiveColdMaxResist", "Max Cold Resistance", .resistances, .percent, order: 12),
        StatDefinition("defensiveLightningMaxResist", "Max Lightning Resistance", .resistances, .percent, order: 13),
        StatDefinition("defensivePoisonMaxResist", "Max Poison Resistance", .resistances, .percent, order: 14),
        StatDefinition("defensiveLifeMaxResist", "Max Vitality Resistance", .resistances, .percent, order: 15),
        StatDefinition("defensiveAetherMaxResist", "Max Aether Resistance", .resistances, .percent, order: 16),
        StatDefinition("defensiveChaosMaxResist", "Max Chaos Resistance", .resistances, .percent, order: 17),
        StatDefinition("defensivePierceMaxResist", "Max Pierce Resistance", .resistances, .percent, order: 18),
        StatDefinition("defensiveBleedingMaxResist", "Max Bleeding Resistance", .resistances, .percent, order: 19),
        StatDefinition("defensiveAllMaxResist", "All Max Resistances", .resistances, .percent, order: 20),
    ]

    private static let controlResistances: [StatDefinition] = [
        StatDefinition("defensiveStun", "Stun Resistance", .controlResistances, .percent, order: 0),
        StatDefinition("defensiveFreeze", "Freeze Resistance", .controlResistances, .percent, order: 1),
        StatDefinition("defensivePetrify", "Petrify Resistance", .controlResistances, .percent, order: 2),
        StatDefinition("defensiveSleep", "Sleep Resistance", .controlResistances, .percent, order: 3),
        StatDefinition("defensiveTrap", "Trap Resistance", .controlResistances, .percent, order: 4),
        StatDefinition("defensiveKnockdown", "Knockdown Resistance", .controlResistances, .percent, order: 5),
        StatDefinition("defensiveDisruption", "Skill Disruption Resistance", .controlResistances, .percent, order: 6),
        StatDefinition("defensiveTotalSpeedResistance", "Slow Resistance", .controlResistances, .percent, order: 7),
        StatDefinition("defensiveSlowLifeLeach", "Life Leech Resistance", .controlResistances, .percent, order: 8),
        StatDefinition("defensiveSlowManaLeach", "Energy Leech Resistance", .controlResistances, .percent, order: 9),
        StatDefinition(
            "defensivePercentReflectionResistance",
            "Reflected Damage Reduction",
            .controlResistances,
            .percent,
            order: 10
        ),
    ]

    private static let offence: [StatDefinition] = [
        StatDefinition("characterOffensiveAbility", "Offensive Ability", .offence, .flat, order: 0),
        StatDefinition("characterOffensiveAbilityModifier", "Offensive Ability", .offence, .percent, order: 1),
        StatDefinition("offensiveCritDamageModifier", "Crit Damage", .offence, .percent, order: 2),
        StatDefinition("offensiveTotalDamageModifier", "All Damage", .offence, .percent, order: 3),
        StatDefinition("characterAttackSpeedModifier", "Attack Speed", .offence, .percent, order: 4),
        StatDefinition("characterSpellCastSpeedModifier", "Casting Speed", .offence, .percent, order: 5),
        StatDefinition("characterTotalSpeedModifier", "Total Speed", .offence, .percent, order: 6),
        StatDefinition("characterRunSpeedModifier", "Movement Speed", .offence, .percent, order: 7),
        StatDefinition("weaponDamagePct", "Weapon Damage", .offence, .percent, order: 8),
        StatDefinition("offensiveLifeLeechMin", "Life Leech", .offence, .percent, order: 9),
        StatDefinition("offensivePierceRatioMin", "Converted to Pierce Damage", .offence, .percent, order: 10),
        StatDefinition("racialBonusPercentDamage", "Damage to Race", .offence, .percent, order: 11),
        StatDefinition("racialBonusPercentDefense", "Reduced Damage from Race", .offence, .percent, order: 12),
    ]

    private static let damage: [StatDefinition] = perDamageType { index, type in
        [
            StatDefinition(type.minimumKey, "\(type.title) Damage", .damage, .flat, order: index * 3),
            StatDefinition(type.maximumKey, "\(type.title) Damage", .damage, .flat, order: index * 3),
            StatDefinition(type.modifierKey, "\(type.title) Damage", .damage, .percent, order: index * 3 + 1),
            StatDefinition(type.baseMinimumKey, "Base \(type.title) Damage", .damage, .flat, order: index * 3 + 2),
            StatDefinition(type.baseMaximumKey, "Base \(type.title) Damage", .damage, .flat, order: index * 3 + 2),
        ]
    }

    private static let damageOverTime: [StatDefinition] = perDamageType(DamageType.overTimeCases) { index, type in
        let title = type.overTimeTitle
        return [
            StatDefinition(type.overTimeMinimumKey, title, .damageOverTime, .flat, order: index * 3),
            StatDefinition(type.overTimeModifierKey, title, .damageOverTime, .percent, order: index * 3 + 1),
            StatDefinition(
                type.overTimeDurationModifierKey,
                "\(title) Duration",
                .damageOverTime,
                .percent,
                order: index * 3 + 2
            ),
        ]
    }

    private static let retaliation: [StatDefinition] =
        perDamageType { index, type in
            let title = "\(type.title) Retaliation"
            return [
                StatDefinition(type.retaliationMinimumKey, title, .retaliation, .flat, order: index * 2),
                StatDefinition(type.retaliationModifierKey, title, .retaliation, .percent, order: index * 2 + 1),
            ]
        } + [
            StatDefinition("retaliationTotalDamageModifier", "Total Retaliation Damage", .retaliation, .percent)
        ]

    private static let utility: [StatDefinition] = [
        StatDefinition("skillCooldownReduction", "Skill Cooldown Reduction", .utility, .percent, order: 0),
        StatDefinition("skillManaCostReduction", "Skill Energy Cost", .utility, .percent, order: 1),
        StatDefinition("characterLightRadius", "Light Radius", .utility, .flat, order: 2),
        StatDefinition("characterIncreasedExperience", "Experience Gained", .utility, .percent, order: 3),
        StatDefinition("characterGlobalReqReduction", "Requirements", .utility, .percent, order: 4),
        StatDefinition(
            "characterArmorStrengthReqReduction",
            "Armor Physique Requirement",
            .utility,
            .percent,
            order: 5
        ),
        StatDefinition(
            "offensiveTotalResistanceReductionAbsoluteMin",
            "Reduced Target's Resistances",
            .utility,
            .flat,
            order: 6
        ),
        StatDefinition(
            "offensiveTotalResistanceReductionPercentMin",
            "Reduced Target's Resistances",
            .utility,
            .percent,
            order: 7
        ),
        StatDefinition(
            "offensiveTotalDamageReductionPercentMin",
            "Reduced Target's Damage",
            .utility,
            .percent,
            order: 8
        ),
    ]

    /// Builds one definition set per damage type, numbering them so each type keeps its place in the group.
    private static func perDamageType(
        _ types: [DamageType] = DamageType.allCases,
        _ definitions: (Int, DamageType) -> [StatDefinition]
    ) -> [StatDefinition] {
        types.enumerated().flatMap { definitions($0.offset, $0.element) }
    }
}
