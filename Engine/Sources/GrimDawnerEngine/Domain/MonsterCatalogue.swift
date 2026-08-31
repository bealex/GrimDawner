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

/// What a record in the monster roster actually is.
///
/// Much of the roster is not a creature. The game spawns hazards, traps and pieces of scenery as monsters
/// so that they can be hit and can hit back — *Blizzard* and *Cave-In* are weather with a health bar,
/// *Floor Spikes* are a floor, *Warding Totem* is a totem. Where the game keeps the model says which: an
/// anomaly is drawn from `creatures/anomalies`, a trap from the effect meshes under `fx/meshfx`, an
/// object from the level art or the breakables. A record that dresses itself in armour is a creature
/// whatever its own model is, since only a creature is dressed — which is what the Avatar of Mogdrogen
/// needs, its own model being a headdress.
public enum MonsterKind: String, Codable, Sendable, CaseIterable {
    case creature
    /// Weather and gas: a hazard the game gives no body at all, drawn as an effect and nothing else.
    case anomaly
    /// A thing placed on the ground that goes off — spikes, a mine, a flare.
    case trap
    /// Scenery brought to life: a totem, a nest, a training dummy, a pile of bones.
    case object

    public var title: String {
        switch self {
            case .creature: "Creature"
            case .anomaly: "Anomaly"
            case .trap: "Trap"
            case .object: "Object"
        }
    }

    /// Whether it is a living thing rather than something the game merely spawns as one.
    public var isCreature: Bool { self == .creature }

    /// What the record is, from the model it is drawn with and whether it is dressed.
    public static func of(_ record: ArzRecord) -> MonsterKind {
        let dressed = [ "Head", "Shoulders", "Chest", "Legs", "Feet", "Hands" ]
            .contains { !record.text("default\($0)Piece").isEmpty }
        guard !dressed else { return .creature }

        let mesh = record.text("mesh").lowercased()
        if mesh.hasPrefix("creatures/anomalies/") { return .anomaly }
        if mesh.hasPrefix("fx/meshfx/") { return .trap }
        if mesh.hasPrefix("level art/") || mesh.hasPrefix("items/") { return .object }

        return .creature
    }
}

/// One monster of the listing: what it is called, what it belongs to, and how deep it is met.
public struct CataloguedMonster: Codable, Sendable, Identifiable {
    public let path: String
    public let name: String
    public let rank: MonsterRank
    /// Whether it is a creature at all, or a hazard the game spawns as one.
    public var kind: MonsterKind = .creature
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
    /// Which fight of a several-stage boss this is, for the records the game chains through death. Nil
    /// for everything met in one piece.
    public var phase: Int?
    /// Where the game keeps the record, which is the only thing telling two of the same name apart: the
    /// Kubacabra under `enemies/nemesis` and the one under `enemies/special/fun` are otherwise identical.
    public var origin: String = ""

    public var id: String { path }

    /// What to call it in a listing: a phase says which one it is, since the stages are different fights.
    public var title: String {
        guard let phase else { return name }

        return "\(name) (Phase \(phase))"
    }
}

/// One line of the listing, with its text folded once so the search never folds it again.
public struct MonsterEntry: Identifiable, Sendable {
    public let monster: CataloguedMonster
    public let folded: String

    public var id: String { monster.path }

    public init(_ monster: CataloguedMonster) {
        self.monster = monster
        folded = QuickSearch.folded(
            [ monster.title, monster.faction, monster.race, monster.rank.title, monster.kind.title ].joined()
        )
    }
}

/// Every monster in the game, listed once per installed version and kept on disk.
public struct MonsterCatalogue: Codable, Sendable {
    /// Bumped whenever an entry means something different, so an older listing on disk is discarded.
    public static let version = 7

    public let fingerprint: String
    public let version: Int
    public let monsters: [CataloguedMonster]

    public static func build(from database: GameDatabase) -> MonsterCatalogue {
        var monsters = [CataloguedMonster]()
        var signatures = [String: String]()
        let factions = Self.factionNames(in: database)
        let nemeses = Self.nemeses(in: database)
        let phases = MonsterPhases.map(in: database)

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
                kind: MonsterKind.of(record),
                faction: factions[record.text("factions").lowercased()] ?? "",
                nemesisOf: nemeses[name] ?? "",
                race: database.localised("tag" + record.text("characterRacialProfile")) ?? "",
                minLevel: Int(record.number("minLevel")),
                maxLevel: Int(record.number("maxLevel")),
                dropsLoot: record.number("dropItems") != 0,
                phase: phases[path.lowercased()],
                origin: Self.origin(ofRecordAt: path)
            ))
            signatures[path] = Self.signature(of: record)
        }
        // The same monster is written once per region it is met in, and those copies differ in where
        // they spawn rather than in what they are. One line each is what a reader wants.
        var seen = Set<String>()
        let listed =
            monsters
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            // A phase is its own line: the stages of one fight are different creatures with different
            // models, different skills, and — usually — loot on the last of them alone.
            .filter {
                seen.insert("\($0.name)|\($0.rank.rawValue)|\($0.faction)|\($0.phase ?? 0)|\($0.origin)")
                    .inserted
            }

        return MonsterCatalogue(fingerprint: database.fingerprint, version: Self.version, monsters: listed)
    }

    /// What the game's own folders say a record is for.
    ///
    /// Nothing in a record states this — the roster's shape is the folder tree — so the folder is read
    /// instead, most particular first: `enemies/special/fun` before `enemies/special`. It is what lets a
    /// reader tell the Kubacabra that is fought from the joke copy of it that is not.
    public static func origin(ofRecordAt path: String) -> String {
        let folders: [(String, String)] = [
            ("/nemesis/", "Nemesis"),
            ("/special/fun/", "Fun"),
            ("/bounties/", "Bounty"),
            ("/devotion/", "Devotion"),
            ("/waveevent", "Wave Event"),
            ("/boss&quest/", "Boss & Quest"),
            ("/hero/", "Hero"),
            ("/faction/", "Faction"),
            ("/special/", "Special"),
            ("/anomalies/", "Anomaly"),
            ("/ambient/", "Ambient"),
            ("/npcs/", "NPC"),
        ]
        let lowered = path.lowercased()
        if lowered.hasPrefix("records/endlessdungeon/") { return "Shattered Realm" }

        return folders.first { lowered.contains($0.0) }?.1 ?? ""
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
