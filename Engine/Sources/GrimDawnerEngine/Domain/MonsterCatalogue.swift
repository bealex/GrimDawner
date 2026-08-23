// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// What the game calls a monster's rank, in the order it grows dangerous.
public enum MonsterRank: String, Codable, Sendable, CaseIterable, Comparable {
    case common = "Common"
    case champion = "Champion"
    case hero = "Hero"
    case quest = "Quest"
    case boss = "Boss"
    case superBoss = "SuperBoss"

    public var title: String { self == .superBoss ? "Super Boss" : rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (allCases.firstIndex(of: lhs) ?? 0) < (allCases.firstIndex(of: rhs) ?? 0)
    }
}

/// One monster of the listing: what it is called, what it belongs to, and how deep it is met.
public struct CataloguedMonster: Codable, Sendable, Identifiable {
    public let path: String
    public let name: String
    public let rank: MonsterRank
    /// The faction pack the record puts it in: who it counts as for hostility and for what killing it
    /// does to a standing. Most creatures carry the Aetherials' whatever they are made of, so this says
    /// less about a monster than it looks like it does.
    public let faction: String
    /// The faction whose nemesis this is, which is the faction that actually owns it. Empty otherwise.
    public var nemesisOf: String = ""
    /// The race the game's "damage to <race>" bonuses name — Beast, Undead, Chthonic.
    public let race: String
    public let minLevel: Int
    public let maxLevel: Int
    /// Whether it drops anything at all, since much of the roster is scenery that does not.
    public let dropsLoot: Bool
    /// The record's own file name, carried only where several records share a name and differ in what
    /// they hold — three Ravagers of Minds are three different fights.
    public var variant: String = ""

    public var id: String { path }
}

/// One line of the listing, with its text folded once so the search never folds it again.
public struct MonsterEntry: Identifiable, Sendable {
    public let monster: CataloguedMonster
    public let folded: String

    public var id: String { monster.path }

    public init(_ monster: CataloguedMonster) {
        self.monster = monster
        folded = QuickSearch.folded([ monster.name, monster.faction, monster.race, monster.rank.title ].joined())
    }
}

/// Every monster in the game, listed once per installed version and kept on disk.
public struct MonsterCatalogue: Codable, Sendable {
    /// Bumped whenever an entry means something different, so an older listing on disk is discarded.
    public static let version = 4

    public let fingerprint: String
    public let version: Int
    public let monsters: [CataloguedMonster]

    public static func build(from database: GameDatabase) -> MonsterCatalogue {
        var monsters = [CataloguedMonster]()
        var signatures = [String: String]()
        let factions = Self.factionNames(in: database)
        let nemeses = Self.nemeses(in: database)

        database.sweep(prefix: "records/creatures/enemies/") { path, record in
            guard
                record.text("Class") == "Monster",
                let rank = MonsterRank(rawValue: record.text("monsterClassification")),
                let name = database.localised(record.text("description")),
                !name.isEmpty
            else { return }

            monsters.append(CataloguedMonster(
                path: path,
                name: name,
                rank: rank,
                faction: factions[record.text("factions").lowercased()] ?? "",
                nemesisOf: nemeses[name] ?? "",
                race: database.localised("tag" + record.text("characterRacialProfile")) ?? "",
                minLevel: Int(record.number("minLevel")),
                maxLevel: Int(record.number("maxLevel")),
                dropsLoot: record.number("dropItems") != 0
            ))
            signatures[path] = Self.signature(of: record)
        }
        // The same monster is written once per region it is met in, and those copies differ in where
        // they spawn rather than in what they are. One line each is what a reader wants.
        var seen = Set<String>()
        let listed =
            monsters
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .filter { seen.insert("\($0.name)|\($0.rank.rawValue)|\($0.faction)").inserted }

        return MonsterCatalogue(fingerprint: database.fingerprint, version: Self.version, monsters: listed)
    }

    /// Which faction each nemesis belongs to, by the nemesis's own name.
    ///
    /// A monster's own record does not say: Kubacabra is the Beasts' nemesis and its record names the
    /// Aetherials. The faction pack is what says so, through `nemesisSpawn`, and a nemesis is written as
    /// several records — one per phase — that share a name.
    public static func nemeses(in database: GameDatabase) -> [String: String] {
        var names = [String: String]()

        database.sweep(prefix: "records/controllers/factions/") { _, record in
            guard
                case let spawn = record.text("nemesisSpawn"),
                !spawn.isEmpty,
                let monster = database.record(spawn),
                let name = database.localised(monster.text("description")),
                case let identifier = record.text("myFaction"),
                !identifier.isEmpty
            else { return }

            names[name] = database.localised("tagFaction" + identifier) ?? identifier
        }
        return names
    }

    /// What makes one monster record different from another that shares its name: what it fights with,
    /// what it is worth and what it leaves behind. Where a region simply repeats a monster, this string
    /// is the same and the copy collapses.
    private static func signature(of record: ArzRecord) -> String {
        let interesting = [
            "characterAttributeEquations", "monsterClassification", "factions", "characterRacialProfile",
            "minLevel", "maxLevel", "experiencePoints", "attackSkillName", "dyingSkillName",
        ]
        var parts = [String]()

        for field in record.fieldOrder {
            guard
                interesting.contains(field)
                    || field.hasPrefix("skillName") || field.hasPrefix("skillLevel")
                    || field.hasPrefix("specialAttack") || field.hasPrefix("loot")
                    || field.hasPrefix("chanceToEquip") || field.hasPrefix("defensive")
            else { continue }

            let text = record.text(field)
            parts.append("\(field)=\(text.isEmpty ? String(record.number(field)) : text)")
        }
        return parts.joined(separator: ";")
    }

    /// What each faction record is called, by its own path: a monster names the record, and the record
    /// names the faction the reputation window shows.
    private static func factionNames(in database: GameDatabase) -> [String: String] {
        var names = [String: String]()

        database.sweep(prefix: "records/controllers/factions/") { path, record in
            let identifier = record.text("myFaction")
            guard !identifier.isEmpty else { return }

            names[path.lowercased()] = database.localised("tagFaction" + identifier) ?? identifier
        }
        return names
    }
}

/// Keeps the monster listing on disk between launches, as the item directory does.
public enum MonsterCatalogueStore {
    public static func load(fingerprint: String) -> MonsterCatalogue? {
        guard
            let url = fileURL(fingerprint: fingerprint),
            let data = try? Data(contentsOf: url),
            let catalogue = try? JSONDecoder().decode(MonsterCatalogue.self, from: data),
            catalogue.fingerprint == fingerprint,
            catalogue.version == MonsterCatalogue.version
        else { return nil }

        return catalogue
    }

    public static func save(_ catalogue: MonsterCatalogue) {
        guard let url = fileURL(fingerprint: catalogue.fingerprint) else { return }

        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(catalogue).write(to: url, options: .atomic)
        discardOlderCatalogues(keeping: url)
    }

    private static func fileURL(fingerprint: String) -> URL? {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return caches?.appending(path: "GrimDawner/monsters-\(MonsterCatalogue.version)-\(fingerprint).json")
    }

    private static func discardOlderCatalogues(keeping current: URL) {
        let folder = current.deletingLastPathComponent()
        let stale = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("monsters-") && $0 != current }

        for url in stale ?? [] { try? FileManager.default.removeItem(at: url) }
    }
}
