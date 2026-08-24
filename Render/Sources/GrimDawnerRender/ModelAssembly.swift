// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation
import GrimDawnerEngine

/// What a monster is drawn from: one model, or several worn together.
///
/// A beast is a single model. A human is a head and the gear it is dressed in — the creature record
/// names only the head, and the game hangs armour off the same skeleton. Every piece is modelled in the
/// same bind pose, so drawing them in one scene puts them where they belong. A weapon is not: it is
/// modelled at the origin and hung off a hand.
public struct ModelAssembly: Sendable {
    /// Which hand a weapon is held in.
    public enum Hand: Sendable {
        case right
        case left
    }

    /// One piece of a monster, and the skin it wears.
    public struct Part: Sendable {
        public let mesh: String
        public let texture: String
        /// Set for a weapon, which hangs off that hand's bone instead of standing in the bind pose.
        public let hand: Hand?

        public init(mesh: String, texture: String, hand: Hand? = nil) {
            self.mesh = mesh
            self.texture = texture
            self.hand = hand
        }
    }

    public let parts: [Part]

    public init(parts: [Part]) { self.parts = parts }

    /// The slots a worn model comes from, in the order they are drawn.
    public static let wornFields = [ "Head", "Shoulders", "Chest", "Legs", "Feet", "Hands" ]

    /// The slots a weapon comes from.
    public static let heldFields: [(field: String, hand: Hand)] = [ ("RightHand", .right), ("LeftHand", .left) ]

    /// Reads a monster's record for everything it is drawn from.
    ///
    /// `default<Slot>Piece` is what the game dresses a creature in, and every human names all six; a
    /// creature that names none is drawn from its own model alone. Where a slot is empty but the loot
    /// lists something for it, that is what it walks around wearing, since the game equips what it rolls.
    ///
    /// A weapon is only ever a roll: no record says which one a monster carries, only which tables it
    /// draws from and that it equips what it rolls. So one is drawn from those tables the way the game
    /// weighs them, from a stream primed with the creature's own record path — the same monster keeps the
    /// same weapon, and two monsters drawing from one table rarely hold the same thing.
    public static func of(_ monster: ResolvedMonster, in database: GameDatabase) -> ModelAssembly {
        var parts = [Part]()
        if !monster.meshPath.isEmpty {
            parts.append(Part(mesh: monster.meshPath, texture: monster.texturePath))
        }

        let creature = database.record(monster.path)
        let isFemale = creature?.text("characterGenderProfile").lowercased() == "female"
        for slot in wornFields {
            let dressed = creature?.text("default\(slot)Piece") ?? ""
            let path = dressed.isEmpty ? carried(slot, of: monster) : dressed
            guard let gear = database.record(path), let part = worn(gear, female: isFemale) else { continue }

            parts.append(part)
        }

        var draws = ItemRoll.Random(seed: seed(of: monster.path))
        var bothHands = false
        for held in heldFields {
            guard
                !bothHands,
                let slot = monster.equipment.first(where: { $0.field == held.field }),
                let path = rolled(from: slot, drawing: &draws),
                let weapon = database.record(path),
                weapon.recordClass.hasPrefix("Weapon"),
                !weapon.text("mesh").isEmpty
            else { continue }

            // A two-handed weapon fills both hands, so nothing is drawn in the other one.
            bothHands = weapon.recordClass.hasSuffix("2h")
            parts.append(Part(mesh: weapon.text("mesh"), texture: weapon.text("baseTexture"), hand: held.hand))
        }
        return ModelAssembly(parts: parts)
    }

    /// The likeliest entry of an equipment slot, which is what the game rolls most often.
    private static func carried(_ slot: String, of monster: ResolvedMonster) -> String {
        monster.equipment.first { $0.field == slot }?.entries.first?.items.first?.recordPath ?? ""
    }

    /// One item out of a slot, each entry and each item within it weighed as the game weighs it.
    private static func rolled(from slot: MonsterLootSlot, drawing draws: inout ItemRoll.Random) -> String? {
        guard let entry = weighed(slot.entries, by: \.share, drawing: &draws) else { return nil }

        return weighed(entry.items, by: \.share, drawing: &draws)?.recordPath
    }

    private static func weighed<Element>(
        _ elements: [Element],
        by share: KeyPath<Element, Double>,
        drawing draws: inout ItemRoll.Random
    ) -> Element? {
        let total = elements.reduce(0) { $0 + max(0, $1[keyPath: share]) }
        guard total > 0 else { return elements.first }

        var landed = Double(draws.next() % 1_000_000) / 1_000_000 * total
        for element in elements {
            landed -= element[keyPath: share]
            if landed <= 0 { return element }
        }
        return elements.last
    }

    /// One armour record's model and skin, in the creature's own gender.
    private static func worn(_ gear: ArzRecord, female: Bool) -> Part? {
        let mesh = [
            female ? gear.text("armorFemaleMesh") : gear.text("armorMaleMesh"),
            gear.text("armorNativeMesh"),
            gear.text("mesh"),
        ]
        .first { !$0.isEmpty }

        guard let mesh else { return nil }

        return Part(mesh: mesh, texture: gear.text("baseTexture"))
    }

    /// A stream primed from the creature's own path: `Hasher` cannot be used, since its seed changes with
    /// every launch and the same monster would hold a different weapon each time the app opened.
    private static func seed(of path: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in path.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return hash & 0x7FFF_FFFF
    }
}
