// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation
import Testing

@testable import GrimDawnerEngine

/// The interaction arithmetic, pinned to the shape the game's binary and one controlled community
/// measurement agree on — [AttackPipeline.md](../../../Documentation/AttackPipeline.md) has both.
///
/// Per-type percentages and the attribute bonus sum into one pool; the total-damage modifier
/// multiplies once over it; the hit figure is floored at 55 and read directly as the chance to land.
/// It needs the installed game: set `GRIM_DAWN_FOLDER`, and it skips when that is absent.
struct EncounterTests {
    private static var database: GameDatabase? {
        guard let folder = ProcessInfo.processInfo.environment["GRIM_DAWN_FOLDER"] else { return nil }

        return try? GameDatabase(gameFolder: URL(fileURLWithPath: folder))
    }

    /// The Dread's charged finale against a character who stops nothing, so what lands is exactly what
    /// was thrown and every layer of the attacker's arithmetic is visible in one figure.
    @Test
    func composesAMonsterBlowTheWayTheEngineDoes() throws {
        guard let database = Self.database else { return }

        let skills = SkillResolver(database: database)
        let resolver = MonsterResolver(
            database: database,
            skills: skills,
            items: ItemResolver(database: database, skills: skills)
        )
        guard
            let monster = resolver.monster(
                at: "records/creatures/enemies/boss&quest/thedread_02.dbr",
                level: 100,
                difficulty: .ultimate
            ),
            let cadence = monster.abilities.first(where: { $0.skill.recordPath.hasSuffix("thedread_cadence.dbr") })
        else { return }

        var sheet = CharacterSheet()
        sheet.defensiveAbility = 2000
        sheet.health = 20000

        let engine = EncounterEngine(database: database)
        let blow = engine.encounter(of: sheet, against: monster, swinging: cadence).defending

        // The raw figures: the skill's own flat damage plus the whole of the creature's blow, since a
        // weapon attack carries 100% of it.
        let raw = EncounterEngine.damage(of: cadence, swungBy: monster)
        let total = 1 + monster.stats.value("offensiveTotalDamageModifier") / 100

        // Physical rides Cunning at the equation's rate, additively with the summed modifiers — The
        // Dread's read −107% and still land hard because ~1200 Cunning is worth almost five hundred.
        let physicalPool =
            monster.stats.value("offensivePhysicalModifier")
            + cadence.skill.stats.value("offensivePhysicalModifier")
            + monster.cunning / 245 * 100
        let physical = try #require(blow.shares.first { $0.type == .physical })
        let expectedPhysical = try #require(raw[.physical]).lowerBound * (1 + physicalPool / 100) * total
        #expect(abs(physical.thrown.lowerBound - expectedPhysical) < 1)
        // Nothing on the sheet stops anything, so the blow lands whole.
        #expect(abs(physical.landed.lowerBound - expectedPhysical) < 1)

        // Vitality rides Spirit at its own rate.
        let lifePool =
            monster.stats.value("offensiveLifeModifier")
            + cadence.skill.stats.value("offensiveLifeModifier")
            + monster.spirit / 215 * 100
        let life = try #require(blow.shares.first { $0.type == .vitality })
        let expectedLife = try #require(raw[.vitality]).lowerBound * (1 + lifePool / 100) * total
        #expect(abs(life.thrown.lowerBound - expectedLife) < 1)

        // The hit figure is floored at 55 and read directly as the chance to land; the sheet carries
        // no dodge to take off it.
        #expect(blow.probabilityToHit >= 55)
        #expect(blow.hitChance == min(blow.probabilityToHit, 100))

        // A finale fires once its swings have built its charges, not every swing.
        let charges = database.record(cadence.skill.recordPath)?.number("skillChargeLevel") ?? 0
        #expect(charges > 1)
        #expect(abs(engine.rate(of: cadence, on: monster) - 1.5 / charges) < 0.001)
    }

    /// A creature whose record names no attack skill at all still swings its own body. 293 of the
    /// game's 3,081 named monsters fight that way, and reading them as having no attack at all had the
    /// Oversized Maggot — which one-shots a level 100 character — throwing nothing.
    @Test
    func swingsTheCreaturesOwnBodyWhereNoAttackSkillIsNamed() throws {
        guard let database = Self.database else { return }

        let skills = SkillResolver(database: database)
        let resolver = MonsterResolver(
            database: database,
            skills: skills,
            items: ItemResolver(database: database, skills: skills)
        )
        guard
            let maggot = resolver.monster(
                at: "records/creatures/enemies/special/sand_03.dbr",
                level: 100,
                difficulty: .ultimate
            )
        else { return }

        // Nothing in any of its attack slots, so nothing to name as the attack it swings with.
        #expect(!maggot.abilities.contains { $0.role == .attack || $0.role == .special })
        #expect(EncounterEngine.attack(of: maggot) == nil)

        // Its body is `damagebase_physical06`, which is the whole of what it throws.
        let body = EncounterEngine.baseDamage(of: maggot)
        #expect(body[.physical]?.lowerBound ?? 0 > 5000)

        var sheet = CharacterSheet()
        sheet.defensiveAbility = 2000
        sheet.health = 20000

        let engine = EncounterEngine(database: database)
        let fight = engine.encounter(of: sheet, against: maggot)
        #expect(fight.defending.landed.lowerBound > 0)
        #expect(fight.monsterRate > 0)
        #expect(engine.totalDamagePerSecond(of: maggot, against: sheet) > 0)
    }

    /// A character does not stand still under the blows it takes. What it regenerates and what its
    /// attack leeches back are part of how long it lasts, and reading a fight without them made a boss
    /// look lethal that the character's own healing outruns.
    @Test
    func countsWhatTheCharacterHealsBackWhileItFights() throws {
        guard let database = Self.database else { return }

        let skills = SkillResolver(database: database)
        let resolver = MonsterResolver(
            database: database,
            skills: skills,
            items: ItemResolver(database: database, skills: skills)
        )
        guard
            let monster = resolver.monster(
                at: "records/creatures/enemies/boss&quest/thedread_02.dbr",
                level: 100,
                difficulty: .ultimate
            )
        else { return }

        var sheet = CharacterSheet()
        sheet.defensiveAbility = 2000
        sheet.health = 20000
        sheet.healthRegen = 250
        // "% of Attack Damage converted to Health", the game's own key.
        sheet.contributions.increase("offensiveLifeLeechMin", by: 20)

        let fight = EncounterEngine(database: database).encounter(of: sheet, against: monster)
        #expect(fight.regeneration == 250)
        // A fifth of what the attack lands over a second comes back as health.
        #expect(abs(fight.leeched - fight.damagePerSecond * 0.2) < 0.01)
        #expect(abs(fight.healedPerSecond - (250 + fight.leeched)) < 0.01)

        // Nothing leeched where nothing lands.
        var bare = sheet
        bare.contributions = StatBlock()
        let dry = EncounterEngine(database: database).encounter(of: bare, against: monster)
        #expect(dry.leeched == 0)
    }

    /// An item that enhances a skill carries its figures on a modifier record of its own, and where the
    /// skill it enhances is one the character keeps up those figures are on the sheet. A ring's
    /// ascendant affix granting +100 Health to Spectral Binding was 113 health the game showed and the
    /// app did not.
    ///
    /// It needs a save to read: set `GRIM_DAWN_SAVE`, and it skips when that is absent.
    @Test
    func putsAnItemsEnhancementOfAPermanentSkillOnTheSheet() throws {
        guard
            let database = Self.database,
            let path = ProcessInfo.processInfo.environment["GRIM_DAWN_SAVE"]
        else { return }

        let url = URL(fileURLWithPath: path)
        let character = CharacterBuilder(database: database).build(
            try Gdc.Parser.parse(try Data(contentsOf: url)),
            file: CharacterFile(
                folderName: url.deletingLastPathComponent().lastPathComponent,
                directory: url.deletingLastPathComponent(),
                playerFile: url
            )
        )
        let permanent = Set(
            character.masteries.flatMap(\.skills)
                .filter { $0.isLearned && $0.isAlwaysOn }
                .map { $0.recordPath.lowercased() }
        )
        var wanted = StatBlock()
        for item in character.equippedItems {
            for granted in item.grantedSkills
            where granted.kind == .enhanced && permanent.contains(granted.recordPath.lowercased()) {
                guard let changes = granted.modifications else { continue }

                wanted.merge(changes.stats)
            }
        }
        try #require(!wanted.values.isEmpty)

        // Every figure those modifiers carry has to be somewhere in what feeds the sheet. Read as "at
        // least", since other sources add to the same keys.
        for (key, value) in wanted.values where value > 0 {
            let carried = character.sheet.contributions.value(key)
            #expect(carried >= value - 0.001, "\(key): enhanced by \(value), sheet carries \(carried)")
        }
    }

    /// The six damage bands as `combatformulas.dbr` states them, which the roll model depends on.
    @Test
    func readsTheCritBandsFromTheRecord() throws {
        guard let database = Self.database else { return }

        let bands = EncounterEngine(database: database).critBands()
        #expect(bands.map(\.threshold) == [ 70, 90, 105, 120, 130, 135 ])
        for (multiplier, expected) in zip(bands.map(\.multiplier), [ 1.0, 1.1, 1.2, 1.3, 1.4, 1.5 ]) {
            #expect(abs(multiplier - expected) < 0.001)
        }
    }
}
