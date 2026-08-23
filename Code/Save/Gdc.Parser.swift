// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

extension Gdc {
    /// Reads a `player.gdc` into its blocks.
    ///
    /// Field layouts were verified against a Fangs of Asterkarn save (block versions: info 5, biography 8,
    /// inventory 11, stash 11, skills 8, stats 12) and the whole file is required to parse with nothing
    /// left over, so a format change in a future patch surfaces as an error rather than as silent garbage.
    enum Parser {
        private static let magic: UInt32 = 0x5843_4447  // "GDCX" little-endian

        static func parse(_ data: Data) throws -> SaveFile {
            var reader = try Reader(data)
            var save = SaveFile()

            guard try reader.integer() == magic else { throw Reader.Failure.unexpectedValue("file magic") }
            guard try reader.integer() == 2 else { throw Reader.Failure.unexpectedValue("preamble version") }

            save.header = try readHeader(&reader)
            guard try reader.peekInt() == 0 else { throw Reader.Failure.unexpectedValue("header terminator") }

            save.version = try reader.integer()
            _ = try reader.uniqueId()

            save.info = try readInfo(&reader)
            save.biography = try readBiography(&reader)
            save.inventory = try readInventory(&reader)
            save.stashTabs = try readStash(&reader)
            try skipUidBlocks(&reader)
            save.skills = try readSkills(&reader)
            save.loreNotes = try readLoreNotes(&reader)
            (save.currentFaction, save.factions) = try readFactions(&reader)

            // UI settings and seen tutorial pages: no nested blocks, nothing this app shows.
            for id: UInt32 in [ 14, 15 ] {
                let block = try reader.blockStart(expecting: id)
                try reader.skipToEnd(of: block)
                try reader.blockEnd(block)
            }

            save.stats = try readPlayStats(&reader)
            try skipTriggerTokens(&reader)

            guard
                reader.isAtEnd
            else {
                throw Reader.Failure.unexpectedValue("\(reader.remaining) trailing bytes")
            }

            return save
        }

        // MARK: - Header and identity

        private static func readHeader(_ reader: inout Reader) throws -> Header {
            var header = Header()
            header.name = try reader.wideString()
            header.isMale = try reader.flag()
            header.classTag = try reader.string()
            header.level = try reader.integer()
            header.isHardcore = try reader.flag()
            header.expansionFlags = try reader.byte()
            return header
        }

        private static func readInfo(_ reader: inout Reader) throws -> Info {
            let block = try reader.blockStart(expecting: 1)
            _ = try reader.integer()  // block version

            var info = Info()
            info.isInMainQuest = try reader.flag()
            info.hasBeenInGame = try reader.flag()
            info.lastDifficulty = try reader.byte()
            info.greatestDifficultyCompleted = try reader.byte()
            info.iron = try reader.integer()
            info.greatestSurvivalDifficultyCompleted = try reader.byte()
            info.tributes = try reader.integer()
            info.compassState = try reader.byte()
            info.showsSkillHelp = try reader.flag()
            info.alternateWeaponSet = try reader.flag()
            info.alternateWeaponSetEnabled = try reader.flag()
            info.texture = try reader.string()

            let filterCount = try reader.count(limit: 256)
            var filters = [UInt8]()
            filters.reserveCapacity(filterCount)
            for _ in 0 ..< filterCount { filters.append(try reader.byte()) }
            info.lootFilters = filters

            try reader.blockEnd(block)
            return info
        }

        private static func readBiography(_ reader: inout Reader) throws -> Biography {
            let block = try reader.blockStart(expecting: 2)
            _ = try reader.integer()

            var biography = Biography()
            biography.level = try reader.integer()
            biography.experience = try reader.integer()
            biography.attributePoints = try reader.integer()
            biography.skillPoints = try reader.integer()
            biography.devotionPoints = try reader.integer()
            biography.totalDevotionUnlocked = try reader.integer()
            biography.physique = try reader.float()
            biography.cunning = try reader.float()
            biography.spirit = try reader.float()
            biography.health = try reader.float()
            biography.energy = try reader.float()

            try reader.blockEnd(block)
            return biography
        }

        // MARK: - Items

        private static func readInventory(_ reader: inout Reader) throws -> Inventory {
            let block = try reader.blockStart(expecting: 3)
            _ = try reader.integer()

            var inventory = Inventory()
            inventory.hasData = try reader.flag()

            if inventory.hasData {
                let sackCount = try reader.count(limit: 64)
                inventory.focusedSack = try reader.integer()
                inventory.selectedSack = try reader.integer()

                for _ in 0 ..< sackCount {
                    let sackBlock = try reader.blockStart(expecting: 0)
                    _ = try reader.flag()
                    let items = try reader.array(InventoryItem.read)
                    inventory.sacks.append(Sack(items: items))
                    try reader.blockEnd(sackBlock)
                }

                inventory.usesAlternateWeaponSet = try reader.flag()
                inventory.equipment = try (0 ..< 12).map { _ in try EquipmentItem.read(&reader) }
                _ = try reader.flag()
                inventory.weaponSet1 = try (0 ..< 2).map { _ in try EquipmentItem.read(&reader) }
                _ = try reader.flag()
                inventory.weaponSet2 = try (0 ..< 2).map { _ in try EquipmentItem.read(&reader) }
            }

            try reader.blockEnd(block)
            return inventory
        }

        private static func readStash(_ reader: inout Reader) throws -> [StashTab] {
            let block = try reader.blockStart(expecting: 4)
            _ = try reader.integer()

            let tabCount = try reader.count(limit: 256)
            var tabs = [StashTab]()
            for _ in 0 ..< tabCount {
                let tabBlock = try reader.blockStart(expecting: 0)
                var stashTab = StashTab()
                stashTab.width = try reader.integer()
                stashTab.height = try reader.integer()
                stashTab.items = try reader.array(StashItem.read)
                _ = try reader.trailingBytes(of: tabBlock)
                tabs.append(stashTab)
                try reader.blockEnd(tabBlock)
            }

            try reader.blockEnd(block)
            return tabs
        }

        // MARK: - World progress

        /// Respawn points, riftgates, map markers and shrines — lists of world UIDs this app does not show.
        private static func skipUidBlocks(_ reader: inout Reader) throws {
            for id: UInt32 in [ 5, 6, 7, 17 ] {
                let block = try reader.blockStart(expecting: id)
                try reader.skipToEnd(of: block)
                try reader.blockEnd(block)
            }
        }

        private static func skipTriggerTokens(_ reader: inout Reader) throws {
            let block = try reader.blockStart(expecting: 10)
            try reader.skipToEnd(of: block)
            try reader.blockEnd(block)
        }

        // MARK: - Skills

        private static func readSkills(_ reader: inout Reader) throws -> Skills {
            let block = try reader.blockStart(expecting: 8)
            _ = try reader.integer()

            var skills = Skills()
            skills.skills = try reader.array { reader in
                var skill = Skill()
                skill.name = try reader.string()
                skill.level = try reader.integer()
                skill.isEnabled = try reader.flag()
                skill.unknownFlag = try reader.flag()
                skill.isDevotion = try reader.integer()
                skill.experience = try reader.integer()
                skill.isActive = try reader.integer()
                _ = try reader.byte()
                _ = try reader.byte()
                skill.autoCastSkill = try reader.string()
                skill.autoCastController = try reader.string()
                return skill
            }

            skills.masteriesAllowed = try reader.integer()
            skills.skillReclamationPointsUsed = try reader.integer()
            skills.devotionReclamationPointsUsed = try reader.integer()

            skills.itemSkills = try reader.array { reader in
                var itemSkill = ItemSkill()
                itemSkill.name = try reader.string()
                itemSkill.autoCastSkill = try reader.string()
                itemSkill.autoCastController = try reader.string()
                itemSkill.itemSlot = try reader.integer()
                itemSkill.itemName = try reader.string()
                return itemSkill
            }

            _ = try reader.trailingBytes(of: block)
            try reader.blockEnd(block)
            return skills
        }

        private static func readLoreNotes(_ reader: inout Reader) throws -> [String] {
            let block = try reader.blockStart(expecting: 12)
            _ = try reader.integer()
            let notes = try reader.array { try $0.string() }
            try reader.blockEnd(block)
            return notes
        }

        private static func readFactions(_ reader: inout Reader) throws -> (UInt32, [Faction]) {
            let block = try reader.blockStart(expecting: 13)
            _ = try reader.integer()

            let current = try reader.integer()
            let factions = try reader.array { reader in
                var faction = Faction()
                faction.isModified = try reader.flag()
                faction.isUnlocked = try reader.flag()
                faction.value = try reader.float()
                faction.positiveBoost = try reader.float()
                faction.negativeBoost = try reader.float()
                return faction
            }

            try reader.blockEnd(block)
            return (current, factions)
        }

        // MARK: - Play statistics

        private static func readPlayStats(_ reader: inout Reader) throws -> PlayStats {
            let block = try reader.blockStart(expecting: 16)
            _ = try reader.integer()

            var stats = PlayStats()
            stats.playTime = try reader.integer()
            stats.deaths = try reader.integer()
            stats.kills = try reader.integer()
            stats.experienceFromKills = try reader.integer()
            stats.healthPotionsUsed = try reader.integer()
            stats.energyPotionsUsed = try reader.integer()
            stats.maxLevel = try reader.integer()
            stats.hitsReceived = try reader.integer()
            stats.hitsInflicted = try reader.integer()
            stats.criticalHitsInflicted = try reader.integer()
            stats.criticalHitsReceived = try reader.integer()
            stats.greatestDamageInflicted = try reader.float()

            stats.perDifficulty = try (0 ..< 3).map { _ in
                var record = MonsterRecord()
                record.greatestKilledName = try reader.string()
                record.greatestKilledLevel = try reader.integer()
                record.greatestKilledLifeAndMana = try reader.integer()
                record.lastHit = try reader.string()
                record.lastHitBy = try reader.string()
                return record
            }

            stats.championKills = try reader.integer()
            stats.lastHit = try reader.float()
            stats.lastHitBy = try reader.float()
            stats.greatestDamageReceived = try reader.float()
            stats.heroKills = try reader.integer()
            stats.itemsCrafted = try reader.integer()
            stats.relicsCrafted = try reader.integer()
            stats.transcendentRelicsCrafted = try reader.integer()
            stats.mythicalRelicsCrafted = try reader.integer()
            stats.shrinesRestored = try reader.integer()
            stats.oneShotChestsOpened = try reader.integer()
            stats.loreNotesCollected = try reader.integer()
            stats.bossKills = try (0 ..< 3).map { _ in try reader.integer() }
            stats.survivalWaveTier = try reader.integer()
            stats.greatestSurvivalScore = try reader.integer()
            stats.cooldownRemaining = try reader.integer()
            stats.cooldownTotal = try reader.integer()

            _ = try reader.array { reader -> (String, UInt32) in (try reader.string(), try reader.integer()) }

            stats.shatteredRealmSouls = try reader.integer()
            stats.shatteredRealmEssence = try reader.integer()
            stats.skippedDifficulty = try reader.flag()
            _ = try reader.trailingBytes(of: block)

            try reader.blockEnd(block)
            return stats
        }
    }
}
