// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import SwiftUI

/// The damage types Grim Dawn tracks, with the `.dbr` field stems they use.
///
/// The database spells several of them differently from the UI — vitality is `Life`, acid is `Poison`,
/// bleeding is `SlowBleeding` — so the raw stems live here rather than being spread through the engine.
enum DamageType: String, CaseIterable, Sendable {
    case physical = "Physical"
    case pierce = "Pierce"
    case fire = "Fire"
    case cold = "Cold"
    case lightning = "Lightning"
    case acid = "Poison"
    case vitality = "Life"
    case aether = "Aether"
    case chaos = "Chaos"
    case elemental = "Elemental"

    /// Types that also exist as a damage-over-time variant. Pierce appears here as bleeding, which is the
    /// name the game gives its pierce-family damage over time.
    static let overTimeCases: [DamageType] = [ .physical, .fire, .cold, .lightning, .acid, .vitality, .pierce ]

    var title: String {
        switch self {
            case .physical: "Physical"
            case .pierce: "Pierce"
            case .fire: "Fire"
            case .cold: "Cold"
            case .lightning: "Lightning"
            case .acid: "Acid"
            case .vitality: "Vitality"
            case .aether: "Aether"
            case .chaos: "Chaos"
            case .elemental: "Elemental"
        }
    }

    var overTimeTitle: String {
        switch self {
            case .physical: "Internal Trauma"
            case .fire: "Burn"
            case .cold: "Frostburn"
            case .lightning: "Electrocute"
            case .acid: "Poison"
            case .vitality: "Vitality Decay"
            case .pierce: "Bleeding"
            default: title + " over Time"
        }
    }

    var color: Color {
        switch self {
            case .physical: Color(red: 0.85, green: 0.82, blue: 0.72)
            case .pierce: Color(red: 0.72, green: 0.74, blue: 0.78)
            case .fire: Color(red: 0.95, green: 0.48, blue: 0.20)
            case .cold: Color(red: 0.45, green: 0.75, blue: 0.98)
            case .lightning: Color(red: 0.98, green: 0.86, blue: 0.35)
            case .acid: Color(red: 0.56, green: 0.82, blue: 0.28)
            case .vitality: Color(red: 0.88, green: 0.36, blue: 0.62)
            case .aether: Color(red: 0.62, green: 0.80, blue: 0.86)
            case .chaos: Color(red: 0.70, green: 0.32, blue: 0.85)
            case .elemental: Color(red: 0.95, green: 0.72, blue: 0.35)
        }
    }

    // MARK: - Database field names

    var minimumKey: String { "offensive\(rawValue)Min" }
    var maximumKey: String { "offensive\(rawValue)Max" }
    var modifierKey: String { "offensive\(rawValue)Modifier" }
    var baseMinimumKey: String { "offensiveBase\(rawValue)Min" }
    var baseMaximumKey: String { "offensiveBase\(rawValue)Max" }

    var overTimeMinimumKey: String { "offensiveSlow\(overTimeStem)Min" }
    var overTimeMaximumKey: String { "offensiveSlow\(overTimeStem)Max" }
    var overTimeModifierKey: String { "offensiveSlow\(overTimeStem)Modifier" }
    var overTimeDurationMinimumKey: String { "offensiveSlow\(overTimeStem)DurationMin" }
    var overTimeDurationModifierKey: String { "offensiveSlow\(overTimeStem)DurationModifier" }

    var retaliationMinimumKey: String { "retaliation\(rawValue)Min" }
    var retaliationMaximumKey: String { "retaliation\(rawValue)Max" }
    var retaliationModifierKey: String { "retaliation\(rawValue)Modifier" }

    /// Resistance field for this type; the elemental case covers fire, cold and lightning at once.
    var resistanceKey: String {
        self == .elemental ? "defensiveElementalResistance" : "defensive\(rawValue)"
    }

    private var overTimeStem: String { self == .pierce ? "Bleeding" : rawValue }
}
