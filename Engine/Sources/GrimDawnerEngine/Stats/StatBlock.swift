// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// A bag of `.dbr` stat values, summed as they are collected.
///
/// Grim Dawn adds every source of a given stat together — two rings with `+20% Fire Resistance` give
/// `+40%` — so a plain sum is the whole aggregation rule for the flat and percentage fields alike.
public struct StatBlock: Sendable {
    public fileprivate(set) var values: [String: Double] = [:]

    /// `+N` to a specific skill, keyed by the skill's `.dbr` path.
    public private(set) var skillBonuses: [String: Int] = [:]
    /// `+N` to every skill in a mastery, keyed by the mastery's `.dbr` path.
    public private(set) var masteryBonuses: [String: Int] = [:]
    /// `+N` to all skills, from any source.
    public private(set) var allSkillBonus: Int = 0
    /// Damage conversions declared by gear: a share of one damage type dealt as another.
    public private(set) var conversions: [Conversion] = []

    public struct Conversion: Sendable, Hashable {
        public let source: String
        public let target: String
        public let percent: Double
    }

    public subscript(key: String) -> Double {
        get { values[key] ?? 0 }
        set { values[key] = newValue }
    }

    public func value(_ key: String) -> Double { values[key] ?? 0 }

    public mutating func increase(_ key: String, by amount: Double) {
        guard amount != 0 else { return }

        values[key, default: 0] += amount
    }

    public mutating func addSkillBonus(_ path: String, _ levels: Int) {
        guard !path.isEmpty, levels != 0 else { return }

        skillBonuses[path.lowercased(), default: 0] += levels
    }

    public mutating func addMasteryBonus(_ path: String, _ levels: Int) {
        guard !path.isEmpty, levels != 0 else { return }

        masteryBonuses[path.lowercased(), default: 0] += levels
    }

    public mutating func addAllSkillBonus(_ levels: Int) {
        allSkillBonus += levels
    }

    public mutating func addConversion(_ conversion: Conversion) {
        conversions.append(conversion)
    }

    public mutating func merge(_ other: StatBlock) {
        for (key, amount) in other.values { values[key, default: 0] += amount }
        for (path, levels) in other.skillBonuses { skillBonuses[path, default: 0] += levels }
        for (path, levels) in other.masteryBonuses { masteryBonuses[path, default: 0] += levels }
        allSkillBonus += other.allSkillBonus
        conversions += other.conversions
    }

    /// Total `+N` that applies to one skill: its own bonus, its mastery's, and the all-skills bonus.
    public func bonus(forSkill path: String, mastery masteryPath: String?) -> Int {
        var total = allSkillBonus + (skillBonuses[path.lowercased()] ?? 0)
        if let masteryPath { total += masteryBonuses[masteryPath.lowercased()] ?? 0 }
        return total
    }

    /// The block's skill bonuses and conversions alone, for merging beside a rolled set of values.
    public func withoutCataloguedValues() -> StatBlock {
        var copy = self
        copy.values = [:]
        return copy
    }

    /// True when the block carries nothing a character sheet would show.
    public var hasNothingToShow: Bool {
        catalogued().isEmpty && allSkillBonus == 0 && skillBonuses.isEmpty && conversions.isEmpty
    }

    /// One line per stat, with the flat and percentage variants of the same thing folded together: the
    /// game writes them as two fields, but they read as one line — "Aether Damage +11 & +50%".
    public static func merged(
        _ lines: [(definition: StatDefinition, value: Double)]
    ) -> [(title: String, parts: [(definition: StatDefinition, value: Double)])] {
        var order = [String]()
        var parts = [String: [(definition: StatDefinition, value: Double)]]()

        for line in lines {
            if parts[line.definition.title] == nil { order.append(line.definition.title) }
            parts[line.definition.title, default: []].append(line)
        }
        return order.map { (title: $0, parts: parts[$0] ?? []) }
    }

    /// The stats the catalogue knows about, grouped and ordered for display.
    public func catalogued() -> [(group: StatGroup, lines: [(definition: StatDefinition, value: Double)])] {
        var grouped = [StatGroup: [(StatDefinition, Double)]]()

        for (key, amount) in values {
            guard amount != 0, let definition = StatCatalog.definition(for: key) else { continue }

            grouped[definition.group, default: []].append((definition, amount))
        }

        return StatGroup.allCases.compactMap { group in
            guard let lines = grouped[group], !lines.isEmpty else { return nil }

            let sorted = lines.sorted { $0.0.order < $1.0.order }
            return (group, sorted.map { (definition: $0.0, value: $0.1) })
        }
    }
}
