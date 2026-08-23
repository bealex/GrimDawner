// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// One thing a monster does: an attack it swings, a skill it casts, or a passive it simply has.
public struct MonsterAbility: Identifiable, Sendable {
    public enum Role: Sendable {
        case attack
        case special
        case onDeath
        case passive

        public var title: String {
            switch self {
                case .attack: "Attack"
                case .special: "Special Attack"
                case .onDeath: "On Death"
                case .passive: "Passive"
            }
        }
    }

    public let id = UUID()
    public let skill: ResolvedSkill
    /// The name the game gives it, absent for most of what a monster fights with: those records carry a
    /// developer's file name, which is worth nothing to a reader.
    public var title: String? { skill.properName }
    /// What its record class says it is — a weapon attack, a fan of projectiles, an aura.
    public let kind: String
    public let role: Role
    /// How close it has to be, as the record words it — ShortRange, MediumRange, LongRange.
    public let range: String?
    /// Seconds before it first uses this, and seconds between uses.
    public let delay: Double?
    public let cooldown: Double?
}

/// One thing a monster can leave behind, either an item or a table of them.
public struct MonsterLootEntry: Identifiable, Sendable {
    /// A single item a loot table can produce.
    public struct Item: Identifiable, Sendable {
        public let id = UUID()
        public let name: String
        /// The item's own record, which is what says how it is worn and what it looks like.
        public let recordPath: String
        public let iconPath: String
        /// The item's share of its table, as a percentage.
        public let share: Double
    }

    public let id = UUID()
    /// The item's own name, empty for a table: a loot table's file name is an identifier, not a name,
    /// and what it holds is what a reader is after.
    public let name: String
    public let iconPath: String
    /// Share of the slot, as a percentage: the game weighs the entries of one slot against each other.
    public let share: Double
    /// What the table holds, most likely first. Empty where the entry is a single item.
    public let items: [Item]

    /// How the entry reads when it is a table rather than one item.
    public var title: String {
        guard name.isEmpty else { return name }

        return items.count == 1 ? items[0].name : "One of \(items.count) items"
    }
}

/// One equipment slot's worth of loot: what the monster carries there and how likely it is to.
public struct MonsterLootSlot: Identifiable, Sendable {
    public let id = UUID()
    public let slot: String
    /// The field stem the game writes this slot as — `RightHand`, `Chest` — for anything that has to
    /// know where a piece is worn rather than what it is called.
    public let field: String
    /// The chance the slot holds anything at all.
    public let chance: Double
    public let entries: [MonsterLootEntry]
}

/// A monster read at one level: what it is, what it can do, and what it carries.
public struct ResolvedMonster: Sendable {
    public let path: String
    public let name: String
    public let rank: MonsterRank
    /// The faction pack its record puts it in, which says less than it looks like it does.
    public let faction: String
    /// The faction whose nemesis it is, which is the faction that owns it. Empty for everything else.
    public let nemesisOf: String
    public let race: String
    /// The model the game draws it with, and the skin that model wears.
    public let meshPath: String
    public let texturePath: String
    public let level: Int
    public let levelRange: ClosedRange<Int>
    /// Monsters are worth far more on the deeper difficulties, so nothing here means anything without it.
    public let difficulty: Difficulty
    public let experience: Double
    public let physique: Double
    public let cunning: Double
    public let spirit: Double
    public let health: Double
    public let energy: Double
    public let offensiveAbility: Double
    public let defensiveAbility: Double
    /// Everything its record, its bio equations and its permanent skills carry, summed as written.
    public let stats: StatBlock
    public let abilities: [MonsterAbility]
    public let loot: [MonsterLootSlot]

    /// True for the celestial bosses, whose record carries an adjuster that cancels the game's own
    /// ascendant-mode bonus. Neither is in effect in an ordinary fight, so neither is counted.
    public let cancelsAscendantMode: Bool

    public var armor: Double {
        stats.value("defensiveProtection") * (1 + stats.value("defensiveProtectionModifier") / 100)
    }

    public var resistances: [ResistanceKind: Double] {
        Dictionary(uniqueKeysWithValues: ResistanceKind.allCases.map {
            ($0, StatComposition.total(feeding: $0.resistanceKey, in: stats))
        })
    }

    public var attacks: [MonsterAbility] { abilities.filter { $0.role != .passive } }
    public var passives: [MonsterAbility] { abilities.filter { $0.role == .passive } }
}

/// Reads a monster's record: its stats at a level, the skills it carries, and its loot.
public struct MonsterResolver {
    public init(database: GameDatabase, skills: SkillResolver, items: ItemResolver) {
        self.database = database
        self.skills = skills
        self.items = items
    }

    public let database: GameDatabase
    public let skills: SkillResolver
    public let items: ItemResolver

    /// The slots a monster carries something in, in the order the game's own fields run.
    private static let lootSlots: [(field: String, title: String)] = [
        ("RightHand", "Right Hand"), ("LeftHand", "Left Hand"), ("Head", "Head"), ("Chest", "Chest"),
        ("Shoulders", "Shoulders"), ("Legs", "Legs"), ("Feet", "Feet"), ("Hands", "Hands"),
        ("Finger1", "Ring"), ("Finger2", "Ring"), ("Misc1", "Drop 1"), ("Misc2", "Drop 2"), ("Misc3", "Drop 3"),
    ]

    /// How deep a loot table is followed. A master table names a level table, which names the table for
    /// the band the monster is in, which names the items — four steps, with room to spare.
    private static let lootDepth = 6

    /// The adjustment the game lays over every enemy, by difficulty and party size. Each stat is written
    /// as twelve numbers: three difficulties of four party sizes.
    private static let difficultyAdjustmentPath = "records/game/balancingadjustment_mp+difficulty_enemies01.dbr"
    /// What the game grants a monster in ascendant mode. A celestial boss's record carries a skill that
    /// is this exactly negated, so neither counts in a fight that is not in that mode.
    private static let ascendantAdjustmentPath = "records/game/balancingadjustment_ultramode_enemies01.dbr"

    public func monster(at path: String, level: Int, difficulty: Difficulty = .ultimate) -> ResolvedMonster? {
        guard let record = database.record(path), record.text("Class") == "Monster" else { return nil }

        let bounds = Int(record.number("minLevel")) ... max(Int(record.number("maxLevel")), 1)
        let level = min(max(level, bounds.lowerBound), bounds.upperBound)
        let ascendant = adjustment(at: Self.ascendantAdjustmentPath, index: 0)
        let all = abilities(of: record, atLevel: level)
        let counted = all.filter { !cancels(ascendant, $0) }
        let block = stats(
            of: record,
            atLevel: level,
            abilities: counted,
            adjustment: adjustment(at: Self.difficultyAdjustmentPath, index: Int(difficulty.rawValue) * 4)
        )
        let bio = bioValues(of: record, atLevel: level)
        let physique = scaled(block, base: bio["characterStrength"], "characterStrength")
        let cunning = scaled(block, base: bio["characterDexterity"], "characterDexterity")
        let formulas = CombatFormulas(database: database)

        return ResolvedMonster(
            path: path,
            name: database.localised(record.text("description")) ?? ItemResolver.readableName(from: path),
            rank: MonsterRank(rawValue: record.text("monsterClassification")) ?? .common,
            faction: factionName(of: record),
            nemesisOf: MonsterCatalogue.nemeses(in: database)[
                database.localised(record.text("description")) ?? ""
            ] ?? "",
            race: database.localised("tag" + record.text("characterRacialProfile")) ?? "",
            meshPath: record.text("mesh"),
            texturePath: record.text("baseTexture").isEmpty
                ? record.text("baseTextures") : record.text("baseTexture"),
            level: level,
            levelRange: bounds,
            difficulty: difficulty,
            experience: record.number("experiencePoints"),
            physique: physique,
            cunning: cunning,
            spirit: scaled(block, base: bio["characterIntelligence"], "characterIntelligence"),
            health: scaled(block, base: bio["characterLife"], "characterLife"),
            energy: scaled(block, base: bio["characterMana"], "characterMana"),
            // Both abilities fold in an attribute and the level, so the game's own equations decide them.
            offensiveAbility: formulas.ability(
                equationKey: "offensiveAbilityEquation",
                flat: (bio["characterOffensiveAbility"] ?? 0) + block.value("characterOffensiveAbility"),
                attribute: cunning,
                percent: block.value("characterOffensiveAbilityModifier"),
                level: Double(level)
            ),
            defensiveAbility: formulas.ability(
                equationKey: "defensiveAbilityEquation",
                flat: (bio["characterDefensiveAbility"] ?? 0) + block.value("characterDefensiveAbility"),
                attribute: physique,
                percent: block.value("characterDefensiveAbilityModifier"),
                level: Double(level)
            ),
            stats: block,
            abilities: all,
            loot: loot(of: record, atLevel: level),
            cancelsAscendantMode: counted.count != all.count
        )
    }

    /// A pool or an attribute: what the level's equation gives, what the sheet adds, and the percentage
    /// over both.
    private func scaled(_ block: StatBlock, base: Double?, _ key: String) -> Double {
        ((base ?? 0) + block.value(key)) * (1 + block.value("\(key)Modifier") / 100)
    }

    /// One column of an adjustment pak, which writes each stat as one number per difficulty and party
    /// size. Single-player is the first of each difficulty's four.
    private func adjustment(at path: String, index: Int) -> StatBlock {
        var block = StatBlock()
        guard let record = database.record(path) else { return block }

        for field in record.fieldOrder {
            guard
                StatCatalog.definition(for: field) != nil,
                case let numbers = record[field]?.numbers ?? [],
                !numbers.isEmpty
            else { continue }

            block.increase(field, by: numbers[min(index, numbers.count - 1)])
        }
        return block
    }

    /// True for the skill a celestial boss carries to cancel the game's ascendant-mode adjustment: it is
    /// that adjustment negated, stat for stat, and neither is in effect in an ordinary fight.
    private func cancels(_ ascendant: StatBlock, _ ability: MonsterAbility) -> Bool {
        let stats = ability.skill.stats
        guard !ascendant.values.isEmpty, !stats.values.isEmpty else { return false }

        return ascendant.values.allSatisfy { key, value in abs(stats.value(key) + value) < 0.001 }
    }

    private func factionName(of record: ArzRecord) -> String {
        guard
            let faction = database.record(record.text("factions")),
            case let identifier = faction.text("myFaction"),
            !identifier.isEmpty
        else { return "" }

        return database.localised("tagFaction" + identifier) ?? identifier
    }

    // MARK: - Stats

    /// What the monster is worth at this level: the equations its bio record holds, the stats written on
    /// the record itself, and whatever its permanent skills add.
    ///
    /// A monster states its pools as equations of its level rather than as numbers — `characterLife` reads
    /// `((charLevel*195)^1.53)+50000` — so nothing is known until a level is chosen.
    private func stats(
        of record: ArzRecord,
        atLevel level: Int,
        abilities: [MonsterAbility],
        adjustment: StatBlock
    ) -> StatBlock {
        var block = StatBlock()

        for (key, value) in record.fields {
            guard StatCatalog.definition(for: key) != nil, let number = value.numbers.first else { continue }

            block.increase(key, by: number)
        }

        for ability in abilities where ability.role == .passive {
            block.merge(ability.skill.stats)
        }
        block.merge(adjustment)
        return block
    }

    /// What a monster's own equations give at a level: its pools, its attributes and the base of each
    /// ability, none of which the record states as a number.
    ///
    /// A monster states these as equations of its level rather than as numbers — `characterLife` reads
    /// `((charLevel*195)^1.53)+50000` — so nothing is known until a level is chosen.
    private func bioValues(of record: ArzRecord, atLevel level: Int) -> [String: Double] {
        guard let bio = database.record(record.text("characterAttributeEquations")) else { return [:] }

        let variables = [
            "charLevel": Double(level),
            // The regeneration equations carry the gear's own contribution and the tick length; a monster
            // wears none, and one second is the tick the numbers are quoted in.
            "lifeRegen": 0, "manaRegen": 0, "lifeRegenMod": 0, "manaRegenMod": 0, "elapsedTime": 1,
        ]
        var values = [String: Double]()
        for field in bio.fieldOrder {
            guard
                StatCatalog.definition(for: field) != nil,
                let equation = try? Equation(bio.text(field)),
                let value = try? equation.value(variables)
            else { continue }

            values[field] = value
        }
        return values
    }

    // MARK: - Skills

    private func abilities(of record: ArzRecord, atLevel level: Int) -> [MonsterAbility] {
        let levels = skillLevels(of: record, atLevel: level)
        var abilities = [MonsterAbility]()
        var seen = Set<String>()

        func add(
            _ path: String,
            role: MonsterAbility.Role,
            range: String? = nil,
            delay: Double? = nil,
            cooldown: Double? = nil
        ) {
            guard !path.isEmpty, seen.insert(path.lowercased()).inserted else { return }
            guard let skill = skills.skill(at: path, level: levels[path.lowercased()] ?? 1) else { return }

            abilities.append(MonsterAbility(
                skill: skill,
                kind: SkillKind.phrase(forClass: skill.recordClass) ?? "Skill",
                role: Self.role(of: skill, asked: role),
                range: range,
                delay: delay,
                cooldown: cooldown
            ))
        }

        add(record.text("attackSkillName"), role: .attack)
        add(
            record.text("specialAttackSkillName"),
            role: .special,
            range: record.text("specialAttackRange"),
            delay: record.number("specialAttackDelay"),
            cooldown: record.number("specialAttackTimeout")
        )
        for index in 2 ... 5 {
            add(
                record.text("specialAttack\(index)SkillName"),
                role: .special,
                range: record.text("specialAttack\(index)Range"),
                delay: record.number("specialAttack\(index)Delay"),
                cooldown: record.number("specialAttack\(index)Timeout")
            )
        }
        add(record.text("dyingSkillName"), role: .onDeath)

        // Whatever is left in the skill list is either a passive adjuster or a skill the controller
        // fires on its own; the record's class is what says which.
        for path in levels.keys.sorted() {
            guard let skill = skills.skill(at: path, level: levels[path] ?? 1) else { continue }

            add(path, role: skill.isAlwaysOn ? .passive : .special)
        }
        return abilities
    }

    /// Where a skill belongs on the sheet. The record's own slot says what the monster uses it for, but
    /// its class overrules that slot for the two the slot gets wrong: a skill that only fires as the
    /// monster falls is not an attack, and one that simply holds while it lives is a passive.
    private static func role(of skill: ResolvedSkill, asked role: MonsterAbility.Role) -> MonsterAbility.Role {
        if skill.recordClass.contains("OnDeath") { return .onDeath }
        if skill.isAlwaysOn || skill.recordClass.hasPrefix("Skill_Passive") { return .passive }

        return role
    }

    /// The level each of the monster's skills runs at, which the record states as an equation of its own
    /// level: `skillLevel4 = charLevel/4+1`.
    private func skillLevels(of record: ArzRecord, atLevel level: Int) -> [String: Int] {
        var levels = [String: Int]()

        for index in 1 ... 32 {
            let path = record.text("skillName\(index)")
            guard !path.isEmpty else { continue }

            let source = record.text("skillLevel\(index)")
            let value =
                (try? Equation(source).value([ "charLevel": Double(level) ])) ?? record.number("skillLevel\(index)")
            levels[path.lowercased()] = max(1, Int(value))
        }
        return levels
    }

    // MARK: - Loot

    private func loot(of record: ArzRecord, atLevel level: Int) -> [MonsterLootSlot] {
        guard record.number("dropItems") != 0 else { return [] }

        return Self.lootSlots.compactMap { slot in
            var weights = [(path: String, weight: Double)]()
            for index in 1 ... 6 {
                let path = record.text("loot\(slot.field)Item\(index)")
                guard !path.isEmpty else { continue }

                weights.append((path, record.number("chanceToEquip\(slot.field)Item\(index)")))
            }
            guard !weights.isEmpty else { return nil }

            let total = weights.reduce(0) { $0 + $1.weight }
            let entries = weights.map { entry in
                MonsterLootEntry(
                    name: itemName(at: entry.path),
                    iconPath: itemIcon(at: entry.path),
                    share: total > 0 ? entry.weight * 100 / total : 0,
                    items: contents(of: entry.path, atLevel: level)
                )
            }
            // A slot with no stated chance is one the monster always carries something in.
            let chance =
                record.fields["chanceToEquip\(slot.field)"] == nil
                ? 100
                : record.number("chanceToEquip\(slot.field)")
            return MonsterLootSlot(
                slot: slot.title,
                field: slot.field,
                chance: chance,
                entries: entries.sorted { $0.share > $1.share }
            )
        }
    }

    /// The artwork of the item a loot entry points at, and nothing for a table.
    private func itemIcon(at path: String) -> String {
        guard let record = database.record(path), !record.recordClass.hasPrefix("LootItemTable") else { return "" }

        return ItemResolver.iconPath(of: record)
    }

    /// The name of the item a loot entry points at, and nothing for an entry that is a table: a table's
    /// file name is an identifier rather than a name, and what it holds is what a reader is after.
    private func itemName(at path: String) -> String {
        guard let record = database.record(path), !record.recordClass.hasPrefix("LootItemTable") else { return "" }

        return ItemResolver.itemName(of: record, in: database) ?? ""
    }

    /// The items one loot table can produce, with the share each takes of it.
    ///
    /// Tables nest three ways and this follows all of them: a master table names tables, a level table
    /// names one table per level band — which is why the monster's own level decides what it drops — and
    /// a weighted table names the items. Weights fold along the way, so a share is a share of the whole.
    private func contents(of path: String, atLevel level: Int) -> [MonsterLootEntry.Item] {
        var shares = [String: Double]()
        var names = [String: (name: String, path: String, icon: String)]()

        func walk(_ path: String, share: Double, depth: Int) {
            guard share > 0.0001, depth < Self.lootDepth, let record = database.record(path) else { return }

            switch record.recordClass {
                case let recordClass where recordClass.hasPrefix("Loot"):
                    var children = [(path: String, weight: Double)]()
                    for index in 1 ... 60 {
                        let child = record.text("lootName\(index)")
                        guard !child.isEmpty else { continue }

                        children.append((child, record.number("lootWeight\(index)")))
                    }
                    let total = children.reduce(0) { $0 + $1.weight }
                    guard total > 0 else { return }

                    for child in children {
                        walk(child.path, share: share * child.weight / total, depth: depth + 1)
                    }

                case "LevelTable":
                    // One table per level band, and the monster's own level picks the band.
                    let bands = record["levels"]?.numbers ?? []
                    let tables = record["records"]?.texts ?? []
                    guard !tables.isEmpty else { return }

                    let index = bands.lastIndex { $0 <= Double(level) } ?? 0
                    walk(tables[min(index, tables.count - 1)], share: share, depth: depth + 1)

                default:
                    // Keyed by name rather than by record: the same item is written once per level it
                    // is generated at, and one line each is what a reader wants.
                    guard let name = ItemResolver.itemName(of: record, in: database) else { return }

                    shares[name, default: 0] += share
                    names[name] = (name, path, ItemResolver.iconPath(of: record))
            }
        }

        walk(path, share: 100, depth: 0)
        return
            shares
            .sorted { $0.value > $1.value }
            .prefix(60)
            .map { name, share in
                MonsterLootEntry.Item(
                    name: name,
                    recordPath: names[name]?.path ?? "",
                    iconPath: names[name]?.icon ?? "",
                    share: share
                )
            }
    }
}
