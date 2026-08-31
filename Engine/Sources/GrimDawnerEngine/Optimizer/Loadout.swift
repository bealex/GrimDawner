// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// A component or an augment the search can put into one piece of worn gear.
public struct LoadoutFitting: Sendable, Identifiable, Hashable {
    public enum Kind: String, Sendable {
        case component = "Component"
        case augment = "Augment"
    }

    public let recordPath: String
    public let name: String
    public let iconPath: String
    public let kind: Kind
    public let levelRequirement: Int
    /// The faction whose merchant sells it and the standing that takes — augments only.
    public let faction: String
    public let standing: String

    public var id: String { recordPath }

    public static func == (lhs: LoadoutFitting, rhs: LoadoutFitting) -> Bool {
        lhs.recordPath == rhs.recordPath
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(recordPath) }
}

/// One worn piece the search can fit, with everything that goes into it.
public struct LoadoutSocket: Sendable, Identifiable {
    /// Where the piece is worn. The two weapon hands are not `EquipmentSlot` cases, so they carry
    /// their own index instead.
    public enum Place: Sendable, Hashable {
        case equipment(EquipmentSlot)
        case weapon(Int)
    }

    public let place: Place
    public let title: String
    public let itemName: String
    public let iconPath: String
    /// What the piece is, as the item directory names it — "Sword", "Head". What fits is decided by this.
    public let kind: String
    public let components: [LoadoutFitting]
    public let augments: [LoadoutFitting]
    /// What is in the piece now, so a plan can be read against what the character already wears.
    public let wornComponent: String
    public let wornAugment: String

    public var id: String { title + itemName }

    /// True where the piece takes nothing at all, which is every piece no component and no augment names.
    public var isEmpty: Bool { components.isEmpty && augments.isEmpty }
}

/// What one socket ends up holding.
public struct LoadoutChoice: Sendable, Identifiable {
    public let socket: LoadoutSocket
    public let component: LoadoutFitting?
    public let augment: LoadoutFitting?

    public var id: String { socket.id }

    /// True where this differs from what the character wears now, which is what a reader has to act on.
    public var isChanged: Bool {
        component?.recordPath ?? "" != socket.wornComponent || augment?.recordPath ?? "" != socket.wornAugment
    }
}

/// What the search is being asked for beyond capped resistances.
public enum LoadoutGoal: String, CaseIterable, Sendable, Identifiable {
    case attack = "Attack"
    case defence = "Defence"
    case balanced = "Balanced"

    public var id: String { rawValue }

    public var detail: String {
        switch self {
            case .attack: "Offensive Ability and the chosen skill's damage"
            case .defence: "Defensive Ability, Armor Rating and absorption"
            case .balanced: "Both at once, each weighed against what the character has now"
        }
    }

    public var symbolName: String {
        switch self {
            case .attack: "bolt.fill"
            case .defence: "shield.fill"
            case .balanced: "scalemass"
        }
    }
}

/// What every plan has to reach before anything else is weighed.
public struct LoadoutTarget: Sendable {
    /// The resistances that have to be at their maximum, and how far past it to push each.
    public var required: Set<ResistanceKind>
    /// Percentage points beyond the cap to aim for, which is what survives a resistance-reducing enemy.
    public var overcap: Double
    /// The Defensive Ability the defence and balanced plans should reach. Unlike the caps this is a
    /// thing to aim at rather than a thing to hold: a plan that cannot reach it is still returned, and
    /// says by how much it fell short.
    public var minimumDefensiveAbility: Double

    public init(required: Set<ResistanceKind>, overcap: Double = 0, minimumDefensiveAbility: Double = 0) {
        self.required = required
        self.overcap = overcap
        self.minimumDefensiveAbility = minimumDefensiveAbility
    }

    /// The resistances the game caps at 80 and a build is expected to hold there. Physical caps
    /// nowhere near it and is left out.
    public static var standard: LoadoutTarget {
        LoadoutTarget(required: Set(ResistanceKind.allCases.filter { $0 != .physical }))
    }
}

/// One answer: what to socket, and what the character is worth once it is.
public struct LoadoutPlan: Sendable, Identifiable {
    public let id = UUID()
    public let goal: LoadoutGoal
    public let choices: [LoadoutChoice]
    /// The character as it stands with this plan socketed, built the same way the app builds any
    /// character, so every figure on it is the app's own rather than the search's.
    public let sheet: CharacterSheet
    /// The chosen skill's damage a second, absent when no skill was chosen.
    public let skillDamagePerSecond: Double?
    /// Resistances still short of their target, which is what makes a plan infeasible.
    public let shortfalls: [ResistanceKind: Double]
    /// How far under the asked-for Defensive Ability it landed, if it did. Not a reason to call the
    /// plan infeasible — only the caps are.
    public let defensiveAbilityShortfall: Double

    public var isFeasible: Bool { shortfalls.isEmpty }

    public var changedCount: Int { choices.filter(\.isChanged).count }

    /// Every faction an augment in this plan is bought from, and the standing it asks for.
    public var vendors: [(faction: String, standing: String)] {
        var seen = Set<String>()
        var found = [(faction: String, standing: String)]()
        for choice in choices {
            guard let augment = choice.augment, !augment.faction.isEmpty else { continue }
            guard seen.insert("\(augment.faction)|\(augment.standing)").inserted else { continue }

            found.append((augment.faction, augment.standing))
        }
        return found.sorted { $0.faction.localizedStandardCompare($1.faction) == .orderedAscending }
    }
}

/// How far the search has got, for a caller that has to say so while it waits.
public struct LoadoutProgress: Sendable {
    public let goal: LoadoutGoal
    public let fraction: Double
    public let stage: String
}
