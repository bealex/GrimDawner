// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation
import Testing

@testable import GrimDawnerEngine

/// What a monster is worth, checked against the figures GrimTools prints for the same record.
///
/// The game has no window that shows a monster's sheet, so this is the only reference there is. It needs
/// the installed game, whose folder is machine-specific: set `GRIM_DAWN_FOLDER` to run it, and it skips
/// when that is absent.
struct MonsterStatsTests {
    private static var database: GameDatabase? {
        guard let folder = ProcessInfo.processInfo.environment["GRIM_DAWN_FOLDER"] else { return nil }

        return try? GameDatabase(gameFolder: URL(fileURLWithPath: folder))
    }

    /// Ravager of Minds at monster level 100 on Ultimate, as the monster database prints it.
    ///
    /// It is the hardest case there is: its pools come from level equations, its passives adjust them,
    /// the difficulty lays its own adjustment over everything, and it carries the skill that cancels the
    /// game's ascendant-mode bonus.
    @Test
    func readsACelestialBossAsTheMonsterDatabaseDoes() throws {
        guard let database = Self.database else { return }

        let skills = SkillResolver(database: database)
        let resolver = MonsterResolver(
            database: database,
            skills: skills,
            items: ItemResolver(database: database, skills: skills)
        )
        guard
            let monster = resolver.monster(
                at: "records/creatures/enemies/boss&quest/wendigo_ravager_mindsc.dbr",
                level: 100,
                difficulty: .ultimate
            )
        else { return }

        #expect(monster.physique.rounded() == 1544)
        #expect(monster.cunning.rounded() == 1254)
        #expect(monster.spirit.rounded() == 1144)
        #expect(monster.health.rounded() == 27_359_591)
        #expect(monster.energy.rounded() == 1_370_047)
        #expect(monster.offensiveAbility.rounded() == 2780)
        #expect(monster.defensiveAbility.rounded() == 2828)
        #expect(monster.armor.rounded() == 2406)
        #expect(monster.resistances[.fire]?.rounded() == 93)
        #expect(monster.resistances[.vitality]?.rounded() == 123)
        #expect(monster.resistances[.physical]?.rounded() == 87)
        #expect(monster.cancelsAscendantMode)
    }

    /// The Keeper of the Seal at level 109, Ultimate Ascendant, inside a Treacherous Domain — pinned to
    /// the running game itself, whose health bar read 10,983,499. The challenge layer is the last piece
    /// of that figure: without it the sheet stops five percent short.
    @Test
    func laysAChallengeAreaOverAnAscendantBoss() throws {
        guard let database = Self.database else { return }

        let skills = SkillResolver(database: database)
        let resolver = MonsterResolver(
            database: database,
            skills: skills,
            items: ItemResolver(database: database, skills: skills)
        )

        let areas = ChallengeArea.all(in: database)
        #expect(areas.map(\.name) == [ "Dangerous Domain", "Treacherous Domain", "Forbidden Domain" ])

        guard
            let treacherous = areas.first(where: { $0.name == "Treacherous Domain" }),
            let monster = resolver.monster(
                at: "records/creatures/enemies/boss&quest/statue_roguelike_entranceguardian_01.dbr",
                level: 109,
                difficulty: .ultimate,
                isAscendant: true,
                challengeArea: treacherous.adjustment
            )
        else { return }

        #expect(abs(monster.health - 10_983_499) < 10)
        #expect(monster.offensiveAbility.rounded() == 2991)
        #expect(monster.defensiveAbility.rounded() == 2721)

        // Grand Magus Morgoneth at level 111 inside a Forbidden Domain, from a recorded fight whose
        // bar read 13,256,496. Mutators were rolled and unknown, and it does not matter: none of the
        // game's monster mutators touches health.
        guard
            let forbidden = areas.first(where: { $0.name == "Forbidden Domain" }),
            let magus = resolver.monster(
                at: "records/creatures/enemies/boss&quest/eldritcharmor_roguelike_02a.dbr",
                level: 111,
                difficulty: .ultimate,
                isAscendant: true,
                challengeArea: forbidden.adjustment
            )
        else { return }

        #expect(abs(magus.health - 13_256_496) < 10)
    }
}
