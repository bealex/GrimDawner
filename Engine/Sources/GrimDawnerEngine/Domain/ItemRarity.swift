// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import SwiftUI

/// An item's quality tier, matching the game's `itemClassification` values.
///
/// Colours are the ones the game itself uses, read from `records/ui/styles/text/style_items*.dbr`.
public enum ItemRarity: Int, Comparable, Sendable {
    case broken = 0
    case common = 1
    case magical = 2
    case rare = 3
    case epic = 4
    case legendary = 5
    case quest = 6
    case relic = 7
    case component = 8
    case lore = 9
    case augment = 10

    public init(classification: String) {
        switch classification.lowercased() {
            case "common": self = .common
            case "magical": self = .magical
            case "rare": self = .rare
            case "epic": self = .epic
            case "legendary": self = .legendary
            case "quest": self = .quest
            case "broken": self = .broken
            case "lore": self = .lore
            default: self = .common
        }
    }

    /// Components, relics and augments carry no `itemClassification`: their record class is what they are.
    public init?(recordClass: String) {
        switch recordClass {
            case "ItemRelic": self = .component
            case "ItemArtifact": self = .relic
            case "ItemEnchantment": self = .augment
            default: return nil
        }
    }

    public static func < (lhs: ItemRarity, rhs: ItemRarity) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
            case .broken: "Broken"
            case .common: "Common"
            case .magical: "Magical"
            case .rare: "Rare"
            case .epic: "Epic"
            case .legendary: "Legendary"
            case .quest: "Quest"
            case .relic: "Relic"
            case .component: "Component"
            case .lore: "Lore"
            case .augment: "Augment"
        }
    }

    public var color: Color {
        switch self {
            case .broken: Color(red: 0.70, green: 0.70, blue: 0.70)
            case .common: Color(red: 1.00, green: 1.00, blue: 1.00)
            case .magical: Color(red: 0.95, green: 0.90, blue: 0.10)
            case .rare: Color(red: 0.25, green: 0.95, blue: 0.30)
            case .epic: Color(red: 0.20, green: 0.55, blue: 0.81)
            case .legendary: Color(red: 0.65, green: 0.22, blue: 1.00)
            case .quest: Color(red: 0.70, green: 0.60, blue: 0.80)
            case .relic: Color(red: 0.95, green: 0.64, blue: 0.30)
            case .component: Color(red: 0.57, green: 0.80, blue: 0.00)
            case .lore: Color(red: 0.76, green: 0.69, blue: 0.78)
            case .augment: Color(red: 0.40, green: 0.80, blue: 0.85)
        }
    }

    /// Whether items of this tier take random prefixes and suffixes.
    public var takesAffixes: Bool { self == .common || self == .magical || self == .rare }
}
