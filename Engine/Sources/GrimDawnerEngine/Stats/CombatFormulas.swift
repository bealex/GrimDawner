// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// The game's own combat equations, which decide the figures no record states outright.
///
/// Offensive and defensive ability are the pair that matters here: both fold in an attribute and the
/// character's level, so neither can be read off a record. A monster is worked out exactly as a
/// character is — the game runs one set of equations for everything that fights.
public struct CombatFormulas {
    public init(database: GameDatabase) { self.database = database }

    public let database: GameDatabase

    private static let path = "records/game/combatformulas.dbr"

    public func ability(
        equationKey: String,
        flat: Double,
        attribute: Double,
        percent: Double,
        level: Double
    ) -> Double {
        let variables: [String: Double] = [
            "offensiveAbilityDV": flat,
            "defensiveAbilityDV": flat,
            "characterLevelDV": level,
            "dexterityDV": attribute,
            "strengthDV": attribute,
            "bonusDV": 0,
            "offensiveAbilityModifierDV": percent,
            "defensiveAbilityModifierDV": percent,
        ]

        guard
            let formulas = database.record(Self.path),
            case let source = formulas.text(equationKey),
            !source.isEmpty,
            let equation = try? Equation(source),
            let value = try? equation.value(variables)
        else {
            // Matches the shipped equations; only reached if the record is missing.
            return (flat + level * 12 + attribute * 0.5) * (1 + percent / 100) + 53
        }

        return value
    }
}
