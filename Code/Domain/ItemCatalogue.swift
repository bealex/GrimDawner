// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// One line of the item directory: enough to list and search on, not the whole item.
struct CataloguedItem: Codable, Identifiable, Sendable {
    /// The record's path, which is also how the full item is read back.
    let path: String
    let name: String
    let iconPath: String
    /// The record's class, as the game writes it — `WeaponMelee_Sword`, `ArmorProtective_Head`.
    let recordClass: String
    let rarity: Int
    let itemLevel: Int
    let levelRequirement: Int
    /// The stats the item carries, by the names the sheet shows, so the directory can be filtered by them.
    let stats: [String]

    /// The three crafting classes the game names differently from their record class.
    static let craftingKinds = [
        "ItemRelic": "Component", "ItemArtifact": "Relic", "ItemEnchantment": "Augment",
    ]

    var id: String { path }

    var quality: ItemRarity { ItemRarity(rawValue: rarity) ?? .common }

    /// What kind of thing it is, from the tail of its class: `ArmorJewelry_Amulet` reads as "Amulet",
    /// `WeaponMelee_Axe2h` as "Axe (2-handed)".
    var kind: String {
        if let kind = Self.craftingKinds[recordClass] { return kind }

        let tail = recordClass.split(separator: "_").last.map(String.init) ?? recordClass
        var words = ""
        for character in tail {
            if character.isUppercase, !words.isEmpty { words.append(" ") }
            words.append(character)
        }

        for hands in [ "1", "2" ] where words.hasSuffix("\(hands)h") {
            return "\(words.dropLast(2)) (\(hands)-handed)"
        }
        return words
    }
}

/// A catalogued item with everything searchable about it folded once, ready for the search field.
struct DirectoryEntry: Identifiable, Sendable {
    let item: CataloguedItem
    let folded: String

    var id: String { item.path }

    init(_ item: CataloguedItem) {
        self.item = item
        folded = QuickSearch.folded(([ item.name, item.kind ] + item.stats).joined())
    }
}

/// Every named item in the game, listed once per installed version and kept on disk.
struct ItemCatalogue: Codable, Sendable {
    /// Bumped whenever an entry means something different, so an older listing on disk is discarded.
    static let version = 4

    /// The database this was built from; a patched game produces a different one and is listed again.
    let fingerprint: String
    let version: Int
    let items: [CataloguedItem]

    /// The record trees worth listing. Everything else under `records/items` is loot tables, affixes,
    /// lore notes and potions, none of which the directory is for.
    private static let itemClassPrefixes = [ "Armor", "Weapon" ]

    static func build(from database: GameDatabase) -> ItemCatalogue {
        var items = [CataloguedItem]()

        database.sweep(prefix: "records/items/") { path, record in
            let recordClass = record.recordClass
            guard
                Self.itemClassPrefixes.contains(where: { recordClass.hasPrefix($0) })
                    || CataloguedItem.craftingKinds[recordClass] != nil,
                let name = ItemResolver.itemName(of: record, in: database),
                !name.isEmpty
            else { return }

            items.append(CataloguedItem(
                path: path,
                name: name,
                iconPath: Self.iconPath(of: record),
                recordClass: recordClass,
                rarity: Self.rarity(of: record, at: path).rawValue,
                itemLevel: record.integer("itemLevel"),
                levelRequirement: record.integer("levelRequirement"),
                stats: Self.statTitles(of: record)
            ))
        }

        // An item is written once per level tier, so its variants read in order under the one name.
        items.sort {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.levelRequirement < $1.levelRequirement : order == .orderedAscending
        }
        return ItemCatalogue(fingerprint: database.fingerprint, version: Self.version, items: items)
    }

    /// The names of the stats a record actually carries; a field left at zero grants nothing.
    private static func statTitles(of record: ArzRecord) -> [String] {
        var titles = [String]()
        for (key, value) in record.fields {
            guard
                value.number != 0,
                let title = StatCatalog.definition(for: key)?.title,
                !titles.contains(title)
            else { continue }

            titles.append(title)
        }
        return titles.sorted()
    }

    private static func iconPath(of record: ArzRecord) -> String {
        for key in [ "bitmap", "artifactBitmap", "relicBitmap", "shardBitmap" ] {
            let path = record.text(key)
            if !path.isEmpty { return path }
        }
        return ""
    }

    private static func rarity(of record: ArzRecord, at path: String) -> ItemRarity {
        if let crafting = ItemRarity(recordClass: record.recordClass) { return crafting }
        if path.contains("/questitems/") { return .quest }

        return ItemRarity(classification: record.text("itemClassification"))
    }
}

/// Keeps the catalogue on disk between launches, since listing 26,000 records is not a per-launch job.
enum ItemCatalogueStore {
    /// Reads the catalogue for this database, or nothing when the game has been patched since.
    static func load(fingerprint: String) -> ItemCatalogue? {
        guard
            let url = fileURL(fingerprint: fingerprint),
            let data = try? Data(contentsOf: url),
            let catalogue = try? JSONDecoder().decode(ItemCatalogue.self, from: data),
            catalogue.fingerprint == fingerprint,
            catalogue.version == ItemCatalogue.version
        else { return nil }

        return catalogue
    }

    static func save(_ catalogue: ItemCatalogue) {
        guard let url = fileURL(fingerprint: catalogue.fingerprint) else { return }

        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(catalogue).write(to: url, options: .atomic)
        discardOlderCatalogues(keeping: url)
    }

    private static func fileURL(fingerprint: String) -> URL? {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return caches?.appending(path: "GrimDawner/items-\(ItemCatalogue.version)-\(fingerprint).json")
    }

    /// A patched game leaves its predecessor's listing behind; only the current one is worth keeping.
    private static func discardOlderCatalogues(keeping current: URL) {
        let folder = current.deletingLastPathComponent()
        let stale = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("items-") && $0 != current }

        for url in stale ?? [] { try? FileManager.default.removeItem(at: url) }
    }
}
