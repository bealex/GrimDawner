// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// What a difficulty itself takes off a character's resistances.
///
/// The game states it in `records/game/balancingadjustment_mp+difficulty_players01.dbr` as an array of
/// four player counts per difficulty, so Ultimate single-player reads the ninth entry — −50% to fire,
/// cold, lightning, pierce and poison, −25% to aether, chaos, vitality, bleeding and life leech.
///
/// **Ascendant adds nothing to it.** Every record under `records/interactive/ascendant/` adjusts a
/// monster; there is no player row for it. A character fighting in Ascendant carries Ultimate's penalty
/// and no more, so planning for Ultimate is planning for Ascendant.
public enum DifficultyPenalty {
    public static func of(_ difficulty: Difficulty, in database: GameDatabase, resolver: SkillResolver) -> StatBlock {
        guard let record = database.record(recordPath) else { return StatBlock() }

        return resolver.stats(of: record, atLevel: Int(difficulty.rawValue) * playerCounts + 1)
    }

    private static let recordPath = "records/game/balancingadjustment_mp+difficulty_players01.dbr"
    /// The adjustment is written once per party size; a save read from disk is one character alone.
    private static let playerCounts = 4
}
