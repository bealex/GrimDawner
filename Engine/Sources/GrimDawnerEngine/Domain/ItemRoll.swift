// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// The game's own item randomiser: the numbers a record holds are the middle of a band, and each
/// item rolls its own values from its seed.
///
/// The engine walks the item's stores in a fixed order, drawing from one MINSTD stream as it goes, so
/// a stat's value depends on every stat drawn before it. The order and the per-store mechanics below
/// follow the community's reverse-engineering of the engine
/// ([marius00/GrimDawnItemStats](https://github.com/marius00/GrimDawnItemStats)); nothing in the
/// shipped data describes them.
public enum ItemRoll {
    /// One record's fields, as the roller reads them.
    public struct Table {
        public var values: [String: Double] = [:]
        public var text: [String: String] = [:]

        public var isEmpty: Bool { values.isEmpty && text.isEmpty }

        public func has(_ field: String) -> Bool { values[field] != nil }

        public func value(_ field: String) -> Double { values[field] ?? 0 }
    }

    /// The jitter an item's own record rolls at. Affixes roll at their `lootRandomizerJitter`.
    public static let baseJitter = 20.0

    /// Where a roll's draws come from: the item's own stream, or the end of the band it rolls in.
    public enum Draws {
        case seeded(Random)
        case lowest
        case highest

        /// The step within `0 ... 2 * spread` this draw lands on.
        public mutating func step(within spread: Double) -> Double {
            switch self {
                case var .seeded(random):
                    let modulus = max(Int64(2 * spread + 1), 1)
                    let value = Double(random.next() % modulus)
                    self = .seeded(random)
                    return value
                case .lowest: return 0
                case .highest: return 2 * spread
            }
        }
    }

    /// Park-Miller MINSTD by Schrage's method, primed once with the item's seed as the game primes it.
    public struct Random {
        private var state: Int64

        public init(seed: UInt32) {
            state = Self.step(Int64(seed))
        }

        public mutating func next() -> Int64 {
            state = Self.step(state)
            return state
        }

        private static func step(_ seed: Int64) -> Int64 {
            let high = seed / 127_773
            let low = seed % 127_773
            let result = 16807 * low - 2836 * high
            return result < 0 ? result + 2_147_483_647 : result
        }
    }

    // MARK: - Rolling one value

    /// The integer-uniform roll the character, damage, retaliation and defence stores use.
    public static func jitterChar(_ value: Double, _ percent: Double, _ draws: inout Draws) -> Double {
        guard value != 0, percent != 0 else { return value }

        var spread = (value * percent * 0.01).rounded(.towardZero)
        if spread == 0 { spread = 1 }

        let rolled = draws.step(within: spread) - spread + value
        // The game snaps a roll that lands inside ±1 back to the record's value; the draw still counted.
        return abs(rolled) < 1 ? value : rolled
    }

    /// As `jitterChar`, but a skill stat draws even where it cannot move and never gets the ±1 floor.
    public static func jitterSkill(_ value: Double, _ percent: Double, _ draws: inout Draws) -> Double {
        guard value != 0 else { return value }

        let spread = (value * percent * 0.01).rounded(.towardZero)
        let rolled = draws.step(within: spread) - spread + value
        return abs(rolled) < 1 ? value : rolled
    }

    /// An item's offensive scale, applied after the roll in the single precision the game uses.
    public static func applyScale(_ rolled: Double, _ scalePercent: Double) -> Double {
        let product = Float(rolled) * Float(100 + scalePercent)
        return Double((product / 100).rounded(.towardZero))
    }

    /// Conversions roll multiplicatively rather than by integer steps.
    public static func jitterConversion(_ value: Double, _ percent: Double, _ draws: inout Draws) -> Double {
        guard percent > 0 else { return value }

        let share = Float(percent * 0.01)
        // The draw runs over the whole 31-bit range here, so the band's ends are its ends.
        let position: Float
        switch draws {
            case var .seeded(random):
                position = Float(random.next()) * Float(pow(2.0, -31.0))
                draws = .seeded(random)
            case .lowest: position = 0
            case .highest: position = 1
        }
        let factor = position * (2 * share) + (1 - share)
        return min(max(value * Double(factor), 0), 100)
    }

    public static func roundAway(_ value: Double) -> Double { value.rounded(.toNearestOrAwayFromZero) }
}
