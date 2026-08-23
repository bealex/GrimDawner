// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

public extension Gdc {
    /// One item as the save stores it: DBR paths for every part, plus the seeds that rolled its values.
    public struct Item: Sendable {
        /// A bare item, for reading one of the game's own records rather than a save entry.
        public init(baseName: String = "") { self.baseName = baseName }

        public var baseName = ""
        public var prefixName = ""
        public var suffixName = ""
        public var modifierName = ""
        public var transmuteName = ""
        public var seed: UInt32 = 0
        public var relicName = ""
        public var relicBonus = ""
        public var relicSeed: UInt32 = 0
        public var augmentName = ""
        public var augmentUnknown: UInt32 = 0
        public var augmentSeed: UInt32 = 0
        /// Fangs of Asterkarn ascendant affix; empty on items from earlier expansions.
        public var ascendedName = ""
        public var ascendedSeed: UInt32 = 0
        public var unknown1: UInt32 = 0
        public var stackCount: UInt32 = 0
        public var unknown2: UInt32 = 0
        public var unknown3: UInt32 = 0

        public var isEmpty: Bool { baseName.isEmpty }

        public static func read(_ reader: inout Reader) throws -> Item {
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

    public struct InventoryItem: Sendable {
        public var item: Item
        public var x: UInt32
        public var y: UInt32

        public static func read(_ reader: inout Reader) throws -> InventoryItem {
            InventoryItem(item: try Item.read(&reader), x: try reader.integer(), y: try reader.integer())
        }
    }

    public struct StashItem: Sendable {
        public var item: Item
        public var x: Float
        public var y: Float

        public static func read(_ reader: inout Reader) throws -> StashItem {
            StashItem(item: try Item.read(&reader), x: try reader.float(), y: try reader.float())
        }
    }

    public struct EquipmentItem: Sendable {
        public var item: Item
        public var isAttached: Bool

        public static func read(_ reader: inout Reader) throws -> EquipmentItem {
            EquipmentItem(item: try Item.read(&reader), isAttached: try reader.flag())
        }
    }

    public struct Sack: Sendable {
        public var items: [InventoryItem] = []
    }

    public struct StashTab: Sendable {
        public var width: UInt32 = 0
        public var height: UInt32 = 0
        public var items: [StashItem] = []
    }

    public struct Inventory: Sendable {
        public var hasData = false
        public var focusedSack: UInt32 = 0
        public var selectedSack: UInt32 = 0
        public var sacks: [Sack] = []
        public var usesAlternateWeaponSet = false
        /// Twelve gear slots in the order the game writes them; see `EquipmentSlot`.
        public var equipment: [EquipmentItem] = []
        public var weaponSet1: [EquipmentItem] = []
        public var weaponSet2: [EquipmentItem] = []
    }

    public struct Header: Sendable {
        public var name = ""
        public var isMale = false
        public var classTag = ""
        public var level: UInt32 = 0
        public var isHardcore = false
        public var expansionFlags: UInt8 = 0
    }

    public struct Info: Sendable {
        public var isInMainQuest = false
        public var hasBeenInGame = false
        public var lastDifficulty: UInt8 = 0
        public var greatestDifficultyCompleted: UInt8 = 0
        public var iron: UInt32 = 0
        public var greatestSurvivalDifficultyCompleted: UInt8 = 0
        public var tributes: UInt32 = 0
        public var compassState: UInt8 = 0
        public var showsSkillHelp = false
        public var alternateWeaponSet = false
        public var alternateWeaponSetEnabled = false
        public var texture = ""
        public var lootFilters: [UInt8] = []
    }

    public struct Biography: Sendable {
        public var level: UInt32 = 0
        public var experience: UInt32 = 0
        public var attributePoints: UInt32 = 0
        public var skillPoints: UInt32 = 0
        public var devotionPoints: UInt32 = 0
        public var totalDevotionUnlocked: UInt32 = 0
        public var physique: Float = 0
        public var cunning: Float = 0
        public var spirit: Float = 0
        public var health: Float = 0
        public var energy: Float = 0
    }

    public struct Skill: Sendable {
        public var name = ""
        public var level: UInt32 = 0
        public var isEnabled = false
        public var unknownFlag = false
        /// One for every constellation node, zero for mastery skills — a marker, not a rank.
        public var isDevotion: UInt32 = 0
        public var experience: UInt32 = 0
        public var isActive: UInt32 = 0
        public var autoCastSkill = ""
        public var autoCastController = ""
    }

    public struct ItemSkill: Sendable {
        public var name = ""
        public var autoCastSkill = ""
        public var autoCastController = ""
        public var itemSlot: UInt32 = 0
        public var itemName = ""
    }

    public struct Skills: Sendable {
        public var skills: [Skill] = []
        public var masteriesAllowed: UInt32 = 0
        public var skillReclamationPointsUsed: UInt32 = 0
        public var devotionReclamationPointsUsed: UInt32 = 0
        public var itemSkills: [ItemSkill] = []
    }

    public struct Faction: Sendable {
        public var isModified = false
        public var isUnlocked = false
        public var value: Float = 0
        public var positiveBoost: Float = 0
        public var negativeBoost: Float = 0
    }

    public struct MonsterRecord: Sendable {
        public var greatestKilledName = ""
        public var greatestKilledLevel: UInt32 = 0
        public var greatestKilledLifeAndMana: UInt32 = 0
        public var lastHit = ""
        public var lastHitBy = ""
    }

    public struct PlayStats: Sendable {
        public var playTime: UInt32 = 0
        public var deaths: UInt32 = 0
        public var kills: UInt32 = 0
        public var experienceFromKills: UInt32 = 0
        public var healthPotionsUsed: UInt32 = 0
        public var energyPotionsUsed: UInt32 = 0
        public var maxLevel: UInt32 = 0
        public var hitsReceived: UInt32 = 0
        public var hitsInflicted: UInt32 = 0
        public var criticalHitsInflicted: UInt32 = 0
        public var criticalHitsReceived: UInt32 = 0
        public var greatestDamageInflicted: Float = 0
        public var perDifficulty: [MonsterRecord] = []
        public var championKills: UInt32 = 0
        public var lastHit: Float = 0
        public var lastHitBy: Float = 0
        public var greatestDamageReceived: Float = 0
        public var heroKills: UInt32 = 0
        public var itemsCrafted: UInt32 = 0
        public var relicsCrafted: UInt32 = 0
        public var transcendentRelicsCrafted: UInt32 = 0
        public var mythicalRelicsCrafted: UInt32 = 0
        public var shrinesRestored: UInt32 = 0
        public var oneShotChestsOpened: UInt32 = 0
        public var loreNotesCollected: UInt32 = 0
        public var bossKills: [UInt32] = []
        public var survivalWaveTier: UInt32 = 0
        public var greatestSurvivalScore: UInt32 = 0
        public var cooldownRemaining: UInt32 = 0
        public var cooldownTotal: UInt32 = 0
        public var shatteredRealmSouls: UInt32 = 0
        public var shatteredRealmEssence: UInt32 = 0
        public var skippedDifficulty = false
    }

    /// A parsed `player.gdc`.
    public struct SaveFile: Sendable {
        public var header = Header()
        public var version: UInt32 = 0
        public var info = Info()
        public var biography = Biography()
        public var inventory = Inventory()
        public var stashTabs: [StashTab] = []
        public var skills = Skills()
        public var loreNotes: [String] = []
        public var factions: [Faction] = []
        public var currentFaction: UInt32 = 0
        public var stats = PlayStats()
    }
}

public extension Gdc.SaveFile {
    public var difficulty: Difficulty { Difficulty(rawValue: info.lastDifficulty & 0b11) ?? .normal }
    public var greatestDifficulty: Difficulty {
        Difficulty(rawValue: info.greatestDifficultyCompleted & 0b11) ?? .normal
    }
}

public enum Difficulty: UInt8, CaseIterable, Sendable {
    case normal = 0
    case elite = 1
    case ultimate = 2

    public var title: String {
        switch self {
            case .normal: "Normal"
            case .elite: "Elite"
            case .ultimate: "Ultimate"
        }
    }
}

/// The twelve gear slots, in the order `player.gdc` stores them.
public enum EquipmentSlot: Int, CaseIterable, Sendable {
    case head, neck, chest, legs, feet, hands, ring1, ring2, waist, shoulders, medal, relic

    public var title: String {
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
    public var hitRegionChanceKey: String? {
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

    public var symbolName: String {
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
