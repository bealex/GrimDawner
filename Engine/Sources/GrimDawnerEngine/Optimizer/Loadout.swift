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

/// What the search is being asked for: what every plan has to reach, and how hard to look for it.
public struct LoadoutTarget: Sendable {
    /// The difficulty the plan is for, which decides how much the game itself takes off the character's
    /// resistances before anything is socketed. A set of fittings that caps on Elite is under the cap
    /// the moment Ultimate starts, so this is what says which fight is being planned for. Ascendant is
    /// Ultimate here: the game's ascendant adjustment is the monsters' alone.
    public var difficulty: Difficulty
    /// Percentage points beyond the cap to aim for, which is what survives a resistance-reducing enemy.
    public var overcap: Double
    /// The Defensive Ability the defence and balanced plans should reach. Unlike the caps this is a
    /// thing to aim at rather than a thing to hold: a plan that cannot reach it is still returned, and
    /// says by how much it fell short.
    public var minimumDefensiveAbility: Double
    /// The Armor Absorption, as a percentage, those same plans should reach. Aimed at the same way:
    /// a plan short of it comes back all the same and says so.
    public var minimumArmorAbsorption: Double
    /// The Armor Rating past which more is worth nothing to the plan, so a socket that would have gone
    /// on armour goes somewhere else instead. Zero asks for no ceiling. It is not a limit the search is
    /// held to — armour that comes along with something else worth having is kept, and a plan may land
    /// above it.
    public var armorCeiling: Double
    /// Whether to finish each run with a pass over every pair of sockets. Coordinate ascent settles
    /// where no single change helps, which is blind to two that only pay off together — the half of a
    /// resistance neither socket can cap alone. The pass is exact over pairs and costs several times the
    /// sweeps, so it can be turned off.
    public var refinesPairs: Bool
    /// Whether to go one level further and walk every trio of sockets too, which is exact over three at
    /// a time and nothing is shortlisted out of it. Two hundred million combinations a pass on a full
    /// character — minutes rather than seconds — so it is off unless it is asked for.
    public var refinesTriples: Bool

    public init(
        difficulty: Difficulty = .ultimate,
        overcap: Double = 0,
        minimumDefensiveAbility: Double = 0,
        minimumArmorAbsorption: Double = 0,
        armorCeiling: Double = 0,
        refinesPairs: Bool = true,
        refinesTriples: Bool = false
    ) {
        self.difficulty = difficulty
        self.overcap = overcap
        self.minimumDefensiveAbility = minimumDefensiveAbility
        self.minimumArmorAbsorption = minimumArmorAbsorption
        self.armorCeiling = armorCeiling
        self.refinesPairs = refinesPairs
        self.refinesTriples = refinesTriples
    }

    /// The resistances the game caps at 80 and a build is expected to hold there, which every plan is
    /// held to. Physical caps nowhere near it and is left out.
    public static let capped = Set(ResistanceKind.allCases.filter { $0 != .physical })

    /// The ask a plan is made against unless the reader changes it: the hardest fight in the game.
    public static var standard: LoadoutTarget { LoadoutTarget() }
}

/// One answer: what to socket, and what the character is worth once it is.
public struct LoadoutPlan: Sendable, Identifiable {
    public let id = UUID()
    public let goal: LoadoutGoal
    /// The difficulty it was planned for, which is what its sheet's resistances are read on.
    public let difficulty: Difficulty
    public let choices: [LoadoutChoice]
    /// The character as it stands with this plan socketed, built the same way the app builds any
    /// character, so every figure on it is the app's own rather than the search's.
    public let sheet: CharacterSheet
    /// What the difficulty itself takes off each resistance. It is already inside the sheet's figures,
    /// and is most of why a plan has to work as hard as it does.
    public let difficultyPenalty: [ResistanceKind: Double]
    /// The chosen skill's damage a second, absent when no skill was chosen.
    public let skillDamagePerSecond: Double?
    /// Resistances still short of their target, which is what makes a plan infeasible.
    public let shortfalls: [ResistanceKind: Double]
    /// How far under the asked-for Defensive Ability it landed, if it did. Not a reason to call the
    /// plan infeasible — only the caps are.
    public let defensiveAbilityShortfall: Double
    /// The same for Armor Absorption, in percentage points.
    public let armorAbsorptionShortfall: Double

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
