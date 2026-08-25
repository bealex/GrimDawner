// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// The affixes one item can roll, as the game decides them.
///
/// An item's own record says nothing about its affixes. What decides them is the loot table that
/// produces it: a `LootItemTable_DynWeight` lists items in `lootName1…N` and, beside them, the affix
/// tables anything rolled off it draws from — `prefixTableName1…N` and `suffixTableName1…N` for a magic
/// roll, `rarePrefixTableName1…N` and `rareSuffixTableName1…N` for the rare band. An item listed by
/// several tables can roll anything any of them offers.
public struct ItemAffixPool: Sendable {
    /// One affix a table offers, at the band it belongs to.
    public struct Choice: Identifiable, Sendable, Hashable {
        public let path: String
        public let name: String
        public let kind: CataloguedAffix.Kind
        /// Whether it comes from the rare band rather than the magic one.
        public let isRare: Bool
        public let levelRequirement: Int

        public var id: String { path }
    }

    public let prefixes: [Choice]
    public let suffixes: [Choice]

    public init(prefixes: [Choice], suffixes: [Choice]) {
        self.prefixes = prefixes
        self.suffixes = suffixes
    }

    public var isEmpty: Bool { prefixes.isEmpty && suffixes.isEmpty }

    /// What the item at this path can roll. Reading it walks the tables that name the item, which is
    /// one sweep of the loot tree; the database keeps the answer for everything asked after the first.
    public static func of(itemAt path: String, in database: GameDatabase) -> ItemAffixPool {
        let tables = affixTables(in: database)[path.lowercased()] ?? []
        guard !tables.isEmpty else { return ItemAffixPool(prefixes: [], suffixes: []) }

        var prefixes = [String: Choice]()
        var suffixes = [String: Choice]()
        for table in tables {
            for choice in affixes(inTableAt: table.path, kind: table.kind, isRare: table.isRare, in: database) {
                if choice.kind == .prefix {
                    prefixes[choice.path] = choice
                } else {
                    suffixes[choice.path] = choice
                }
            }
        }

        func sorted(_ choices: [String: Choice]) -> [Choice] {
            choices.values.sorted {
                $0.name == $1.name
                    ? $0.path < $1.path : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }

        return ItemAffixPool(prefixes: sorted(prefixes), suffixes: sorted(suffixes))
    }

    /// One affix table's contents, read as choices.
    private static func affixes(
        inTableAt path: String,
        kind: CataloguedAffix.Kind,
        isRare: Bool,
        in database: GameDatabase
    ) -> [Choice] {
        guard let table = database.record(path) else { return [] }

        return table.fieldOrder.compactMap { key in
            guard key.hasPrefix("randomizerName") else { return nil }

            let affix = table.text(key)
            guard !affix.isEmpty, let record = database.record(affix) else { return nil }

            // An affix with no name of its own is one the game never prints; it is still rolled, and a
            // reader picking one is better served by its file name than by a blank line.
            let name =
                database.localised(record.text("lootRandomizerName"))
                ?? (affix as NSString).lastPathComponent.replacingOccurrences(of: ".dbr", with: "")
            return Choice(
                path: affix,
                name: name,
                kind: kind,
                isRare: isRare,
                levelRequirement: record.integer("levelRequirement")
            )
        }
    }

    /// One affix table an item can draw from.
    private struct Table: Sendable, Hashable {
        let path: String
        let kind: CataloguedAffix.Kind
        let isRare: Bool
    }

    /// Every item the loot tree names, and the affix tables named beside it. One sweep of the loot
    /// tables answers it for the whole game, so the database keeps it.
    private static func affixTables(in database: GameDatabase) -> [String: [Table]] {
        database.swept("item-affix-tables") { database -> [String: [Table]] in
            var pools = [String: Set<Table>]()

            database.sweep(prefix: "records/items/loottables/") { _, record in
                guard record.recordClass.hasPrefix("LootItemTable_Dyn") else { return }

                var tables = Set<Table>()
                for key in record.fieldOrder {
                    let named = record.text(key)
                    guard !named.isEmpty else { continue }

                    if key.hasPrefix("prefixTableName") {
                        tables.insert(Table(path: named, kind: .prefix, isRare: false))
                    } else if key.hasPrefix("suffixTableName") {
                        tables.insert(Table(path: named, kind: .suffix, isRare: false))
                    } else if key.hasPrefix("rarePrefixTableName") {
                        tables.insert(Table(path: named, kind: .prefix, isRare: true))
                    } else if key.hasPrefix("rareSuffixTableName") {
                        tables.insert(Table(path: named, kind: .suffix, isRare: true))
                    }
                }
                guard !tables.isEmpty else { return }

                for key in record.fieldOrder where key.hasPrefix("lootName") {
                    let item = record.text(key).lowercased()
                    guard !item.isEmpty else { continue }

                    pools[item, default: []].formUnion(tables)
                }
            }
            return pools.mapValues { Array($0) }
        }
    }
}
