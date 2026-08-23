// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// The character an item is being read against: which skills its masteries hold, and which of those
/// it has spent a point on.
struct SkillContext: Sendable {
    let own: Set<String>
    let learned: Set<String>
}

/// What one worn item changes about one skill.
struct SkillModification: Identifiable, Sendable {
    let id = UUID()
    let itemName: String
    let iconPath: String
    let changes: SkillChanges
}

/// One equipment slot with whatever occupies it.
struct EquippedItem: Identifiable, Sendable {
    let id = UUID()
    let slot: EquipmentSlot
    let item: ResolvedItem?
}

/// A weapon set — one or two hands, depending on what is held.
struct WeaponSet: Identifiable, Sendable {
    let id = UUID()
    let index: Int
    let items: [ResolvedItem?]
    let isActive: Bool

    var title: String { "Weapon Set \(index + 1)" }
}

/// A faction's standing, as the game's faction window reports it.
struct ResolvedFaction: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let iconPath: String
    let value: Double
    let tier: String
    /// How far through the current tier the standing sits, from 0 to 1.
    let progress: Double
    /// The reputation at which the next tier begins, or nil once the top tier is reached.
    let nextThreshold: Double?
    /// False for the engine's own hostility groups, which you cannot earn reputation with.
    let isReputation: Bool

    var isHostile: Bool { value < 0 }
    var isAtCap: Bool { nextThreshold == nil }

    /// Reads as "25,000" at the cap, or "18,200 / 25,000" while there is further to go.
    var valueText: String {
        let current = value.formatted(.number.precision(.fractionLength(0)))
        guard let nextThreshold else { return current }

        return "\(current) / \(nextThreshold.formatted(.number.precision(.fractionLength(0))))"
    }
}

/// A save file fully resolved against the game database: the object the whole UI reads from.
struct ResolvedCharacter: Sendable {
    let file: CharacterFile
    let save: Gdc.SaveFile

    let name: String
    let className: String
    let level: Int
    let isHardcore: Bool
    let difficulty: Difficulty
    let greatestDifficulty: Difficulty

    let masteries: [ResolvedMastery]
    let devotion: DevotionMap
    let itemGrantedSkills: [ResolvedSkill]

    /// What the worn gear changes about a skill, by the skill's record path, lowercased.
    let skillModifications: [String: [SkillModification]]

    /// Every skill the character's own masteries hold, lowercased, for telling a `+N` line about one
    /// of them from a `+N` line about a skill of some other class.
    var masterySkillPaths: Set<String> {
        Set(masteries.flatMap { $0.skills.map { $0.recordPath.lowercased() } })
    }

    /// The skills the character has actually spent a point on; gear that changes any other one is
    /// changing nothing.
    var learnedSkillPaths: Set<String> {
        Set(masteries.flatMap { mastery in
            mastery.skills.filter { $0.baseLevel > 0 }.map { $0.recordPath.lowercased() }
        })
    }

    var skillContext: SkillContext {
        SkillContext(own: masterySkillPaths, learned: learnedSkillPaths)
    }

    /// The equipment panel's own geometry, absent only when the game's UI records cannot be read.
    let doll: EquipmentDoll?
    let equipment: [EquippedItem]
    let weaponSets: [WeaponSet]
    /// The item sets the worn gear belongs to, and what that many pieces grant.
    let sets: [ResolvedSet]
    let inventory: [ResolvedItem]
    let stash: [ResolvedItem]

    let factions: [ResolvedFaction]
    /// What the difficulty takes off the character's resistances, which the game's own sheet shows too.
    let difficultyPenalty: StatBlock
    let sheet: CharacterSheet

    /// Standings you earn through play, which is what the game's faction window lists.
    var reputations: [ResolvedFaction] { factions.filter(\.isReputation) }
    /// The engine's hostility groups: monster families you are simply at war with.
    var hostilityGroups: [ResolvedFaction] { factions.filter { !$0.isReputation } }

    var devotionPointsUsed: Int { devotion.takenStars }
    var playTime: Duration { .seconds(Int(save.stats.playTime)) }

    /// Every texture the character's views will draw, ordered so what a tab shows first is decoded first.
    ///
    /// The stash alone runs to a couple of hundred items; warming those ahead of the skill panel would
    /// leave the panel waiting on artwork nothing is looking at yet.
    var iconPaths: [String] {
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

    var equippedItems: [ResolvedItem] {
        equipment.compactMap(\.item) + weaponSets.flatMap { $0.items.compactMap { $0 } }
    }
}

extension Duration {
    /// Play time reads best as whole hours and minutes.
    var hoursAndMinutes: String {
        let total = components.seconds
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
