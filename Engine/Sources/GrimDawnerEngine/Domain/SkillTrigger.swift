// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// What sets an item's own skill off: the chance it fires on, and what has to happen first.
///
/// The controller a record names holds the trigger and the chance; the game's wording for the pair is a
/// `tagAutoSkillConditionNN` string, which reads "(25% Chance on Attack)". Which tag goes with which
/// `triggerType` is the one thing the data does not state — the template lists the triggers in the
/// engine's own order, the tags in another — so the pairing below is by what each says.
public enum SkillTrigger {
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

    /// The condition fields a skill states on its own record, and the tag the game words each with.
    ///
    /// Each tag is named after the field it words, which is how the pairing is known rather than
    /// guessed — `LifeMonitorPercent` reads "Activates when Health drops below {%.1f0}%" and takes the
    /// field's own value. `onHitActivationChance` is the exception: it has no tag of its own, so its
    /// chance is worded with the generic one and what it waits for comes from the record's class.
    private static let conditionFields = [
        (field: "lifeMonitorPercent", tag: "LifeMonitorPercent"),
        (field: "skillChanceWeight", tag: "SkillChanceWeight"),
        (field: "filterCaster", tag: "FilterCaster"),
    ]

    /// What a record's own class says it waits for, where the class is the only thing that says it.
    ///
    /// These are the app's words, not the game's: nothing in the database spells them out, and a skill
    /// that only fires on a critical hit reads as permanently on without them.
    private static let classConditions = [
        ("OnCrit", "on a critical hit"),
        ("OnKill", "on a kill"),
        ("OnHit", "on hit"),
        ("OnLife", "at low health"),
    ]

    /// Everything that has to happen before a skill does anything, worded as the game words it where
    /// the game words it at all. Empty for a skill that simply runs.
    public static func conditions(ofSkillAt path: String, in database: GameDatabase) -> [String] {
        guard !path.isEmpty, let record = database.record(path) else { return [] }

        var found = [String]()
        for condition in conditionFields {
            guard
                let value = record[condition.field]?.numbers.first,
                value != 0,
                let wording = database.localised(condition.tag)
            else { continue }

            found.append(format(wording, [ value ]))
        }

        // A chance to fire says nothing without what it fires on, and only the class carries that.
        if case let chance = record.number("onHitActivationChance"), chance > 0 {
            let waits = classConditions.first { record.recordClass.contains($0.0) }?.1 ?? "on hit"
            let wording = database.localised("SkillActivationChance") ?? "Chance of Activating"
            found.append("\(chance.formatted(.number.precision(.fractionLength(0))))% \(wording.lowercased()) \(waits)")
        }
        return found
    }

    /// How the game words the controller at `path`, or nothing when a record names none.
    public static func text(ofControllerAt path: String, in database: GameDatabase) -> String? {
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
