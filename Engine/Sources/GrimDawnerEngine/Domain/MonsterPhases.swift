// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// Which fight of a several-stage boss a record is.
///
/// A boss that changes shape partway through is written as one record per stage, and the game chains
/// them: a record that dies spawns the next through `poolToSpawnOnDeath`, a pool naming the records it
/// can put in its place. Those records are separate monsters — a different model, different skills, and
/// often loot on the last one alone — so a reader wants them apart, not collapsed into one line.
public enum MonsterPhases {
    /// The phase of every record that is part of a chain, by record path. A record in no chain is absent.
    ///
    /// Working this out reads every creature the game ships, which takes the better part of a second, so
    /// the answer is kept on the database and every caller after the first pays nothing.
    public static func map(in database: GameDatabase) -> [String: Int] {
        database.swept("monster-phases") { build(in: $0) }
    }

    private static func build(in database: GameDatabase) -> [String: Int] {
        var spawns = [String: [String]]()
        var names = [String: String]()

        database.sweep(prefix: "records/creatures/enemies/") { path, record in
            guard record.text("Class") == "Monster" else { return }

            names[path.lowercased()] = record.text("description")
            let pool = record.text("poolToSpawnOnDeath")
            guard !pool.isEmpty, let spawned = database.record(pool) else { return }

            // A pool names what it can put in the dying creature's place, weighted; the names are what
            // matters here, since a phase is a phase whichever of them comes up.
            let next = (1 ... 12).compactMap { index -> String? in
                let name = spawned.text("name\(index)")
                return name.isEmpty ? nil : name.lowercased()
            }
            guard !next.isEmpty else { return }

            spawns[path.lowercased()] = next
        }

        // Only a chain that stays the same creature is a phase: a boss that dies into a swarm of
        // something else has spawned adds, not changed shape.
        var followed = [String: [String]]()
        for (path, next) in spawns {
            let kept = next.filter { names[$0] != nil && names[$0] == names[path] }
            if !kept.isEmpty { followed[path] = kept }
        }
        guard !followed.isEmpty else { return [:] }

        let later = Set(followed.values.joined())
        var phases = [String: Int]()
        for start in followed.keys where !later.contains(start) {
            walk(start, phase: 1, through: followed, into: &phases)
        }
        return phases
    }

    /// Numbers one chain from its first record on. A pool that loops back is stopped by the phase
    /// already written, since a record cannot be two phases of the same fight.
    private static func walk(
        _ path: String,
        phase: Int,
        through followed: [String: [String]],
        into phases: inout [String: Int]
    ) {
        guard phases[path] == nil, phase <= 12 else { return }

        phases[path] = phase
        for next in followed[path] ?? [] {
            walk(next, phase: phase + 1, through: followed, into: &phases)
        }
    }
}
