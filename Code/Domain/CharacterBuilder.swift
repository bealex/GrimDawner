// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// Resolves a parsed save against the game database into the model the UI renders.
struct CharacterBuilder {
    let database: GameDatabase

    func build(_ save: Gdc.SaveFile, file: CharacterFile) -> ResolvedCharacter {
        let skills = SkillResolver(database: database)
        let items = ItemResolver(database: database, skills: skills)
        let devotions = DevotionResolver(database: database, skills: skills)

        let equipment = equipment(from: save.inventory, using: items)
        let weaponSets = weaponSets(from: save.inventory, using: items)
        let equipped = equipment.compactMap(\.item) + weaponSets.flatMap { $0.items.compactMap { $0 } }

        var gearStats = StatBlock()
        for item in equipped { gearStats.merge(item.stats) }

        // A set's bonuses are worn gear too, and they add skill ranks, so they land before the skills do.
        let sets = items.sets(worn: equipped)
        for set in sets { gearStats.merge(set.bonuses) }

        // Skill levels depend on gear bonuses, and the passives they unlock then feed back into the sheet,
        // so gear is resolved first and skills second.
        let devotionStats = devotions.stats(from: save)
        let masteries = skills.masteries(from: save, gearBonuses: gearStats, devotionBonuses: devotionStats)

        let penalty = difficultyPenalty(for: save.difficulty, resolver: skills)

        var total = gearStats
        for mastery in masteries { total.merge(mastery.bonuses) }
        total.merge(devotionStats)
        total.merge(passiveStats(masteries: masteries, resolver: skills))
        total.merge(penalty)

        let claimed = Set(
            masteries.flatMap { mastery in mastery.skills.map { $0.recordPath.lowercased() } }
                + masteries.map { $0.recordPath.lowercased() }
        )

        return ResolvedCharacter(
            file: file,
            save: save,
            name: save.header.name,
            className: database.text(save.header.classTag),
            level: Int(save.biography.level),
            isHardcore: save.header.isHardcore,
            difficulty: save.difficulty,
            greatestDifficulty: save.greatestDifficulty,
            masteries: masteries,
            devotion: devotions.map(from: save),
            itemGrantedSkills: skills.looseSkills(from: save, claimed: claimed),
            skillModifications: Self.skillModifications(of: equipped),
            doll: LayoutResolver(database: database).equipmentDoll(),
            equipment: equipment,
            weaponSets: weaponSets,
            sets: sets,
            inventory: save.inventory.sacks.flatMap { $0.items.compactMap { items.resolve($0.item) } },
            stash: save.stashTabs.flatMap { $0.items.compactMap { items.resolve($0.item) } },
            factions: factions(from: save),
            difficultyPenalty: penalty,
            sheet: StatEngine(database: database).sheet(
                for: save,
                contributions: total,
                bodyArmor: bodyArmor(from: equipment)
            )
        )
    }

    /// What each worn item changes about a skill, gathered under the skill it changes.
    private static func skillModifications(of items: [ResolvedItem]) -> [String: [SkillModification]] {
        var changes = [String: [SkillModification]]()
        for item in items {
            for granted in item.grantedSkills where granted.kind == .enhanced {
                guard let modifications = granted.modifications, !modifications.isEmpty else { continue }

                changes[granted.recordPath.lowercased(), default: []].append(SkillModification(
                    itemName: item.displayName,
                    iconPath: item.iconPath,
                    changes: modifications
                ))
            }
        }
        return changes
    }

    /// Armour on the six hit-region slots, which the engine weights rather than sums.
    private func bodyArmor(from equipment: [EquippedItem]) -> [EquipmentSlot: Double] {
        var values = [EquipmentSlot: Double]()
        for equipped in equipment where equipped.slot.hitRegionChanceKey != nil {
            values[equipped.slot] = equipped.item?.stats.value("defensiveProtection") ?? 0
        }
        return values
    }

    private func equipment(from inventory: Gdc.Inventory, using items: ItemResolver) -> [EquippedItem] {
        EquipmentSlot.allCases.map { slot in
            EquippedItem(
                slot: slot,
                item: inventory.equipment.indices.contains(slot.rawValue)
                    ? items.resolve(inventory.equipment[slot.rawValue].item)
                    : nil
            )
        }
    }

    private func weaponSets(from inventory: Gdc.Inventory, using items: ItemResolver) -> [WeaponSet] {
        [
            WeaponSet(
                index: 0,
                items: inventory.weaponSet1.map { items.resolve($0.item) },
                isActive: !inventory.usesAlternateWeaponSet
            ),
            WeaponSet(
                index: 1,
                items: inventory.weaponSet2.map { items.resolve($0.item) },
                isActive: inventory.usesAlternateWeaponSet
            ),
        ]
    }

    /// What the difficulty itself takes off the character's resistances.
    ///
    /// The game states this in `balancingadjustment_mp+difficulty_players01.dbr`: an array of four player
    /// counts per difficulty, so Ultimate single-player reads the ninth entry — −50% to fire, cold,
    /// lightning, pierce and poison, −25% to aether, chaos, vitality, bleeding and life leech resistance.
    private func difficultyPenalty(for difficulty: Difficulty, resolver: SkillResolver) -> StatBlock {
        guard let record = database.record(Self.difficultyAdjustmentPath) else { return StatBlock() }

        return resolver.stats(of: record, atLevel: Int(difficulty.rawValue) * Self.playerCounts + 1)
    }

    private static let difficultyAdjustmentPath = "records/game/balancingadjustment_mp+difficulty_players01.dbr"
    /// The adjustment is written once per party size; a save read from disk is one character alone.
    private static let playerCounts = 4

    /// Stats from the skills that are permanently in effect, read at their effective rank.
    ///
    /// Only always-on skills count — an ability the player has to press does not belong on a character
    /// sheet — and a skill that carries its numbers on the buff it drives is read there.
    private func passiveStats(masteries: [ResolvedMastery], resolver: SkillResolver) -> StatBlock {
        var block = StatBlock()

        for mastery in masteries {
            for skill in mastery.sheetSkills {
                guard let record = database.record(skill.recordPath) else { continue }

                block.merge(resolver.effects(of: record, atLevel: skill.totalLevel))
            }
        }

        return block
    }

    // MARK: - Factions

    /// One slot of the save's positional faction array.
    private struct FactionSlot {
        let name: String
        let iconPath: String
        /// True for factions the player earns reputation with. The rest are the engine's own hostility
        /// groups — beasts, Chthonians, the undead — which the game's faction window leaves out.
        let isPlayerFacing: Bool
        /// The character's own faction, which is bookkeeping rather than a standing.
        let isPlayerItself: Bool
    }

    /// The save stores reputations positionally. The order is the engine's own: the six named factions,
    /// then every `factionUserN` in numeric order — cross-checked against a finished character's standings.
    private func factions(from save: Gdc.SaveFile) -> [ResolvedFaction] {
        let slots = factionSlots()
        let thresholds = factionThresholds()

        return save.factions.enumerated().compactMap { index, faction in
            guard index < slots.count else { return nil }

            let slot = slots[index]
            guard !slot.name.isEmpty, !slot.isPlayerItself else { return nil }
            // A standing worth showing is one the character has met or has any history with.
            guard faction.isUnlocked || faction.value != 0 else { return nil }

            let value = Double(faction.value)
            return ResolvedFaction(
                name: slot.name,
                iconPath: slot.iconPath,
                value: value,
                tier: Self.tier(for: value, thresholds: thresholds),
                progress: Self.progress(for: value, thresholds: thresholds),
                nextThreshold: Self.nextThreshold(for: value, thresholds: thresholds),
                isReputation: slot.isPlayerFacing
            )
        }
    }

    private func factionSlots() -> [FactionSlot] {
        guard let table = database.record("records/game/gamefactions.dbr") else { return [] }

        // The record names two factions rather than numbering them; they sit at User0 and User1.
        let named = [
            "factionPlayer", "factionSurvivors", "factionAetherials",
            "factionBeasts", "factionCthonians", "factionOutlaws",
            "factionDrifters", "factionNeutralNPC",
        ]
        let users = table.fields.keys
            .compactMap { key -> (Int, String)? in
                guard key.hasPrefix("factionUser"), let number = Int(key.dropFirst(11)) else { return nil }

                return (number, key)
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)

        return (named + users).map { key in
            guard
                let record = database.record(table.text(key)),
                case let identifier = record.text("myFaction"),
                !identifier.isEmpty
            else { return FactionSlot(name: "", iconPath: "", isPlayerFacing: false, isPlayerItself: false) }

            return FactionSlot(
                name: database.localised("tagFaction" + identifier) ?? identifier,
                iconPath: record.text("factionIcon"),
                isPlayerFacing: record["questEnabled"]?.number == 1,
                isPlayerItself: identifier == "Player"
            )
        }
    }

    private func factionThresholds() -> [(value: Double, title: String)] {
        guard let table = database.record("records/game/gamefactions.dbr") else { return [] }

        return (1 ... 8).compactMap { index in
            let value = table.number("factionValue\(index)")
            let tierTag = table.text("factionTag\(index)")
            guard !tierTag.isEmpty else { return nil }

            return (value, database.localised(tierTag) ?? tierTag)
        }
        .sorted { $0.value < $1.value }
    }

    private static func tier(for value: Double, thresholds: [(value: Double, title: String)]) -> String {
        var title = thresholds.first?.title ?? ""
        for threshold in thresholds where value >= threshold.value { title = threshold.title }
        return title
    }

    private static func nextThreshold(
        for value: Double,
        thresholds: [(value: Double, title: String)]
    ) -> Double? {
        thresholds.first { $0.value > value }?.value
    }

    /// Where the standing sits between the tier it has reached and the next one.
    private static func progress(for value: Double, thresholds: [(value: Double, title: String)]) -> Double {
        guard let index = thresholds.lastIndex(where: { value >= $0.value }) else { return 0 }
        guard index + 1 < thresholds.count else { return 1 }

        let lower = thresholds[index].value
        let upper = thresholds[index + 1].value
        guard upper > lower else { return 1 }

        return min(max((value - lower) / (upper - lower), 0), 1)
    }
}
