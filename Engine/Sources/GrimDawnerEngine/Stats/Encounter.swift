// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// What one blow is worth: how often it lands, how hard it hits, and what stops it.
public struct Blow: Sendable {
    /// One damage type's share of the blow, before and after whatever the target has against it.
    public struct Share: Sendable, Identifiable {
        public let type: DamageType
        /// What the attacker throws, before the target's own defences.
        public let thrown: Double
        /// What is left after resistance, and after armour for the physical share.
        public let landed: Double
        /// The resistance that ate the difference, as a percentage.
        public let resisted: Double

        public var id: String { type.rawValue }
        public var stopped: Double { thrown - landed }
    }

    /// The game's own `probabilityToHitEquation` for this pairing, before it is read as a chance.
    public let probabilityToHit: Double
    public let hitChance: Double
    /// The damage bands this pairing's hit figure reaches. `combatformulas.dbr` states six of them —
    /// a threshold and what a blow landing past it is multiplied by — and the highest one reached is
    /// the hardest this pairing can hit. How often each is rolled is the game's own business and is not
    /// guessed at here.
    public let bands: [(threshold: Double, multiplier: Double)]
    /// What the character's own critical damage bonus adds on top of a band.
    public let critDamage: Double
    public let shares: [Share]

    public var thrown: Double { shares.reduce(0) { $0 + $1.thrown } }
    public var landed: Double { shares.reduce(0) { $0 + $1.landed } }

    /// The most a blow is multiplied by: the best band reached, and the character's own crit bonus.
    public var bestMultiplier: Double { (bands.last?.multiplier ?? 1) * (1 + critDamage / 100) }
    /// What a blow lands at its best.
    public var best: Double { landed * bestMultiplier }
    /// What the blow averages once misses are counted in, at the plain multiplier and not the best.
    public var expected: Double { landed * hitChance / 100 }
}

/// The two of them fighting: what the character does to the monster, and the monster to the character.
///
/// Everything here is the game's own arithmetic out of `records/game/combatformulas.dbr` — the
/// probability-to-hit equation, the bands it is read in, and the two armour equations. Nothing is
/// transcribed: the record is evaluated as written, so a patch that changes the maths changes this.
public struct Encounter: Sendable {
    public let attacking: Blow
    public let defending: Blow
    /// What the character's blows come to over a second, at the rate the sheet says it swings.
    public let attackRate: Double

    public var damagePerSecond: Double { attacking.expected * attackRate }
}

public struct EncounterEngine {
    public init(database: GameDatabase) {
        self.database = database
        formulas = database.record(Self.path)
    }

    public let database: GameDatabase
    private let formulas: ArzRecord?

    private static let path = "records/game/combatformulas.dbr"

    /// Reads one fight: the character swinging at the monster, and the monster swinging back.
    ///
    /// `skill` is what the character is swinging with. Given none, that is the weapon damage the sheet
    /// carries — the floor every build stands on. Given a skill, it is that skill's own damage at the
    /// rank the character has it, raised by the same bonuses the sheet raises everything by.
    public func encounter(
        of sheet: CharacterSheet,
        against monster: ResolvedMonster,
        using skill: ResolvedSkill? = nil
    ) -> Encounter {
        let attacking = blow(
            flat: skill.map { Self.damage(of: $0) } ?? sheet.flatDamage,
            modifiers: sheet.damageModifiers,
            offensive: sheet.offensiveAbility,
            against: monster.defensiveAbility,
            resistances: monster.resistances,
            armor: monster.armor,
            absorption: absorption(of: monster),
            critDamage: sheet.critDamage
        )
        let defending = blow(
            flat: monsterDamage(of: monster),
            modifiers: monsterModifiers(of: monster),
            offensive: monster.offensiveAbility,
            against: sheet.defensiveAbility,
            resistances: sheet.resistances,
            armor: sheet.armor,
            absorption: sheet.armorAbsorption,
            critDamage: 0
        )
        return Encounter(
            attacking: attacking,
            defending: defending,
            attackRate: sheet.attacksPerSecond > 0 ? sheet.attacksPerSecond : 1
        )
    }

    /// One side swinging at the other.
    private func blow(
        flat: [DamageType: Double],
        modifiers: [DamageType: Double],
        offensive: Double,
        against defensive: Double,
        resistances: [ResistanceKind: Double],
        armor: Double,
        absorption: Double,
        critDamage: Double
    ) -> Blow {
        let hit = probabilityToHit(offensive: offensive, defensive: defensive)
        let reached = critBands().filter { hit >= $0.threshold }

        var shares = [Blow.Share]()
        for type in DamageType.allCases where type != .elemental {
            let thrown = (flat[type] ?? 0) * (1 + (modifiers[type] ?? 0) / 100)
            guard thrown > 0 else { continue }

            let resisted = resistances[ResistanceKind(damage: type) ?? .physical] ?? 0
            var landed = thrown * (1 - min(resisted, 100) / 100)
            if type == .physical { landed = throughArmor(landed, armor: armor, absorption: absorption) }

            shares.append(Blow.Share(type: type, thrown: thrown, landed: max(landed, 0), resisted: resisted))
        }

        return Blow(
            probabilityToHit: hit,
            hitChance: min(100, max(hit, number("pthMinimum", or: 55))),
            bands: reached,
            critDamage: critDamage,
            shares: shares.sorted { $0.landed > $1.landed }
        )
    }

    /// The game's own hit equation, evaluated as the record writes it.
    public func probabilityToHit(offensive: Double, defensive: Double) -> Double {
        guard
            let source = formulas?.text("probabilityToHitEquation"),
            !source.isEmpty,
            let equation = try? Equation(source),
            let value = try? equation.value([
                "offensiveAbilityDV": offensive,
                "defensiveAbilityDV": max(defensive, 1),
            ])
        else { return 0 }

        return value
    }

    /// The bands a landed blow is multiplied in, as the record numbers them.
    public func critBands() -> [(threshold: Double, multiplier: Double)] {
        (1 ... 6).compactMap { index in
            let threshold = number("pthThreshold\(index)", or: 0)
            let multiplier = number("pthDamageModifier\(index)", or: 0)
            guard threshold > 0, multiplier > 0 else { return nil }

            return (threshold, multiplier)
        }
    }

    /// The two armour equations the record carries: one for a blow the armour swallows whole, one for a
    /// blow bigger than the armour, where only the armour's own worth is absorbed.
    public func throughArmor(_ damage: Double, armor: Double, absorption: Double) -> Double {
        let variables: [String: Double] = [
            "physicalDamageDV": damage,
            "sumProtectionDV": armor,
            "sumAbsorptionDV": absorption / 100,
        ]
        let key = damage > armor ? "physicalDamageDefenseEquationDGP" : "physcialDamageDefenseEquationDLEP"
        guard
            let source = formulas?.text(key),
            !source.isEmpty,
            let equation = try? Equation(source),
            let value = try? equation.value(variables)
        else { return damage }

        return value
    }

    /// What a skill throws before anything raises it: the flat damage its own record carries at the
    /// rank the character has it. What a skill takes from the weapon it is swung with is not modelled,
    /// so a weapon-damage skill reads low here.
    public static func damage(of skill: ResolvedSkill) -> [DamageType: Double] {
        var damage = [DamageType: Double]()
        for type in DamageType.allCases {
            let low = skill.stats.value(type.minimumKey)
            let high = skill.stats.value(type.maximumKey)
            let average = high > low ? (low + high) / 2 : low
            if average > 0 { damage[type] = average }
        }
        return damage
    }

    /// What a monster swings for, read off its own record's damage stats.
    private func monsterDamage(of monster: ResolvedMonster) -> [DamageType: Double] {
        var damage = [DamageType: Double]()
        for type in DamageType.allCases {
            let low = monster.stats.value(type.minimumKey)
            let high = monster.stats.value(type.maximumKey)
            let average = high > low ? (low + high) / 2 : low
            if average > 0 { damage[type] = average }
        }
        return damage
    }

    private func monsterModifiers(of monster: ResolvedMonster) -> [DamageType: Double] {
        Dictionary(uniqueKeysWithValues: DamageType.allCases.map {
            ($0, StatComposition.total(feeding: $0.modifierKey, in: monster.stats))
        })
    }

    /// How much of a physical blow a monster's armour swallows: the share the engine gives everything
    /// that wears armour, raised by whatever the monster's own record adds to it.
    private func absorption(of monster: ResolvedMonster) -> Double {
        let base = database.record("records/game/gameengine.dbr")?.number("armorDefensiveAbsorption") ?? 70
        return min(100, base * (1 + monster.stats.value("defensiveAbsorptionModifier") / 100))
    }

    private func number(_ key: String, or fallback: Double) -> Double {
        guard let value = formulas?.number(key), value != 0 else { return fallback }

        return value
    }
}
