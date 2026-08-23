// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

extension Gdc {
    /// One item as the save stores it: DBR paths for every part, plus the seeds that rolled its values.
    struct Item: Sendable {
        var baseName = ""
        var prefixName = ""
        var suffixName = ""
        var modifierName = ""
        var transmuteName = ""
        var seed: UInt32 = 0
        var relicName = ""
        var relicBonus = ""
        var relicSeed: UInt32 = 0
        var augmentName = ""
        var augmentUnknown: UInt32 = 0
        var augmentSeed: UInt32 = 0
        /// Fangs of Asterkarn ascendant affix; empty on items from earlier expansions.
        var ascendedName = ""
        var ascendedSeed: UInt32 = 0
        var unknown1: UInt32 = 0
        var stackCount: UInt32 = 0
        var unknown2: UInt32 = 0
        var unknown3: UInt32 = 0

        var isEmpty: Bool { baseName.isEmpty }

        static func read(_ reader: inout Reader) throws -> Item {
            var item = Item()
            item.baseName = try reader.string()
            item.prefixName = try reader.string()
            item.suffixName = try reader.string()
            item.modifierName = try reader.string()
            item.transmuteName = try reader.string()
            item.seed = try reader.integer()
            item.relicName = try reader.string()
            item.relicBonus = try reader.string()
            item.relicSeed = try reader.integer()
            item.augmentName = try reader.string()
            item.augmentUnknown = try reader.integer()
            item.augmentSeed = try reader.integer()
            item.ascendedName = try reader.string()
            item.ascendedSeed = try reader.integer()
            item.unknown1 = try reader.integer()
            item.stackCount = try reader.integer()
            item.unknown2 = try reader.integer()
            item.unknown3 = try reader.integer()
            return item
        }
    }

    struct InventoryItem: Sendable {
        var item: Item
        var x: UInt32
        var y: UInt32

        static func read(_ reader: inout Reader) throws -> InventoryItem {
            InventoryItem(item: try Item.read(&reader), x: try reader.integer(), y: try reader.integer())
        }
    }

    struct StashItem: Sendable {
        var item: Item
        var x: Float
        var y: Float

        static func read(_ reader: inout Reader) throws -> StashItem {
            StashItem(item: try Item.read(&reader), x: try reader.float(), y: try reader.float())
        }
    }

    struct EquipmentItem: Sendable {
        var item: Item
        var isAttached: Bool

        static func read(_ reader: inout Reader) throws -> EquipmentItem {
            EquipmentItem(item: try Item.read(&reader), isAttached: try reader.flag())
        }
    }

    struct Sack: Sendable {
        var items: [InventoryItem] = []
    }

    struct StashTab: Sendable {
        var width: UInt32 = 0
        var height: UInt32 = 0
        var items: [StashItem] = []
    }

    struct Inventory: Sendable {
        var hasData = false
        var focusedSack: UInt32 = 0
        var selectedSack: UInt32 = 0
        var sacks: [Sack] = []
        var usesAlternateWeaponSet = false
        /// Twelve gear slots in the order the game writes them; see `EquipmentSlot`.
        var equipment: [EquipmentItem] = []
        var weaponSet1: [EquipmentItem] = []
        var weaponSet2: [EquipmentItem] = []
    }

    struct Header: Sendable {
        var name = ""
        var isMale = false
        var classTag = ""
        var level: UInt32 = 0
        var isHardcore = false
        var expansionFlags: UInt8 = 0
    }

    struct Info: Sendable {
        var isInMainQuest = false
        var hasBeenInGame = false
        var lastDifficulty: UInt8 = 0
        var greatestDifficultyCompleted: UInt8 = 0
        var iron: UInt32 = 0
        var greatestSurvivalDifficultyCompleted: UInt8 = 0
        var tributes: UInt32 = 0
        var compassState: UInt8 = 0
        var showsSkillHelp = false
        var alternateWeaponSet = false
        var alternateWeaponSetEnabled = false
        var texture = ""
        var lootFilters: [UInt8] = []
    }

    struct Biography: Sendable {
        var level: UInt32 = 0
        var experience: UInt32 = 0
        var attributePoints: UInt32 = 0
        var skillPoints: UInt32 = 0
        var devotionPoints: UInt32 = 0
        var totalDevotionUnlocked: UInt32 = 0
        var physique: Float = 0
        var cunning: Float = 0
        var spirit: Float = 0
        var health: Float = 0
        var energy: Float = 0
    }

    struct Skill: Sendable {
        var name = ""
        var level: UInt32 = 0
        var isEnabled = false
        var unknownFlag = false
        /// One for every constellation node, zero for mastery skills — a marker, not a rank.
        var isDevotion: UInt32 = 0
        var experience: UInt32 = 0
        var isActive: UInt32 = 0
        var autoCastSkill = ""
        var autoCastController = ""
    }

    struct ItemSkill: Sendable {
        var name = ""
        var autoCastSkill = ""
        var autoCastController = ""
        var itemSlot: UInt32 = 0
        var itemName = ""
    }

    struct Skills: Sendable {
        var skills: [Skill] = []
        var masteriesAllowed: UInt32 = 0
        var skillReclamationPointsUsed: UInt32 = 0
        var devotionReclamationPointsUsed: UInt32 = 0
        var itemSkills: [ItemSkill] = []
    }

    struct Faction: Sendable {
        var isModified = false
        var isUnlocked = false
        var value: Float = 0
        var positiveBoost: Float = 0
        var negativeBoost: Float = 0
    }

    struct MonsterRecord: Sendable {
        var greatestKilledName = ""
        var greatestKilledLevel: UInt32 = 0
        var greatestKilledLifeAndMana: UInt32 = 0
        var lastHit = ""
        var lastHitBy = ""
    }

    struct PlayStats: Sendable {
        var playTime: UInt32 = 0
        var deaths: UInt32 = 0
        var kills: UInt32 = 0
        var experienceFromKills: UInt32 = 0
        var healthPotionsUsed: UInt32 = 0
        var energyPotionsUsed: UInt32 = 0
        var maxLevel: UInt32 = 0
        var hitsReceived: UInt32 = 0
        var hitsInflicted: UInt32 = 0
        var criticalHitsInflicted: UInt32 = 0
        var criticalHitsReceived: UInt32 = 0
        var greatestDamageInflicted: Float = 0
        var perDifficulty: [MonsterRecord] = []
        var championKills: UInt32 = 0
        var lastHit: Float = 0
        var lastHitBy: Float = 0
        var greatestDamageReceived: Float = 0
        var heroKills: UInt32 = 0
        var itemsCrafted: UInt32 = 0
        var relicsCrafted: UInt32 = 0
        var transcendentRelicsCrafted: UInt32 = 0
        var mythicalRelicsCrafted: UInt32 = 0
        var shrinesRestored: UInt32 = 0
        var oneShotChestsOpened: UInt32 = 0
        var loreNotesCollected: UInt32 = 0
        var bossKills: [UInt32] = []
        var survivalWaveTier: UInt32 = 0
        var greatestSurvivalScore: UInt32 = 0
        var cooldownRemaining: UInt32 = 0
        var cooldownTotal: UInt32 = 0
        var shatteredRealmSouls: UInt32 = 0
        var shatteredRealmEssence: UInt32 = 0
        var skippedDifficulty = false
    }

    /// A parsed `player.gdc`.
    struct SaveFile: Sendable {
        var header = Header()
        var version: UInt32 = 0
        var info = Info()
        var biography = Biography()
        var inventory = Inventory()
        var stashTabs: [StashTab] = []
        var skills = Skills()
        var loreNotes: [String] = []
        var factions: [Faction] = []
        var currentFaction: UInt32 = 0
        var stats = PlayStats()
    }
}

extension Gdc.SaveFile {
    var difficulty: Difficulty { Difficulty(rawValue: info.lastDifficulty & 0b11) ?? .normal }
    var greatestDifficulty: Difficulty {
        Difficulty(rawValue: info.greatestDifficultyCompleted & 0b11) ?? .normal
    }
}

enum Difficulty: UInt8, CaseIterable, Sendable {
    case normal = 0
    case elite = 1
    case ultimate = 2

    var title: String {
        switch self {
            case .normal: "Normal"
            case .elite: "Elite"
            case .ultimate: "Ultimate"
        }
    }
}

/// The twelve gear slots, in the order `player.gdc` stores them.
enum EquipmentSlot: Int, CaseIterable, Sendable {
    case head, neck, chest, legs, feet, hands, ring1, ring2, waist, shoulders, medal, relic

    var title: String {
        switch self {
            case .head: "Head"
            case .neck: "Amulet"
            case .chest: "Chest"
            case .legs: "Legs"
            case .feet: "Feet"
            case .hands: "Hands"
            case .ring1: "Ring"
            case .ring2: "Ring"
            case .waist: "Belt"
            case .shoulders: "Shoulders"
            case .medal: "Medal"
            case .relic: "Relic"
        }
    }

    /// The `combatformulas.dbr` field giving how often this slot is the one struck.
    ///
    /// Only the six armour slots are hit regions; armour from anywhere else is added to every region, so
    /// those slots have no chance of their own.
    var hitRegionChanceKey: String? {
        switch self {
            case .head: "combatRegionHeadChance"
            case .shoulders: "combatRegionShouldersChance"
            case .chest: "combatRegionTorsoChance"
            case .hands: "combatRegionArmsChance"
            case .legs: "combatRegionLegsChance"
            case .feet: "combatRegionFeetChance"
            default: nil
        }
    }

    var symbolName: String {
        switch self {
            case .head: "brain.head.profile"
            case .neck: "link"
            case .chest: "tshirt"
            case .legs: "figure.walk"
            case .feet: "shoeprints.fill"
            case .hands: "hand.raised"
            case .ring1, .ring2: "circle.circle"
            case .waist: "minus.rectangle"
            case .shoulders: "figure.arms.open"
            case .medal: "seal"
            case .relic: "sparkles"
        }
    }
}
