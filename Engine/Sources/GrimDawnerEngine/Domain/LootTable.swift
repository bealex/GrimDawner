// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// What a loot table can produce, with the share each item takes of it.
///
/// Tables nest three ways and this follows all of them: a master table names tables, a level table names
/// one table per level band — which is why the level it is read at decides what comes out — and a
/// weighted table names the items. Weights fold along the way, so a share is a share of the whole.
///
/// A monster names one table and a chest names a `fixeditemloot` of its own shape, but both bottom out
/// in the same weighted tables.
public enum LootTable {
    /// How far a table may nest before the walk gives up.
    private static let depth = 6
    /// The most items worth listing out of one table.
    private static let listed = 60
    /// The slots a chest's own table writes, which the template fixes at six.
    private static let containerSlots = 6
    /// The entries one chest slot may name.
    private static let containerEntries = 6

    /// What one weighted table can produce.
    public static func contents(
        of path: String,
        atLevel level: Int,
        in database: GameDatabase
    ) -> [MonsterLootEntry.Item] {
        var walker = Walker(database: database, level: level)
        walker.walk(path, share: 100, depth: 0)
        return walker.items()
    }

    /// What a chest leaves behind, and how many things come out of it.
    ///
    /// A chest's table is not a weighted list but a grid: six slots of named tables, each carrying one
    /// chance per thing the chest drops. Position by position those chances are weighed against one
    /// another, so the first thing out can be drawn from a richer table than the last — which is how a
    /// chest promises a legendary without promising three. A position every slot writes a zero at is
    /// one the chest does not fill, and counting the rest is what says how much comes out.
    ///
    /// Shares are of one thing that comes out, so they total a hundred however many that is.
    public static func contents(
        ofContainerAt path: String,
        atLevel level: Int,
        in database: GameDatabase
    ) -> (items: [MonsterLootEntry.Item], drops: Int) {
        guard let record = database.record(path) else { return ([], 0) }

        let chances = (1 ... containerSlots).map { record["loot\($0)Chance"]?.numbers ?? [] }
        let positions = chances.map(\.count).max() ?? 0
        guard positions > 0 else { return ([], 0) }

        func chance(_ slot: Int, at position: Int) -> Double {
            let values = chances[slot]
            return position < values.count ? values[position] : 0
        }

        var filled = 0
        var walker = Walker(database: database, level: level)
        for position in 0 ..< positions {
            let total = (0 ..< containerSlots).reduce(0.0) { $0 + chance($1, at: position) }
            guard total > 0 else { continue }

            filled += 1
            for slot in 0 ..< containerSlots where chance(slot, at: position) > 0 {
                walker.walk(slot: record, number: slot + 1, share: 100 * chance(slot, at: position) / total)
            }
        }
        guard filled > 0 else { return ([], 0) }

        return (walker.items(dividedBy: Double(filled)), filled)
    }

    /// Follows tables down to the items, gathering what each is worth on the way.
    private struct Walker {
        let database: GameDatabase
        let level: Int

        private var shares = [String: Double]()
        private var found = [String: (path: String, icon: String, rarity: ItemRarity)]()

        init(database: GameDatabase, level: Int) {
            self.database = database
            self.level = level
        }

        /// One slot of a chest's table: the tables it names, weighed against each other.
        mutating func walk(slot record: ArzRecord, number: Int, share: Double) {
            var entries = [(path: String, weight: Double)]()
            for index in 1 ... LootTable.containerEntries {
                let path = record.text("loot\(number)Name\(index)")
                guard !path.isEmpty else { continue }

                entries.append((path, record.number("loot\(number)Weight\(index)")))
            }
            let total = entries.reduce(0) { $0 + $1.weight }
            guard total > 0 else { return }

            for entry in entries {
                walk(entry.path, share: share * entry.weight / total, depth: 0)
            }
        }

        mutating func walk(_ path: String, share: Double, depth: Int) {
            guard share > 0.0001, depth < LootTable.depth, let record = database.record(path) else { return }

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
                    // One table per level band, and the level it is read at picks the band.
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
                    found[name] = (
                        path,
                        ItemResolver.iconPath(of: record),
                        ItemRarity(recordClass: record.recordClass)
                            ?? ItemRarity(classification: record.text("itemClassification"))
                    )
            }
        }

        func items(dividedBy divisor: Double = 1) -> [MonsterLootEntry.Item] {
            shares
                // Ties are broken by name: a dictionary hands them over in a different order every
                // launch, and what is drawn from this list — the weapon a monster is holding — would
                // change with it.
                .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                .prefix(LootTable.listed)
                .map { name, share in
                    MonsterLootEntry.Item(
                        name: name,
                        recordPath: found[name]?.path ?? "",
                        iconPath: found[name]?.icon ?? "",
                        share: share / divisor,
                        rarity: found[name]?.rarity ?? .common
                    )
                }
        }
    }
}
