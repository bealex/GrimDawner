// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// How far the game's own range names reach.
///
/// A skill says which of them it is used at in `distanceProfile` — `Melee`, `Short`, `Moderate`, `Long`,
/// `Maximum`, `Boss` — and `records/game/gameengine.dbr` is what says how far each of those is.
public struct GameRanges: Sendable {
    public init(_ database: GameDatabase) {
        let record = database.record(Self.recordPath)
        var found = [String: Double]()
        for name in Self.names {
            let value = record?.number(name.prefix(1).lowercased() + name.dropFirst() + "Range") ?? 0
            if value > 0 { found[name.lowercased()] = value }
        }
        distances = found
    }

    /// How far one of the game's range names reaches, or nothing for a name it does not use.
    public func distance(named name: String) -> Double? { distances[name.lowercased()] }

    /// How far a skill is used from, out of its own `distanceProfile`. A skill that lists several — the
    /// game writes the whole vocabulary for one used at any range — states nothing about where it is
    /// used and reads as nothing, as does one that names none.
    public func distance(ofSkill skill: ArzRecord) -> Double? {
        let named = skill.text("distanceProfile").split(separator: ";").map(String.init)
        guard named.count == 1 else { return nil }

        return distance(named: named[0])
    }

    private static let recordPath = "records/game/gameengine.dbr"
    private static let names = [ "Melee", "Short", "Moderate", "Long", "Maximum", "Boss" ]

    private let distances: [String: Double]
}
