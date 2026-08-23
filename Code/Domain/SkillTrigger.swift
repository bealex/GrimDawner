// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// What sets an item's own skill off: the chance it fires on, and what has to happen first.
///
/// The controller a record names holds the trigger and the chance; the game's wording for the pair is a
/// `tagAutoSkillConditionNN` string, which reads "(25% Chance on Attack)". Which tag goes with which
/// `triggerType` is the one thing the data does not state — the template lists the triggers in the
/// engine's own order, the tags in another — so the pairing below is by what each says.
enum SkillTrigger {
    private static let conditionTags = [
        "LowHealth": "tagAutoSkillCondition01",
        "LowMana": "tagAutoSkillCondition02",
        "HitByEnemy": "tagAutoSkillCondition03",
        "HitByMelee": "tagAutoSkillCondition04",
        "HitByProjectile": "tagAutoSkillCondition05",
        "CastBuff": "tagAutoSkillCondition06",
        "AttackEnemy": "tagAutoSkillCondition07",
        "OnEquip": "tagAutoSkillCondition08",
        "HitByCrit": "tagAutoSkillCondition09",
        "AttackEnemyCrit": "tagAutoSkillCondition10",
        "Block": "tagAutoSkillCondition11",
        "OnKill": "tagAutoSkillCondition12",
    ]

    /// How the game words the controller at `path`, or nothing when a record names none.
    static func text(ofControllerAt path: String, in database: GameDatabase) -> String? {
        guard
            !path.isEmpty,
            let controller = database.record(path),
            case let trigger = controller.text("triggerType"),
            let tag = conditionTags[trigger],
            let wording = database.localised(tag)
        else { return nil }

        // The threshold is only in the record when it is not the engine's default of zero, and the two
        // tags that name one read as nonsense without it.
        let threshold = controller.number("triggerParam")
        guard
            threshold > 0 || !wording.contains("{%.0f1}")
        else {
            return "(\(controller.integer("chanceToRun"))% Chance at Low \(trigger == "LowMana" ? "Energy" : "Health"))"
        }

        return format(wording, [ Double(controller.integer("chanceToRun")), threshold ])
    }

    /// Fills a game string's `{%d0}` / `{%.0f1}` placeholders with the values they index.
    private static func format(_ wording: String, _ values: [Double]) -> String {
        var text = ""
        var rest = Substring(wording)

        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            text += rest[..<open]
            let token = rest[rest.index(after: open) ..< close]
            rest = rest[rest.index(after: close)...]

            guard
                token.hasPrefix("%"),
                let index = token.last?.wholeNumberValue,
                values.indices.contains(index)
            else { continue }

            let decimals = token.contains(".1f") ? 1 : 0
            text += values[index].formatted(.number.precision(.fractionLength(decimals)))
        }
        return text + rest
    }
}
