// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import SwiftUI

/// The resistances the game's character window lists.
///
/// This is deliberately its own type rather than a view onto `DamageType`: bleeding is a resistance with
/// no matching damage type of its own, and physical resistance behaves as flat damage reduction rather
/// than as one of the elemental family.
public enum ResistanceKind: String, CaseIterable, Sendable {
    case fire
    case cold
    case lightning
    case acid
    case vitality
    case aether
    case chaos
    case pierce
    case bleeding
    case physical

    public var title: String {
        switch self {
            case .fire: "Fire"
            case .cold: "Cold"
            case .lightning: "Lightning"
            case .acid: "Poison & Acid"
            case .vitality: "Vitality"
            case .aether: "Aether"
            case .chaos: "Chaos"
            case .pierce: "Pierce"
            case .bleeding: "Bleeding"
            case .physical: "Physical"
        }
    }

    /// The name where a grid has no room for the full one.
    public var shortTitle: String { self == .acid ? "Poison" : title }

    /// The resistance that stands against a damage type. Every type has one; only bleeding has no type.
    public init?(damage: DamageType) {
        switch damage {
            case .physical: self = .physical
            case .pierce: self = .pierce
            case .fire: self = .fire
            case .cold: self = .cold
            case .lightning: self = .lightning
            case .acid: self = .acid
            case .vitality: self = .vitality
            case .aether: self = .aether
            case .chaos: self = .chaos
            case .elemental: return nil
        }
    }

    /// The `.dbr` stem the game uses, which differs from the display name for several of these.
    private var stem: String {
        switch self {
            case .fire: "Fire"
            case .cold: "Cold"
            case .lightning: "Lightning"
            case .acid: "Poison"
            case .vitality: "Life"
            case .aether: "Aether"
            case .chaos: "Chaos"
            case .pierce: "Pierce"
            case .bleeding: "Bleeding"
            case .physical: "Physical"
        }
    }

    public var resistanceKey: String { "defensive\(stem)" }
    public var maximumKey: String { "defensive\(stem)MaxResist" }

    /// Fire, cold and lightning also take the blanket elemental bonus.
    public var isElemental: Bool { self == .fire || self == .cold || self == .lightning }

    /// Physical resistance is flat damage reduction and is not raised by "all resistances" bonuses.
    public var takesAllResistanceBonus: Bool { self != .physical }

    public var color: Color {
        switch self {
            case .fire: DamageType.fire.color
            case .cold: DamageType.cold.color
            case .lightning: DamageType.lightning.color
            case .acid: DamageType.acid.color
            case .vitality: DamageType.vitality.color
            case .aether: DamageType.aether.color
            case .chaos: DamageType.chaos.color
            case .pierce: DamageType.pierce.color
            case .bleeding: Color(red: 1.00, green: 0.42, blue: 0.42)
            case .physical: DamageType.physical.color
        }
    }
}
