// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// One segment of the line the game draws from a skill to the modifiers along its row.
///
/// The game stores these as a list of tile textures, one per 80-unit step to the right of the skill; the
/// tile's name says whether that step is a plain run or the point where a branch drops away.
public struct SkillConnector: Sendable, Hashable {
    public enum Kind: Sendable {
        case straight
        case branchUp
        case branchDown
        case transmuterStub
    }

    /// How many grid steps to the right of the skill this segment sits.
    public let step: Int
    public let kind: Kind

    public init(step: Int, texture: String) {
        self.step = step
        let name = texture.lowercased()

        if name.contains("branchup") {
            kind = .branchUp
        } else if name.contains("branchdown") {
            kind = .branchDown
        } else if name.contains("transmuter") {
            kind = .transmuterStub
        } else {
            kind = .straight
        }
    }
}

/// A named number from a skill's record, as its in-game tooltip would list it.
public struct SkillParameter: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let value: String
}

/// A skill as the character has it: the points spent, plus whatever else adds to it.
/// What an item changes about a skill: the stats the catalogue knows, and the skill parameters —
/// cooldown, duration, targets — that no stat covers.
public struct SkillChanges: Sendable {
    public var stats = StatBlock()
    public var parameters: [SkillParameter] = []

    public var isEmpty: Bool { stats.hasNothingToShow && parameters.isEmpty }
}

/// What a skill puts on the field: the pet it summons, how long it stands, and what it can do.
public struct ResolvedSummon: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    /// Seconds it lives, or zero when it stands until it dies.
    public let timeToLive: Double
    /// How many of it can stand at once.
    public let limit: Int
    /// The pet's own record: its life, its resistances, whatever the catalogue knows.
    public let stats: StatBlock
    /// The abilities the pet uses, at the ranks its record gives them.
    public let skills: [ResolvedSkill]
}

public struct ResolvedSkill: Identifiable, Sendable {
    public let id = UUID()
    public let recordPath: String
    /// The record's own class, which says whether the skill is permanently in effect.
    public let recordClass: String
    /// The skill this one modifies, for the round nodes that hang off another skill.
    private(set) var modifies: String?
    public let name: String
    public let description: String
    /// Points the character actually spent.
    public let baseLevel: Int
    /// Extra ranks from devotion.
    public let devotionBonus: Int
    /// Extra ranks from gear — `+N to <skill>`, mastery bonuses and all-skill bonuses.
    public let itemBonus: Int
    /// Cap on spent points.
    public let maxLevel: Int
    /// Cap once bonuses are counted; the game calls this the ultimate level.
    public let ultimateLevel: Int
    public let tier: Int
    /// Top-left of the skill's button, in the game's own skill-window coordinates.
    public let position: CGPoint
    /// The button border the panel draws; round marks a modifier, square a skill of its own.
    public let frame: String
    /// Where the icon sits inside that border.
    public let iconOffset: CGPoint
    public let iconPath: String
    public let connectors: [SkillConnector]
    /// Cooldown, energy cost and the like, read at the skill's current rank.
    public let parameters: [SkillParameter]
    /// What the skill adds to every pet the character has, which the game prints as a block of its own.
    public let petBonus: StatBlock
    /// What it summons, for the skills that put something on the field.
    public let summon: ResolvedSummon?
    /// Everything the skill grants at its current rank.
    public let stats: StatBlock

    public var bonusLevel: Int { devotionBonus + itemBonus }

    public var isAlwaysOn: Bool { SkillResolver.isAlwaysOn(recordClass: recordClass) }

    /// The same skill, told which skill it hangs off.
    public func modifying(_ parent: String) -> ResolvedSkill {
        var copy = self
        copy.modifies = parent
        return copy
    }

    public var isModifier: Bool { recordClass == SkillResolver.modifierClass }

    /// The rank the skill actually operates at. Bonuses only carry a skill as far as its ultimate level;
    /// anything past that is wasted, which is why a one-point transmuter stays at one however much `+skill`
    /// the character is wearing.
    public var totalLevel: Int {
        guard baseLevel > 0 else { return 0 }

        return min(baseLevel + bonusLevel, ultimateLevel)
    }
    public var isLearned: Bool { baseLevel > 0 }
    public var isOverCapped: Bool { totalLevel > maxLevel }

    /// Spent, from devotion, from items — the breakdown the character window implies but never shows.
    public var levelBreakdown: String { "\(baseLevel).\(devotionBonus).\(itemBonus)" }

    public var levelText: String {
        guard bonusLevel > 0, baseLevel > 0 else { return "\(baseLevel)/\(maxLevel)" }

        return "\(baseLevel) +\(bonusLevel)"
    }
}

/// One mastery the character has invested in, with its panel of skills.
public struct ResolvedMastery: Identifiable, Sendable {
    public let id = UUID()
    public let recordPath: String
    public let name: String
    public let iconPath: String
    /// Points in the mastery bar itself.
    public let level: Int
    public let maxLevel: Int
    public let skills: [ResolvedSkill]
    /// Attributes and pools the mastery bar grants at its current level.
    public let bonuses: StatBlock
    /// The panel geometry the game lays these skills out on.
    public let panel: MasteryPanel

    public var spentPoints: Int { level + skills.reduce(0) { $0 + $1.baseLevel } }

    /// The skills permanently in effect: passives and toggled auras, plus the modifiers hanging off them.
    ///
    /// A modifier of an attack changes that attack and belongs nowhere near a character sheet; a modifier
    /// of an aura is in effect for as long as the aura is.
    public var sheetSkills: [ResolvedSkill] {
        let permanent = Set(skills.filter { $0.isLearned && $0.isAlwaysOn }.map { $0.recordPath.lowercased() })

        return skills.filter { skill in
            guard skill.isLearned else { return false }
            guard !skill.isAlwaysOn else { return true }

            return skill.modifies.map { permanent.contains($0.lowercased()) } ?? false
        }
    }
}
