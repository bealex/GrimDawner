// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// A blueprint the game sells or drops, and the item it makes.
///
/// The record runs one way only — a blueprint names what it produces in `artifactName`, and nothing on
/// an item says a blueprint exists for it — so answering "can this be crafted?" means reading every
/// blueprint once and keeping the map.
public struct ItemBlueprint: Sendable, Identifiable {
    public let recordPath: String
    public let name: String
    public let iconPath: String
    /// What the crafter charges, which the record writes as text.
    public let cost: Int
    /// What it consumes, in the order the record lists it, with how many of each.
    public let reagents: [Reagent]

    public struct Reagent: Sendable, Identifiable {
        public let recordPath: String
        public let name: String
        public let iconPath: String
        public let quantity: Int

        public var id: String { recordPath }
    }

    public var id: String { recordPath }

    /// Which blueprint makes each item, by the record path of the item it produces.
    ///
    /// Built once for the database and kept, since it takes a walk of every record to work out.
    public static func map(in database: GameDatabase) -> [String: ItemBlueprint] {
        database.swept("blueprints") { database in
            var found = [String: ItemBlueprint]()

            database.sweep(prefix: "records/items/") { path, record in
                guard
                    record.recordClass == "ItemArtifactFormula",
                    case let makes = record.text("artifactName").lowercased(),
                    !makes.isEmpty,
                    let name = ItemResolver.itemName(of: record, in: database),
                    !name.isEmpty
                else { return }

                found[makes] = ItemBlueprint(
                    recordPath: path,
                    name: name,
                    iconPath: record.text("artifactFormulaBitmapName"),
                    cost: Int(record.text("artifactCreationCost")) ?? 0,
                    reagents: Self.reagents(of: record, in: database)
                )
            }
            return found
        }
    }

    /// The base material first, as the crafting window lists it, then the pieces.
    private static func reagents(of record: ArzRecord, in database: GameDatabase) -> [Reagent] {
        let named = [ "reagentBase" ] + (1 ... 3).map { "reagent\($0)" }

        return named.compactMap { key in
            guard
                case let path = record.text("\(key)BaseName"),
                !path.isEmpty,
                let reagent = database.record(path),
                let name = ItemResolver.itemName(of: reagent, in: database),
                !name.isEmpty
            else { return nil }

            return Reagent(
                recordPath: path,
                name: name,
                iconPath: ItemResolver.iconPath(of: reagent),
                quantity: max(1, Int(record.number("\(key)Quantity")))
            )
        }
    }
}
