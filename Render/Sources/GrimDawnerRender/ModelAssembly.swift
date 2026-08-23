// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation
import GrimDawnerEngine

/// What a monster is drawn from: one model, or several worn together.
///
/// A beast is a single model. A human is a head and whatever it wears — the record names only the head,
/// and the game hangs armour and weapons off the same skeleton. Every piece is modelled in the same bind
/// pose, so drawing them in one scene puts them where they belong.
public struct ModelAssembly: Sendable {
    /// One piece of a monster, and the skin it wears.
    public struct Part: Sendable {
        public let mesh: String
        public let texture: String

        public init(mesh: String, texture: String) {
            self.mesh = mesh
            self.texture = texture
        }
    }

    public let parts: [Part]

    public init(parts: [Part]) { self.parts = parts }

    /// The slots a worn model comes from, in the order they are drawn.
    ///
    /// Armour only. A weapon is modelled at the origin and hung off a hand bone, and the skeleton is the
    /// one part of the format this does not read — so a sword drawn here would lie on the floor.
    public static let wornFields = [ "Head", "Chest", "Shoulders", "Legs", "Feet", "Hands" ]

    /// Reads a monster's record for everything it is drawn from.
    ///
    /// The loot lists say what it carries; the likeliest entry of each slot is what it is wearing, since
    /// that is what the game rolls most often. An armour record names a male and a female model and the
    /// creature's own profile says which.
    public static func of(_ monster: ResolvedMonster, in database: GameDatabase) -> ModelAssembly {
        var parts = [Part]()
        if !monster.meshPath.isEmpty {
            parts.append(Part(mesh: monster.meshPath, texture: monster.texturePath))
        }

        let isFemale = database.record(monster.path)?.text("characterGenderProfile").lowercased() == "female"
        for slot in wornFields {
            guard
                let carried = monster.loot.first(where: { $0.field == slot }),
                let item = carried.entries.first?.items.first,
                !item.recordPath.isEmpty,
                let record = database.record(item.recordPath)
            else { continue }

            let mesh = [
                isFemale ? record.text("armorFemaleMesh") : record.text("armorMaleMesh"),
                record.text("mesh"),
            ]
            .first { !$0.isEmpty }

            guard let mesh else { continue }

            parts.append(Part(mesh: mesh, texture: record.text("baseTexture")))
        }
        return ModelAssembly(parts: parts)
    }
}
