// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// Resolves a parsed save against the game database into the model the UI renders.
public struct CharacterBuilder {
    public init(database: GameDatabase) { self.database = database }

    public let database: GameDatabase

    /// `readAt` reads the character as it would stand on another difficulty, since the game takes more
    /// off its resistances the deeper it goes. Nothing else about a character depends on where it is,
    /// so this changes the penalty and nothing more. Absent, the save's own difficulty is used.
    public func build(
        _ save: Gdc.SaveFile,
        file: CharacterFile,
        readAt difficulty: Difficulty? = nil
    ) -> ResolvedCharacter {
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

        let read = difficulty ?? save.difficulty
        let penalty = DifficultyPenalty.of(read, in: database, resolver: skills)

        var total = gearStats
        for mastery in masteries { total.merge(mastery.bonuses) }
        total.merge(devotionStats)
        total.merge(passiveStats(masteries: masteries, resolver: skills))
        total.merge(Self.enhancementStats(of: equipped, over: masteries))
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
            difficulty: read,
            greatestDifficulty: save.greatestDifficulty,
            masteries: masteries,
            devotion: devotions.map(from: save),
            itemGrantedSkills: skills.looseSkills(from: save, claimed: claimed),
            skillModifications: Self.skillModifications(of: equipped),
            skillRankSources: Self.skillRankSources(of: equipped, sets: sets),
            petBonuses: petBonuses(items: equipped, masteries: masteries, devotion: devotions.map(from: save)),
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
                bodyArmor: bodyArmor(from: equipment),
                weaponSpeed: weaponSpeed(of: weaponSets)
            ),
            bodyArmor: bodyArmor(from: equipment),
            weaponSpeed: weaponSpeed(of: weaponSets)
        )
    }

    /// What each worn item changes about a skill, gathered under the skill it changes.
    private static func skillModifications(of items: [ResolvedItem]) -> [String: [SkillModification]] {
        var changes = [String: [SkillModification]]()
        for item in items {
            for granted in item.grantedSkills where granted.kind == .enhanced {
                guard let modifications = granted.modifications, !modifications.isEmpty else { continue }

                changes[granted.recordPath.lowercased(), default: []].append(
                    SkillModification(item: item, changes: modifications)
                )
            }
        }
        return changes
    }

    /// What the gear's "Enhances" lines put on the sheet.
    ///
    /// An item that enhances a skill carries the figures on a modifier record of its own rather than on
    /// the item, and those figures are on the sheet exactly as a mastery's own modifier is — but only
    /// where the skill they enhance is one the character keeps up. A modifier that rides an attack the
    /// reader has to press belongs to that attack, not to the sheet.
    ///
    /// A ring's ascendant affix granting +100 Health to Spectral Binding is 113 health the game shows
    /// and the app did not.
    private static func enhancementStats(
        of items: [ResolvedItem],
        over masteries: [ResolvedMastery]
    ) -> StatBlock {
        let permanent = Set(
            masteries.flatMap(\.skills)
                .filter { $0.isLearned && $0.isAlwaysOn }
                .map { $0.recordPath.lowercased() }
        )
        var block = StatBlock()
        for item in items {
            for granted in item.grantedSkills
            where granted.kind == .enhanced && permanent.contains(granted.recordPath.lowercased()) {
                guard let modifications = granted.modifications else { continue }

                block.merge(modifications.stats)
            }
        }
        return block
    }

    /// What the character grants every pet it has: from gear, from the skills that are always in
    /// effect, and from the devotion stars taken.
    private func petBonuses(
        items: [ResolvedItem],
        masteries: [ResolvedMastery],
        devotion: DevotionMap
    ) -> StatBlock {
        var block = StatBlock()
        for item in items { block.merge(item.petBonus) }
        for mastery in masteries {
            for skill in mastery.sheetSkills { block.merge(skill.petBonus) }
        }
        for constellation in devotion.constellations {
            for star in constellation.stars where star.isTaken { block.merge(star.skill.petBonus) }
        }
        return block
    }

    /// Every `+N to skill` the gear carries, one entry per thing that grants it.
    private static func skillRankSources(of items: [ResolvedItem], sets: [ResolvedSet])
        -> [SkillRankSource]
    {
        var sources = [SkillRankSource]()

        func collect(_ stats: StatBlock, name: String, iconPath: String, item: ResolvedItem?) {
            for (path, levels) in stats.skillBonuses where levels != 0 {
                sources.append(SkillRankSource(
                    name: name,
                    iconPath: iconPath,
                    levels: levels,
                    reach: .skill,
                    path: path,
                    item: item
                ))
            }
            for (path, levels) in stats.masteryBonuses where levels != 0 {
                sources.append(SkillRankSource(
                    name: name,
                    iconPath: iconPath,
                    levels: levels,
                    reach: .mastery,
                    path: path,
                    item: item
                ))
            }
            if stats.allSkillBonus != 0 {
                sources.append(SkillRankSource(
                    name: name,
                    iconPath: iconPath,
                    levels: stats.allSkillBonus,
                    reach: .everySkill,
                    path: "",
                    item: item
                ))
            }
        }

        for item in items {
            collect(item.stats, name: item.displayName, iconPath: item.iconPath, item: item)
        }
        for set in sets { collect(set.bonuses, name: set.name, iconPath: "", item: nil) }
        return sources
    }

    /// What the weapon in hand does to the base attack rate. Only the set being held counts.
    private func weaponSpeed(of sets: [WeaponSet]) -> Double {
        let held = sets.first { $0.isActive } ?? sets.first
        return held?.items
            .compactMap { $0.flatMap { database.record($0.raw.baseName) } }
            .map { $0.number("characterBaseAttackSpeed") }
            .reduce(0, +) ?? 0
    }

    /// Armour on the six hit-region slots, which the engine weights rather than sums.
    private func bodyArmor(from equipment: [EquippedItem]) -> [EquipmentSlot: Double] {
        var values = [EquipmentSlot: Double]()
        for equipped in equipment where equipped.slot.hitRegionChanceKey != nil {
            // A component's bonus armour belongs to the piece it is socketed in: the game's own
            // per-region breakdown credits it to that region and to no other.
            values[equipped.slot] =
                (equipped.item?.stats.value("defensiveProtection") ?? 0)
                + (equipped.item?.stats.value("defensiveBonusProtection") ?? 0)
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
        public let name: String
        public let iconPath: String
        /// True for factions the player earns reputation with. The rest are the engine's own hostility
        /// groups — beasts, Chthonians, the undead — which the game's faction window leaves out.
        public let isPlayerFacing: Bool
        /// The character's own faction, which is bookkeeping rather than a standing.
        public let isPlayerItself: Bool
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
