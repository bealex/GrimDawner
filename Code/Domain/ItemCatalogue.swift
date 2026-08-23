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
    /// The game's badge for what the item is, or empty. A directory item wears no affixes, so this is
    /// its own record's doing: a monster infrequent, or an awakened piece.
    let qualityMarkPath: String
    let itemLevel: Int
    let levelRequirement: Int
    /// The stats the item carries, by the names the sheet shows, so the directory can be filtered by them.
    let stats: [String]
    /// The awakened item this one becomes when the Ashes of Awakening are spent on it, and its name.
    /// Empty for the great majority of items, which no blueprint upgrades.
    var awakenedPath = ""
    var awakenedName = ""
    /// The ashes' own artwork, carried here so a row can mark an upgradeable item without a database
    /// lookup of its own. Repeated on the hundred-odd items a blueprint covers.
    var upgradeIconPath = ""

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

/// One line of the affix catalogue: a prefix or a suffix a random item can roll.
struct CataloguedAffix: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case prefix = "Prefix"
        case suffix = "Suffix"
    }

    let path: String
    let name: String
    let kind: Kind
    let rarity: Int
    let levelRequirement: Int
    /// The stats it grants, by the names the sheet shows, so the catalogue filters by what an affix does.
    let stats: [String]

    var id: String { path }

    var quality: ItemRarity { ItemRarity(rawValue: rarity) ?? .common }
}

/// A catalogued affix folded once for the search field.
struct AffixEntry: Identifiable, Sendable {
    let affix: CataloguedAffix
    let folded: String

    var id: String { affix.path }

    init(_ affix: CataloguedAffix) {
        self.affix = affix
        folded = QuickSearch.folded(([ affix.name, affix.kind.rawValue ] + affix.stats).joined())
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
    static let version = 6

    /// The database this was built from; a patched game produces a different one and is listed again.
    let fingerprint: String
    let version: Int
    let items: [CataloguedItem]
    let affixes: [CataloguedAffix]

    /// The record trees worth listing. Everything else under `records/items` is loot tables, affixes,
    /// lore notes and potions, none of which the directory is for.
    private static let itemClassPrefixes = [ "Armor", "Weapon" ]

    /// The material an epic piece is upgraded with, which is what makes it upgradeable at all.
    private static let awakeningAshes = "records/items/crafting/materials/craft_awakeningashes.dbr"

    static func build(from database: GameDatabase) -> ItemCatalogue {
        var items = [CataloguedItem]()
        var affixes = [CataloguedAffix]()
        // Blueprint records sit among the items, so the upgrades are gathered in the same pass and
        // matched to the items they upgrade once the sweep has seen every one of them.
        var upgrades = [String: String]()

        database.sweep(prefix: "records/items/") { path, record in
            let recordClass = record.recordClass
            if let affix = Self.affix(record, at: path, in: database) {
                affixes.append(affix)
                return
            }
            if recordClass == "ItemArtifactFormula" {
                let reagents = (1 ... 3).map { record.text("reagent\($0)BaseName") }
                if reagents.contains(Self.awakeningAshes), case let base = record.text("reagentBaseBaseName"),
                        !base.isEmpty {
                    upgrades[base.lowercased()] = record.text("artifactName")
                }
            }
            guard
                Self.itemClassPrefixes.contains(where: { recordClass.hasPrefix($0) })
                    || CataloguedItem.craftingKinds[recordClass] != nil,
                let name = ItemResolver.itemName(of: record, in: database),
                !name.isEmpty
            else { return }

            let rarity = Self.rarity(of: record, at: path)
            let mark = ItemQualityMark(ItemQualityMark.Parts(
                isMonsterInfrequent: rarity == .rare && ItemQualityMark.isGear(recordClass: recordClass),
                isAwakened: path.contains("/awakened/"),
                rarity: rarity
            ))
            items.append(CataloguedItem(
                path: path,
                name: name,
                iconPath: Self.iconPath(of: record),
                recordClass: recordClass,
                rarity: rarity.rawValue,
                qualityMarkPath: mark?.texturePath ?? "",
                itemLevel: record.integer("itemLevel"),
                levelRequirement: record.integer("levelRequirement"),
                stats: Self.statTitles(of: record)
            ))
        }

        let ashesIcon = database.record(Self.awakeningAshes).map { Self.iconPath(of: $0) } ?? ""
        let names = Dictionary(items.map { ($0.path.lowercased(), $0.name) }, uniquingKeysWith: { first, _ in first })
        for index in items.indices {
            guard let awakened = upgrades[items[index].path.lowercased()] else { continue }

            items[index].awakenedPath = awakened
            items[index].awakenedName = names[awakened.lowercased()] ?? ""
            items[index].upgradeIconPath = ashesIcon
        }

        // An item is written once per level tier, so its variants read in order under the one name.
        items.sort {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.levelRequirement < $1.levelRequirement : order == .orderedAscending
        }
        affixes.sort {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.levelRequirement < $1.levelRequirement : order == .orderedAscending
        }
        return ItemCatalogue(fingerprint: database.fingerprint, version: Self.version, items: items, affixes: affixes)
    }

    /// A prefix or suffix a random item can roll, which the folder it sits in says it is.
    private static func affix(_ record: ArzRecord, at path: String, in database: GameDatabase)
        -> CataloguedAffix?
    {
        guard
            record.recordClass == "LootRandomizer",
            case let kind:CataloguedAffix.Kind? = path.contains("/prefix/")
                ? .prefix : (path.contains("/suffix/") ? .suffix : nil),
            let kind,
            let name = database.localised(record.text("lootRandomizerName")),
            !name.isEmpty
        else { return nil }

        return CataloguedAffix(
            path: path,
            name: name,
            kind: kind,
            rarity: ItemRarity(classification: record.text("itemClassification")).rawValue,
            levelRequirement: record.integer("levelRequirement"),
            stats: Self.statTitles(of: record)
        )
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
