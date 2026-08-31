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

    /// How many sweeps one run takes. Coordinate ascent settles in a handful; the rest is the price
    /// climbing until the resistances are met.
    public static let sweeps = 80
    /// How many runs each goal makes, from a different starting point each time.
    public static let runs = 8

    /// One run of the search. `seed` picks its starting point: run 0 starts from what is worn.
    public func run(goal: LoadoutGoal, seed: UInt64, progress: (Double) -> Void) -> [LoadoutChoiceIndex] {
        var random = ItemRoll.Random(seed: UInt32(truncatingIfNeeded: seed))
        var choice = seed == 0 ? problem.worn : randomChoice(&random)
        // The running total carries the character underneath it, so a candidate is scored by adding
        // one option to it rather than by adding every socket up again.
        var total = problem.evaluator.base + stats(of: choice)
        var prices = [Double](repeating: 0, count: wanted.count)
        let wantedAbility = self.wantedAbility(for: goal)
        var abilityPrice = 0.0

        var best = choice
        var bestScore = -Double.infinity
        var hasFeasible = false

        for round in 0 ..< Self.sweeps {
            guard !Task.isCancelled else { break }

            sweep(&choice, &total, goal: goal, prices: prices, wantedAbility: wantedAbility, abilityPrice: abilityPrice)

            let figures = problem.evaluator.figures(absolute: total)
            let short = shortfall(figures)
            let value = problem.evaluator.score(figures, goal: goal)
            if short <= 0, value > bestScore || !hasFeasible {
                best = choice
                bestScore = value
                hasFeasible = true
            }

            // The price rises while anything is short and eases back once everything is met, so a run
            // that has already paid too much for resistances can spend the slack on the goal again.
            for index in prices.indices where wanted[index] > 0 {
                let missing = max(0, wanted[index] - figures.resistance[index])
                prices[index] = max(0, prices[index] + Self.step * (missing > 0 ? 1 : -0.25))
            }
            if wantedAbility > 0 {
                let missing = wantedAbility - figures.defensiveAbility
                abilityPrice = max(0, abilityPrice + Self.abilityStep * (missing > 0 ? 1 : -0.25))
            }
            progress(Double(round + 1) / Double(Self.sweeps))
        }

        // Nothing feasible was found, so the last state is the closest this run came.
        return hasFeasible ? best : choice
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

    // MARK: - The sweep

    /// How fast the price on a point of missing resistance climbs. Small enough that a run does not
    /// buy resistance it does not need on the first round it falls short.
    private static let step: Double = 0.004
    /// The same for a point of missing Defensive Ability. Ability runs in the thousands where a
    /// resistance runs in tens, so a point of it is charged proportionally less — but still enough
    /// that a run will give up armour and health to reach the figure it was asked for.
    private static let abilityStep: Double = 0.000_2

    /// Walks every coordinate once, taking each one's best option with the others held still.
    private func sweep(
        _ choice: inout [LoadoutChoiceIndex],
        _ total: inout LoadoutStats,
        goal: LoadoutGoal,
        prices: [Double],
        wantedAbility: Double,
        abilityPrice: Double
    ) {
        for socket in choice.indices {
            pick(
                &choice[socket].component,
                &total,
                among: problem.componentStats[socket],
                goal: goal,
                prices: prices,
                wantedAbility: wantedAbility,
                abilityPrice: abilityPrice
            )
            pick(
                &choice[socket].augment,
                &total,
                among: problem.augmentStats[socket],
                goal: goal,
                prices: prices,
                wantedAbility: wantedAbility,
                abilityPrice: abilityPrice
            )
        }
    }

    /// Takes the best of one coordinate's options, leaving `total` holding whichever it took.
    private func pick(
        _ chosen: inout Int,
        _ total: inout LoadoutStats,
        among options: [LoadoutStats],
        goal: LoadoutGoal,
        prices: [Double],
        wantedAbility: Double,
        abilityPrice: Double
    ) {
        total -= options[chosen]

        var best = chosen
        var bestScore = -Double.infinity
        for index in options.indices {
            let value = problem.evaluator.penalisedScore(
                total,
                plus: options[index],
                goal: goal,
                wanted: wanted,
                prices: prices,
                wantedAbility: wantedAbility,
                abilityPrice: abilityPrice
            )
            if value > bestScore {
                bestScore = value
                best = index
            }
        }

        chosen = best
        total += options[best]
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
