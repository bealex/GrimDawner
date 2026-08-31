// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// Runs the search for every goal at once and reads each winner back as a whole character.
///
/// Each goal's runs are independent, so they go out as separate tasks and the machine's cores are all
/// put to work; a run reports how far along it is as it goes.
public enum LoadoutSearch {
    /// What one goal's best run came to.
    private struct Finding: Sendable {
        let goal: LoadoutGoal
        let choice: [LoadoutChoiceIndex]
        let score: Double
        let isFeasible: Bool
    }

    public static func plans(
        for character: ResolvedCharacter,
        database: GameDatabase,
        catalogue: [CataloguedItem],
        skill: ResolvedSkill?,
        target: LoadoutTarget,
        goals: [LoadoutGoal] = LoadoutGoal.allCases,
        progress: @escaping @Sendable (LoadoutProgress) -> Void
    ) async -> [LoadoutPlan] {
        let problem = LoadoutProblemBuilder(database: database, catalogue: catalogue)
            .problem(for: character, skill: skill)
        guard !problem.isEmpty else { return [] }

        let optimizer = LoadoutOptimizer(problem: problem, target: target)
        let findings = await withTaskGroup(of: Finding.self) { group in
            for goal in goals {
                for run in 0 ..< LoadoutOptimizer.runs {
                    group.addTask(priority: .userInitiated) {
                        let tracker = RunProgress(goal: goal, run: run, runs: LoadoutOptimizer.runs)
                        let choice = optimizer.run(goal: goal, seed: UInt64(run)) { fraction in
                            progress(tracker.reading(fraction))
                        }
                        let figures = optimizer.figures(of: choice)
                        return Finding(
                            goal: goal,
                            choice: choice,
                            score: problem.evaluator.score(figures, goal: goal),
                            isFeasible: optimizer.shortfalls(of: choice).isEmpty
                        )
                    }
                }
            }

            var found = [Finding]()
            for await finding in group { found.append(finding) }
            return found
        }

        // A plan that holds the resistances beats one that scores higher without them: the cap is the
        // one thing the search is not allowed to trade away.
        return goals.compactMap { goal in
            let best =
                findings
                .filter { $0.goal == goal }
                .max { left, right in
                    left.isFeasible == right.isFeasible
                        ? left.score < right.score
                        : (!left.isFeasible && right.isFeasible)
                }
            guard let best else { return nil }

            return plan(
                best,
                problem: problem,
                optimizer: optimizer,
                character: character,
                database: database,
                skill: skill
            )
        }
    }

    /// Reads one finding back as a whole character: the save with the plan's fittings socketed, built
    /// the way any character is, so the figures shown are the app's own and not the search's.
    private static func plan(
        _ finding: Finding,
        problem: LoadoutProblem,
        optimizer: LoadoutOptimizer,
        character: ResolvedCharacter,
        database: GameDatabase,
        skill: ResolvedSkill?
    ) -> LoadoutPlan {
        let choices = problem.sockets.indices.map { index in
            LoadoutChoice(
                socket: problem.sockets[index],
                component: problem.components[index][finding.choice[index].component],
                augment: problem.augments[index][finding.choice[index].augment]
            )
        }

        let rebuilt = CharacterBuilder(database: database)
            .build(save(of: character, wearing: choices), file: character.file)
        let damage = skill.map { EncounterEngine.damage(of: $0) } ?? [:]
        let thrown = damage.reduce(0) { running, entry in
            running + entry.value * (1 + (rebuilt.sheet.damageModifiers[entry.key] ?? 0) / 100)
        }

        return LoadoutPlan(
            goal: finding.goal,
            choices: choices,
            sheet: rebuilt.sheet,
            skillDamagePerSecond: damage.isEmpty ? nil : thrown * rebuilt.sheet.attacksPerSecond,
            shortfalls: optimizer.shortfalls(of: finding.choice),
            defensiveAbilityShortfall: max(
                0,
                optimizer.wantedAbility(for: finding.goal) - rebuilt.sheet.defensiveAbility
            )
        )
    }

    /// The character's save with the plan's fittings put in, which is what reading a plan back means.
    ///
    /// A component's completion bonus is left out: the game draws it at random from the component's own
    /// table, so no plan can promise one, and a plan reads as the least it is worth rather than the most.
    private static func save(of character: ResolvedCharacter, wearing choices: [LoadoutChoice]) -> Gdc.SaveFile {
        var save = character.save
        for choice in choices {
            switch choice.socket.place {
                case let .equipment(slot):
                    guard save.inventory.equipment.indices.contains(slot.rawValue) else { continue }

                    fit(&save.inventory.equipment[slot.rawValue].item, with: choice)
                case let .weapon(index):
                    let isAlternate = save.inventory.usesAlternateWeaponSet
                    if isAlternate, save.inventory.weaponSet2.indices.contains(index) {
                        fit(&save.inventory.weaponSet2[index].item, with: choice)
                    } else if !isAlternate, save.inventory.weaponSet1.indices.contains(index) {
                        fit(&save.inventory.weaponSet1[index].item, with: choice)
                    }
            }
        }
        return save
    }

    private static func fit(_ item: inout Gdc.Item, with choice: LoadoutChoice) {
        item.relicName = choice.component?.recordPath ?? ""
        item.relicBonus = ""
        item.augmentName = choice.augment?.recordPath ?? ""
    }

    /// One run's share of its goal's progress bar.
    private struct RunProgress: Sendable {
        let goal: LoadoutGoal
        let run: Int
        let runs: Int

        func reading(_ fraction: Double) -> LoadoutProgress {
            LoadoutProgress(
                goal: goal,
                fraction: (Double(run) + fraction) / Double(runs),
                stage: "Run \(run + 1) of \(runs)"
            )
        }
    }
}
