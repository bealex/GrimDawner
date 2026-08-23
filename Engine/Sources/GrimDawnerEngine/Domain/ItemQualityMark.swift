// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// The badge the game stamps on an item's slot: a monster infrequent's gem, a double rare's pair of them,
/// the frame an ascendant affix adds.
///
/// The artwork is the game's, under `ui/character/`. Which piece goes with which item is decided in the
/// engine and stated nowhere in the data, so the pairing below follows the texture names.
public enum ItemQualityMark: String, Sendable {
    case monsterInfrequent = "item_monsterinfrequent"
    case doubleRare = "item_doublerare"
    case doubleRareMonsterInfrequent = "item_doubleraremonsterinfrequent"
    case awakened = "item_awakened"
    case ascendedCommon = "item_ascended_common"
    case ascendedMagic = "item_ascended_magic"
    case ascendedRare = "item_ascended_rare"
    case ascendedEpic = "item_ascended_epic"
    case ascendedLegendary = "item_ascended_legendary"
    case ascendedDoubleRare = "item_ascended_doublerare"
    case ascendedDoubleRareMonsterInfrequent = "item_ascended_doubleraremi"

    public var texturePath: String { "ui/character/\(rawValue).tex" }

    /// What the item is made of, as the badge cares about it.
    public struct Parts {
        /// The item's own record is rare — a monster infrequent, which is green without any affix.
        public var isMonsterInfrequent = false
        /// Both affix slots carry a rare affix, which is what "double rare" means.
        public var isDoubleRare = false
        public var isAscended = false
        /// Awakened items sit under `records/items/awakened/`, the only mark the data gives them.
        public var isAwakened = false
        public var rarity: ItemRarity = .common
    }

    /// Only armour and weapons wear these badges.
    public static func isGear(recordClass: String) -> Bool {
        recordClass.hasPrefix("Armor") || recordClass.hasPrefix("Weapon")
    }

    /// The badge these parts earn, or nothing for an item the game leaves unmarked.
    public init?(_ parts: Parts) {
        guard let mark = parts.isAscended ? Self.ascended(parts) : Self.plain(parts) else { return nil }

        self = mark
    }

    private static func plain(_ parts: Parts) -> ItemQualityMark? {
        switch (parts.isDoubleRare, parts.isMonsterInfrequent) {
            case (true, true): .doubleRareMonsterInfrequent
            case (true, false): .doubleRare
            case (false, true): .monsterInfrequent
            case (false, false): parts.isAwakened ? .awakened : nil
        }
    }

    /// An ascendant affix frames the item, in the colour of what it already was.
    private static func ascended(_ parts: Parts) -> ItemQualityMark {
        guard
            !parts.isDoubleRare
        else {
            return parts.isMonsterInfrequent ? .ascendedDoubleRareMonsterInfrequent : .ascendedDoubleRare
        }

        return switch parts.rarity {
            case .legendary: .ascendedLegendary
            case .epic: .ascendedEpic
            case .rare: .ascendedRare
            case .magical: .ascendedMagic
            default: .ascendedCommon
        }
    }
}
