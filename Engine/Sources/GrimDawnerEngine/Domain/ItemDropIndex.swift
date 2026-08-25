// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// Who drops one item, and how often.
public struct ItemDropSource: Codable, Sendable, Identifiable, Hashable {
    /// The monster's own record, so a reader can open it.
    public let monsterPath: String
    public let name: String
    public let rank: MonsterRank
    /// The chance of walking away with the item when that monster dies, as a percentage: the slot's
    /// own chance, the entry's weight and the item's weight in its table, multiplied out.
    public let chance: Double

    public var id: String { monsterPath }

    /// What the app calls a drop worth listing on its own. Below this the roster is thousands of
    /// monsters that could, in principle, produce almost any generated item.
    public static let significant: Double = 1
}

/// Every monster that can drop each item, worked out once for the whole game.
///
/// Nothing states this: the game's tables run the other way, from a monster to what it can leave behind.
/// Answering it for one item means walking every monster's tables, which takes half a minute, so the
/// answer is built once per installed version and kept beside the item and monster listings.
public struct ItemDropIndex: Codable, Sendable {
    /// Bumped whenever an entry means something different, so an older index on disk is discarded.
    public static let version = 1

    public let fingerprint: String
    public let version: Int
    /// Sources by item name, folded. Keyed by name rather than by record because the game writes one
    /// record per level tier of the same item and a table names whichever tier suits its own band: a
    /// reader asking about *Ixall's Blaze* means the item, not the copy written for level 94.
    public let sources: [String: [ItemDropSource]]

    public func sources(forItemNamed name: String) -> [ItemDropSource] {
        (sources[name.lowercased()] ?? []).sorted {
            $0.chance == $1.chance
                ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.chance > $1.chance
        }
    }

    /// Walks every monster that leaves anything behind and records what it can produce.
    ///
    /// `progress` is called with how far along it is, so a caller can say so while it waits.
    public static func build(
        from database: GameDatabase,
        progress: ((Double) -> Void)? = nil
    ) -> ItemDropIndex {
        let skills = SkillResolver(database: database)
        let resolver = MonsterResolver(
            database: database,
            skills: skills,
            items: ItemResolver(database: database, skills: skills)
        )

        var wanted = [(path: String, name: String, rank: MonsterRank)]()
        var seen = Set<String>()
        database.sweep(prefix: "records/creatures/enemies/") { path, record in
            guard
                record.text("Class") == "Monster",
                record.number("dropItems") != 0,
                let rank = MonsterRank(rawValue: record.text("monsterClassification")),
                let name = database.localised(record.text("description")),
                !name.isEmpty
            else { return }

            wanted.append((path, name, rank))
        }

        var sources = [String: [ItemDropSource]]()
        for (index, monster) in wanted.enumerated() {
            progress?(Double(index) / Double(max(wanted.count, 1)))
            // Read at the deepest level it is met at, which is where its own tables are richest.
            guard let resolved = resolver.monster(at: monster.path, level: 100) else { continue }
            // The same monster written once per region drops the same things; one line each is what a
            // reader wants, and the copies would otherwise fill the list with itself.
            guard seen.insert("\(monster.name)|\(monster.rank.rawValue)").inserted else { continue }

            for slot in resolved.loot {
                for entry in slot.entries {
                    for item in entry.items where !item.name.isEmpty {
                        let chance = slot.chance / 100 * entry.share / 100 * item.share
                        guard chance > 0.0001 else { continue }

                        sources[item.name.lowercased(), default: []].append(ItemDropSource(
                            monsterPath: monster.path,
                            name: monster.name,
                            rank: monster.rank,
                            chance: chance
                        ))
                    }
                }
            }
        }
        progress?(1)

        // A monster can reach one item down several paths — two slots, two tables — and those are
        // chances of the same kill, so they add rather than listing the monster twice.
        let merged = sources.mapValues { found -> [ItemDropSource] in
            var byMonster = [String: ItemDropSource]()
            for source in found {
                guard
                    let known = byMonster[source.monsterPath]
                else {
                    byMonster[source.monsterPath] = source
                    continue
                }

                byMonster[source.monsterPath] = ItemDropSource(
                    monsterPath: known.monsterPath,
                    name: known.name,
                    rank: known.rank,
                    chance: known.chance + source.chance
                )
            }
            return Array(byMonster.values)
        }
        return ItemDropIndex(fingerprint: database.fingerprint, version: Self.version, sources: merged)
    }
}

/// Keeps the drop index on disk between launches, as the item and monster listings are kept.
public enum ItemDropIndexStore {
    public static func load(fingerprint: String) -> ItemDropIndex? {
        guard
            let url = fileURL(fingerprint: fingerprint),
            let data = try? Data(contentsOf: url),
            let index = try? JSONDecoder().decode(ItemDropIndex.self, from: data),
            index.fingerprint == fingerprint,
            index.version == ItemDropIndex.version
        else { return nil }

        return index
    }

    public static func save(_ index: ItemDropIndex) {
        guard let url = fileURL(fingerprint: index.fingerprint) else { return }

        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(index).write(to: url, options: .atomic)
        discardOlder(keeping: url)
    }

    private static func fileURL(fingerprint: String) -> URL? {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return caches?.appending(path: "GrimDawner/drops-\(ItemDropIndex.version)-\(fingerprint).json")
    }

    private static func discardOlder(keeping current: URL) {
        let folder = current.deletingLastPathComponent()
        let stale = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("drops-") && $0 != current }

        for url in stale ?? [] { try? FileManager.default.removeItem(at: url) }
    }
}
