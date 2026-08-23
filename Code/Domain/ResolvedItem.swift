// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// One part of an item — its base, an affix, a component, an augment — with the stats that part grants.
struct ItemPart: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case base = "Base"
        case prefix = "Prefix"
        case suffix = "Suffix"
        case modifier = "Crafting Bonus"
        case component = "Component"
        case completionBonus = "Completion Bonus"
        case augment = "Augment"
        case ascendant = "Ascendant Affix"
        case transmuter = "Transmuter"
    }

    let id = UUID()
    let kind: Kind
    let name: String
    let recordPath: String
    let iconPath: String
    let levelRequirement: Int
    let stats: StatBlock
    /// Skills the part grants outright, such as a component's granted ability.
    let grantedSkills: [GrantedSkill]

    /// What to call the part: its name, or simply what kind of part it is when it has none.
    /// True for the parts that roll together from the item's seed rather than adding a fixed amount.
    var isRolled: Bool {
        switch kind {
            case .base, .prefix, .suffix, .modifier: true
            default: false
        }
    }

    var title: String { name.isEmpty ? kind.rawValue : name }
    var subtitle: String? { name.isEmpty ? nil : kind.rawValue }
}

/// Something an item does to the character's skills.
struct GrantedSkill: Identifiable, Sendable {
    enum Kind: Sendable {
        /// The item confers a usable ability of its own.
        case granted
        /// The item adds ranks to a skill the character already has.
        case added
        /// The item alters how a skill behaves, the way an ascendant affix does.
        case enhanced
    }

    let id = UUID()
    let name: String
    let recordPath: String
    let level: Int
    let kind: Kind
    /// The skill as the game defines it, for the effects the sidebar lists under this line.
    let skill: ResolvedSkill?
    /// What sets the skill off, worded as the game words it: "(25% Chance on Attack)".
    var trigger: String?
    /// The mastery the skill belongs to, for a `+N` line about a skill outside the character's own.
    var mastery: String?
    /// What the item changes about the skill, for the `Skill_Modifier` an "Enhances" line points at.
    var modifications: SkillChanges?

    /// Some component skills carry no name anywhere in the database; they are known by what they do.
    var title: String { name.isEmpty ? "Granted ability" : name }

    var summary: String {
        switch kind {
            case .granted:
                [
                    level > 1 ? "Grants \(title) (level \(level))" : "Grants \(title)", trigger,
                ]
                .compactMap { $0 }.joined(separator: " ")
            case .added: "+\(level) to \(title)"
            case .enhanced: "Enhances \(title)"
        }
    }

    var symbolName: String {
        switch kind {
            case .granted: "wand.and.rays"
            case .added: "plus.circle"
            case .enhanced: "arrow.up.forward.circle"
        }
    }
}

/// An item from the save, resolved against the game database into something showable.
struct ResolvedItem: Identifiable, Sendable {
    let id = UUID()
    let raw: Gdc.Item
    let parts: [ItemPart]

    let iconPath: String
    let baseName: String
    let prefixName: String
    let suffixName: String
    let rarity: ItemRarity
    /// The game's own badge for what the item is — a monster infrequent, a double rare, an ascended
    /// piece — or empty when it wears none.
    let qualityMarkPath: String
    let itemLevel: Int
    let levelRequirement: Int
    let requirements: [String: Double]
    let stackCount: Int
    /// Flavour text from the record, when it has any.
    let flavourText: String

    /// Everything the item contributes: its own numbers as this copy rolled them, plus what its
    /// components and augments add.
    let stats: StatBlock
    /// The same, with every roll at the bottom and the top of its band — the range the game prints.
    let statsLowest: StatBlock
    let statsHighest: StatBlock
    /// What the item grants every pet the character has, which the game lists in a panel of its own.
    var petBonus = StatBlock()

    var displayName: String {
        [ prefixName, baseName, suffixName ]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var grantedSkills: [GrantedSkill] { parts.flatMap(\.grantedSkills) }

    var isEmpty: Bool { raw.isEmpty }
}

/// An item set the character has pieces of, and what wearing that many grants.
///
/// A set record holds its bonuses as arrays indexed by how many of its members are worn, which is the
/// same shape a skill's per-rank arrays have.
struct ResolvedSet: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let piecesWorn: Int
    let totalPieces: Int
    let bonuses: StatBlock
    /// Ranks the set adds to skills once enough of it is worn.
    let grantedSkills: [GrantedSkill]

    var isComplete: Bool { piecesWorn >= totalPieces }
    var summary: String { "\(piecesWorn) of \(totalPieces) pieces" }
}
