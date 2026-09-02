// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// Searches for the components and augments that hold every resistance at its cap and make the most of
/// what is left over.
///
/// **The whole space cannot be walked.** Thirteen sockets, each taking one of a few dozen components
/// and one of a few dozen augments, come to something like 10^39 combinations; a machine counting a
/// billion a second would still be at it long after the sun burns out. So this does not enumerate.
///
/// It is coordinate ascent under a rising price on falling short. Every socket's component and every
/// socket's augment is one coordinate; a sweep walks each in turn and takes that coordinate's best
/// option while the rest are held still, which is exact for one move and cheap because a move is an
/// add and a subtract over a couple of dozen numbers. Resistances enter as a price per point short: the
/// price starts at nothing, so the first sweeps chase the goal alone, and it rises each round until
/// nothing is short — which is what makes the capped-resistance constraint bind without ever being
/// searched for directly. Several runs start from different places and the best feasible one wins,
/// since coordinate ascent finds a local best and different starts find different ones.
public struct LoadoutOptimizer: Sendable {
    public init(problem: LoadoutProblem, target: LoadoutTarget) {
        self.problem = problem
        self.target = target
        wanted = problem.evaluator.wanted(for: target)
    }

    public let problem: LoadoutProblem
    public let target: LoadoutTarget
    private let wanted: [Double]

    /// The Defensive Ability the goal is asked to reach. The attack plan is never held to it: it is
    /// there to stop the defensive ones trading ability away for armour and health.
    public func wantedAbility(for goal: LoadoutGoal) -> Double {
        goal == .attack ? 0 : target.minimumDefensiveAbility
    }

    /// The Armor Absorption the goal is asked to reach, held the same way and by the same plans.
    public func wantedAbsorption(for goal: LoadoutGoal) -> Double {
        goal == .attack ? 0 : target.minimumArmorAbsorption
    }

    /// How many sweeps one run takes. Coordinate ascent settles in a handful; the rest is the price
    /// climbing until the resistances are met.
    public static let sweeps = 80
    /// How many runs each goal makes, from a different starting point each time.
    public static let runs = 8
    /// How many times the pair pass may go round. One swap can open another, and it stops the moment a
    /// whole pass finds nothing, so the cap is only there to bound the worst case.
    public static let passes = 4
    /// How many times the triple pass may go round. One is minutes, so this is a hard stop rather
    /// than a bound on the worst case.
    public static let triplePasses = 2

    /// One run of the search. `seed` picks its starting point: run 0 starts from what is worn.
    public func run(goal: LoadoutGoal, seed: UInt64, progress: (Double) -> Void) -> [LoadoutChoiceIndex] {
        var random = ItemRoll.Random(seed: UInt32(truncatingIfNeeded: seed))
        var choice = seed == 0 ? problem.worn : randomChoice(&random)
        // The running total carries the character underneath it, so a candidate is scored by adding
        // one option to it rather than by adding every socket up again.
        var total = problem.evaluator.base + stats(of: choice)
        var pressure = LoadoutPressure(wantedResistance: wanted)
        pressure.wantedDefensiveAbility = wantedAbility(for: goal)
        pressure.wantedAbsorption = wantedAbsorption(for: goal)

        var best = choice
        var bestScore = -Double.infinity
        var hasFeasible = false

        for round in 0 ..< Self.sweeps {
            guard !Task.isCancelled else { break }

            sweep(&choice, &total, goal: goal, under: pressure)

            let figures = problem.evaluator.figures(absolute: total)
            let short = shortfall(figures)
            let value = score(figures, goal: goal)
            if short <= 0, value > bestScore || !hasFeasible {
                best = choice
                bestScore = value
                hasFeasible = true
            }

            // The price rises while anything is short and eases back once everything is met, so a run
            // that has already paid too much for resistances can spend the slack on the goal again.
            for index in pressure.resistancePrices.indices where wanted[index] > 0 {
                let missing = max(0, wanted[index] - figures.resistance[index])
                pressure.resistancePrices[index] = max(
                    0,
                    pressure.resistancePrices[index] + Self.step * (missing > 0 ? 1 : -0.25)
                )
            }
            if pressure.wantedDefensiveAbility > 0 {
                let missing = pressure.wantedDefensiveAbility - figures.defensiveAbility
                pressure.defensiveAbilityPrice = max(
                    0,
                    pressure.defensiveAbilityPrice + Self.abilityStep * (missing > 0 ? 1 : -0.25)
                )
            }
            if pressure.wantedAbsorption > 0 {
                let missing = pressure.wantedAbsorption - figures.armorAbsorption
                pressure.absorptionPrice = max(0, pressure.absorptionPrice + Self.step * (missing > 0 ? 1 : -0.25))
            }
            progress(Double(round + 1) / Double(Self.sweeps) * shares.sweeps)
        }

        // Nothing feasible was found, so the last state is the closest this run came.
        var settled = hasFeasible ? best : choice
        guard target.refinesPairs || target.refinesTriples else { return settled }

        // The pair pass first whatever was asked for: it is three hundred times cheaper than the triple
        // pass, and every move it makes is one the triple pass would otherwise find the expensive way.
        refine(&settled, goal: goal, under: pressure) { fraction in
            progress(shares.sweeps + shares.pairs * fraction)
        }
        guard target.refinesTriples else { return settled }

        refineTriples(&settled, goal: goal, under: pressure) { fraction in
            progress(shares.sweeps + shares.pairs + (1 - shares.sweeps - shares.pairs) * fraction)
        }
        return settled
    }

    /// How a run's progress bar is divided, which is nothing like how its work is: the triple pass is
    /// minutes where the sweeps are a tenth of a second.
    private var shares: (sweeps: Double, pairs: Double) {
        if target.refinesTriples { return (0.04, 0.06) }
        if target.refinesPairs { return (0.75, 0.25) }

        return (1, 0)
    }

    /// What a set of choices comes to, for a caller that has one and wants it read.
    public func stats(of choice: [LoadoutChoiceIndex]) -> LoadoutStats {
        var total = LoadoutStats()
        for (index, pick) in choice.enumerated() {
            total += problem.componentStats[index][pick.component]
            total += problem.augmentStats[index][pick.augment]
        }
        return total
    }

    public func figures(of choice: [LoadoutChoiceIndex]) -> LoadoutFigures {
        problem.evaluator.figures(stats(of: choice))
    }

    public func shortfalls(of choice: [LoadoutChoiceIndex]) -> [ResistanceKind: Double] {
        problem.evaluator.shortfalls(figures(of: choice), wanted: wanted)
    }

    /// What a plan is worth under this target, which is the ask's own armour ceiling included.
    public func score(_ figures: LoadoutFigures, goal: LoadoutGoal) -> Double {
        problem.evaluator.score(figures, goal: goal, armorCeiling: target.armorCeiling)
    }

    // MARK: - The sweep

    /// How fast the price on a point of missing resistance climbs. Small enough that a run does not
    /// buy resistance it does not need on the first round it falls short.
    private static let step: Double = 0.004
    /// The same for a point of missing Defensive Ability. Ability runs in the thousands where a
    /// resistance and absorption run in tens, so a point of it is charged proportionally less — but
    /// still enough that a run will give up armour and health to reach the figure it was asked for.
    private static let abilityStep: Double = 0.000_2

    /// Walks every coordinate once, taking each one's best option with the others held still.
    private func sweep(
        _ choice: inout [LoadoutChoiceIndex],
        _ total: inout LoadoutStats,
        goal: LoadoutGoal,
        under pressure: LoadoutPressure
    ) {
        for socket in choice.indices {
            pick(&choice[socket].component, &total, among: problem.componentStats[socket], goal: goal, under: pressure)
            pick(&choice[socket].augment, &total, among: problem.augmentStats[socket], goal: goal, under: pressure)
        }
    }

    /// Takes the best of one coordinate's options, leaving `total` holding whichever it took.
    private func pick(
        _ chosen: inout Int,
        _ total: inout LoadoutStats,
        among options: [LoadoutStats],
        goal: LoadoutGoal,
        under pressure: LoadoutPressure
    ) {
        total -= options[chosen]

        var best = chosen
        var bestScore = -Double.infinity
        for index in options.indices {
            let value = problem.evaluator.penalisedScore(
                total,
                plus: options[index],
                goal: goal,
                under: pressure,
                armorCeiling: target.armorCeiling
            )
            if value > bestScore {
                bestScore = value
                best = index
            }
        }

        chosen = best
        total += options[best]
    }

    // MARK: - The pair pass

    /// Every pair of coordinates walked together, which is what one at a time cannot see.
    ///
    /// Coordinate ascent settles where no single change helps, and two sockets that only pay off
    /// together — the half of a resistance neither can cap alone — are invisible to it. This tries every
    /// pair against every pair of their options, which is exact over pairs and takes in every single
    /// change besides, as the case where one of the two stays where it is. It goes round again while it
    /// keeps finding something, since one swap can open another.
    func refine(
        _ choice: inout [LoadoutChoiceIndex],
        goal: LoadoutGoal,
        under pressure: LoadoutPressure,
        progress: (Double) -> Void
    ) {
        var total = problem.evaluator.base + stats(of: choice)
        let coordinates = problem.sockets.count * 2

        for pass in 0 ..< Self.passes {
            var improved = false
            for first in 0 ..< coordinates {
                guard !Task.isCancelled else { return }

                for second in (first + 1) ..< coordinates {
                    if swapped(&choice, &total, first, second, goal: goal, under: pressure) { improved = true }
                }
                progress((Double(pass) + Double(first + 1) / Double(coordinates)) / Double(Self.passes))
            }
            guard improved else { return }
        }
    }

    /// Every triple of coordinates walked together, the whole of it — every option of each against
    /// every option of the other two, nothing shortlisted.
    ///
    /// It is to the pair pass what the pair pass is to the sweeps, one level up: three sockets that only
    /// pay off together are invisible to both. On a full character that is 2,600 triples over some two
    /// hundred million combinations a pass, which is minutes rather than seconds, so it runs only when
    /// it is asked for. The pair pass runs again between rounds, since a triple swap can leave a cheap
    /// pair move behind it.
    func refineTriples(
        _ choice: inout [LoadoutChoiceIndex],
        goal: LoadoutGoal,
        under pressure: LoadoutPressure,
        progress: (Double) -> Void
    ) {
        var total = problem.evaluator.base + stats(of: choice)
        let coordinates = problem.sockets.count * 2

        for pass in 0 ..< Self.triplePasses {
            var improved = false
            for first in 0 ..< coordinates {
                guard !Task.isCancelled else { return }

                for second in (first + 1) ..< coordinates {
                    for third in (second + 1) ..< coordinates {
                        if swappedThree(&choice, &total, first, second, third, goal: goal, under: pressure) {
                            improved = true
                        }
                    }
                }
                progress((Double(pass) + Double(first + 1) / Double(coordinates)) / Double(Self.triplePasses))
            }
            guard improved else { return }

            refine(&choice, goal: goal, under: pressure) { _ in }
            total = problem.evaluator.base + stats(of: choice)
        }
    }

    /// Three coordinates against every triple of their options, taking the best that neither drops a
    /// resistance further under its cap nor scores worse. True where it moved.
    ///
    /// The merit is two of the game's equations interpreted, so it is read only for a candidate the
    /// shortfall already allows — which on a plan that holds its caps is a small part of the whole.
    private func swappedThree(
        _ choice: inout [LoadoutChoiceIndex],
        _ total: inout LoadoutStats,
        _ first: Int,
        _ second: Int,
        _ third: Int,
        goal: LoadoutGoal,
        under pressure: LoadoutPressure
    ) -> Bool {
        let firstOptions = options(at: first)
        let secondOptions = options(at: second)
        let thirdOptions = options(at: third)
        let wasFirst = index(in: choice, at: first)
        let wasSecond = index(in: choice, at: second)
        let wasThird = index(in: choice, at: third)

        var bestShort = shortfall(of: total)
        var bestScore = merit(total, goal: goal, under: pressure)
        var bestFirst = wasFirst
        var bestSecond = wasSecond
        var bestThird = wasThird

        total -= firstOptions[wasFirst]
        total -= secondOptions[wasSecond]
        total -= thirdOptions[wasThird]

        for candidate in firstOptions.indices {
            total += firstOptions[candidate]
            for other in secondOptions.indices {
                total += secondOptions[other]
                for last in thirdOptions.indices {
                    total += thirdOptions[last]
                    let short = shortfall(of: total)
                    if short < bestShort + Self.margin {
                        let value = merit(total, goal: goal, under: pressure)
                        if short < bestShort - Self.margin || value > bestScore + Self.margin {
                            bestShort = short
                            bestScore = value
                            bestFirst = candidate
                            bestSecond = other
                            bestThird = last
                        }
                    }
                    total -= thirdOptions[last]
                }
                total -= secondOptions[other]
            }
            total -= firstOptions[candidate]
        }

        total += firstOptions[bestFirst]
        total += secondOptions[bestSecond]
        total += thirdOptions[bestThird]
        setIndex(&choice, at: first, to: bestFirst)
        setIndex(&choice, at: second, to: bestSecond)
        setIndex(&choice, at: third, to: bestThird)
        return bestFirst != wasFirst || bestSecond != wasSecond || bestThird != wasThird
    }

    /// Two coordinates against every pair of their options, taking the best that neither drops a
    /// resistance further under its cap nor scores worse. True where it moved.
    private func swapped(
        _ choice: inout [LoadoutChoiceIndex],
        _ total: inout LoadoutStats,
        _ first: Int,
        _ second: Int,
        goal: LoadoutGoal,
        under pressure: LoadoutPressure
    ) -> Bool {
        let firstOptions = options(at: first)
        let secondOptions = options(at: second)
        let wasFirst = index(in: choice, at: first)
        let wasSecond = index(in: choice, at: second)

        total -= firstOptions[wasFirst]
        total -= secondOptions[wasSecond]

        // Where it already stands, so nothing moves for a tie: a swap worth nothing would only send the
        // pass round again.
        total += firstOptions[wasFirst]
        total += secondOptions[wasSecond]
        var bestShort = shortfall(of: total)
        var bestScore = merit(total, goal: goal, under: pressure)
        total -= secondOptions[wasSecond]
        total -= firstOptions[wasFirst]

        var bestFirst = wasFirst
        var bestSecond = wasSecond
        for candidate in firstOptions.indices {
            total += firstOptions[candidate]
            for other in secondOptions.indices {
                total += secondOptions[other]
                let short = shortfall(of: total)
                // Scored only where the shortfall allows it at all: the merit is two equations, and
                // this runs a few hundred thousand times a pass.
                if short < bestShort + Self.margin {
                    let value = merit(total, goal: goal, under: pressure)
                    if short < bestShort - Self.margin || value > bestScore + Self.margin {
                        bestShort = short
                        bestScore = value
                        bestFirst = candidate
                        bestSecond = other
                    }
                }
                total -= secondOptions[other]
            }
            total -= firstOptions[candidate]
        }

        total += firstOptions[bestFirst]
        total += secondOptions[bestSecond]
        setIndex(&choice, at: first, to: bestFirst)
        setIndex(&choice, at: second, to: bestSecond)
        return bestFirst != wasFirst || bestSecond != wasSecond
    }

    /// Close enough to call two plans the same. Without it a swap worth a billionth would keep the pass
    /// going round for ever.
    private static let margin = 0.000_001
    /// One empty option, so scoring a whole total allocates nothing.
    private static let nothing = LoadoutStats()

    /// A coordinate is one socket's component or its augment, so socket *n* holds coordinates 2n and
    /// 2n + 1.
    private func options(at coordinate: Int) -> [LoadoutStats] {
        coordinate.isMultiple(of: 2)
            ? problem.componentStats[coordinate / 2] : problem.augmentStats[coordinate / 2]
    }

    private func index(in choice: [LoadoutChoiceIndex], at coordinate: Int) -> Int {
        coordinate.isMultiple(of: 2) ? choice[coordinate / 2].component : choice[coordinate / 2].augment
    }

    private func setIndex(_ choice: inout [LoadoutChoiceIndex], at coordinate: Int, to index: Int) {
        if coordinate.isMultiple(of: 2) {
            choice[coordinate / 2].component = index
        } else {
            choice[coordinate / 2].augment = index
        }
    }

    private func merit(_ total: LoadoutStats, goal: LoadoutGoal, under pressure: LoadoutPressure) -> Double {
        problem.evaluator.penalisedScore(
            total,
            plus: Self.nothing,
            goal: goal,
            under: pressure,
            armorCeiling: target.armorCeiling
        )
    }

    /// How far short of the caps a running total falls, read off the stats rather than off figures
    /// built for it: the pair pass asks this hundreds of thousands of times.
    private func shortfall(of stats: LoadoutStats) -> Double {
        var missing = 0.0
        for index in wanted.indices where wanted[index] > 0 {
            missing += max(0, wanted[index] - stats.resistance[index])
        }
        return missing
    }

    private func shortfall(_ figures: LoadoutFigures) -> Double {
        var missing = 0.0
        for index in wanted.indices where wanted[index] > 0 {
            missing += max(0, wanted[index] - figures.resistance[index])
        }
        return missing
    }

    private func randomChoice(_ random: inout ItemRoll.Random) -> [LoadoutChoiceIndex] {
        func index(_ count: Int) -> Int {
            count > 0 ? Int(abs(random.next()) % Int64(count)) : 0
        }

        return problem.sockets.indices.map { socket in
            LoadoutChoiceIndex(
                component: index(problem.componentStats[socket].count),
                augment: index(problem.augmentStats[socket].count)
            )
        }
    }
}
