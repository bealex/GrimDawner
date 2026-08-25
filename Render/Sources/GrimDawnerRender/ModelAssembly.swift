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
    public enum Hand: Hashable, Sendable {
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

    /// The slots a worn model comes from, in the order they are drawn: the record field a creature
    /// names its default piece in, and the gear slot a character wears its own in.
    public static let wornSlots: [(field: String, slot: EquipmentSlot)] = [
        ("Head", .head), ("Shoulders", .shoulders), ("Chest", .chest),
        ("Legs", .legs), ("Feet", .feet), ("Hands", .hands),
    ]

    public static var wornFields: [String] { wornSlots.map(\.field) }

    /// The slots a weapon comes from.
    public static let heldFields: [(field: String, hand: Hand)] = [ ("RightHand", .right), ("LeftHand", .left) ]

    /// What to put in a monster's hands in place of what its own tables roll.
    ///
    /// A record names only the tables a weapon is drawn from, so what a monster holds is a roll. Naming
    /// a record here holds that one instead; naming the empty string holds nothing; leaving a hand unset
    /// rolls it as the game would.
    public struct Hands: Sendable, Equatable {
        public var right: String?
        public var left: String?

        public init(right: String? = nil, left: String? = nil) {
            self.right = right
            self.left = left
        }

        public subscript(hand: Hand) -> String? {
            get { hand == .right ? right : left }
            set { if hand == .right { right = newValue } else { left = newValue } }
        }

        public var isEmpty: Bool { right == nil && left == nil }
    }

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
    /// Naming a weapon in `hands` overrides the roll for that hand, which is what lets a reader see the
    /// same monster with each of the things it might be carrying.
    public static func of(_ monster: ResolvedMonster, in database: GameDatabase, holding hands: Hands = Hands())
        -> ModelAssembly {
        var parts = [Part]()
        let creature = database.record(monster.path)
        let isFemale = creature?.text("characterGenderProfile").lowercased() == "female"

        // A dressed creature's own model is its head, and every human record but one names the head its
        // gender wears. The Avatar of Mogdrogen names its wolf-skull headdress there, which leaves the
        // rig with nothing to put a face on, so the head goes under whatever the record named.
        if let creature, isDressed(creature), monster.meshPath.lowercased().hasPrefix("items/"),
           case let head = playerRecord(male: !isFemale, in: database)?.text("mesh") ?? "", !head.isEmpty {
            parts.append(Part(mesh: head, texture: ""))
        }
        if !monster.meshPath.isEmpty {
            parts.append(Part(mesh: monster.meshPath, texture: monster.texturePath))
        }

        for slot in wornFields {
            let dressed = creature?.text("default\(slot)Piece") ?? ""
            let path = dressed.isEmpty ? carried(slot, of: monster) : dressed
            guard let gear = database.record(path), let part = worn(gear, female: isFemale) else { continue }

            parts.append(part)
        }

        var draws = ItemRoll.Random(seed: seed(of: monster.path))
        var bothHands = false
        for held in heldFields {
            // The roll is drawn whatever is chosen, so choosing for one hand does not change the other.
            let slot = monster.equipment.first { $0.field == held.field }
            let roll = slot.map { rolled(from: $0, drawing: &draws) } ?? nil
            guard
                !bothHands,
                let path = hands[held.hand] ?? roll,
                !path.isEmpty,
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

    /// Every weapon a monster might be holding in one hand, which is what a reader can pick between.
    public static func candidates(for hand: Hand, of monster: ResolvedMonster, in database: GameDatabase)
        -> [(path: String, name: String)] {
        guard
            let field = heldFields.first(where: { $0.hand == hand })?.field,
            let slot = monster.equipment.first(where: { $0.field == field })
        else { return [] }

        var seen = Set<String>()
        return slot.entries.flatMap(\.items).compactMap { item in
            guard
                seen.insert(item.recordPath.lowercased()).inserted,
                let weapon = database.record(item.recordPath),
                weapon.recordClass.hasPrefix("Weapon"),
                !weapon.text("mesh").isEmpty
            else { return nil }

            return (item.recordPath, item.name)
        }
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

    /// Whether the record puts armour on the creature, which is what says it is drawn on a human rig.
    static func isDressed(_ creature: ArzRecord) -> Bool {
        wornFields.contains { !creature.text("default\($0)Piece").isEmpty }
    }

    /// The creature the game plays as, which is the `Player` record of the gender asked for.
    ///
    /// No record names it, so it is looked for rather than written down. The search stays inside the
    /// player's own folder: the game ships a third `Player` record under `records/sandbox`, left over
    /// from a test pose.
    static func playerRecord(male: Bool, in database: GameDatabase) -> ArzRecord? {
        // Looking for it walks the whole path list, and the doll rebuilds whenever the character swaps
        // hands, so the answer is kept the first time it is worked out.
        // The path is cached rather than the record: the record is memoised anyway, and a cache of
        // something optional cannot tell a miss from an answer of nothing.
        let found = database.swept("player-record-\(male ? "male" : "female")") { database -> String in
            var path = ""
            database.sweep(prefix: "records/creatures/pc/") { candidate, record in
                guard
                    path.isEmpty,
                    record.recordClass == "Player",
                    record.text("characterGenderProfile").lowercased() == (male ? "male" : "female")
                else { return }

                path = candidate
            }
            return path
        }
        return found.isEmpty ? nil : database.record(found)
    }

    /// One armour record's model and skin, in the creature's own gender.
    static func worn(_ gear: ArzRecord, female: Bool) -> Part? {
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
