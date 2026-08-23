// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

public extension ItemRoll {
    /// Which store a field belongs to, which decides how it is drawn and whether it takes the scale.
    public enum Store: Sendable {
        case char
        case flat
        case slowFlat
        case damage
        case leech
        case offensiveReflex
        case offensiveSlow
        case offensiveReduction
        case retaliationFlat
        case retaliationDuration
        case retaliationModifier
        case retaliationReflex
        case retaliationFear
        case defence
        case conversion
        case skill
    }

    public struct Draw: Sendable {
        public let store: Store
        public let field: String
        public let scales: Bool
    }

    /// Every rollable field, in the order the engine draws them.
    public static let drawOrder: [Draw] = {
        var order = [Draw]()
        order += characterFields.map { Draw(store: .char, field: $0, scales: false) }
        order += flatFields.map { Draw(store: .flat, field: $0, scales: true) }
        order += slowFlatFields.map { Draw(store: .slowFlat, field: $0, scales: true) }
        order += damageFields.map { Draw(store: .damage, field: $0, scales: !nonScaling.contains($0)) }
        order += leechFields.map { Draw(store: .leech, field: $0, scales: false) }
        order += offensiveReflexFields.map { Draw(store: .offensiveReflex, field: $0, scales: false) }
        order += offensiveSlowFields.map { Draw(store: .offensiveSlow, field: $0.field, scales: $0.scales) }
        order += offensiveReductionFields.map { Draw(store: .offensiveReduction, field: $0, scales: false) }
        order += retaliationFlatFields.map { Draw(store: .retaliationFlat, field: $0, scales: false) }
        order += retaliationDurationFields.map { Draw(store: .retaliationDuration, field: $0, scales: false) }
        order += [ Draw(store: .retaliationFear, field: "retaliationFearMin", scales: false) ]
        order += retaliationModifierFields.map { Draw(store: .retaliationModifier, field: $0, scales: false) }
        order += retaliationDurationPercentFields.map { Draw(store: .retaliationDuration, field: $0, scales: false) }
        order += retaliationReflexFields.map { Draw(store: .retaliationReflex, field: $0, scales: false) }
        order += defenceFields.map { Draw(store: .defence, field: $0, scales: false) }
        // The retaliation multiplier draws after the defence store rather than with its own.
        order += [ Draw(store: .retaliationModifier, field: "retaliationDamageMultModifier", scales: false) ]
        order += conversionFields.map { Draw(store: .conversion, field: $0, scales: false) }
        order += skillFields.map { Draw(store: .skill, field: $0, scales: false) }
        return order
    }()

    public static let characterFields = [
        "characterStrength", "characterDexterity", "characterIntelligence", "characterLife", "characterMana",
        "characterStrengthModifier", "characterDexterityModifier", "characterIntelligenceModifier",
        "characterLifeModifier", "characterManaModifier", "characterLifeMultModifier",
        "characterOffensiveAbility", "characterDefensiveAbility", "characterOffensiveAbilityModifier",
        "characterDefensiveAbilityModifier", "characterLifeRegen", "characterLifeRegenModifier",
        "characterManaRegenModifier", "characterConstitutionModifier", "characterHealIncreasePercent",
        "characterTotalSpeedModifier", "characterAttackSpeedModifier", "characterAttackSpeedMaxModifier",
        "characterSpellCastSpeedModifier", "characterSpellCastSpeedMaxModifier", "characterRunSpeedModifier",
        "characterRunSpeedMaxModifier", "characterDefensiveBlockRecoveryReduction",
        "characterEnergyAbsorptionPercent", "characterDodgePercent", "characterDeflectProjectile",
        "characterManaLimitReserve", "characterManaLimitReserveModifier",
    ]

    public static let flatFields = [
        "offensivePhysical", "offensiveBonusPhysical", "offensivePierce", "offensiveFire", "offensiveCold",
        "offensiveLightning", "offensivePoison", "offensiveLife", "offensiveAether", "offensiveChaos",
        "offensiveElemental",
    ]

    public static let slowFlatFields = [
        "offensiveSlowPhysical", "offensiveSlowBleeding", "offensiveSlowFire", "offensiveSlowCold",
        "offensiveSlowLightning", "offensiveSlowPoison", "offensiveSlowLife", "offensiveSlowAether",
        "offensiveSlowChaos", "offensiveSlowLifeLeach", "offensiveSlowManaLeach",
    ]

    public static let offensiveReflexFields = [
        "offensiveStun", "offensiveKnockdown", "offensiveSleep", "offensiveFreeze", "offensivePetrify",
    ]

    /// A speed slow takes the item's scale; an ability reduction does not.
    public static let offensiveSlowFields: [(field: String, scales: Bool)] = [
        ("offensiveSlowTotalSpeed", true), ("offensiveSlowAttackSpeed", true),
        ("offensiveSlowSpellCastSpeed", true), ("offensiveSlowRunSpeed", true),
        ("offensiveSlowOffensiveAbility", false), ("offensiveSlowDefensiveAbility", false),
    ]

    public static let damageFields = [
        "offensiveTotalDamageModifier", "offensiveCritDamageModifier", "offensivePhysicalModifier",
        "offensivePierceModifier", "offensiveFireModifier", "offensiveColdModifier",
        "offensiveLightningModifier", "offensivePoisonModifier", "offensiveLifeModifier",
        "offensiveAetherModifier", "offensiveChaosModifier", "offensiveElementalModifier",
        "offensiveSlowPhysicalModifier", "offensiveSlowPhysicalDurationModifier",
        "offensiveSlowBleedingModifier", "offensiveSlowBleedingDurationModifier",
        "offensiveSlowFireModifier", "offensiveSlowFireDurationModifier",
        "offensiveSlowColdModifier", "offensiveSlowColdDurationModifier",
        "offensiveSlowLightningModifier", "offensiveSlowLightningDurationModifier",
        "offensiveSlowPoisonModifier", "offensiveSlowPoisonDurationModifier",
        "offensiveSlowLifeModifier", "offensiveSlowLifeDurationModifier",
        "offensiveSlowAetherModifier", "offensiveSlowChaosModifier",
    ]

    /// A damage modifier carrying a chance becomes its own proc line rather than joining the total.
    public static let chanceSplitFields: Set<String> = [
        "offensivePhysicalModifier", "offensivePierceModifier", "offensiveFireModifier",
        "offensiveColdModifier", "offensiveLightningModifier", "offensivePoisonModifier",
        "offensiveLifeModifier", "offensiveAetherModifier", "offensiveChaosModifier",
        "offensiveElementalModifier",
    ]

    public static let leechFields = [ "offensiveLifeLeech" ]

    public static let offensiveReductionFields = [
        "offensivePhysicalReductionPercent", "offensiveElementalReductionPercent",
        "offensiveTotalDamageReductionPercent", "offensiveTotalDamageReductionAbsolute",
        "offensiveTotalResistanceReductionPercent", "offensiveTotalResistanceReductionAbsolute",
        "offensivePhysicalResistanceReductionPercent", "offensivePhysicalResistanceReductionAbsolute",
        "offensiveElementalResistanceReductionPercent", "offensiveElementalResistanceReductionAbsolute",
    ]

    public static let retaliationFlatFields = [
        "retaliationPhysical", "retaliationPierce", "retaliationFire", "retaliationCold",
        "retaliationLightning", "retaliationPoison", "retaliationLife", "retaliationAether",
        "retaliationChaos", "retaliationElemental",
    ]

    public static let retaliationDurationFields = [
        "retaliationSlowPhysical", "retaliationSlowPierce", "retaliationSlowFire", "retaliationSlowCold",
        "retaliationSlowLightning", "retaliationSlowPoison", "retaliationSlowLife", "retaliationSlowAether",
        "retaliationSlowChaos", "retaliationSlowBleeding",
    ]

    public static let retaliationDurationPercentFields = [ "retaliationSlowAttackSpeed", "retaliationSlowRunSpeed" ]

    public static let retaliationModifierFields = [
        "retaliationTotalDamageModifier", "retaliationPhysicalModifier", "retaliationPierceModifier",
        "retaliationFireModifier", "retaliationColdModifier", "retaliationLightningModifier",
        "retaliationPoisonModifier", "retaliationLifeModifier", "retaliationAetherModifier",
        "retaliationChaosModifier", "retaliationElementalModifier",
    ]

    public static let retaliationReflexFields = [ "retaliationStun", "retaliationFreeze", "retaliationConfusion" ]

    public static let defenceFields = [
        "defensiveBlockModifier", "defensiveBlockAmountModifier", "defensiveProtectionModifier",
        "defensiveAbsorptionModifier",
        "defensivePhysical", "defensivePierce", "defensiveFire", "defensiveCold", "defensiveLightning",
        "defensivePoison", "defensiveLife", "defensiveAether", "defensiveChaos",
        "defensiveElementalResistance", "defensiveBleeding",
        "defensiveSlowLifeLeach", "defensiveSlowManaLeach", "defensiveManaBurn", "defensiveAllResistance",
        "defensivePhysicalModifier", "defensivePierceModifier", "defensiveFireModifier",
        "defensiveColdModifier", "defensiveLightningModifier", "defensivePoisonModifier",
        "defensiveLifeModifier", "defensiveAetherModifier", "defensiveChaosModifier",
        "defensiveElementalModifier", "defensiveBleedingModifier",
        "defensiveSlowLifeLeachModifier", "defensiveSlowManaLeachModifier",
        "defensivePhysicalDuration", "defensiveFireDuration", "defensiveColdDuration",
        "defensiveLightningDuration", "defensivePoisonDuration", "defensiveLifeDuration",
        "defensiveAetherDuration", "defensiveChaosDuration", "defensiveBleedingDuration",
        "defensiveSlowLifeLeachDuration", "defensiveSlowManaLeachDuration",
        "defensivePhysicalDurationModifier", "defensiveFireDurationModifier", "defensiveColdDurationModifier",
        "defensiveLightningDurationModifier", "defensivePoisonDurationModifier",
        "defensiveLifeDurationModifier", "defensiveAetherDurationModifier", "defensiveChaosDurationModifier",
        "defensiveBleedingDurationModifier", "defensiveSlowLifeLeachDurationModifier",
        "defensiveSlowManaLeachDurationModifier",
        "defensiveDisruption", "defensiveStun", "defensiveStunModifier", "defensiveFreeze",
        "defensiveTrap", "defensivePetrify", "defensiveSleep", "defensiveSleepModifier",
        "defensiveKnockdown", "defensiveKnockdownModifier", "defensiveTaunt", "defensiveFear",
        "defensiveConfusion", "defensiveConvert", "defensiveTotalSpeedResistance", "defensiveCrowdControl",
        "defensiveReflect", "defensiveReflectModifier", "defensivePercentCurrentLife",
        "defensivePercentReflectionResistance",
    ]

    public static let conversionFields = [ "conversionPercentage", "conversionPercentage2" ]

    public static let skillFields = [
        "skillCooldownReduction", "skillManaCostReduction", "skillComboChargeSpendReduction",
        "skillProjectileSpeedModifier", "skillCooldownReductionModifier", "skillManaCostReductionModifier",
    ]

    /// Only these skill fields draw early, and only when an affix carries them.
    public static let earlySkillFields: Set<String> = [ "skillCooldownReduction", "skillManaCostReduction" ]

    /// Crit and total damage never take the item's scale.
    public static let nonScaling: Set<String> = [ "offensiveCritDamageModifier", "offensiveTotalDamageModifier" ]

    /// Shield block figures are read straight from the record: no roll, no draw.
    public static let fixedBlockFields: Set<String> = [
        "defensiveBlock", "defensiveBlockChance", "blockAbsorption", "blockRecoveryTime",
    ]

    public static let fixedFields: Set<String> = [
        "characterBaseAttackSpeed", "characterManaRegen", "characterConstitution", "characterAttackSpeed",
        "characterSpellCastSpeed", "characterRunSpeed", "characterIncreasedExperience",
        "characterIncreasedGold", "characterLightRadius", "characterGlobalReqReduction",
        "characterLevelReqReduction", "characterModifierPoints", "defensiveProtection",
    ]

    public static let statPrefixes = [
        "offensive", "defensive", "retaliation", "character", "skill", "conversion", "blockAbsorption",
        "blockRecovery",
    ]

    /// True for a field the game reads as written, which is also a field that consumes no draw.
    public static func isFixed(_ field: String) -> Bool {
        if fixedFields.contains(field) || fixedBlockFields.contains(field) { return true }
        if field.hasPrefix("character"), field.hasSuffix("ReqReduction") { return true }
        if field.hasPrefix("offensiveBase"), field.hasSuffix("Min") || field.hasSuffix("Max") { return true }
        if field.hasPrefix("offensiveSlow"), field.hasSuffix("DurationMin") { return true }
        if field.hasPrefix("offensive"), field.hasSuffix("RatioMin") { return true }
        if field == "offensiveGlobalChance" || field == "retaliationGlobalChance" { return true }
        if field.hasPrefix("offensive") || field.hasPrefix("retaliation") {
            if field.hasSuffix("Global") { return true }
        }
        if field.hasSuffix("Chance"), !field.hasSuffix("GlobalChance") {
            return field.hasPrefix("offensive") || field.hasPrefix("retaliation") || field.hasPrefix("skill")
        }
        return false
    }
}
