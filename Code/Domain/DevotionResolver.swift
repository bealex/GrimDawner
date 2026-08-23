// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import CoreGraphics
import Foundation
import SwiftUI

/// Builds the devotion window: the sky the game draws, with the stars this save has taken lit.
struct DevotionResolver {
    let database: GameDatabase
    let skills: SkillResolver

    private static let masterTablePath = "records/ui/skills/devotion/devotion_mastertable.dbr"
    private static let constellationCount = 200
    private static let starsPerConstellation = 12
    private static let affinityCount = 5

    /// A constellation before the character's affinity is known, which is what gates availability.
    private struct Draft {
        let name: String
        let description: String
        let iconPath: String
        let position: CGPoint
        let stars: [DevotionStar]
        let given: [ResolvedConstellation.Affinity]
        let required: [ResolvedConstellation.Affinity]
        let bonuses: StatBlock
        let takenTint: DevotionTint
        let availableTint: DevotionTint
        let lockedTint: DevotionTint

        var isComplete: Bool { stars.allSatisfy(\.isTaken) }
    }

    func map(from save: Gdc.SaveFile) -> DevotionMap {
        guard let table = database.record(Self.masterTablePath) else { return .empty }

        let taken = takenStars(in: save)
        let drafts = (1 ... Self.constellationCount).compactMap { index -> Draft? in
            guard
                case let path = table.text("devotionConstellation\(index)"),
                !path.isEmpty,
                let record = database.record(path)
            else { return nil }

            return draft(record, taken: taken)
        }

        var earned = [String: Int]()
        for draft in drafts where draft.isComplete {
            for affinity in draft.given { earned[affinity.name, default: 0] += affinity.amount }
        }

        return DevotionMap(
            constellations: drafts.map { constellation($0, earned: earned) },
            nebulas: nebulas(in: table),
            tile: table.text("bgTile"),
            links: DevotionMap.Links(
                active: table.text("connectionActiveTexture"),
                inactive: table.text("connectionInactiveTexture"),
                locked: table.text("connectionLockedTexture"),
                width: table.number("connectionWidth")
            ),
            affinities: affinities(in: table, earned: earned),
            bounds: CGRect(
                x: -table.number("sizeX") / 2,
                y: -table.number("sizeY") / 2,
                width: table.number("sizeX"),
                height: table.number("sizeY")
            )
        )
    }

    /// Stats from the devotion stars that are permanently in effect.
    ///
    /// The celestial powers a constellation ends in are attacks and timed buffs; their numbers belong to
    /// the proc rather than to the character, so they are left out here exactly as an active skill is.
    func stats(from save: Gdc.SaveFile) -> StatBlock {
        var block = StatBlock()
        for entry in save.skills.skills where entry.isDevotion != 0 && entry.level > 0 {
            guard let record = database.record(entry.name), SkillResolver.isAlwaysOn(record) else { continue }

            block.merge(skills.stats(of: record, atLevel: Int(entry.level)))
        }
        return block
    }

    private func takenStars(in save: Gdc.SaveFile) -> [String: Int] {
        Dictionary(
            save.skills.skills
                .filter { $0.isDevotion != 0 && $0.level > 0 }
                .map { ($0.name.lowercased(), Int($0.level)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: - Constellations

    private func draft(_ record: ArzRecord, taken: [String: Int]) -> Draft {
        let background = database.record(record.text("constellationBackground"))
        var stars = [DevotionStar]()
        var bonuses = StatBlock()

        for index in 1 ... Self.starsPerConstellation {
            guard
                case let buttonPath = record.text("devotionButton\(index)"),
                !buttonPath.isEmpty,
                let button = database.record(buttonPath),
                case let skillPath = button.text("skillName"),
                let skillRecord = database.record(skillPath)
            else { continue }

            let level = taken[skillPath.lowercased()]
            guard let skill = skills.skill(at: skillPath, level: level ?? 0) else { continue }

            // Only what the star gives permanently, so this reads as the sheet reads.
            if let level, SkillResolver.isAlwaysOn(skillRecord) {
                bonuses.merge(skills.stats(of: skillRecord, atLevel: level))
            }
            stars.append(DevotionStar(
                position: CGPoint(x: button.number("bitmapPositionX"), y: button.number("bitmapPositionY")),
                skill: skill,
                isTaken: level != nil,
                isPower: !skillRecord.text("Class").hasPrefix("Skill_Passive"),
                sprite: button.text(level != nil ? "bitmapNameUp" : "bitmapNameDisabled"),
                // The link field names the star this one hangs off, counting from one.
                linkedTo: record["devotionLinks\(index)"].map { Int($0.number) - 1 }
            ))
        }

        return Draft(
            name: database.localised(record.text("constellationDisplayTag")) ?? record.text("FileDescription"),
            description: database.localised(record.text("constellationInfoTag")) ?? "",
            iconPath: background?.text("bitmapName") ?? "",
            position: CGPoint(
                x: background?.number("bitmapPositionX") ?? 0,
                y: background?.number("bitmapPositionY") ?? 0
            ),
            stars: stars,
            given: affinities(in: record, prefix: "affinityGiven"),
            required: affinities(in: record, prefix: "affinityRequired"),
            bonuses: bonuses,
            takenTint: tint(in: record, prefix: "constellationActive"),
            availableTint: tint(in: record, prefix: "constellationAvailable"),
            lockedTint: tint(in: record, prefix: "constellationUnavailable")
        )
    }

    private func constellation(_ draft: Draft, earned: [String: Int]) -> ResolvedConstellation {
        ResolvedConstellation(
            name: draft.name,
            description: draft.description,
            iconPath: draft.iconPath,
            position: draft.position,
            stars: draft.stars,
            affinityGiven: draft.given,
            affinityRequired: draft.required,
            bonuses: draft.bonuses,
            isAvailable: draft.required.allSatisfy { earned[$0.name, default: 0] >= $0.amount },
            takenTint: draft.takenTint,
            availableTint: draft.availableTint,
            lockedTint: draft.lockedTint
        )
    }

    private func affinities(in record: ArzRecord, prefix: String) -> [ResolvedConstellation.Affinity] {
        (1 ... 3).compactMap { index in
            let name = record.text("\(prefix)Name\(index)")
            let amount = record.integer("\(prefix)\(index)")
            guard !name.isEmpty, amount > 0 else { return nil }

            return ResolvedConstellation.Affinity(name: name, amount: amount)
        }
    }

    // MARK: - The sky

    private func nebulas(in table: ArzRecord) -> [DevotionMap.Nebula] {
        (table["nebulaSections"]?.texts ?? []).compactMap { path in
            guard let record = database.record(path) else { return nil }

            return DevotionMap.Nebula(
                bitmap: record.text("bitmapName"),
                position: CGPoint(x: record.number("bitmapPositionX"), y: record.number("bitmapPositionY"))
            )
        }
    }

    /// The five affinities, named and coloured by the devotion window itself.
    private func affinities(in table: ArzRecord, earned: [String: Int]) -> [DevotionMap.Affinity] {
        (1 ... Self.affinityCount).compactMap { index in
            let padded = String(format: "%02d", index)
            guard let name = database.localised("tagDevotionAffinity\(padded)") else { return nil }

            return DevotionMap.Affinity(
                name: name,
                icon: database.bitmap(inRecordAt: table.text("affinity\(padded)Bitmap")),
                color: tint(in: table, prefix: name.lowercased()).color,
                earned: earned[name, default: 0]
            )
        }
    }

    private func tint(in record: ArzRecord, prefix: String) -> DevotionTint {
        DevotionTint(
            color: Color(
                red: record.number("\(prefix)Red"),
                green: record.number("\(prefix)Green"),
                blue: record.number("\(prefix)Blue")
            ),
            opacity: record.number("\(prefix)Alpha")
        )
    }
}
