// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation
import Testing

@testable import GrimDawnerEngine

/// The optimizer ranks plans with figures of its own rather than with a built character, because
/// building one for each of the hundreds of thousands of combinations it tries would take days. That
/// makes its arithmetic a second telling of the sheet's, and this is what keeps the two honest: read
/// the character's own fittings back through the evaluator and the figures must be the sheet's.
///
/// It needs the installed game and a save to read: set `GRIM_DAWN_FOLDER` and `GRIM_DAWN_SAVE`, and
/// it skips when either is absent.
struct LoadoutOptimizerTests {
    private static var database: GameDatabase? {
        guard let folder = ProcessInfo.processInfo.environment["GRIM_DAWN_FOLDER"] else { return nil }

        return try? GameDatabase(gameFolder: URL(fileURLWithPath: folder))
    }

    private static func character(in database: GameDatabase) throws -> ResolvedCharacter? {
        guard let path = ProcessInfo.processInfo.environment["GRIM_DAWN_SAVE"] else { return nil }

        let url = URL(fileURLWithPath: path)
        let save = try Gdc.Parser.parse(try Data(contentsOf: url))
        return CharacterBuilder(database: database).build(
            save,
            file: CharacterFile(
                folderName: url.deletingLastPathComponent().lastPathComponent,
                directory: url.deletingLastPathComponent(),
                playerFile: url
            )
        )
    }

    @Test
    func readsTheWornFittingsAsTheSheetDoes() throws {
        guard let database = Self.database, let character = try Self.character(in: database) else { return }

        let problem = LoadoutProblemBuilder(database: database, catalogue: ItemCatalogue.build(from: database).items)
            .problem(for: character, skill: nil)
        try #require(!problem.isEmpty)

        let figures = LoadoutOptimizer(problem: problem, target: .standard).figures(of: problem.worn)
        let sheet = character.sheet

        #expect(abs(figures.offensiveAbility - sheet.offensiveAbility) < 0.01)
        #expect(abs(figures.defensiveAbility - sheet.defensiveAbility) < 0.01)
        #expect(abs(figures.armor - sheet.armor) < 0.01)
        #expect(abs(figures.armorAbsorption - sheet.armorAbsorption) < 0.01)
        #expect(abs(figures.health - sheet.health) < 0.01)

        // The difficulty's own penalty — Ultimate takes 50% off fire, cold, lightning, pierce and
        // poison and 25% off the rest — is part of the character's contributions, so it is already in
        // both figures. These matching is what says the search is optimising against the resistances
        // the character actually fights with rather than against unpenalised ones.
        for kind in ResistanceKind.allCases {
            #expect(abs(figures.resistance(kind) - (sheet.resistances[kind] ?? 0)) < 0.01)
            #expect(abs(figures.maximumResistance(kind) - (sheet.maxResistances[kind] ?? 0)) < 0.01)
        }
    }

    /// The one thing the search may not trade away is the cap, so a plan that reaches it has to still
    /// hold it once the whole character is built again from the save it writes.
    @Test
    func holdsEveryResistanceAtItsCap() async throws {
        guard let database = Self.database, let character = try Self.character(in: database) else { return }

        let plans = await LoadoutSearch.plans(
            for: character,
            database: database,
            catalogue: ItemCatalogue.build(from: database).items,
            skill: nil,
            target: .standard,
            progress: { _ in }
        )
        try #require(!plans.isEmpty)

        for plan in plans where plan.isFeasible {
            for kind in LoadoutTarget.standard.required {
                let held = plan.sheet.resistances[kind] ?? 0
                let cap = character.sheet.maxResistances[kind] ?? 80
                #expect(held >= cap, "\(plan.goal.rawValue) leaves \(kind.title) at \(held), under \(cap)")
            }
        }
    }
}
