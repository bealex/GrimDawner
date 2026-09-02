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

        // Read where the save itself is, since that is the sheet being compared against.
        let problem = LoadoutProblemBuilder(database: database, catalogue: ItemCatalogue.build(from: database).items)
            .problem(for: character, skill: nil, readAt: character.difficulty)
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
    ///
    /// Run without the pair pass, which is not what this is about and costs an unoptimised build
    /// minutes: `thePairPassFindsWhatOneAtATimeCannot` covers that on its own.
    @Test
    func holdsEveryResistanceAtItsCap() async throws {
        guard let database = Self.database, let character = try Self.character(in: database) else { return }

        var target = LoadoutTarget.standard
        target.refinesPairs = false
        let plans = await LoadoutSearch.plans(
            for: character,
            database: database,
            catalogue: ItemCatalogue.build(from: database).items,
            skill: nil,
            target: target,
            progress: { _ in }
        )
        try #require(!plans.isEmpty)

        let halved: Set<ResistanceKind> = [ .fire, .cold, .lightning, .pierce, .acid ]
        for plan in plans {
            // The plan carries what the difficulty took off each resistance, which is what the sidebar
            // says beside the figure it reached.
            #expect(plan.difficulty == .ultimate)
            for kind in LoadoutTarget.capped {
                #expect(plan.difficultyPenalty[kind] == (halved.contains(kind) ? -50 : -25))
            }
            guard plan.isFeasible else { continue }

            for kind in LoadoutTarget.capped {
                let held = plan.sheet.resistances[kind] ?? 0
                let cap = plan.sheet.maxResistances[kind] ?? 80
                #expect(held >= cap, "\(plan.goal.rawValue) leaves \(kind.title) at \(held), under \(cap)")
            }
        }
    }

    /// An armour ceiling stops the score paying for armour past it, which is what sends the socket
    /// somewhere else. Two plans built from one set of fittings differ only in that.
    @Test
    func stopsPayingForArmorPastTheCeiling() throws {
        guard let database = Self.database, let character = try Self.character(in: database) else { return }

        let problem = LoadoutProblemBuilder(database: database, catalogue: ItemCatalogue.build(from: database).items)
            .problem(for: character, skill: nil)
        try #require(!problem.isEmpty)

        let figures = LoadoutOptimizer(problem: problem, target: .standard).figures(of: problem.worn)
        try #require(figures.armor > 10)

        let ceiling = figures.armor / 2
        var capped = LoadoutTarget.standard
        capped.armorCeiling = ceiling
        let free = LoadoutOptimizer(problem: problem, target: .standard)
        let held = LoadoutOptimizer(problem: problem, target: capped)

        // Held under the ceiling the plan is worth less, since half its armour now counts for nothing.
        #expect(held.score(figures, goal: .defence) < free.score(figures, goal: .defence))

        // A ceiling the character is already under changes nothing at all.
        var loose = LoadoutTarget.standard
        loose.armorCeiling = figures.armor * 2
        let unbound = LoadoutOptimizer(problem: problem, target: loose)
        #expect(abs(unbound.score(figures, goal: .defence) - free.score(figures, goal: .defence)) < 0.000_1)
    }

    /// Falling short of the asked-for Armor Absorption costs the plan, which is what makes the search
    /// buy it. The attack plan is never charged: it is a defensive figure.
    @Test
    func chargesAPlanForMissingTheAbsorptionItWasAskedFor() throws {
        guard let database = Self.database, let character = try Self.character(in: database) else { return }

        let problem = LoadoutProblemBuilder(database: database, catalogue: ItemCatalogue.build(from: database).items)
            .problem(for: character, skill: nil)
        try #require(!problem.isEmpty)

        let optimizer = LoadoutOptimizer(problem: problem, target: .standard)
        let total = problem.evaluator.base + optimizer.stats(of: problem.worn)
        try #require(problem.evaluator.figures(absolute: total).armorAbsorption < 100)

        let free = LoadoutPressure(wantedResistance: problem.evaluator.wanted(for: .standard))
        var pressed = free
        pressed.wantedAbsorption = 100
        pressed.absorptionPrice = 1
        #expect(
            problem.evaluator.penalisedScore(total, plus: LoadoutStats(), goal: .defence, under: pressed)
                < problem.evaluator.penalisedScore(total, plus: LoadoutStats(), goal: .defence, under: free)
        )

        var wanting = LoadoutTarget.standard
        wanting.minimumArmorAbsorption = 100
        let held = LoadoutOptimizer(problem: problem, target: wanting)
        #expect(held.wantedAbsorption(for: .defence) == 100)
        #expect(held.wantedAbsorption(for: .balanced) == 100)
        #expect(held.wantedAbsorption(for: .attack) == 0)
    }

    /// The pair pass is what turns "no single change helps" into "no change to one socket and no
    /// change to two helps". It may never give up a cap to do it — where the plan already stands is
    /// among the candidates, and a resistance falling further short outranks any score.
    @Test
    func thePairPassFindsWhatOneAtATimeCannot() throws {
        guard let database = Self.database, let character = try Self.character(in: database) else { return }

        let problem = LoadoutProblemBuilder(database: database, catalogue: ItemCatalogue.build(from: database).items)
            .problem(for: character, skill: nil)
        try #require(!problem.isEmpty)

        func run(refining: Bool) -> (short: Double, score: Double) {
            var target = LoadoutTarget.standard
            target.refinesPairs = refining
            let optimizer = LoadoutOptimizer(problem: problem, target: target)
            let choice = optimizer.run(goal: .balanced, seed: 0) { _ in }
            return (
                optimizer.shortfalls(of: choice).values.reduce(0, +),
                optimizer.score(optimizer.figures(of: choice), goal: .balanced)
            )
        }

        let plain = run(refining: false)
        let refined = run(refining: true)

        #expect(refined.short <= plain.short + 0.000_1)
        // Measured on this character rather than guaranteed: what the pass is worth depends on the
        // fittings. A pass that finds nothing at all here means it has stopped working.
        #expect(refined.score > plain.score)
    }

    /// The trio pass, checked against the only thing that settles it: the whole space, enumerated.
    ///
    /// Cut the problem to three sockets whose augments cannot move and every coordinate that can move
    /// fits inside one trio, so the pass is exhaustive over it — and six options each is 216
    /// combinations, which can simply be counted out and compared.
    @Test
    func theTrioPassIsExactWhereTheWholeSpaceFitsInATrio() throws {
        guard let database = Self.database, let character = try Self.character(in: database) else { return }

        let whole = LoadoutProblemBuilder(database: database, catalogue: ItemCatalogue.build(from: database).items)
            .problem(for: character, skill: nil)
        try #require(whole.sockets.count >= 3)
        try #require(whole.componentStats.prefix(3).allSatisfy { $0.count >= 6 })

        let nothing = [ LoadoutStats() ]
        let problem = LoadoutProblem(
            sockets: Array(whole.sockets.prefix(3)),
            components: whole.components.prefix(3).map { Array($0.prefix(6)) },
            augments: whole.augments.prefix(3).map { Array($0.prefix(1)) },
            componentStats: whole.componentStats.prefix(3).map { Array($0.prefix(6)) },
            augmentStats: whole.augmentStats.prefix(3).map { _ in nothing },
            evaluator: whole.evaluator,
            worn: [LoadoutChoiceIndex](repeating: LoadoutChoiceIndex(), count: 3)
        )

        let target = LoadoutTarget.standard
        let optimizer = LoadoutOptimizer(problem: problem, target: target)
        let wanted = problem.evaluator.wanted(for: target)
        // No prices, so what the pass maximises is the plan's own score and nothing else — which is
        // what the count-out below can be compared against.
        let pressure = LoadoutPressure(wantedResistance: wanted)

        func read(_ stats: LoadoutStats) -> (short: Double, score: Double) {
            var missing = 0.0
            for index in wanted.indices where wanted[index] > 0 {
                missing += max(0, wanted[index] - stats.resistance[index])
            }
            return (
                missing,
                problem.evaluator.penalisedScore(
                    stats,
                    plus: LoadoutStats(),
                    goal: .defence,
                    under: pressure,
                    armorCeiling: 0
                )
            )
        }

        // Every one of the 216, so there is something to be exact against.
        var best = (short: Double.infinity, score: -Double.infinity)
        for first in 0 ..< 6 {
            for second in 0 ..< 6 {
                for third in 0 ..< 6 {
                    var stats = problem.evaluator.base
                    stats += problem.componentStats[0][first]
                    stats += problem.componentStats[1][second]
                    stats += problem.componentStats[2][third]
                    let read = read(stats)
                    if read.short < best.short - 0.000_1
                            || (read.short < best.short + 0.000_1 && read.score > best.score) {
                        best = read
                    }
                }
            }
        }

        var choice = [LoadoutChoiceIndex](repeating: LoadoutChoiceIndex(), count: 3)
        optimizer.refineTriples(&choice, goal: .defence, under: pressure) { _ in }
        let found = read(problem.evaluator.base + optimizer.stats(of: choice))

        #expect(abs(found.short - best.short) < 0.000_1)
        #expect(abs(found.score - best.score) < 0.000_1)
    }

    /// A plan is made for the difficulty being fought on, not the one the save sits in. Ultimate takes
    /// 50% off fire, cold, lightning, pierce and poison and 25% off the rest, so the same fittings read
    /// that much lower there — which is what the search then has to make up.
    @Test
    func readsResistancesOnTheDifficultyBeingPlannedFor() throws {
        guard let database = Self.database, let character = try Self.character(in: database) else { return }

        let builder = LoadoutProblemBuilder(database: database, catalogue: ItemCatalogue.build(from: database).items)
        let onNormal = builder.problem(for: character, skill: nil, readAt: .normal).evaluator.current
        let onUltimate = builder.problem(for: character, skill: nil, readAt: .ultimate).evaluator.current

        let halved: Set<ResistanceKind> = [ .fire, .cold, .lightning, .pierce, .acid ]
        for kind in LoadoutTarget.capped {
            let taken = onNormal.resistance(kind) - onUltimate.resistance(kind)
            #expect(
                abs(taken - (halved.contains(kind) ? 50 : 25)) < 0.01,
                "\(kind.title) loses \(taken) going to Ultimate"
            )
        }

        // Nothing but the resistances moves with it: the same gear is the same gear either way.
        #expect(abs(onNormal.armor - onUltimate.armor) < 0.01)
        #expect(abs(onNormal.offensiveAbility - onUltimate.offensiveAbility) < 0.01)
        #expect(abs(onNormal.health - onUltimate.health) < 0.01)
    }
}
