// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// One prefix or suffix in full: what it grants, and the band each figure rolls in.
///
/// An affix has no copy of its own — it is always worn by some item — so there is no seed here and no
/// rolled value, only the ends of each band.
public struct ResolvedAffix: Identifiable, Sendable {
    public let id = UUID()
    public let path: String
    public let name: String
    public let kind: CataloguedAffix.Kind
    public let rarity: ItemRarity
    public let levelRequirement: Int
    /// How far a figure can move from the number the record holds, as a percentage.
    public let jitter: Double
    public let statsLowest: StatBlock
    public let statsHighest: StatBlock
    public let grantedSkills: [GrantedSkill]

    public var summary: String {
        [ kind.rawValue, rarity.title, levelRequirement > 0 ? "Requires level \(levelRequirement)" : nil ]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
