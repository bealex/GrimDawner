// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// One line of the item directory: enough to list and search on, not the whole item.
public struct CataloguedItem: Codable, Identifiable, Sendable {
    /// The record's path, which is also how the full item is read back.
    public let path: String
    public let name: String
    public let iconPath: String
    /// The record's class, as the game writes it — `WeaponMelee_Sword`, `ArmorProtective_Head`.
    public let recordClass: String
    public let rarity: Int
    /// The game's badge for what the item is, or empty. A directory item wears no affixes, so this is
    /// its own record's doing: a monster infrequent, or an awakened piece.
    public let qualityMarkPath: String
    public let itemLevel: Int
    public let levelRequirement: Int
    /// The stats the item carries, by the names the sheet shows, so the directory can be filtered by them.
    public let stats: [String]
    /// The faction whose merchant sells this, and the standing it takes — augments only, since they
    /// are the items a faction sells rather than drops.
    public var soldBy = ""
    public var standing = ""
    /// The awakened item this one becomes when the Ashes of Awakening are spent on it, and its name.
    /// Empty for the great majority of items, which no blueprint upgrades.
    public var awakenedPath = ""
    public var awakenedName = ""
    /// The ashes' own artwork, carried here so a row can mark an upgradeable item without a database
    /// lookup of its own. Repeated on the hundred-odd items a blueprint covers.
    public var upgradeIconPath = ""
    /// The kinds of equipment this can be put into, named as `kind` names them — "Sword",
    /// "Head", "Amulet". Components and augments only; everything else is applied to nothing.
    public var appliesTo = [String]()

    /// The three crafting classes the game names differently from their record class.
    public static let craftingKinds = [
        "ItemRelic": "Component", "ItemArtifact": "Relic", "ItemEnchantment": "Augment",
    ]

    /// Everything else under `records/items` that carries a name and is worth listing.
    ///
    /// The class is all the game gives: nothing states a category, and the record's own class name
    /// reads badly on its own — `ItemArtifactFormula` is what a player calls a blueprint. The last two
    /// are world objects rather than things carried, kept because they are named and asked after.
    public static let otherKinds = [
        "ItemArtifactFormula": "Blueprint",
        "QuestItem": "Quest Item",
        "ItemNote": "Lore Note",
        "ItemTransmuter": "Illusion",
        "ItemTransmuterSet": "Illusion Set",
        "OneShot_Scroll": "Scroll",
        "OneShot_SkillUnlock": "Formula",
        "OneShot_PotionHealth": "Potion",
        "OneShot_PotionMana": "Potion",
        "OneShot_Food": "Food",
        "ItemFactionBooster": "Faction Booster",
        "ItemFactionWarrant": "Faction Warrant",
        "ItemUsableSkill": "Usable",
        "ItemDifficultyUnlock": "Merit",
        "FixedItemContainer": "Trove",
        "Destructible": "Destructible",
    ]

    /// Every class the directory lists beyond armour and weapons.
    static var namedKinds: [String: String] { craftingKinds.merging(otherKinds) { first, _ in first } }

    public var id: String { path }

    public var quality: ItemRarity { ItemRarity(rawValue: rarity) ?? .common }

    /// A monster infrequent: a piece of gear whose own record is classified rare, which is what the
    /// game's green badge marks. Every rare record in the directory is one — an item only reaches rare
    /// any other way by rolling two rare affixes, and a base record carries no affixes.
    public var isMonsterInfrequent: Bool {
        quality == .rare && ItemQualityMark.isGear(recordClass: recordClass)
    }

    /// What kind of thing it is, from the tail of its class: `ArmorJewelry_Amulet` reads as "Amulet",
    /// `WeaponMelee_Axe2h` as "Axe (2-handed)".
    public var kind: String { Self.kind(ofClass: recordClass) }

    public static func kind(ofClass recordClass: String) -> String {
        if let kind = namedKinds[recordClass] { return kind }

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
public struct CataloguedAffix: Codable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case prefix = "Prefix"
        case suffix = "Suffix"
    }

    public let path: String
    public let name: String
    public let kind: Kind
    public let rarity: Int
    public let levelRequirement: Int
    /// The stats it grants, by the names the sheet shows, so the catalogue filters by what an affix does.
    public let stats: [String]

    public var id: String { path }

    public var quality: ItemRarity { ItemRarity(rawValue: rarity) ?? .common }
}

/// A catalogued affix folded once for the search field.
public struct AffixEntry: Identifiable, Sendable {
    public let affix: CataloguedAffix
    public let folded: String

    public var id: String { affix.path }

    public init(_ affix: CataloguedAffix) {
        self.affix = affix
        folded = QuickSearch.folded(([ affix.name, affix.kind.rawValue ] + affix.stats).joined())
    }
}

/// A catalogued item with everything searchable about it folded once, ready for the search field.
public struct DirectoryEntry: Identifiable, Sendable {
    public let item: CataloguedItem
    public let folded: String

    public var id: String { item.path }

    public init(_ item: CataloguedItem) {
        self.item = item
        folded = QuickSearch.folded(([ item.name, item.kind ] + item.stats).joined())
    }
}

/// Every named item in the game, listed once per installed version and kept on disk.
public struct ItemCatalogue: Codable, Sendable {
    /// Bumped whenever an entry means something different, so an older listing on disk is discarded.
    public static let version = 10

    /// The database this was built from; a patched game produces a different one and is listed again.
    public let fingerprint: String
    public let version: Int
    public let items: [CataloguedItem]
    public let affixes: [CataloguedAffix]

    /// The record trees worth listing. Everything else under `records/items` is loot tables, affixes,
    /// lore notes and potions, none of which the directory is for.
    private static let itemClassPrefixes = [ "Armor", "Weapon" ]

    /// The material an epic piece is upgraded with, which is what makes it upgradeable at all.
    private static let awakeningAshes = "records/items/crafting/materials/craft_awakeningashes.dbr"

    public static func build(from database: GameDatabase) -> ItemCatalogue {
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
                    || CataloguedItem.namedKinds[recordClass] != nil,
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
                iconPath: ItemResolver.iconPath(of: record),
                recordClass: recordClass,
                rarity: rarity.rawValue,
                qualityMarkPath: mark?.texturePath ?? "",
                itemLevel: record.integer("itemLevel"),
                levelRequirement: record.integer("levelRequirement"),
                stats: Self.statTitles(of: record),
                soldBy: record.text("factionSource"),
                appliesTo: Self.slotFlags(of: record)
            ))
        }

        let vendors = Self.vendors(in: database)
        let factions = Self.factionNames(in: database)
        for index in items.indices {
            guard case let source = items[index].soldBy, !source.isEmpty else { continue }

            items[index].soldBy = factions[source] ?? source
            items[index].standing = vendors[items[index].path.lowercased()] ?? ""
        }

        let ashesIcon = database.record(Self.awakeningAshes).map { ItemResolver.iconPath(of: $0) } ?? ""
        let names = Dictionary(items.map { ($0.path.lowercased(), $0.name) }, uniquingKeysWith: { first, _ in first })
        for index in items.indices {
            guard let awakened = upgrades[items[index].path.lowercased()] else { continue }

            items[index].awakenedPath = awakened
            items[index].awakenedName = names[awakened.lowercased()] ?? ""
            items[index].upgradeIconPath = ashesIcon
        }

        // A slot flag is the tail of the class the equipment it fits is written as — `sword2h` for
        // `WeaponMelee_Sword2h` — so the equipment itself says what each flag means.
        let slots = Self.slotKinds(of: items)
        for index in items.indices where !items[index].appliesTo.isEmpty {
            items[index].appliesTo = items[index].appliesTo.compactMap { slots[$0] }.sorted()
        }

        // The same weapon is written once per enemy that carries it — three Pine Staffs at level 1,
        // identical but for the monster wielding them. One line each is enough.
        var seen = Set<String>()
        items = items.filter { item in
            seen.insert(
                "\(item.name)|\(item.recordClass)|\(item.levelRequirement)|\(item.stats.joined(separator: ","))"
            )
            .inserted
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

    /// Which faction each `factionSource` names — the augment records say `User7`, and the game's
    /// faction table says which faction that is.
    private static func factionNames(in database: GameDatabase) -> [String: String] {
        guard let table = database.record("records/game/gamefactions.dbr") else { return [:] }

        var names = [String: String]()
        for key in table.fields.keys where key.hasPrefix("factionUser") {
            guard
                let record = database.record(table.text(key)),
                case let identifier = record.text("myFaction"),
                !identifier.isEmpty
            else { continue }

            names[String(key.dropFirst("faction".count))] =
                database.localised("tagFaction" + identifier)
                ?? identifier
        }
        return names
    }

    /// The standing a faction's merchant asks for before it will sell an item.
    ///
    /// The merchant's table lists what it stocks but states no standing; its own file name does —
    /// `factiontables/blacklegion_honored_01.dbr` — and the words there are the game's own tier names.
    private static func vendors(in database: GameDatabase) -> [String: String] {
        let standings = [ "revered", "honored", "respected", "friendly", "tolerated" ]
        var sold = [String: String]()

        database.sweep(prefix: "records/creatures/npcs/merchants/") { path, record in
            let file = path.split(separator: "/").last.map(String.init)?.lowercased() ?? ""
            guard let standing = standings.first(where: { file.contains($0) }) else { return }

            for field in record.fieldOrder {
                for entry in record[field]?.texts ?? [] where entry.hasSuffix(".dbr") {
                    sold[entry.lowercased()] = standing.capitalized
                }
            }
        }
        return sold
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

    /// What each slot flag names, by the kind the directory lists that equipment under.
    private static func slotKinds(of items: [CataloguedItem]) -> [String: String] {
        var kinds = [String: String]()
        for item in items where CataloguedItem.craftingKinds[item.recordClass] == nil {
            guard let tail = item.recordClass.split(separator: "_").last else { continue }

            kinds[tail.lowercased()] = item.kind
        }
        return kinds
    }

    /// The slots a component or an augment fits, as its own record names them: a flag per slot,
    /// switched on. Left raw here, since the classes they name are only all known once the sweep ends.
    private static func slotFlags(of record: ArzRecord) -> [String] {
        guard CataloguedItem.craftingKinds[record.recordClass] != nil else { return [] }

        return record.fields.compactMap { key, value in
            guard case let .flag(values) = value, values.first == true else { return nil }

            return key
        }
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

    private static func rarity(of record: ArzRecord, at path: String) -> ItemRarity {
        if let crafting = ItemRarity(recordClass: record.recordClass) { return crafting }
        if path.contains("/questitems/") { return .quest }

        return ItemRarity(classification: record.text("itemClassification"))
    }
}

/// Keeps the catalogue on disk between launches, since listing 26,000 records is not a per-launch job.
public enum ItemCatalogueStore {
    /// Reads the catalogue for this database, or nothing when the game has been patched since.
    public static func load(fingerprint: String) -> ItemCatalogue? {
        guard
            let url = fileURL(fingerprint: fingerprint),
            let data = try? Data(contentsOf: url),
            let catalogue = try? JSONDecoder().decode(ItemCatalogue.self, from: data),
            catalogue.fingerprint == fingerprint,
            catalogue.version == ItemCatalogue.version
        else { return nil }

        return catalogue
    }

    public static func save(_ catalogue: ItemCatalogue) {
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
