// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// Builds mastery panels from a save's skill entries.
///
/// Panel geometry comes from the game's own UI records (`records/ui/skills/…`), so a panel matches the
/// in-game window rather than an invented arrangement.
public struct SkillResolver {
    public init(database: GameDatabase) { self.database = database }

    public let database: GameDatabase

    private static let masteryMarker = "_classtraining_"
    /// A pet record names its abilities in numbered slots; seventeen is as many as the game writes.
    private static let petSkillSlots = 17

    /// Skill record classes whose bonuses apply without the player pressing anything — passives, and the
    /// toggled auras a character leaves running.
    private static let alwaysOnClasses: Set<String> = [
        "Skill_Passive",
        "SkillBuff_Passive",
        "Skill_BuffSelfToggled",
        "Skill_BuffRadiusToggled",
        "Skill_BuffAttackRadiusToggled",
        "Skill_Transmuter",
    ]

    /// True when a skill is permanently in effect, which is what a character sheet may count.
    ///
    /// A celestial power is an attack or a timed buff: its numbers are the proc's own damage, not the
    /// character's, and adding them to the sheet would inflate every damage line it touches. So is a
    /// passive that waits on a condition — `Skill_PassiveOnLifeBuffSelf` only wakes at low health.
    public static func isAlwaysOn(_ record: ArzRecord) -> Bool {
        isAlwaysOn(recordClass: record.recordClass)
    }

    public static func isAlwaysOn(recordClass: String) -> Bool {
        alwaysOnClasses.contains(recordClass)
    }

    /// The class the game gives a modifier: a round node hanging off the skill it changes.
    public static let modifierClass = "Skill_Modifier"

    /// Ties every modifier to the skill it hangs off.
    ///
    /// The panel is where the game states this: a modifier sits along its parent's row, to the right of
    /// it, with only other modifiers of the same parent in between. Reading the connector tiles instead
    /// would miss the parents that have no connector list — `elementalinfusion1` is one.
    private static func linkedToWhatTheyModify(_ skills: [ResolvedSkill]) -> [ResolvedSkill] {
        let placed = skills.filter { $0.position != .zero }

        return skills.map { skill in
            guard skill.isModifier, skill.position != .zero else { return skill }

            // The same row only: a transmuter hangs half a row below the skill it changes, and a modifier
            // belongs to the skill the row starts with rather than to that transmuter.
            let candidates = placed.filter {
                !$0.isModifier && $0.position.y == skill.position.y && $0.position.x < skill.position.x
            }
            guard let parent = candidates.max(by: { $0.position.x < $1.position.x }) else { return skill }

            return skill.modifying(parent.recordPath)
        }
    }

    public func masteries(
        from save: Gdc.SaveFile,
        gearBonuses: StatBlock,
        devotionBonuses: StatBlock
    ) -> [ResolvedMastery] {
        let spent = Dictionary(
            save.skills.skills.map { ($0.name.lowercased(), Int($0.level)) },
            uniquingKeysWith: { first, _ in first }
        )

        return save.skills.skills
            .filter { $0.name.lowercased().contains(Self.masteryMarker) && $0.level > 0 }
            .compactMap {
                mastery(path: $0.name, level: Int($0.level), spent: spent, gear: gearBonuses, devotion: devotionBonuses)
            }
    }

    /// Skills a character has that no mastery panel claims — item-granted abilities and the like.
    public func looseSkills(from save: Gdc.SaveFile, claimed: Set<String>) -> [ResolvedSkill] {
        save.skills.skills
            .filter { entry in
                entry.level > 0 && entry.isDevotion == 0
                    && !claimed.contains(entry.name.lowercased())
                    && !entry.name.lowercased().contains("/skills/default/")
            }
            .compactMap { skill(at: $0.name, level: Int($0.level)) }
    }

    /// What a `Skill_Modifier` record an item names changes about the skill it points at.
    public func changes(of modifier: ArzRecord, atLevel level: Int) -> SkillChanges {
        // A change to a summon or a mine keeps its numbers on the record `petSkillName` names.
        let record = database.record(modifier.text("petSkillName")) ?? modifier
        var stats = stats(of: record, atLevel: level)
        for suffix in [ "", "2", "3", "4" ] {
            let percent = record.number("conversionPercentage\(suffix)")
            guard
                percent != 0,
                case let source = record.text("conversionInType\(suffix)"),
                case let target = record.text("conversionOutType\(suffix)"),
                !source.isEmpty,
                !target.isEmpty
            else { continue }

            stats.addConversion(StatBlock.Conversion(source: source, target: target, percent: percent))
        }
        return SkillChanges(stats: stats, parameters: parameters(of: record, atLevel: level))
    }

    /// The mastery a skill belongs to, which its record's `playerclassNN` folder names.
    public func masteryName(ofSkillAt path: String) -> String? {
        guard
            let identifier = Self.classIdentifier(from: path),
            let table = database.record("records/ui/skills/\(identifier)/classtable.dbr")
        else { return nil }

        return database.localised(table.text("skillTabTitle"))
    }

    /// One skill outside a mastery panel — an ability an item grants, or a devotion star.
    public func skill(at path: String, level: Int) -> ResolvedSkill? {
        guard let record = database.record(path) else { return nil }

        return skill(record: record, path: path, ranks: Ranks(spent: level), button: nil)
    }

    // MARK: - Masteries

    private func mastery(
        path: String,
        level: Int,
        spent: [String: Int],
        gear: StatBlock,
        devotion: StatBlock
    ) -> ResolvedMastery? {
        guard
            let record = database.record(path),
            let classIdentifier = Self.classIdentifier(from: path),
            let table = database.record("records/ui/skills/\(classIdentifier)/classtable.dbr")
        else { return nil }

        var skills = [ResolvedSkill]()
        for buttonPath in table["tabSkillButtons"]?.texts ?? [] {
            guard
                let button = database.record(buttonPath),
                case let skillPath = button.text("skillName"),
                !skillPath.isEmpty,
                !skillPath.lowercased().contains(Self.masteryMarker),
                let skillRecord = database.record(skillPath)
            else { continue }

            skills.append(skill(
                record: skillRecord,
                path: skillPath,
                ranks: Ranks(
                    spent: spent[skillPath.lowercased()] ?? 0,
                    devotion: devotion.bonus(forSkill: skillPath, mastery: path),
                    items: gear.bonus(forSkill: skillPath, mastery: path)
                ),
                button: Button(record: button)
            ))
        }
        skills = Self.linkedToWhatTheyModify(skills)

        return ResolvedMastery(
            recordPath: path,
            name: database.localised(table.text("skillTabTitle")) ?? skillName(record, path: path),
            iconPath: database.bitmap(inRecordAt: table.text("skillPaneMasteryBitmap")),
            level: level,
            maxLevel: max(1, record.integer("skillMaxLevel")),
            skills: skills,
            bonuses: stats(of: record, atLevel: level),
            panel: LayoutResolver(database: database).masteryPanel(classTable: table)
        )
    }

    /// Where a skill's ranks come from, kept together so the builder reads as one idea.
    private struct Ranks {
        public var spent: Int = 0
        public var devotion: Int = 0
        public var items: Int = 0
    }

    /// The panel button a skill is drawn on, when it has one.
    private struct Button {
        public let position: CGPoint
        public let frame: String
        public let iconOffset: CGPoint

        public init(record: ArzRecord) {
            position = CGPoint(x: record.number("bitmapPositionX"), y: record.number("bitmapPositionY"))
            frame = record.text("bitmapNameUp")
            iconOffset = CGPoint(x: record.number("skillOffsetX"), y: record.number("skillOffsetY"))
        }
    }

    private func skill(
        record: ArzRecord,
        path: String,
        ranks: Ranks,
        button: Button?,
        summons: Bool = true
    ) -> ResolvedSkill {
        let baseLevel = ranks.spent
        let devotionBonus = ranks.devotion
        let itemBonus = ranks.items

        // A skill that only drives a buff states no ranks of its own; the buff it drives holds them,
        // along with the per-rank arrays. Reading the ceiling from the skill alone pins such a skill at
        // rank 1 however many points and item bonuses it has.
        let ranked = record.integer("skillMaxLevel") > 0 ? record : (linkedRecord(of: record) ?? record)
        let maxLevel = max(1, ranked.integer("skillMaxLevel"))
        let ultimateLevel = max(maxLevel, ranked.integer("skillUltimateLevel"))
        let rank = baseLevel > 0 ? min(baseLevel + devotionBonus + itemBonus, ultimateLevel) : 0

        return ResolvedSkill(
            recordPath: path,
            recordClass: record.recordClass,
            modifies: nil,
            name: skillName(record, path: path),
            properName: properName(of: record),
            description: description(of: record) ?? "",
            baseLevel: baseLevel,
            devotionBonus: devotionBonus,
            itemBonus: itemBonus,
            maxLevel: maxLevel,
            ultimateLevel: ultimateLevel,
            tier: record.integer("skillTier"),
            position: button?.position ?? .zero,
            frame: button?.frame ?? "",
            iconOffset: button?.iconOffset ?? .zero,
            iconPath: skillIcon(record),
            connectors: Self.connectors(of: record),
            parameters: parameters(of: record, atLevel: max(rank, 1)),
            petBonus: petBonus(of: record, atLevel: max(rank, 1)),
            // A pet's own abilities are read without theirs, so a summon that summons cannot recurse.
            summon: summons ? summon(of: record) : nil,
            stats: effects(of: record, atLevel: max(rank, 1))
        )
    }

    /// What a skill adds to every pet the character has, which the game prints as a block of its own.
    private func petBonus(of record: ArzRecord, atLevel level: Int) -> StatBlock {
        guard let bonus = database.record(record.text("petBonusName")) else { return StatBlock() }

        return stats(of: bonus, atLevel: level)
    }

    /// What a skill puts on the field, for the classes that spawn one.
    public func summon(of record: ArzRecord) -> ResolvedSummon? {
        guard let pet = database.record(record.text("spawnObjects")) else { return nil }

        var abilities = [ResolvedSkill]()
        var stats = stats(of: pet, atLevel: 1)

        for index in 1 ... Self.petSkillSlots {
            guard
                case let path = pet.text("skillName\(index)"),
                !path.isEmpty,
                let ability = database.record(path)
            else { continue }

            let level = max(pet.integer("skillLevel\(index)"), 1)
            // A pet's unnamed skills are its own adjusters — armour, damage, resistances. The game
            // folds them into what the pet is; only the named ones read as abilities.
            guard
                database.localised(ability.text("skillDisplayName")) != nil
            else {
                stats.merge(effects(of: ability, atLevel: level))
                continue
            }

            abilities.append(skill(
                record: ability,
                path: path,
                ranks: Ranks(spent: level),
                button: nil,
                summons: false
            ))
        }

        return ResolvedSummon(
            name: petName(pet, summonedBy: record),
            recordPath: record.text("spawnObjects"),
            isMonster: pet.text("Class") == "Monster",
            timeToLive: record.number("spawnObjectsTimeToLive"),
            limit: record.integer("petLimit"),
            stats: stats,
            skills: abilities
        )
    }

    /// A pet record rarely names itself; the game shows the summon by the skill that calls it.
    private func petName(_ pet: ArzRecord, summonedBy skill: ArzRecord) -> String {
        if let name = database.localised(pet.text("description")) { return name }

        return skillName(skill, path: skill.path)
    }

    /// What a skill does at a rank, its own numbers and those of the buff it drives.
    ///
    /// A skill can carry both — the activation on itself, the effect on the buff — so the two are
    /// merged rather than one chosen over the other.
    public func effects(of record: ArzRecord, atLevel level: Int) -> StatBlock {
        var own = stats(of: record, atLevel: level)
        guard let linked = linkedRecord(of: record) else { return own }

        own.merge(stats(of: linked, atLevel: level))
        return own
    }

    private static func connectors(of record: ArzRecord) -> [SkillConnector] {
        let textures = record["skillConnectionOn"]?.texts ?? []
        return textures.enumerated().map { SkillConnector(step: $0.offset, texture: $0.element) }
    }

    /// One of the level-indexed numbers the game puts at the top of a skill's tooltip.
    private struct ParameterField {
        public let key: String
        public let name: String
        public var unit: String = ""
    }

    private static let parameterFields: [ParameterField] = [
        ParameterField(key: "skillCooldownTime", name: "Cooldown", unit: "s"),
        ParameterField(key: "skillManaCost", name: "Energy Cost"),
        ParameterField(key: "skillActiveDuration", name: "Duration", unit: "s"),
        ParameterField(key: "skillTargetRadius", name: "Radius", unit: "m"),
        ParameterField(key: "skillTargetNumber", name: "Targets"),
        ParameterField(key: "skillProjectileNumber", name: "Projectiles"),
    ]

    public func parameters(of record: ArzRecord, atLevel level: Int) -> [SkillParameter] {
        Self.parameterFields.compactMap { field -> SkillParameter? in
            guard let numbers = record[field.key]?.numbers, !numbers.isEmpty else { return nil }

            let value = numbers[min(max(0, level - 1), numbers.count - 1)]
            guard value != 0 else { return nil }

            let rounded = value == value.rounded() ? "%.0f" : "%.1f"
            return SkillParameter(name: field.name, value: String(format: rounded, value) + field.unit)
        }
    }

    // MARK: - Levelled values

    /// Reads a record's catalogued stats at a given skill level.
    ///
    /// Skill records store most numbers as arrays indexed by level, so a rank-12 aura and a rank-1 aura
    /// read different elements of the same field.
    public func stats(of record: ArzRecord, atLevel level: Int) -> StatBlock {
        var block = StatBlock()
        let index = max(0, level - 1)

        for (key, value) in record.fields {
            guard StatCatalog.definition(for: key) != nil else { continue }

            let numbers = value.numbers
            guard !numbers.isEmpty else { continue }

            block.increase(key, by: numbers[min(index, numbers.count - 1)])
        }

        return block
    }

    // MARK: - Naming

    /// The name the game itself gives a skill, following the same link its own tooltip does. Nothing for
    /// a record that carries none, which is most of what a monster fights with.
    private func properName(of record: ArzRecord) -> String? {
        if let name = database.localised(record.text("skillDisplayName")) { return name }

        return linkedRecord(of: record).flatMap { database.localised($0.text("skillDisplayName")) }
    }

    /// Some skills carry their name only on the buff or pet record they drive, so follow that link before
    /// falling back to the record's file name.
    private func skillName(_ record: ArzRecord, path: String) -> String {
        if let name = database.localised(record.text("skillDisplayName")) { return name }
        if let linked = linkedRecord(of: record), let name = database.localised(linked.text("skillDisplayName")) {
            return name
        }

        let fallback = record.text("FileDescription")
        return fallback.isEmpty ? ItemResolver.readableName(from: path) : fallback
    }

    /// Artwork follows the same link as the name: a skill that only drives a buff has neither of its own.
    private func skillIcon(_ record: ArzRecord) -> String {
        let icon = record.text("skillUpBitmapName")
        guard icon.isEmpty else { return icon }

        return linkedRecord(of: record)?.text("skillUpBitmapName") ?? ""
    }

    /// The buff or pet a skill drives, which is where the game keeps that skill's own presentation.
    private func linkedRecord(of record: ArzRecord) -> ArzRecord? {
        for link in [ "buffSkillName", "petSkillName" ] {
            guard case let path = record.text(link), !path.isEmpty, let target = database.record(path) else { continue }

            return target
        }
        return nil
    }

    private func description(of record: ArzRecord) -> String? {
        if let text = database.localised(record.text("skillBaseDescription")) { return text }

        return linkedRecord(of: record).flatMap { database.localised($0.text("skillBaseDescription")) }
    }

    /// `records/skills/playerclass05/…` → `class05`, the folder its UI records live in.
    private static func classIdentifier(from path: String) -> String? {
        guard let range = path.range(of: "playerclass") else { return nil }

        let digits = path[range.upperBound...].prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }

        return "class" + digits
    }
}
