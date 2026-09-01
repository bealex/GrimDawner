// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// One part of an item — its base, an affix, a component, an augment — with the stats that part grants.
public struct ItemPart: Identifiable, Sendable {
    public enum Kind: String, Sendable {
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

    public let id = UUID()
    public let kind: Kind
    public let name: String
    public let recordPath: String
    public let iconPath: String
    public let levelRequirement: Int
    public let stats: StatBlock
    /// Skills the part grants outright, such as a component's granted ability.
    public let grantedSkills: [GrantedSkill]

    /// What to call the part: its name, or simply what kind of part it is when it has none.
    /// True for the parts that roll together from the item's seed rather than adding a fixed amount.
    public var isRolled: Bool {
        switch kind {
            case .base, .prefix, .suffix, .modifier: true
            default: false
        }
    }

    public var title: String { name.isEmpty ? kind.rawValue : name }
    public var subtitle: String? { name.isEmpty ? nil : kind.rawValue }
}

/// Something an item does to the character's skills.
public struct GrantedSkill: Identifiable, Sendable {
    public enum Kind: Sendable {
        /// The item confers a usable ability of its own.
        case granted
        /// The item adds ranks to a skill the character already has.
        case added
        /// The item alters how a skill behaves, the way an ascendant affix does.
        case enhanced
    }

    /// How far a `+N` line reaches: the skill it names, every skill of a mastery, or every skill at all.
    public enum Reach: Sendable {
        case skill
        case mastery
        case everySkill
    }

    public let id = UUID()
    public let name: String
    public let recordPath: String
    public let level: Int
    public let kind: Kind
    /// What the line covers. Only a `+N` says anything but `.skill`.
    public var reach: Reach = .skill
    /// The skill as the game defines it, for the effects the sidebar lists under this line.
    public let skill: ResolvedSkill?
    /// What sets the skill off, worded as the game words it: "(25% Chance on Attack)".
    public var trigger: String?
    /// The mastery the skill belongs to, for a `+N` line about a skill outside the character's own.
    public var mastery: String?
    /// What the item changes about the skill, for the `Skill_Modifier` an "Enhances" line points at.
    public var modifications: SkillChanges?

    /// Some component skills carry no name anywhere in the database; they are known by what they do.
    public var title: String {
        if reach == .everySkill { return "All skills" }

        return name.isEmpty ? "Granted ability" : name
    }

    /// What the ranks line calls what it is adding to.
    public var ranksTitle: String {
        switch reach {
            case .skill: "ranks"
            case .mastery: "to all skills in \(title)"
            case .everySkill: "to all skills"
        }
    }

    public var summary: String {
        switch kind {
            case .granted:
                [
                    level > 1 ? "Grants \(title) (level \(level))" : "Grants \(title)", trigger,
                ]
                .compactMap { $0 }.joined(separator: " ")
            case .added:
                switch reach {
                    case .skill: "+\(level) to \(title)"
                    case .mastery: "+\(level) to all skills in \(title)"
                    case .everySkill: "+\(level) to all skills"
                }
            case .enhanced: "Enhances \(title)"
        }
    }

    public var symbolName: String {
        switch kind {
            case .granted: "wand.and.rays"
            case .added: "plus.circle"
            case .enhanced: "arrow.up.forward.circle"
        }
    }
}

/// An item from the save, resolved against the game database into something showable.
public struct ResolvedItem: Identifiable, Sendable {
    public let id = UUID()
    public let raw: Gdc.Item
    public let parts: [ItemPart]

    public let iconPath: String
    public let baseName: String
    public let prefixName: String
    public let suffixName: String
    public let rarity: ItemRarity
    /// The game's own badge for what the item is — a monster infrequent, a double rare, an ascended
    /// piece — or empty when it wears none.
    public let qualityMarkPath: String
    public let itemLevel: Int
    public let levelRequirement: Int
    public let requirements: [String: Double]
    public let stackCount: Int
    /// Flavour text from the record, when it has any.
    public let flavourText: String

    /// Everything the item contributes: its own numbers as this copy rolled them, plus what its
    /// components and augments add.
    public let stats: StatBlock
    /// The same, with every roll at the bottom and the top of its band — the range the game prints.
    public let statsLowest: StatBlock
    public let statsHighest: StatBlock
    /// What the item grants every pet the character has, which the game lists in a panel of its own.
    public var petBonus = StatBlock()
    /// The model the game draws it with, for the world objects that carry one instead of an inventory
    /// icon — a chest, a breakable — and the skin that model wears.
    public var meshPath = ""
    public var texturePath = ""
    /// What a container can produce, most likely first, as a share of one thing that comes out of it.
    /// Empty for anything that holds nothing.
    public var contents = [MonsterLootEntry.Item]()
    /// How many things it drops when it is opened.
    public var drops = 0

    public var displayName: String {
        [ prefixName, baseName, suffixName ]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The item's own record. `baseName` beside it is the name the game prints, which is a different
    /// thing entirely: one is `records/items/…/b304e_necklace.dbr`, the other is "Ixall's Blaze".
    public var recordPath: String { raw.baseName }

    public var grantedSkills: [GrantedSkill] { parts.flatMap(\.grantedSkills) }

    public var isEmpty: Bool { raw.isEmpty }
}

/// An item set the character has pieces of, and what wearing that many grants.
///
/// A set record holds its bonuses as arrays indexed by how many of its members are worn, which is the
/// same shape a skill's per-rank arrays have.
public struct ResolvedSet: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let piecesWorn: Int
    public let totalPieces: Int
    public let bonuses: StatBlock
    /// Ranks the set adds to skills once enough of it is worn.
    public let grantedSkills: [GrantedSkill]

    public var isComplete: Bool { piecesWorn >= totalPieces }
    public var summary: String { "\(piecesWorn) of \(totalPieces) pieces" }
}
