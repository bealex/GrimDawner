// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// What a skill record's class says the skill is, for the thousands that carry no name.
///
/// A player's skills are all named; a monster's mostly are not — 442 of them have a name and some 3,500
/// do not, and the record's class is the only thing that says what one does. The game's own tooltip does
/// the same thing, which is why a Ravager's swipe reads as an attack rather than as `ravager_frenzyswipes`.
public enum SkillKind {
    /// Longest match first, so `Skill_AttackProjectileFan` never reads as a plain projectile attack.
    private static let phrases: [(prefix: String, phrase: String)] = [
        ("Skill_AttackProjectileAreaEffect", "Projectile that bursts"),
        ("Skill_AttackProjectileOrbiting", "Orbiting projectiles"),
        ("Skill_AttackProjectileBurst", "Burst of projectiles"),
        ("Skill_AttackProjectileRing", "Ring of projectiles"),
        ("Skill_AttackProjectileDrop", "Falling projectiles"),
        ("Skill_AttackProjectileFan", "Fan of projectiles"),
        ("Skill_AttackProjectile", "Projectile attack"),
        ("Skill_AttackWeaponCharge", "Charged weapon attack"),
        ("Skill_AttackWeaponBlink", "Blink attack"),
        ("Skill_AttackWeapon", "Weapon attack"),
        ("Skill_WPAttack", "Weapon attack"),
        ("Skill_WeaponPool", "Weapon attack"),
        ("Skill_AttackBuffRadius", "Attack that buffs nearby"),
        ("Skill_AttackBuff", "Attack that buffs"),
        ("Skill_AttackRadius", "Area attack"),
        ("Skill_AttackWave", "Wave attack"),
        ("Skill_AttackPattern", "Patterned attack"),
        ("Skill_AttackChain", "Chained attack"),
        ("Skill_Attack", "Attack"),
        ("Skill_BuffRadiusToggled", "Aura"),
        ("Skill_BuffAttackRadius", "Aura that attacks"),
        ("Skill_BuffOther", "Buffs its allies"),
        ("Skill_BuffSelf", "Buffs itself"),
        ("Skill_Buff", "Buff"),
        ("SkillBuff_Passive", "Passive bonus"),
        ("SkillBuff", "Buff"),
        ("Skill_TargetedSpawnPet", "Summons"),
        ("Skill_SpawnPetMonster", "Summons"),
        ("Skill_SpawnPet", "Summons"),
        ("Skill_MonsterGenerator", "Summons"),
        ("Skill_OnDeathSpawnActor", "Leaves something behind"),
        ("Skill_OnDeath", "Fires as it dies"),
        ("Skill_PassiveOnLife", "Passive bonus, triggered at low health"),
        ("Skill_Passive", "Passive bonus"),
        ("Skill_Utility", "Utility"),
        ("Skill_Modifier", "Modifier"),
    ]

    /// What the record's class says this is, or nothing where the class means nothing to a reader.
    public static func phrase(forClass recordClass: String) -> String? {
        phrases.first { recordClass.hasPrefix($0.prefix) }?.phrase
    }
}
