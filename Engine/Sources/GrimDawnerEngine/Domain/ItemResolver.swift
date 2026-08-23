// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// Turns the `.dbr` paths a save stores into named items with their stats.
public struct ItemResolver {
    public init(database: GameDatabase, skills: SkillResolver) {
        self.database = database
        self.skills = skills
    }

    public let database: GameDatabase
    /// Granted skills are resolved through the same reader the mastery panels use.
    public let skills: SkillResolver

    public func resolve(_ item: Gdc.Item) -> ResolvedItem? {
        guard !item.isEmpty, let base = database.record(item.baseName) else { return nil }

        var parts = [ItemPart]()

        let basePart = part(kind: .base, record: base, name: displayName(of: base))
        parts.append(basePart)

        for (kind, path) in [
            (ItemPart.Kind.prefix, item.prefixName),
            (.suffix, item.suffixName),
            (.modifier, item.modifierName),
            (.transmuter, item.transmuteName),
            (.component, item.relicName),
            (.completionBonus, item.relicBonus),
            (.augment, item.augmentName),
            (.ascendant, item.ascendedName),
        ] {
            guard let record = database.record(path) else { continue }

            parts.append(part(kind: kind, record: record, name: affixName(of: record)))
        }

        // Everything the item and its affixes carry is one roll of one stream, so those parts are
        // rolled together; a component or an augment is the same on every copy and simply adds.
        let rolled = roll(item, base: base)
        var stats = rolled.stats
        var lowest = rolled.lowest
        var highest = rolled.highest
        for part in parts where !part.isRolled {
            stats.merge(part.stats)
            lowest.merge(part.stats)
            highest.merge(part.stats)
        }

        let rarity = rarity(base: base, parts: parts, path: item.baseName)
        let petBonus = petBonus(of: item, base: base)
        let mark = ItemQualityMark(ItemQualityMark.Parts(
            // A rare-classified record is a monster infrequent only when it is a piece of gear; a
            // component or an augment carries the same classification and wears no badge.
            isMonsterInfrequent: ItemRarity(classification: base.text("itemClassification")) == .rare
                && ItemQualityMark.isGear(recordClass: base.recordClass),
            isDoubleRare: [ item.prefixName, item.suffixName ].allSatisfy { path in
                database.record(path).map { ItemRarity(classification: $0.text("itemClassification")) } == .rare
            },
            isAscended: !item.ascendedName.isEmpty,
            isAwakened: item.baseName.contains("/awakened/"),
            rarity: rarity
        ))

        return ResolvedItem(
            raw: item,
            parts: parts,
            iconPath: basePart.iconPath,
            baseName: basePart.name,
            prefixName: parts.first { $0.kind == .prefix }?.name ?? "",
            suffixName: parts.first { $0.kind == .suffix }?.name ?? "",
            rarity: rarity,
            qualityMarkPath: mark?.texturePath ?? "",
            itemLevel: base.integer("itemLevel"),
            levelRequirement: parts.map(\.levelRequirement).max() ?? 0,
            requirements: requirements(of: base),
            stackCount: Int(item.stackCount),
            flavourText: database.localised(base.text("itemText")) ?? "",
            stats: stats,
            statsLowest: lowest,
            statsHighest: highest,
            petBonus: petBonus
        )
    }

    /// Classes whose numbers never roll: a component and an augment read the same on every copy.
    private static let fixedClasses: Set<String> = [ "ItemRelic", "ItemEnchantment" ]

    /// What the item grants every pet, rolled from its seed in a stream of its own.
    private func petBonus(of item: Gdc.Item, base: ArzRecord) -> StatBlock {
        var sources = [(table: ItemRoll.Table, jitter: Double)]()
        for (path, jitter) in [
            (item.baseName, ItemRoll.baseJitter),
            (item.prefixName, database.record(item.prefixName)?.number("lootRandomizerJitter") ?? 0),
            (item.suffixName, database.record(item.suffixName)?.number("lootRandomizerJitter") ?? 0),
        ] {
            guard
                let record = database.record(path),
                case let bonusPath = record.text("petBonusName"),
                !bonusPath.isEmpty,
                let bonus = database.record(bonusPath)
            else { continue }

            sources.append((Self.table(of: bonus), jitter))
        }
        guard !sources.isEmpty else { return StatBlock() }

        var block = StatBlock()
        for (key, value) in ItemRoll.petStats(of: sources, seed: item.seed) {
            guard StatCatalog.definition(for: key) != nil else { continue }

            block.increase(key, by: value)
        }
        return block
    }

    /// One affix read on its own, as the catalogue lists it rather than as an item wears it.
    public func affix(at path: String) -> ResolvedAffix? {
        guard let record = database.record(path) else { return nil }

        // The affix rolls at its own jitter, which is the prefix slot's business rather than the base's.
        let sources = ItemRoll.Sources(base: ItemRoll.Table(), prefix: Self.table(of: record), seed: 0)

        func block(_ draws: ItemRoll.Draws) -> StatBlock {
            var block = StatBlock()
            for (key, value) in ItemRoll.stats(of: sources, drawing: draws) {
                guard StatCatalog.definition(for: key) != nil else { continue }

                block.increase(key, by: value)
            }
            return block
        }

        var lowest = block(.lowest)
        var highest = block(.highest)
        var granted = [GrantedSkill]()
        var carried = StatBlock()
        collectSkillBonuses(from: record, into: &carried, granted: &granted)
        collectConversions(from: record, into: &carried)
        lowest.merge(carried.withoutCataloguedValues())
        highest.merge(carried.withoutCataloguedValues())

        return ResolvedAffix(
            path: path,
            name: affixName(of: record),
            kind: path.contains("/prefix/") ? .prefix : .suffix,
            rarity: ItemRarity(classification: record.text("itemClassification")),
            levelRequirement: record.integer("levelRequirement"),
            jitter: record.number("lootRandomizerJitter"),
            statsLowest: lowest,
            statsHighest: highest,
            grantedSkills: granted
        )
    }

    /// The sets the worn items belong to, with the bonuses that many pieces grant.
    public func sets(worn items: [ResolvedItem]) -> [ResolvedSet] {
        var pieces = [String: Int]()
        var order = [String]()

        for item in items {
            guard
                let record = database.record(item.raw.baseName),
                case let path = record.text("itemSetName"),
                !path.isEmpty
            else { continue }

            let key = path.lowercased()
            if pieces[key] == nil { order.append(key) }
            pieces[key, default: 0] += 1
        }

        return order.compactMap { path in
            guard let record = database.record(path), let worn = pieces[path] else { return nil }

            return set(record, at: path, worn: worn)
        }
    }

    private func set(_ record: ArzRecord, at path: String, worn: Int) -> ResolvedSet {
        var bonuses = StatBlock()
        for (key, value) in record.fields {
            guard StatCatalog.definition(for: key) != nil else { continue }

            bonuses.increase(key, by: Self.value(of: value, atPieces: worn))
        }

        var granted = [GrantedSkill]()
        for index in 1 ... 8 {
            let skillPath = record.text("augmentSkillName\(index)")
            guard
                !skillPath.isEmpty,
                let levels = record["augmentSkillLevel\(index)"],
                case let level = Int(Self.value(of: levels, atPieces: worn)),
                level > 0
            else { continue }

            bonuses.addSkillBonus(skillPath, level)
            granted.append(GrantedSkill(
                name: skills.skill(at: skillPath, level: level)?.name ?? "",
                recordPath: skillPath,
                level: level,
                kind: .added,
                skill: skills.skill(at: skillPath, level: level),
                mastery: skills.masteryName(ofSkillAt: skillPath)
            ))
        }

        return ResolvedSet(
            name: database.localised(record.text("setName")) ?? record.text("FileDescription"),
            piecesWorn: worn,
            totalPieces: record["setMembers"]?.texts.count ?? worn,
            bonuses: bonuses,
            grantedSkills: granted
        )
    }

    /// A set's numbers are written one per piece count, so three pieces read the third of them.
    private static func value(of field: ArzValue, atPieces pieces: Int) -> Double {
        let numbers = field.numbers
        guard !numbers.isEmpty else { return 0 }

        return numbers[min(max(pieces - 1, 0), numbers.count - 1)]
    }

    // MARK: - Parts

    private func part(kind: ItemPart.Kind, record: ArzRecord, name: String) -> ItemPart {
        var stats = StatBlock()
        var granted = [GrantedSkill]()

        for (key, value) in record.fields {
            guard StatCatalog.definition(for: key) != nil else { continue }

            stats.increase(key, by: value.number)
        }

        collectSkillBonuses(from: record, into: &stats, granted: &granted)
        collectConversions(from: record, into: &stats)

        return ItemPart(
            kind: kind,
            name: name,
            recordPath: record.path,
            iconPath: Self.iconPath(of: record),
            levelRequirement: record.integer("levelRequirement"),
            stats: stats,
            grantedSkills: granted
        )
    }

    /// What the item's own record and its affixes come to, rolled from the item's seed, and the ends
    /// of the band that roll sits in.
    private func roll(
        _ item: Gdc.Item,
        base: ArzRecord
    ) -> (stats: StatBlock, lowest: StatBlock, highest: StatBlock) {
        // A component or an augment is the same on every copy — the game prints its figures without a
        // band — so it is read as written rather than rolled.
        guard
            !Self.fixedClasses.contains(base.recordClass)
        else {
            var written = StatBlock()
            for (key, value) in base.fields where StatCatalog.definition(for: key) != nil {
                written.increase(key, by: value.number)
            }
            return (written, written, written)
        }

        // A relic ignores the blacksmith's bonus its save entry names: the game shows none.
        let crafted = base.text("Class") == "ItemArtifact" ? nil : table(at: item.modifierName)
        let sources = ItemRoll.Sources(
            base: Self.table(of: base),
            prefix: table(at: item.prefixName),
            suffix: table(at: item.suffixName),
            modifier: crafted,
            seed: item.seed
        )

        func block(_ draws: ItemRoll.Draws?) -> StatBlock {
            var block = StatBlock()
            for (key, value) in ItemRoll.stats(of: sources, drawing: draws) {
                guard StatCatalog.definition(for: key) != nil else { continue }

                block.increase(key, by: value)
            }
            return block
        }

        let rolledKeys = Set(ItemRoll.stats(of: sources).keys)
        var stats = block(nil)
        var lowest = block(.lowest)
        var highest = block(.highest)

        for path in [ item.baseName, item.prefixName, item.suffixName, item.modifierName ] {
            guard let record = database.record(path) else { continue }

            // A field the roller does not model — a resistance cap, say — is carried as written.
            var written = StatBlock()
            for (key, value) in record.fields where !rolledKeys.contains(key) {
                guard StatCatalog.definition(for: key) != nil else { continue }

                written.increase(key, by: value.number)
            }

            // Skill bonuses and conversions are read from the records rather than rolled.
            var granted = [GrantedSkill]()
            collectSkillBonuses(from: record, into: &written, granted: &granted)
            collectConversions(from: record, into: &written)

            stats.merge(written)
            lowest.merge(written)
            highest.merge(written)
        }

        return (stats, lowest, highest)
    }

    private func table(at path: String) -> ItemRoll.Table? {
        guard let record = database.record(path) else { return nil }

        return Self.table(of: record)
    }

    private static func table(of record: ArzRecord) -> ItemRoll.Table {
        var table = ItemRoll.Table()
        for (key, value) in record.fields {
            if case let .text(strings) = value {
                table.values[key] = 0
                table.text[key] = strings.first ?? ""
            } else {
                table.values[key] = value.number
            }
        }
        return table
    }

    /// Reads the `augment*` families: `+N` to a named skill, to a whole mastery, or to every skill.
    private func collectSkillBonuses(
        from record: ArzRecord,
        into stats: inout StatBlock,
        granted: inout [GrantedSkill]
    ) {
        for index in 1 ... 8 {
            let path = record.text("augmentSkillName\(index)")
            guard !path.isEmpty else { continue }

            let levels = record.integer("augmentSkillLevel\(index)")
            stats.addSkillBonus(path, levels)
            granted.append(grantedSkill(at: path, level: levels, kind: .added))
        }

        for index in 1 ... 4 {
            let path = record.text("augmentMasteryName\(index)")
            guard !path.isEmpty else { continue }

            stats.addMasteryBonus(path, record.integer("augmentMasteryLevel\(index)"))
        }

        stats.addAllSkillBonus(record.integer("augmentAllLevel"))

        // An item that changes a skill names the skill and, beside it, a `Skill_Modifier` record
        // holding what it changes.
        for index in 1 ... 4 {
            let path = record.text("modifiedSkillName\(index)")
            guard !path.isEmpty else { continue }

            var enhanced = grantedSkill(at: path, level: 0, kind: .enhanced)
            if let modifier = database.record(record.text("modifierSkillName\(index)")) {
                enhanced.modifications = skills.changes(of: modifier, atLevel: 1)
            }
            granted.append(enhanced)
        }

        let itemSkill = record.text("itemSkillName")
        if !itemSkill.isEmpty {
            var skill = grantedSkill(at: itemSkill, level: itemSkillLevel(record), kind: .granted)
            skill.trigger = SkillTrigger.text(ofControllerAt: record.text("itemSkillAutoController"), in: database)
            granted.append(skill)
        }
    }

    private func grantedSkill(at path: String, level: Int, kind: GrantedSkill.Kind) -> GrantedSkill {
        let skill = skills.skill(at: path, level: level)

        return GrantedSkill(
            name: skillName(path),
            recordPath: path,
            level: level,
            kind: kind,
            skill: skill,
            mastery: skills.masteryName(ofSkillAt: path)
        )
    }

    /// An item skill's level is sometimes a fixed number and sometimes a formula over the item's level.
    private func itemSkillLevel(_ record: ArzRecord) -> Int {
        let fixed = record.integer("itemSkillLevel")
        guard fixed == 0 else { return fixed }

        let formula = record.text("itemSkillLevelEq")
        guard !formula.isEmpty, let equation = try? Equation(formula) else { return 1 }

        let level = try? equation.value([ "itemLevel": Double(record.integer("itemLevel")) ])
        return max(1, Int(level ?? 1))
    }

    private func collectConversions(from record: ArzRecord, into stats: inout StatBlock) {
        for suffix in [ "", "2", "3", "4" ] {
            let percent = record.number("conversionPercentage\(suffix)")
            guard percent != 0 else { continue }

            let source = record.text("conversionInType\(suffix)")
            let target = record.text("conversionOutType\(suffix)")
            guard !source.isEmpty, !target.isEmpty else { continue }

            stats.addConversion(StatBlock.Conversion(source: source, target: target, percent: percent))
        }
    }

    // MARK: - Naming

    private func displayName(of record: ArzRecord) -> String {
        if let name = Self.itemName(of: record, in: database) { return name }
        if let name = database.localised(record.text("description")) { return name }

        let fallback = record.text("FileDescription")
        return fallback.isEmpty ? Self.readableName(from: record.path) : fallback
    }

    /// An item's full name, which the game builds by prefixing its own name with its quality and style.
    ///
    /// The endgame version of a unique is one such style: `tagStyleUniqueTier3` reads "Mythical", and
    /// without it the two versions of an item are indistinguishable.
    /// Components, relics and augments carry no `itemNameTag`; their name is the `description` tag.
    public static func itemName(of record: ArzRecord, in database: GameDatabase) -> String? {
        guard
            let name = database.localised(record.text("itemNameTag"))
                ?? database.localised(record.text("description"))
        else { return nil }

        let prefixes = [ "itemQualityTag", "itemStyleTag" ].compactMap {
            database.localised(record.text($0))
        }
        return (prefixes + [ name ]).joined(separator: " ")
    }

    /// An affix's name, or nothing at all.
    ///
    /// Crafting and completion bonuses are unnamed in the database — the record's own file name is an
    /// author's shorthand, not a name — and the game shows them by what they grant instead.
    private func affixName(of record: ArzRecord) -> String {
        if let name = database.localised(record.text("lootRandomizerName")) { return name }
        if let name = database.localised(record.text("itemNameTag")) { return name }
        if let name = database.localised(record.text("description")) { return name }

        // Ascendant affixes carry no name of their own; they are known by the skill they enhance.
        return modifiedSkillName(of: record) ?? ""
    }

    private func modifiedSkillName(of record: ArzRecord) -> String? {
        for index in 1 ... 4 {
            guard
                case let path = record.text("modifiedSkillName\(index)"),
                !path.isEmpty,
                let skill = database.record(path),
                let name = database.localised(skill.text("skillDisplayName"))
            else { continue }

            return name
        }
        return nil
    }

    /// The skill's name, or nothing at all: several component skills are unnamed in the database, and the
    /// record's own file name is not a name a reader would recognise.
    private func skillName(_ path: String) -> String {
        guard let record = database.record(path) else { return "" }

        if let name = database.localised(record.text("skillDisplayName")) { return name }

        for link in [ "buffSkillName", "petSkillName" ] {
            guard
                case let linked = record.text(link),
                !linked.isEmpty,
                let target = database.record(linked),
                let name = database.localised(target.text("skillDisplayName"))
            else { continue }

            return name
        }
        return ""
    }

    /// Records name their inventory art differently depending on what kind of item they are.
    private static func iconPath(of record: ArzRecord) -> String {
        for key in [ "bitmap", "artifactBitmap", "relicBitmap", "shardBitmap", "artifactFormulaBitmapName" ] {
            let path = record.text(key)
            if !path.isEmpty { return path }
        }
        return ""
    }

    /// Last-resort label built from the record path, so an unknown record still reads as something.
    public static func readableName(from path: String) -> String {
        let file = path.split(separator: "/").last ?? ""
        return file.replacingOccurrences(of: ".dbr", with: "")
    }

    // MARK: - Classification

    private func rarity(base: ArzRecord, parts: [ItemPart], path: String) -> ItemRarity {
        if let crafting = ItemRarity(recordClass: base.recordClass) { return crafting }
        if path.contains("/questitems/") { return .quest }

        let baseRarity = ItemRarity(classification: base.text("itemClassification"))
        guard baseRarity.takesAffixes else { return baseRarity }

        var best = baseRarity
        for part in parts where part.kind == .prefix || part.kind == .suffix {
            guard let record = database.record(part.recordPath) else { continue }

            best = max(best, ItemRarity(classification: record.text("itemClassification")))
        }
        return best
    }

    private func requirements(of record: ArzRecord) -> [String: Double] {
        var values = [String: Double]()
        for (label, key) in [
            ("Physique", "strengthRequirement"),
            ("Cunning", "dexterityRequirement"),
            ("Spirit", "intelligenceRequirement"),
        ] {
            let amount = record.number(key)
            guard amount > 0 else { continue }

            values[label] = amount
        }
        return values
    }
}
