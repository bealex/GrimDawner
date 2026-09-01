// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// What one blow is worth: how often it lands, how hard it hits, and what stops it.
public struct Blow: Sendable {
    /// One damage type's share of the blow, before and after whatever the target has against it.
    ///
    /// Every figure is a range: the game rolls each type between the minimum and the maximum its
    /// sources come to, and a blow is the whole range rolled at once.
    public struct Share: Sendable, Identifiable {
        public let type: DamageType
        /// What the attacker throws, before the target's own defences.
        public let thrown: ClosedRange<Double>
        /// What is left after resistance, and after armour for the physical share.
        public let landed: ClosedRange<Double>
        /// The resistance that ate the difference, as a percentage, after whatever the attacker took
        /// off it.
        public let resisted: Double
        /// What the target's resistance was before the attacker's reductions, where they differ.
        public let resistedBefore: Double
        /// What the target actually holds, cap or no cap. Everything past the cap is overcap: it stops
        /// nothing by itself and is spent absorbing reduction before the cap starts to give.
        public let held: Double
        /// The same once the attacker's reductions have eaten into it, still uncapped.
        public let heldAfterReduction: Double
        /// The most of it the target gets to keep.
        public let cap: Double

        /// The buffer the target started with.
        public var overcap: Double { max(held - cap, 0) }
        /// What is left of that buffer. Once this reaches nothing, further reduction costs real
        /// resistance and what lands starts to climb.
        public var overcapLeft: Double { max(heldAfterReduction - cap, 0) }

        public var id: String { type.rawValue }
        public var average: Double { (landed.lowerBound + landed.upperBound) / 2 }
        public var stopped: Double {
            (thrown.lowerBound + thrown.upperBound) / 2 - average
        }
    }

    /// One of the game's damage bands: what a blow landing in it is multiplied by, and how often this
    /// pairing lands there.
    public struct Band: Sendable, Identifiable {
        public let threshold: Double
        public let multiplier: Double
        /// The share of landed blows that fall in this band, as a percentage.
        public let share: Double
        /// What a blow in this band comes to, at the ends of its own range.
        public let damage: ClosedRange<Double>

        public var id: Double { threshold }
    }

    /// The game's own `probabilityToHitEquation` for this pairing, before it is read as a chance.
    public let probabilityToHit: Double
    public let hitChance: Double
    /// The damage bands this pairing reaches, weakest first. `combatformulas.dbr` states six of them —
    /// a threshold and what a blow landing past it is multiplied by.
    ///
    /// The record says which bands a hit figure reaches but not how the roll picks between them. The
    /// share each carries here reads the roll as even across the pairing's whole hit figure, so a band
    /// is worth the span of hit figure it covers. That is an assumption, and the only one the record
    /// supports without inventing numbers.
    public let bands: [Band]
    /// What a blow is multiplied by where the pairing never clears the lowest band — the game's own
    /// `normalPTHEquation`, which is 1 for anything that does clear it.
    public let weakBlow: Double
    /// What the character's own critical damage bonus adds on top of a band.
    public let critDamage: Double
    /// The share of everything reaching the target that it simply swallows, after resistance and armour.
    public let absorbed: Double
    public let shares: [Share]

    public var thrown: ClosedRange<Double> { total(\.thrown) }
    public var landed: ClosedRange<Double> { total(\.landed) }

    private func total(_ keyPath: KeyPath<Share, ClosedRange<Double>>) -> ClosedRange<Double> {
        let low = shares.reduce(0) { $0 + $1[keyPath: keyPath].lowerBound }
        let high = shares.reduce(0) { $0 + $1[keyPath: keyPath].upperBound }
        return low ... max(low, high)
    }

    /// The most a blow is multiplied by: the best band reached, and the crit bonus where that band is
    /// a critical one. A pairing that crits at all carries the bonus; one that never does is a plain
    /// blow, and a negative bonus has nothing to shrink.
    public var bestMultiplier: Double {
        let best = bands.last?.multiplier ?? 1
        return best * (best > 1 ? 1 + critDamage / 100 : 1) * weakBlow
    }
    /// What a blow lands at its hardest — the top of its range, in the best band it reaches.
    public var best: Double { landed.upperBound * bestMultiplier }
    /// What one blow is multiplied by on average, across the bands and the crit bonus.
    public var averageMultiplier: Double {
        // The crit bonus rides only on the bands that crit, so a blow that lands in the plain band is
        // worth the plain band whatever the bonus says.
        let average = bands.reduce(0) { total, band in
            total + band.multiplier * (band.multiplier > 1 ? 1 + critDamage / 100 : 1) * band.share / 100
        }
        return (average > 0 ? average : 1) * weakBlow
    }

    /// What the blow averages once misses, the roll inside its range and the bands are counted in.
    public var expected: Double {
        (landed.lowerBound + landed.upperBound) / 2 * hitChance / 100 * averageMultiplier
    }

    /// The bands that hit for more than a plain blow, which is what a critical hit is here.
    private var criticals: [Band] { bands.filter { $0.multiplier > 1 } }

    /// How often a swing crits, as a share of every swing: it has to land first.
    public var critChance: Double {
        criticals.reduce(0) { $0 + $1.share } * hitChance / 100
    }

    /// What a critical is worth over a plain blow, once the character's own bonus is on it.
    public var critMultiplier: Double {
        let share = criticals.reduce(0) { $0 + $1.share }
        guard share > 0 else { return 1 }

        let average = criticals.reduce(0) { $0 + $1.multiplier * $1.share } / share
        return average * (1 + critDamage / 100)
    }

    /// What a critical lands for, at the ends of its range.
    public var critDamageRange: ClosedRange<Double> {
        landed.lowerBound * critMultiplier * weakBlow ... landed.upperBound * critMultiplier * weakBlow
    }
}

/// The two of them fighting: what the character does to the monster, and the monster to the character.
///
/// Everything here is the game's own arithmetic out of `records/game/combatformulas.dbr` — the
/// probability-to-hit equation, the bands it is read in, and the two armour equations. Nothing is
/// transcribed: the record is evaluated as written, so a patch that changes the maths changes this.
public struct Encounter: Sendable {
    public let attacking: Blow
    public let defending: Blow
    /// How often the character lands the attack being read: the weapon's own swing rate, or the rate
    /// the chosen skill states.
    public let attackRate: Double
    /// The attack the monster is swinging back with.
    public let monsterAttack: MonsterAbility?
    /// How often it lands that attack.
    public let monsterRate: Double
    /// What the character takes off the monster before its resistances are weighed.
    public let reduction: TargetReduction

    public var damagePerSecond: Double { attacking.expected * attackRate }
    /// What the monster's chosen attack comes to over a second. One attack only: a boss throws several
    /// and cycles them, so this is what that one costs while it is the one being used.
    public var monsterDamagePerSecond: Double { defending.expected * monsterRate }

    /// What a second comes to at the ends of the range, ignoring misses: the honest span a reader can
    /// hold against a monster's health.
    public var damagePerSecondRange: ClosedRange<Double> {
        let low = attacking.landed.lowerBound * (attacking.bands.first?.multiplier ?? 1) * attackRate
        let high = attacking.best * attackRate
        return low ... max(low, high)
    }
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
        using skill: ResolvedSkill? = nil,
        swinging attack: MonsterAbility? = nil,
        reducing reduction: TargetReduction = TargetReduction(),
        /// What the monster has left on the character, worst of each kind.
        suffering debuffs: [MonsterDebuff.Kind: Double] = [:]
    ) -> Encounter {
        let swung = attack ?? Self.attack(of: monster)
        // A debuff is felt as the character being worse, not as the monster being better, so it is
        // taken off the character's own figures before either side swings.
        let offensive = max(sheet.offensiveAbility - (debuffs[.offensiveAbility] ?? 0), 1)
        let defensive = max(sheet.defensiveAbility - (debuffs[.defensiveAbility] ?? 0), 1)
        let dealt = 1 - min(debuffs[.damageDealt] ?? 0, 100) / 100
        // Sundered is written as damage taken rather than as armour lost, so it multiplies what gets
        // through rather than changing any of the character's defences — which is how it carries a blow
        // past what a character with no absorption at all would otherwise feel.
        let sundered = 1 + max(debuffs[.sunder] ?? 0, 0) / 100
        let attacking = blow(
            damage: skill.map { Self.damage(of: $0, swungBy: sheet) } ?? sheet.flatDamageRange,
            modifiers: sheet.damageModifiers,
            scaling: (cunning: sheet.cunning.total, spirit: sheet.spirit.total),
            dealt: dealt,
            offensive: offensive,
            against: monster.defensiveAbility,
            resistances: monster.resistances,
            // A monster wears no cap: the game lets its record state whatever it states, and anything
            // past a hundred is what resistance reduction is for.
            caps: [:],
            reduction: reduction,
            // A monster's record states one armour figure; it wears no regions to spread it over.
            armor: [ (monster.armor, 100) ],
            absorption: absorption(of: monster),
            absorbed: monster.stats.value("damageAbsorptionPercent"),
            taken: 1,
            critDamage: sheet.critDamage
        )
        let defending = blow(
            damage: swung.map { Self.damage(of: $0, swungBy: monster) } ?? [:],
            modifiers: swung.map { Self.modifiers(of: $0.skill, on: monster) } ?? [:],
            // A monster's record states what it swings for outright; the attribute equations are the
            // player's own scaling and are already in the figures its record carries.
            scaling: (cunning: 0, spirit: 0),
            dealt: 1,
            offensive: monster.offensiveAbility,
            against: defensive,
            resistances: sheet.resistances,
            caps: sheet.maxResistances,
            reduction: TargetReduction.of(monster),
            armor: sheet.armorHitChance.map { (sheet.armorBySlot[$0.key] ?? 0, $0.value) },
            absorption: sheet.armorAbsorption,
            absorbed: sheet.contributions.value("damageAbsorptionPercent"),
            taken: sundered,
            critDamage: monster.stats.value("offensiveCritDamageModifier")
        )
        return Encounter(
            attacking: attacking,
            defending: defending,
            attackRate: rate(of: skill, on: sheet),
            monsterAttack: swung,
            monsterRate: rate(of: swung, on: monster),
            reduction: reduction
        )
    }

    /// What a monster swings with unless a reader picks something else: the attack its record calls its
    /// own, and the hardest of its specials where it has no plain attack.
    public static func attack(of monster: ResolvedMonster) -> MonsterAbility? {
        let armed = monster.abilities
            .filter { ($0.role == .attack || $0.role == .special) && thrown(of: $0, of: monster) > 0 }
        return armed.first { $0.role == .attack }
            ?? armed.max {
                thrown(of: $0, of: monster) < thrown(of: $1, of: monster)
            }
    }

    /// What one attack throws, at the middle of every band it carries.
    public static func thrown(of ability: MonsterAbility, of monster: ResolvedMonster) -> Double {
        damage(of: ability, swungBy: monster).values.reduce(0) { $0 + ($1.lowerBound + $1.upperBound) / 2 }
    }

    /// What everything a monster throws comes to over a second, not just the attack being read.
    ///
    /// A boss does not stand there swinging one thing: it swings its own attack and weaves its specials
    /// in between. `monsterskillmanager.tpl` states the knobs — a chance per special slot in `[0..100]`,
    /// and `specialAttackTimeout`, "Seconds - time out for all skill use" — but not the order it picks
    /// them in. So the plain attack runs at its own rate and every other attack is read as firing at
    /// its slot's chance once per timeout. That is an estimate, and the only one the record supports.
    public func totalDamagePerSecond(
        of monster: ResolvedMonster,
        against sheet: CharacterSheet,
        reducing reduction: TargetReduction = TargetReduction(),
        suffering debuffs: [MonsterDebuff.Kind: Double] = [:]
    ) -> Double {
        let armed = monster.abilities
            .filter { ($0.role == .attack || $0.role == .special) && Self.thrown(of: $0, of: monster) > 0 }
        guard let plain = Self.attack(of: monster) else { return 0 }

        // Three slots hold a chance; a boss with more attacks than slots reuses the last one stated.
        let chances = [ "specialAttackChance", "specialAttack2Chance", "specialAttack3Chance" ]
            .compactMap { database.record(monster.path)?.number($0) }
            .filter { $0 > 0 }
        let timeout = max(database.record(monster.path)?.number("specialAttackTimeout") ?? 0, 1)

        var total = 0.0
        var slot = 0
        for ability in armed {
            let fight = encounter(
                of: sheet,
                against: monster,
                swinging: ability,
                reducing: reduction,
                suffering: debuffs
            )
            guard
                ability.skill.recordPath != plain.skill.recordPath
            else {
                total += fight.monsterDamagePerSecond
                continue
            }

            let chance = chances.isEmpty ? 100 : chances[min(slot, chances.count - 1)]
            slot += 1
            total += fight.defending.expected * chance / 100 / timeout
        }
        return total
    }

    /// What a monster's own body hits for, which is its weapon as far as its attacks are concerned.
    ///
    /// A creature carries no inventory weapon; the flat damage on its passives is what a swing of it is
    /// worth — `damagebase_physical06` gives an uber boss 1014 physical — and its attack skills add
    /// their own figures on top of that.
    public static func baseDamage(of monster: ResolvedMonster) -> [DamageType: ClosedRange<Double>] {
        var total = [DamageType: ClosedRange<Double>]()
        for ability in monster.abilities where ability.role == .passive {
            for (type, band) in Self.damage(of: ability.skill) {
                let held = total[type] ?? 0 ... 0
                total[type] = held.lowerBound + band.lowerBound ... held.upperBound + band.upperBound
            }
        }
        return total
    }

    /// One of a monster's attacks: its own figures, plus the share of the creature's own blow it
    /// carries. A skill that states a `weaponDamagePct` carries that much of it; a plain swing of the
    /// creature states none and carries the whole thing.
    public static func damage(
        of ability: MonsterAbility,
        swungBy monster: ResolvedMonster
    ) -> [DamageType: ClosedRange<Double>] {
        var damage = Self.damage(of: ability.skill)
        let stated = ability.skill.stats.value("weaponDamagePct")
        let isSwing = ability.skill.recordClass.contains("AttackWeapon")
        let share = stated > 0 ? stated / 100 : (isSwing ? 1 : 0)
        guard share > 0 else { return damage }

        for (type, carried) in baseDamage(of: monster) where carried.upperBound > 0 {
            let held = damage[type] ?? 0 ... 0
            damage[type] =
                held.lowerBound + carried.lowerBound * share
                ... held.upperBound + carried.upperBound * share
        }
        return damage
    }

    /// What an attack raises its own damage by.
    ///
    /// Per type, only the skill's own figures count: a creature's `offensive…Modifier` total gathers
    /// every passive it carries, including the level-scaled adjusters the game tunes a boss's base
    /// attack with — The Dread's come to −107% physical at level 100 — and laying that over a skill's
    /// stated damage leaves a boss hitting for nothing.
    ///
    /// `offensiveTotalDamageModifier` is a different thing and does count: it is the creature's own,
    /// aimed at everything it deals rather than at one type, and ascendant mode is where it lives —
    /// the mode's adjustment carries +165% of it.
    private static func modifiers(of skill: ResolvedSkill, on monster: ResolvedMonster) -> [DamageType: Double] {
        let total = monster.stats.value("offensiveTotalDamageModifier")
        return Dictionary(uniqueKeysWithValues: DamageType.allCases.map {
            ($0, skill.stats.value($0.modifierKey) + total)
        })
    }

    /// How often the attack being read actually lands.
    ///
    /// Three cases, in the order a record answers them. A skill that states the milliseconds between
    /// its own attacks ticks at that rate — a beam or a channel does not wait for a swing. A skill on
    /// a cooldown fires once each time it comes up, shortened by whatever the character has taken off
    /// its cooldown. Anything else lands at the rate the character swings.
    ///
    /// What speeds a stated interval up is cast speed where the skill is a spell, and attack speed
    /// where it swings the weapon.
    public func rate(of skill: ResolvedSkill?, on sheet: CharacterSheet) -> Double {
        let swing = sheet.attacksPerSecond > 0 ? sheet.attacksPerSecond : 1
        guard let skill, let record = database.record(skill.recordPath) else { return swing }

        if case let interval = Self.sustainedInterval(of: record), interval > 0 {
            let speed = record.recordClass.contains("Spell") ? sheet.castSpeed : sheet.attackSpeed
            return 1 / interval * max(speed, 100) / 100
        }

        let cooldown =
            level(record, "skillCooldownTime", at: skill.baseLevel)
            * (1 - min(sheet.cooldownReduction, 90) / 100)
        // A cooldown shorter than the swing says the skill is always ready, not that it is thrown any
        // faster: what it is pressed with still has to come round.
        return cooldown > 0 ? min(1 / cooldown, swing) : swing
    }

    /// How often a monster lands the attack it is swinging with, read the same three ways a
    /// character's is — its own stated interval, its cooldown, or the rate it swings at otherwise.
    public func rate(of ability: MonsterAbility?, on monster: ResolvedMonster) -> Double {
        let speed = 100 + monster.stats.value("characterAttackSpeedModifier")
        let swing = Self.baseAttackRate * max(speed, 20) / 100
        guard let ability, let record = database.record(ability.skill.recordPath) else { return swing }

        if case let interval = Self.sustainedInterval(of: record), interval > 0 {
            return 1 / interval * max(speed, 20) / 100
        }

        let cooldown = level(record, "skillCooldownTime", at: ability.skill.baseLevel)
        return cooldown > 0 ? min(1 / cooldown, swing) : swing
    }

    /// What the game swings a bare weapon at before any speed bonus.
    private static let baseAttackRate = 1.5

    /// The seconds between ticks of an attack that is held rather than swung, and nothing for anything
    /// else.
    ///
    /// Seven classes write `timeBetweenAttacks` and they do not mean the same thing by it. A beam, a
    /// cone, a drain, a tether and a spin all keep going for as long as they are held, so the interval
    /// is the rate they land at. A charge and a growing radius tick that fast *within one use* — read
    /// as a rate, The Dread's charge becomes ten swings a second — so their own cooldown governs
    /// instead.
    private static let sustainedClasses = [
        "Skill_AttackSpellBeam", "Skill_AttackSpellCone", "Skill_AttackSpellDrain",
        "SkillSecondary_Tether", "Skill_AttackRadiusSpin",
    ]

    private static func sustainedInterval(of record: ArzRecord) -> Double {
        guard sustainedClasses.contains(record.recordClass) else { return 0 }

        return record.number("timeBetweenAttacks") / 1000
    }

    /// One rank's element of a field the game writes once per rank.
    private func level(_ record: ArzRecord, _ key: String, at rank: Int) -> Double {
        let numbers = record[key]?.numbers ?? []
        guard !numbers.isEmpty else { return 0 }

        return numbers[min(max(rank - 1, 0), numbers.count - 1)]
    }

    /// One side swinging at the other.
    private func blow(
        damage: [DamageType: ClosedRange<Double>],
        modifiers: [DamageType: Double],
        scaling: (cunning: Double, spirit: Double),
        /// What the attacker has left of its own damage, as a share: a character whose damage has been
        /// cut deals this much of it.
        dealt: Double,
        offensive: Double,
        against defensive: Double,
        resistances: [ResistanceKind: Double],
        /// The most of each the target actually gets to keep. A character's resistance is capped — the
        /// overcap past it buys nothing but a buffer against reduction — so a sheet reading 158%
        /// vitality still takes what gets past 80.
        caps: [ResistanceKind: Double],
        reduction: TargetReduction,
        /// The armour of each hit region and how often that region is the one struck. The game picks a
        /// region per blow and applies that region's own armour, so a hit bigger than one region's
        /// armour and smaller than another's costs differently depending on where it lands — which the
        /// averaged Armor Rating cannot say.
        armor: [(rating: Double, chance: Double)],
        absorption: Double,
        /// A share of everything that gets this far, swallowed whole. Armor absorption is the armour's
        /// own and stops physical only; this one is aimed at the lot — Mirror of Ereoctes states 100%
        /// of it, which is what makes it a few seconds of standing in a fire and taking nothing.
        absorbed: Double,
        /// What the target takes of everything that reaches it. Sundered writes itself here: a share
        /// above one, which is why it can carry a blow past what the target would otherwise feel.
        taken: Double,
        critDamage: Double
    ) -> Blow {
        let hit = probabilityToHit(offensive: offensive, defensive: defensive)

        // Flat Elemental damage is not a damage type the game ever deals: it is split in three, a third
        // to each of fire, cold and lightning, each then met by that type's own resistance.
        var split = damage
        if let elemental = split.removeValue(forKey: .elemental), elemental.upperBound > 0 {
            for type in DamageType.allCases where type.isElemental {
                let third = elemental.lowerBound / 3 ... elemental.upperBound / 3
                let held = split[type] ?? 0 ... 0
                split[type] = held.lowerBound + third.lowerBound ... held.upperBound + third.upperBound
            }
        }

        var shares = [Blow.Share]()
        for type in DamageType.allCases where type != .elemental {
            guard let written = split[type], written.upperBound > 0 else { continue }

            let raised = (1 + (modifiers[type] ?? 0) / 100) * attributeScale(type, scaling) * max(dealt, 0)
            let thrown = written.lowerBound * raised ... written.upperBound * raised

            let kind = ResistanceKind(damage: type) ?? .physical
            let held = resistances[kind] ?? 0
            let cap = caps[kind] ?? 100
            // Reduction eats the whole figure, overcap and all, and only then is the cap laid over the
            // result — which is the entire reason a build carries an overcap.
            let reduced = reduction.applied(to: held, of: kind)
            let before = min(held, cap)
            let after = min(reduced, cap)

            let swallowed = (1 - min(max(absorbed, 0), 100) / 100) * max(taken, 0)

            func through(_ value: Double) -> Double {
                let left = value * (1 - min(after, 100) / 100)
                guard type == .physical else { return max(left * swallowed, 0) }

                return max(acrossRegions(left, armor: armor, absorption: absorption) * swallowed, 0)
            }

            shares.append(Blow.Share(
                type: type,
                thrown: thrown,
                landed: through(thrown.lowerBound) ... max(through(thrown.lowerBound), through(thrown.upperBound)),
                resisted: after,
                resistedBefore: before,
                held: held,
                heldAfterReduction: reduced,
                cap: cap
            ))
        }

        let landed =
            shares.reduce(0.0) { $0 + $1.landed.lowerBound }
            ... max(shares.reduce(0.0) { $0 + $1.landed.lowerBound }, shares.reduce(0.0) { $0 + $1.landed.upperBound })

        return Blow(
            probabilityToHit: hit,
            hitChance: min(100, max(hit, number("pthMinimum", or: 55))),
            bands: bands(reachedBy: hit, landing: landed),
            weakBlow: weakBlow(at: hit),
            critDamage: critDamage,
            absorbed: min(max(absorbed, 0), 100),
            shares: shares.sorted { $0.average > $1.average }
        )
    }

    /// The bands this hit figure reaches, and how much of the roll each is worth.
    ///
    /// A band runs from its own threshold to the next one, and the last runs to the hit figure itself.
    /// Reading the roll as even across `0 ... hit` makes a band worth the span it covers; everything
    /// under the first threshold lands at the plain multiplier.
    private func bands(reachedBy hit: Double, landing damage: ClosedRange<Double>) -> [Blow.Band] {
        let stated = critBands()
        guard hit > 0, let first = stated.first else { return [] }

        var found = [Blow.Band]()
        let below = min(first.threshold, hit)
        if below > 0 {
            found.append(Blow.Band(threshold: 0, multiplier: 1, share: below / hit * 100, damage: damage))
        }

        for (index, band) in stated.enumerated() where hit > band.threshold {
            let next = index + 1 < stated.count ? min(stated[index + 1].threshold, hit) : hit
            guard next > band.threshold else { continue }

            found.append(Blow.Band(
                threshold: band.threshold,
                multiplier: band.multiplier,
                share: (next - band.threshold) / hit * 100,
                damage: damage.lowerBound * band.multiplier ... damage.upperBound * band.multiplier
            ))
        }
        return found
    }

    /// What the game's own damage equation makes of an attribute: Cunning raises physical and pierce,
    /// Spirit raises everything else. The equations name the attributes as the engine did before they
    /// were renamed.
    private func attributeScale(_ type: DamageType, _ scaling: (cunning: Double, spirit: Double)) -> Double {
        guard
            case let source = formulas?.text(type.scalingEquationKey) ?? "",
            !source.isEmpty,
            let equation = try? Equation(source),
            let value = try? equation.value([
                "physicalDamageDV": 1,
                "pierceDamageDV": 1,
                "magicalDamageDV": 1,
                "dexterityDV": scaling.cunning,
                "intelligenceDV": scaling.spirit,
            ])
        else { return 1 }

        return max(value, 1)
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

    /// What a blow is worth when the hit figure falls short of the first band.
    ///
    /// `normalPTHEquation` states it: a pairing that never clears the lowest threshold does not merely
    /// hit less often, it hits softer, in proportion to how far short it falls.
    private func weakBlow(at hit: Double) -> Double {
        guard let first = critBands().first, hit < first.threshold else { return 1 }
        guard
            case let source = formulas?.text("normalPTHEquation") ?? "",
            !source.isEmpty,
            let equation = try? Equation(source),
            let value = try? equation.value([ "probabilityToHitDV": hit ])
        else { return 1 }

        return max(min(value, 1), 0)
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

    /// What a physical blow costs on average, once every region it could land on is counted.
    private func acrossRegions(
        _ damage: Double,
        armor: [(rating: Double, chance: Double)],
        absorption: Double
    ) -> Double {
        let total = armor.reduce(0) { $0 + $1.chance }
        guard total > 0 else { return damage }

        return armor.reduce(0) { $0 + throughArmor(damage, armor: $1.rating, absorption: absorption) * $1.chance }
            / total
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
    public static func damage(of skill: ResolvedSkill) -> [DamageType: ClosedRange<Double>] {
        var damage = [DamageType: ClosedRange<Double>]()
        for type in DamageType.allCases {
            let low = skill.stats.value(type.minimumKey)
            let high = skill.stats.value(type.maximumKey)
            if low > 0 || high > 0 { damage[type] = low ... max(low, high) }
        }
        return damage
    }

    /// The same, with what the skill takes from the weapon it is swung with.
    ///
    /// A skill states a `weaponDamagePct`, and that share of the whole weapon attack — the weapon's own
    /// damage and every flat bonus the character's gear adds — rides along with the skill's own figures.
    /// A skill at 150% carries one and a half of it; a spell that names no percentage carries none.
    public static func damage(
        of skill: ResolvedSkill,
        swungBy sheet: CharacterSheet
    ) -> [DamageType: ClosedRange<Double>] {
        var damage = Self.damage(of: skill)
        let share = skill.stats.value("weaponDamagePct") / 100
        guard share > 0 else { return damage }

        for (type, carried) in sheet.flatDamageRange where carried.upperBound > 0 {
            let held = damage[type] ?? 0 ... 0
            damage[type] =
                held.lowerBound + carried.lowerBound * share
                ... held.upperBound + carried.upperBound * share
        }
        return damage
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
