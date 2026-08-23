// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import CoreGraphics
import Foundation
import SwiftUI

/// One box on the game's equipment panel: where it sits, and the outline it shows when empty.
public struct DollSlot: Identifiable, Sendable {
    public enum Kind: Sendable, Hashable {
        case equipment(EquipmentSlot)
        case mainHand
        case offHand
    }

    public let id = UUID()
    public let kind: Kind
    public let frame: CGRect
    public let silhouette: String

    public var title: String {
        switch kind {
            case let .equipment(slot): slot.title
            case .mainHand: "Main Hand"
            case .offHand: "Off Hand"
        }
    }

    public var symbolName: String {
        switch kind {
            case let .equipment(slot): slot.symbolName
            case .mainHand: "bolt.horizontal"
            case .offHand: "shield"
        }
    }
}

/// The equipment doll, arranged as the game's character window arranges it.
public struct EquipmentDoll: Sendable {
    public let slots: [DollSlot]
    /// The character window's artwork. The doll occupies its top-left corner, which `canvas` measures.
    public let background: String
    public let canvas: CGSize

    public func slot(_ kind: DollSlot.Kind) -> DollSlot? { slots.first { $0.kind == kind } }
}

/// A mastery's skill panel in the coordinates the game's skill window uses.
public struct MasteryPanel: Sendable {
    /// A mastery level at which the next column of skills opens, and where the window prints it.
    public struct Milestone: Identifiable, Sendable {
        public let id = UUID()
        public let level: Int
        public let centre: CGPoint
    }

    public let background: String
    /// The class artwork the panel is painted over.
    public let artwork: String
    public let bar: String
    public let barOrigin: CGPoint
    public let milestones: [Milestone]
    /// Where the window prints a skill's rank, measured from the top-left of its button.
    public let rankOffset: CGPoint

    /// The colours the window prints a rank in: one carrying bonus ranks, one at its cap, one not learned.
    public let augmentColor: Color
    public let completeColor: Color
    public let unavailableColor: Color
}

/// Reads the geometry of the game's own windows: which box sits where, and what art fills it.
public struct LayoutResolver {
    public init(database: GameDatabase) { self.database = database }

    public let database: GameDatabase

    private static let characterWindowPath = "records/ui/character/character_mastertable.dbr"
    private static let panelBasePath = "records/ui/skills/classcommon/skills_classpanelconfiguration.dbr"
    private static let gameEnginePath = "records/game/gameengine.dbr"

    /// The character window's own mark for each resistance, by the field that names it. The window
    /// draws them beside the numbers; the field name is what says which resistance a mark belongs to.
    private static let resistanceMarks: [(field: String, kind: ResistanceKind)] = [
        ("tab1FireResistanceBitmap", .fire),
        ("tab1IceResistanceBitmap", .cold),
        ("tab1LightningResistanceBitmap", .lightning),
        ("tab1PoisonResistanceBitmap", .acid),
        ("tab1PiercingResistanceBitmap", .pierce),
        ("tab1BleedingResistanceBitmap", .bleeding),
        ("tab1LifeResistanceBitmap", .vitality),
        ("tab1SpiritResistanceBitmap", .aether),
        // The last two fields carry names the template left behind — the artwork is a helm and a
        // magenta bolt, and the character window's own grid shows them against physical and chaos.
        ("tab1StunResistanceBitmap", .physical),
        ("tab1DisruptionResistanceBitmap", .chaos),
    ]

    private static let characterTab1Path =
        "records/ui/character/characterinfotab1/charinfo_mastertable_tab1.dbr"

    /// The artwork the character window puts beside each resistance, for the ones it marks.
    public func resistanceIcons() -> [ResistanceKind: String] {
        guard let table = database.record(Self.characterTab1Path) else { return [:] }

        var icons = [ResistanceKind: String]()
        for mark in Self.resistanceMarks {
            let path = database.bitmap(inRecordAt: table.text(mark.field))
            guard !path.isEmpty else { continue }

            icons[mark.kind] = path
        }
        return icons
    }

    /// The character window's equipment boxes, keyed by the field that names each one.
    private static let dollBoxes: [(key: String, kind: DollSlot.Kind)] = [
        ("equipHead", .equipment(.head)),
        ("equipNeck", .equipment(.neck)),
        ("equipChest", .equipment(.chest)),
        ("equipLegs", .equipment(.legs)),
        ("equipFeet", .equipment(.feet)),
        ("equipHands", .equipment(.hands)),
        ("equipFinger1", .equipment(.ring1)),
        ("equipFinger2", .equipment(.ring2)),
        ("equipWaist", .equipment(.waist)),
        ("equipShoulders", .equipment(.shoulders)),
        ("equipMedal", .equipment(.medal)),
        ("equipArtifact", .equipment(.relic)),
        ("equipHandRight", .mainHand),
        ("equipHandLeft", .offHand),
    ]

    public func equipmentDoll() -> EquipmentDoll? {
        guard let table = database.record(Self.characterWindowPath) else { return nil }

        var slots = [DollSlot]()
        for box in Self.dollBoxes {
            guard let record = database.record(table.text(box.key)) else { continue }

            slots.append(DollSlot(
                kind: box.kind,
                frame: CGRect(
                    x: record.number("itemX"),
                    y: record.number("itemY"),
                    width: record.number("itemXSize"),
                    height: record.number("itemYSize")
                ),
                silhouette: record.text("silhouette")
            ))
        }

        guard let first = slots.first else { return nil }

        let bounds = slots.dropFirst().reduce(first.frame) { $0.union($1.frame) }
        return EquipmentDoll(
            slots: slots,
            background: database.bitmap(inRecordAt: table.text("characterDisplayBitmap")),
            // The panel repeats its top and left insets as its bottom and right margins.
            canvas: CGSize(width: bounds.maxX + bounds.minX, height: bounds.maxY + bounds.minY)
        )
    }

    /// The panel one mastery's skills are laid out on, read from that mastery's class table.
    public func masteryPanel(classTable: ArzRecord) -> MasteryPanel {
        let bar = database.record(classTable.text("masteryBar"))

        return MasteryPanel(
            background: database.bitmap(inRecordAt: classTable.text("skillPaneBaseBitmap")),
            artwork: database.bitmap(inRecordAt: classTable.text("skillPaneMasteryBitmap")),
            bar: bar?.text("bitmapFullName") ?? "",
            barOrigin: CGPoint(x: bar?.number("bitmapPositionX") ?? 0, y: bar?.number("bitmapPositionY") ?? 0),
            milestones: milestones(),
            rankOffset: rankOffset(),
            augmentColor: rankColor("skillLevelAugmentColor"),
            completeColor: rankColor("skillLevelCompleteColor"),
            unavailableColor: rankColor("skillLevelUnavailableColor")
        )
    }

    private func rankOffset() -> CGPoint {
        guard
            let base = database.record(Self.panelBasePath),
            let box = database.record(base.text("skillLevel"))
        else { return .zero }

        return CGPoint(
            x: box.number("textBoxX") + box.number("textBoxXSize") / 2,
            y: box.number("textBoxY") + box.number("textBoxYSize") / 2
        )
    }

    private func rankColor(_ prefix: String) -> Color {
        guard let base = database.record(Self.panelBasePath) else { return .primary }

        return Color(
            red: base.number("\(prefix).R"),
            green: base.number("\(prefix).G"),
            blue: base.number("\(prefix).B")
        )
    }

    /// The mastery levels that open each column of skills, placed where the window prints them.
    private func milestones() -> [MasteryPanel.Milestone] {
        guard
            let levels = database.record(Self.gameEnginePath)?["skillMasteryTierLevel"]?.numbers,
            let base = database.record(Self.panelBasePath)
        else { return [] }

        return levels.enumerated().compactMap { index, level in
            guard let box = database.record(base.text("masteryMilestoneNumber\(index + 1)")) else { return nil }

            return MasteryPanel.Milestone(
                level: Int(level),
                centre: CGPoint(
                    x: box.number("textBoxX") + box.number("textBoxXSize") / 2,
                    y: box.number("textBoxY") + box.number("textBoxYSize") / 2
                )
            )
        }
    }
}
