// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// One prefix or suffix in full: what it grants, and the band each figure rolls in.
///
/// An affix has no copy of its own — it is always worn by some item — so there is no seed here and no
/// rolled value, only the ends of each band.
struct ResolvedAffix: Identifiable, Sendable {
    let id = UUID()
    let path: String
    let name: String
    let kind: CataloguedAffix.Kind
    let rarity: ItemRarity
    let levelRequirement: Int
    /// How far a figure can move from the number the record holds, as a percentage.
    let jitter: Double
    let statsLowest: StatBlock
    let statsHighest: StatBlock
    let grantedSkills: [GrantedSkill]

    var summary: String {
        [ kind.rawValue, rarity.title, levelRequirement > 0 ? "Requires level \(levelRequirement)" : nil ]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
