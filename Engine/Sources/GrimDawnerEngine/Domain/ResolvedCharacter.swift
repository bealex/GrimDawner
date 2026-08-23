// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// The character an item is being read against: which skills its masteries hold, and which of those
/// it has spent a point on.
public struct SkillContext: Sendable {
    public let own: Set<String>
    public let learned: Set<String>
}

/// Ranks one worn item or set adds to a skill, and how far that reaches.
public struct SkillRankSource: Identifiable, Sendable {
    public enum Reach: Sendable {
        /// `+N to <skill>`, which names one skill.
        case skill
        /// `+N to <mastery>`, which lifts every skill of that mastery.
        case mastery
        /// `+N to all skills`.
        case everySkill
    }

    public let id = UUID()
    public let name: String
    public let iconPath: String
    public let levels: Int
    public let reach: Reach
    /// The skill or mastery it names, lowercased. Empty for a bonus to all skills.
    public let path: String

    public func reaches(skill skillPath: String, in masteryPath: String?) -> Bool {
        switch reach {
            case .skill: path == skillPath.lowercased()
            case .mastery: path == masteryPath?.lowercased()
            case .everySkill: true
        }
    }
}

/// What one worn item changes about one skill.
public struct SkillModification: Identifiable, Sendable {
    public let id = UUID()
    public let itemName: String
    public let iconPath: String
    public let changes: SkillChanges
}

/// One equipment slot with whatever occupies it.
public struct EquippedItem: Identifiable, Sendable {
    public let id = UUID()
    public let slot: EquipmentSlot
    public let item: ResolvedItem?
}

/// A weapon set — one or two hands, depending on what is held.
public struct WeaponSet: Identifiable, Sendable {
    public let id = UUID()
    public let index: Int
    public let items: [ResolvedItem?]
    public let isActive: Bool

    public var title: String { "Weapon Set \(index + 1)" }
}

/// A faction's standing, as the game's faction window reports it.
public struct ResolvedFaction: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let iconPath: String
    public let value: Double
    public let tier: String
    /// How far through the current tier the standing sits, from 0 to 1.
    public let progress: Double
    /// The reputation at which the next tier begins, or nil once the top tier is reached.
    public let nextThreshold: Double?
    /// False for the engine's own hostility groups, which you cannot earn reputation with.
    public let isReputation: Bool

    public var isHostile: Bool { value < 0 }
    public var isAtCap: Bool { nextThreshold == nil }

    /// Reads as "25,000" at the cap, or "18,200 / 25,000" while there is further to go.
    public var valueText: String {
        let current = value.formatted(.number.precision(.fractionLength(0)))
        guard let nextThreshold else { return current }

        return "\(current) / \(nextThreshold.formatted(.number.precision(.fractionLength(0))))"
    }
}

public extension [ResolvedFaction] {
    /// Alphabetical, by the viewer's own locale rather than by code point.
    public func sortedByName() -> [ResolvedFaction] {
        sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// A save file fully resolved against the game database: the object the whole UI reads from.
public struct ResolvedCharacter: Sendable {
    public let file: CharacterFile
    public let save: Gdc.SaveFile

    public let name: String
    public let className: String
    public let level: Int
    public let isHardcore: Bool
    public let difficulty: Difficulty
    public let greatestDifficulty: Difficulty

    public let masteries: [ResolvedMastery]
    public let devotion: DevotionMap
    public let itemGrantedSkills: [ResolvedSkill]

    /// What the worn gear changes about a skill, by the skill's record path, lowercased.
    public let skillModifications: [String: [SkillModification]]
    /// Every `+N to skill` the gear carries, kept whole so a skill can ask which of them reach it.
    public let skillRankSources: [SkillRankSource]
    /// What every pet the character has is given, as the game's own Pet Bonuses panel lists it.
    public let petBonuses: StatBlock

    /// Every skill the character's own masteries hold, lowercased, for telling a `+N` line about one
    /// of them from a `+N` line about a skill of some other class.
    public var masterySkillPaths: Set<String> {
        Set(masteries.flatMap { $0.skills.map { $0.recordPath.lowercased() } })
    }

    /// The skills the character has actually spent a point on; gear that changes any other one is
    /// changing nothing.
    public var learnedSkillPaths: Set<String> {
        Set(masteries.flatMap { mastery in
            mastery.skills.filter { $0.baseLevel > 0 }.map { $0.recordPath.lowercased() }
        })
    }

    /// What lifts one skill's rank, most generous first.
    public func rankSources(forSkill path: String, in masteryPath: String?) -> [SkillRankSource] {
        skillRankSources
            .filter { $0.reaches(skill: path, in: masteryPath) }
            .sorted { $0.levels > $1.levels }
    }

    public var skillContext: SkillContext {
        SkillContext(own: masterySkillPaths, learned: learnedSkillPaths)
    }

    /// The equipment panel's own geometry, absent only when the game's UI records cannot be read.
    public let doll: EquipmentDoll?
    public let equipment: [EquippedItem]
    public let weaponSets: [WeaponSet]
    /// The item sets the worn gear belongs to, and what that many pieces grant.
    public let sets: [ResolvedSet]
    public let inventory: [ResolvedItem]
    public let stash: [ResolvedItem]

    public let factions: [ResolvedFaction]
    /// What the difficulty takes off the character's resistances, which the game's own sheet shows too.
    public let difficultyPenalty: StatBlock
    public let sheet: CharacterSheet

    /// Standings you earn through play, which is what the game's faction window lists. Both groups read
    /// alphabetically: the save's own order is positional and says nothing to a reader.
    public var reputations: [ResolvedFaction] { factions.filter(\.isReputation).sortedByName() }
    /// The engine's hostility groups: monster families you are simply at war with.
    public var hostilityGroups: [ResolvedFaction] { factions.filter { !$0.isReputation }.sortedByName() }

    public var devotionPointsUsed: Int { devotion.takenStars }
    public var playTime: Duration { .seconds(Int(save.stats.playTime)) }

    /// Every texture the character's views will draw, ordered so what a tab shows first is decoded first.
    ///
    /// The stash alone runs to a couple of hundred items; warming those ahead of the skill panel would
    /// leave the panel waiting on artwork nothing is looking at yet.
    public var iconPaths: [String] {
        func artwork(of items: [ResolvedItem]) -> [String] {
            items.flatMap { [ $0.iconPath ] + $0.parts.map(\.iconPath) }
        }

        let ordered =
            masteries.flatMap { [ $0.panel.background, $0.panel.artwork, $0.panel.bar ] }
            + masteries.flatMap { mastery in mastery.skills.flatMap { [ $0.frame, $0.iconPath ] } }
            + (doll.map { [ $0.background ] + $0.slots.map(\.silhouette) } ?? [])
            + artwork(of: equippedItems)
            + itemGrantedSkills.map(\.iconPath)
            + factions.map(\.iconPath)
            + devotion.constellations.flatMap { constellation in
                [ constellation.iconPath ] + constellation.stars.map(\.sprite)
            }
            + [ devotion.tile ] + devotion.nebulas.map(\.bitmap)
            + artwork(of: inventory)
            + artwork(of: stash)

        var seen = Set<String>()
        return ordered.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    public var equippedItems: [ResolvedItem] {
        equipment.compactMap(\.item) + weaponSets.flatMap { $0.items.compactMap { $0 } }
    }
}

public extension Duration {
    /// Play time reads best as whole hours and minutes.
    public var hoursAndMinutes: String {
        let total = components.seconds
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
