// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// Everything the search works over: the sockets, what fits each of them, and what each fitting is
/// worth once reduced to the figures a plan is judged on.
///
/// Index 0 of every option list is "nothing", so a socket can always be left empty.
public struct LoadoutProblem: Sendable {
    public let sockets: [LoadoutSocket]
    /// What fits each socket, in the socket's own order with a leading empty option.
    public let components: [[LoadoutFitting?]]
    public let augments: [[LoadoutFitting?]]
    /// The same lists reduced to numbers, which is what the search adds up.
    public let componentStats: [[LoadoutStats]]
    public let augmentStats: [[LoadoutStats]]
    public let evaluator: LoadoutEvaluator
    /// What the character wears now, as indices into the lists above.
    public let worn: [LoadoutChoiceIndex]

    public var isEmpty: Bool { sockets.isEmpty }

    /// How many combinations there are, which is why the search is a search.
    public var combinations: Double {
        zip(components, augments).reduce(1.0) { $0 * Double($1.0.count) * Double($1.1.count) }
    }
}

/// One socket's pick, as positions in that socket's own option lists.
public struct LoadoutChoiceIndex: Sendable, Hashable {
    public var component: Int
    public var augment: Int

    public init(component: Int = 0, augment: Int = 0) {
        self.component = component
        self.augment = augment
    }
}

/// Reads a character into a problem the search can run on.
public struct LoadoutProblemBuilder {
    public init(database: GameDatabase, catalogue: [CataloguedItem]) {
        self.database = database
        self.catalogue = catalogue
    }

    public let database: GameDatabase
    public let catalogue: [CataloguedItem]

    /// Builds the problem for one character. `skill` is what the attack goal is scored on; without one
    /// it falls back to Offensive Ability alone.
    public func problem(for character: ResolvedCharacter, skill: ResolvedSkill?) -> LoadoutProblem {
        let resolver = ItemResolver(database: database, skills: SkillResolver(database: database))
        let weights = hitRegionWeights()
        // The search weighs a type by what the skill throws of it, which is the middle of its band.
        let damageWeights =
            skill
            .map { EncounterEngine.damage(of: $0).mapValues { ($0.lowerBound + $0.upperBound) / 2 } } ?? [:]

        let places = self.places(of: character)
        var sockets = [LoadoutSocket]()
        var components = [[LoadoutFitting?]]()
        var augments = [[LoadoutFitting?]]()
        var componentStats = [[LoadoutStats]]()
        var augmentStats = [[LoadoutStats]]()
        var worn = [LoadoutChoiceIndex]()

        for place in places {
            guard
                let record = database.record(place.item.recordPath),
                case let kind = CataloguedItem.kind(ofClass: record.recordClass),
                case let fitting = fittings(for: kind, upTo: character.level),
                !(fitting.components.isEmpty && fitting.augments.isEmpty)
            else { continue }

            let weight = place.slot.flatMap { weights[$0] } ?? 1
            let socket = LoadoutSocket(
                place: place.place,
                title: place.title,
                itemName: place.item.displayName,
                iconPath: place.item.iconPath,
                kind: kind,
                components: fitting.components,
                augments: fitting.augments,
                wornComponent: place.item.raw.relicName,
                wornAugment: place.item.raw.augmentName
            )
            let componentList: [LoadoutFitting?] = [ nil ] + fitting.components
            let augmentList: [LoadoutFitting?] = [ nil ] + fitting.augments

            sockets.append(socket)
            components.append(componentList)
            augments.append(augmentList)
            componentStats.append(componentList.map {
                stats(of: $0, using: resolver, armorWeight: weight, damageWeights: damageWeights)
            })
            augmentStats.append(augmentList.map {
                stats(of: $0, using: resolver, armorWeight: weight, damageWeights: damageWeights)
            })
            worn.append(LoadoutChoiceIndex(
                component: componentList.firstIndex { $0?.recordPath == place.item.raw.relicName } ?? 0,
                augment: augmentList.firstIndex { $0?.recordPath == place.item.raw.augmentName } ?? 0
            ))
        }

        return LoadoutProblem(
            sockets: sockets,
            components: components,
            augments: augments,
            componentStats: componentStats,
            augmentStats: augmentStats,
            evaluator: evaluator(
                for: character,
                sockets: sockets,
                weights: weights,
                places: places,
                damageWeights: damageWeights
            ),
            worn: worn
        )
    }

    // MARK: - Sockets

    /// One piece of worn gear the search can fit, and where it is worn.
    private struct Place {
        let place: LoadoutSocket.Place
        let title: String
        let item: ResolvedItem
        /// The hit region it is worn on, for the slots that are one.
        let slot: EquipmentSlot?
    }

    /// The gear a component or an augment can go into: everything worn, and the weapons in hand.
    ///
    /// Only the weapon set being held counts, the same way the sheet only reads that one.
    private func places(of character: ResolvedCharacter) -> [Place] {
        var found = character.equipment.compactMap { equipped -> Place? in
            guard let item = equipped.item else { return nil }

            return Place(place: .equipment(equipped.slot), title: equipped.slot.title, item: item, slot: equipped.slot)
        }

        let held = character.weaponSets.first { $0.isActive } ?? character.weaponSets.first
        for (index, item) in (held?.items ?? []).enumerated() {
            guard let item else { continue }

            found.append(Place(place: .weapon(index), title: index == 0 ? "Weapon" : "Off-hand", item: item, slot: nil))
        }
        return found
    }

    /// The components and augments the game says fit a kind of gear, that the character is deep
    /// enough into the game to use.
    private func fittings(for kind: String, upTo level: Int) -> (
        components: [LoadoutFitting], augments: [LoadoutFitting]
    ) {
        var components = [LoadoutFitting]()
        var augments = [LoadoutFitting]()

        for item in catalogue {
            guard item.levelRequirement <= level, item.appliesTo.contains(kind) else { continue }

            let kind: LoadoutFitting.Kind = item.recordClass == "ItemEnchantment" ? .augment : .component
            let fitting = LoadoutFitting(
                recordPath: item.path,
                name: item.name,
                iconPath: item.iconPath,
                kind: kind,
                levelRequirement: item.levelRequirement,
                faction: item.soldBy,
                standing: item.standing
            )
            if kind == .augment { augments.append(fitting) } else { components.append(fitting) }
        }
        return (components, augments)
    }

    private func stats(
        of fitting: LoadoutFitting?,
        using resolver: ItemResolver,
        armorWeight: Double,
        damageWeights: [DamageType: Double]
    ) -> LoadoutStats {
        guard let fitting, let part = resolver.fitting(at: fitting.recordPath) else { return LoadoutStats() }

        return LoadoutStats(part.stats, armorWeight: armorWeight, damageWeights: damageWeights)
    }

    // MARK: - The character underneath

    /// The character with every component and augment taken back out, which is what the search adds to.
    private func evaluator(
        for character: ResolvedCharacter,
        sockets: [LoadoutSocket],
        weights: [EquipmentSlot: Double],
        places: [Place],
        damageWeights: [DamageType: Double]
    ) -> LoadoutEvaluator {
        var bare = character.sheet.contributions
        var worn = StatBlock()
        for item in character.equippedItems {
            for part in item.parts where Self.socketed.contains(part.kind) {
                bare.subtract(part.stats)
                worn.merge(part.stats)
            }
        }

        // Armour is stored weighted, and a block on its own cannot know which region each piece of it
        // sits on. So the bare block is read as though all of it were shared, and the armour actually
        // worn on a hit region is then re-weighted.
        var base = LoadoutStats(bare, armorWeight: 1, damageWeights: damageWeights)
        for place in places {
            guard let slot = place.slot, let weight = weights[slot] else { continue }

            let piece = armor(of: place.item) - socketedArmor(of: place.item)
            base.weightedArmor += piece * (weight - 1)
        }

        var wornStats = LoadoutStats(worn, armorWeight: 1, damageWeights: damageWeights)
        for place in places {
            guard let slot = place.slot, let weight = weights[slot] else { continue }

            wornStats.weightedArmor += socketedArmor(of: place.item) * (weight - 1)
        }

        return LoadoutEvaluator(
            database: database,
            save: character.save,
            base: base,
            worn: wornStats,
            flatSkillDamage: damageWeights.values.reduce(0, +),
            weaponSpeed: weaponSpeed(of: character)
        )
    }

    /// The parts a socket holds: a component, whatever its completion bonus rolled, and an augment.
    private static let socketed: Set<ItemPart.Kind> = [ .component, .completionBonus, .augment ]

    private func armor(of item: ResolvedItem) -> Double {
        item.stats.value("defensiveProtection") + item.stats.value("defensiveBonusProtection")
    }

    private func socketedArmor(of item: ResolvedItem) -> Double {
        item.parts
            .filter { Self.socketed.contains($0.kind) }
            .reduce(0) { $0 + $1.stats.value("defensiveProtection") + $1.stats.value("defensiveBonusProtection") }
    }

    /// How often each hit region is struck, as a share of one, which is how the rating weights armour.
    private func hitRegionWeights() -> [EquipmentSlot: Double] {
        let formulas = database.record("records/game/combatformulas.dbr")
        var chances = [EquipmentSlot: Double]()
        for slot in EquipmentSlot.allCases {
            guard let key = slot.hitRegionChanceKey else { continue }

            chances[slot] = formulas?.number(key) ?? 0
        }

        let total = chances.values.reduce(0, +)
        guard total > 0 else { return [:] }

        return chances.mapValues { $0 / total }
    }

    private func weaponSpeed(of character: ResolvedCharacter) -> Double {
        let held = character.weaponSets.first { $0.isActive } ?? character.weaponSets.first
        return held?.items
            .compactMap { $0.flatMap { database.record($0.raw.baseName) } }
            .map { $0.number("characterBaseAttackSpeed") }
            .reduce(0, +) ?? 0
    }
}
