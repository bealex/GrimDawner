// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation
import GrimDawnerEngine

/// What the player's own character is drawn from, and the pose the game's character window holds it in.
///
/// The save says which of the game's two player creatures it is and which skin was picked for it; the
/// rest is the same assembly a monster is drawn from, except that the gear is worn, not rolled.
public struct CharacterModel: Sendable {
    public let assembly: ModelAssembly
    /// The `.anm` the game's own character window plays: an idle in whatever the character is holding.
    public let animation: String?

    /// Everything the character is drawn from, holding the weapons of the set given.
    public static func of(_ character: ResolvedCharacter, holding set: WeaponSet?, in database: GameDatabase)
        -> CharacterModel? {
        guard let creature = ModelAssembly.playerRecord(male: character.save.header.isMale, in: database)
        else { return nil }

        var parts = [ModelAssembly.Part]()
        let mesh = creature.text("mesh")
        if !mesh.isEmpty {
            // The skin is the one the save picked at creation; the record names only the default.
            let skin = character.save.info.texture
            parts.append(ModelAssembly.Part(
                mesh: mesh,
                texture: skin.isEmpty ? creature.text("playerTextures") : skin
            ))
        }

        let isFemale = creature.text("characterGenderProfile").lowercased() == "female"
        for worn in ModelAssembly.wornSlots {
            let equipped = character.equipment.first { $0.slot == worn.slot }?.item?.raw.baseName ?? ""
            let path = equipped.isEmpty ? creature.text("default\(worn.field)Piece") : equipped
            guard let gear = database.record(path), let part = ModelAssembly.worn(gear, female: isFemale) else {
                continue
            }

            parts.append(part)
        }

        let hands = held(in: set, of: database)
        for hand in hands {
            parts.append(ModelAssembly.Part(
                mesh: hand.record.text("mesh"),
                texture: hand.record.text("baseTexture"),
                hand: hand.hand
            ))
        }

        return CharacterModel(
            assembly: ModelAssembly(parts: parts),
            animation: menuIdle(
                of: creature,
                mainHand: hands.first { $0.hand == .right }?.record,
                offHand: hands.first { $0.hand == .left }?.record,
                in: database
            )
        )
    }

    /// The weapons of a set that are drawn, each in the hand that holds it.
    ///
    /// A set is written main hand first, the way the doll reads it. A two-handed weapon fills both hands,
    /// so nothing is drawn in the other one, and a piece with no model of its own is skipped rather than
    /// drawn at the feet.
    private static func held(in set: WeaponSet?, of database: GameDatabase)
        -> [(record: ArzRecord, hand: ModelAssembly.Hand)] {
        guard let set else { return [] }

        var hands = [(record: ArzRecord, hand: ModelAssembly.Hand)]()
        var bothHands = false
        for (index, hand) in [ (0, ModelAssembly.Hand.right), (1, .left) ] {
            guard
                !bothHands,
                set.items.indices.contains(index),
                let path = set.items[index]?.raw.baseName,
                let weapon = database.record(path),
                weapon.recordClass.hasPrefix("Weapon"),
                !weapon.text("mesh").isEmpty
            else { continue }

            bothHands = weapon.recordClass.hasSuffix("2h")
            hands.append((weapon, hand))
        }
        return hands
    }

    /// The idle the game's character window plays, which is the one for the way the hands are full.
    ///
    /// The animation table names one set per way of holding a weapon — `unarmed`, `sHanded`,
    /// `sHandedShield`, `dHanded`, `sword2h`, `ranged1h`, `dualRanged` — and a weapon's record class
    /// names its own: `WeaponMelee_Sword2h` is the `sword2h` set. The one-handed melee weapons have no
    /// set each, sharing `sHanded`, or `dHanded` when a second one is held.
    private static func menuIdle(
        of creature: ArzRecord,
        mainHand: ArzRecord?,
        offHand: ArzRecord?,
        in database: GameDatabase
    ) -> String? {
        guard let table = database.record(creature.text("charAnimationTableName")) else { return nil }

        for set in sets(mainHand: mainHand, offHand: offHand) + [ "unarmed" ] {
            let animation = table.text("\(set)MenuIdleAnim")
            if !animation.isEmpty { return animation }
        }
        return nil
    }

    /// The animation sets that fit what is held, likeliest first.
    private static func sets(mainHand: ArzRecord?, offHand: ArzRecord?) -> [String] {
        guard let mainHand else { return [] }

        let kind = uncapitalised(String(mainHand.recordClass.split(separator: "_").last ?? ""))
        let offHandClass = offHand?.recordClass ?? ""
        // A weapon in the other hand is dual wielding; a shield or a focus is the same set worn with one.
        guard !offHandClass.hasPrefix("WeaponMelee"), !offHandClass.hasPrefix("WeaponHunting") else {
            return [ kind.hasPrefix("ranged") ? "dualRanged" : "dHanded", kind, "sHanded" ]
        }

        let carried = offHandClass.hasSuffix("Shield") ? "Shield" : offHandClass.hasSuffix("Offhand") ? "Offhand" : ""
        return [ kind + carried, kind, "sHanded" + carried, "sHanded" ]
    }

    private static func uncapitalised(_ name: String) -> String {
        guard let first = name.first else { return name }

        return first.lowercased() + name.dropFirst()
    }
}
