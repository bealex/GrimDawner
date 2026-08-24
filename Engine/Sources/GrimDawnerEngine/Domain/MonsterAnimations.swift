// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// One of the animations a creature can play.
public struct MonsterAnimation: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let title: String
    /// The `.anm` file, named the way the archives are rooted.
    public let path: String
    /// What the game plays it for — `Walk`, `Attack`, `Die`, `Special`.
    public let action: String
    /// The name a skill calls this animation by, which is how an attack finds the one it plays.
    public let reference: String?
}

/// Reads a creature's animation table: which file it plays for which action.
///
/// A creature record names a table rather than files, and the table's fields are the whole vocabulary —
/// `unarmedWalkAnim`, `sword2hAttackAnim2`, `unarmedSpecialAnim7`. A special is numbered rather than
/// named, and the `…SpecialAnimRef7` beside it carries the name a skill asks for it by.
public enum MonsterAnimations {
    /// The animations a creature is drawn with, in the order a reader wants them.
    ///
    /// Only the unarmed set is read. A table written for the player holds one set per weapon it can
    /// hold, and this draws no weapons, so the poses that hold one would be a hand closed around nothing.
    public static func of(_ record: ArzRecord, in database: GameDatabase) -> [MonsterAnimation] {
        guard let table = database.record(record.text("charAnimationTableName")) else { return [] }

        var references = [String: String]()
        var found = [MonsterAnimation]()

        // `SpecialAnimRef7` names what `SpecialAnim7` plays, so both are filed under `Special7`.
        for key in table.fieldOrder where key.hasPrefix(prefix) {
            let name = String(key.dropFirst(prefix.count))
            guard let suffix = name.range(of: "AnimRef[0-9]*$", options: .regularExpression) else { continue }

            let action = String(name[name.startIndex ..< suffix.lowerBound])
            let index = name[name.index(suffix.lowerBound, offsetBy: 7) ..< suffix.upperBound]
            references[action + index] = table.text(key)
        }

        for key in table.fieldOrder where key.hasPrefix(prefix) {
            let path = table.text(key)
            let name = String(key.dropFirst(prefix.count))
            guard
                !path.isEmpty,
                let suffix = name.range(of: "Anim[0-9]*$", options: .regularExpression),
                !found.contains(where: { $0.path == path })
            else { continue }

            let action = String(name[name.startIndex ..< suffix.lowerBound])
            let index = String(name[name.index(suffix.lowerBound, offsetBy: 4) ..< suffix.upperBound])
            let reference = references[action + index]

            found.append(MonsterAnimation(
                title: title(action: action, index: index, reference: reference),
                path: path,
                action: action,
                reference: reference
            ))
        }
        return found.sorted { order(of: $0) < order(of: $1) }
    }

    private static let prefix = "unarmed"

    /// The actions a reader looks for first; everything else keeps the order the table wrote it in.
    private static let leading = [ "LongIdle", "AttackIdle", "Walk", "Run", "Attack", "SpellAttack", "Special" ]

    private static func order(of animation: MonsterAnimation) -> Int {
        leading.firstIndex(of: animation.action) ?? leading.count
    }

    /// What to call it: the name a skill asks for it by, or the action itself.
    private static func title(action: String, index: String, reference: String?) -> String {
        if let reference, !reference.isEmpty { return spaced(reference) }

        return spaced(action) + (index.isEmpty || index == "1" ? "" : " \(index)")
    }

    /// `SpellAttack` reads as *Spell attack*, `GroundSlam` as *Ground slam*.
    private static func spaced(_ name: String) -> String {
        var words = ""
        for (index, character) in name.enumerated() {
            if index > 0, character.isUppercase, !name[name.index(name.startIndex, offsetBy: index - 1)].isUppercase {
                words += " "
                words += character.lowercased()
            } else {
                words.append(character)
            }
        }
        return words
    }
}
