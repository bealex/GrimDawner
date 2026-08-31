// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation
import GrimDawnerEngine

/// What the loadout search is doing and what it has found.
///
/// The search runs off the main thread across every core the machine has; this is where it reports
/// back to, so the tab can say how far along each goal is while it waits.
@Observable @MainActor
final class OptimizerState {
    private(set) var plans: [LoadoutPlan] = []
    private(set) var progress: [LoadoutGoal: Double] = [:]
    private(set) var stage: [LoadoutGoal: String] = [:]
    private(set) var isSearching = false
    /// True once a search has run, so an empty result reads as "nothing found" rather than as
    /// a tab that has not been asked anything yet.
    private(set) var hasSearched = false
    var selectedPlan: LoadoutPlan.ID?

    private var task: Task<Void, Never>?

    /// Runs the search. A second call replaces whatever is running.
    func search(
        character: ResolvedCharacter,
        database: GameDatabase,
        catalogue: [CataloguedItem],
        skill: ResolvedSkill?,
        target: LoadoutTarget
    ) {
        cancel()
        plans = []
        selectedPlan = nil
        progress = [:]
        stage = [:]
        isSearching = true
        hasSearched = true

        // Built here rather than inside the task: the runs report from threads of their own, and a
        // closure nested in one that already holds `self` weakly cannot capture it again.
        let note: @Sendable (LoadoutProgress) -> Void = { [weak self] reading in
            Task { @MainActor in self?.note(reading) }
        }

        task = Task { [weak self] in
            let found = await LoadoutSearch.plans(
                for: character,
                database: database,
                catalogue: catalogue,
                skill: skill,
                target: target,
                progress: note
            )
            guard !Task.isCancelled else { return }

            self?.finish(with: found)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isSearching = false
    }

    /// A run only ever moves its goal's bar forward, since eight of them report out of order.
    private func note(_ reading: LoadoutProgress) {
        guard isSearching, reading.fraction > (progress[reading.goal] ?? 0) else { return }

        progress[reading.goal] = reading.fraction
        stage[reading.goal] = reading.stage
    }

    private func finish(with found: [LoadoutPlan]) {
        plans = found
        selectedPlan = found.first?.id
        isSearching = false
        task = nil
    }
}
