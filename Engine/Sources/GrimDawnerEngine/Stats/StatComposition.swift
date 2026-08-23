// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// Which stats feed one figure of the character sheet.
///
/// Several of the game's bonuses are blanket ones — "+3% to all resistances", "+15% elemental
/// resistance", "+10% total damage" — and the figure they reach folds them in without naming them.
/// Anything reading a figure's own key alone, a breakdown most of all, would miss them.
public enum StatComposition {
    /// One stat feeding a figure: the key it is stored under, and what a line about it should say it
    /// is, empty for the figure's own key.
    public struct Part: Sendable {
        public let key: String
        public let note: String
    }

    public static func parts(feeding key: String) -> [Part] {
        var parts = [ Part(key: key, note: "") ]

        if let kind = ResistanceKind.allCases.first(where: { $0.resistanceKey == key }) {
            if kind.takesAllResistanceBonus {
                parts.append(Part(key: "defensiveAllResistance", note: "all resistances"))
            }
            if kind.isElemental {
                parts.append(Part(key: "defensiveElementalResistance", note: "elemental resistance"))
            }
        } else if ResistanceKind.allCases.contains(where: { $0.maximumKey == key }) {
            parts.append(Part(key: "defensiveAllMaxResist", note: "all maximum resistances"))
        } else if let type = DamageType.allCases.first(where: { $0.modifierKey == key }), type != .elemental {
            parts.append(Part(key: "offensiveTotalDamageModifier", note: "total damage"))
            if type.isElemental {
                parts.append(Part(key: "offensiveElementalModifier", note: "elemental damage"))
            }
        } else if let type = DamageType.allCases.first(where: { $0.minimumKey == key }), type.isElemental {
            // Flat elemental damage is that much of each of the three.
            parts.append(Part(key: DamageType.elemental.minimumKey, note: "elemental damage"))
        } else if DamageType.overTimeCases.contains(where: { $0.overTimeModifierKey == key }) {
            // The game's own panel says so: a character with +65% bleeding and +35% total damage reads
            // +100% on its Bleed Modifier line.
            parts.append(Part(key: "offensiveTotalDamageModifier", note: "total damage"))
        }
        return parts
    }

    /// What one figure comes to, blanket bonuses included.
    public static func total(feeding key: String, in stats: StatBlock) -> Double {
        parts(feeding: key).reduce(0) { $0 + stats.value($1.key) }
    }
}
