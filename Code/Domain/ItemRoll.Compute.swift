// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

extension ItemRoll {
    /// What the roller was given: the item's own record and the affixes that roll alongside it.
    struct Sources {
        var base = Table()
        var prefix: Table?
        var suffix: Table?
        var modifier: Table?
        var seed: UInt32 = 0
    }

    /// The stats an item actually carries, rolled from its seed.
    ///
    /// Every source is walked in one pass because they share a single stream: a prefix's draw shifts
    /// what the base rolls next, so the sources cannot be rolled apart and added up afterwards.
    static func stats(of sources: Sources, drawing draws: Draws? = nil) -> [String: Double] {
        var pass = Pass(sources: sources, draws: draws ?? .seeded(Random(seed: sources.seed)))
        return pass.run()
    }

    /// What an item grants every pet the character has.
    ///
    /// The block is rolled apart from the item's own stats: each record that carries one — the item's,
    /// its prefix's, its suffix's — rolls its own stream from the item's seed, so a pet bonus neither
    /// takes draws from the item's figures nor gives them any.
    static func petStats(of sources: [(table: Table, jitter: Double)], seed: UInt32) -> [String: Double] {
        var total = [String: Double]()
        for source in sources {
            var pass = Pass(
                sources: Sources(base: source.table, seed: seed),
                draws: .seeded(Random(seed: seed)),
                baseJitter: source.jitter
            )
            for (key, value) in pass.run() { total[key, default: 0] += value }
        }
        return total
    }

    /// One roll of one item.
    private struct Pass {
        let base: Table
        let prefix: Table?
        let suffix: Table?
        let modifier: Table?

        let baseJitter: Double
        let prefixJitter: Double
        let suffixJitter: Double
        let modifierJitter: Double
        let scale: Double

        var random: Draws
        var result = [String: Double]()
        var handledDuration = Set<String>()
        var earlySkill = [String: Double]()
        var earlySkillDone: Bool
        let prefixHasSkill: Bool
        let suffixHasSkill: Bool

        init(sources: Sources, draws: Draws, baseJitter: Double = ItemRoll.baseJitter) {
            base = sources.base
            prefix = sources.prefix
            suffix = sources.suffix
            modifier = sources.modifier

            self.baseJitter = baseJitter
            prefixJitter = sources.prefix?.value("lootRandomizerJitter") ?? 0
            suffixJitter = sources.suffix?.value("lootRandomizerJitter") ?? 0
            modifierJitter = sources.modifier?.value("lootRandomizerJitter") ?? 0
            scale =
                sources.base.value("attributeScalePercent")
                + (sources.prefix?.value("lootRandomizerScale") ?? 0)
                + (sources.suffix?.value("lootRandomizerScale") ?? 0)
                + (sources.modifier?.value("lootRandomizerScale") ?? 0)

            random = draws
            prefixHasSkill = ItemRoll.earlySkillFields.contains { sources.prefix?.has($0) ?? false }
            suffixHasSkill = ItemRoll.earlySkillFields.contains { sources.suffix?.has($0) ?? false }
            earlySkillDone = !(prefixHasSkill || suffixHasSkill)
        }

        /// The sources that roll, paired with the jitter each rolls at. The base is last: only the
        /// damage and defence stores draw it first, and those say so themselves.
        private var affixes: [(table: Table, jitter: Double)] {
            [ (prefix, prefixJitter), (suffix, suffixJitter), (modifier, modifierJitter) ]
                .compactMap { table, jitter in table.map { ($0, jitter) } }
        }

        private var everySource: [(table: Table, jitter: Double)] {
            [ (base, baseJitter) ] + affixes
        }

        private var hasAffix: Bool { prefix != nil || suffix != nil || modifier != nil }

        private var isOffhand: Bool { base.text["Class"] == "WeaponArmor_Offhand" }

        mutating func run() -> [String: Double] {
            for draw in ItemRoll.drawOrder {
                switch draw.store {
                    case .flat, .slowFlat, .retaliationFlat: rollPair(draw)
                    case .offensiveReflex, .retaliationReflex, .retaliationDuration: rollWithComponents(draw)
                    case .offensiveSlow: rollSlow(draw)
                    case .offensiveReduction: rollReduction(draw)
                    case .leech: rollLeech(draw)
                    case .conversion: rollConversion(draw)
                    default: rollScalar(draw)
                }
            }
            echoFixedFields()
            return result
        }

        // MARK: - The stores

        /// A flat damage line: its minimum and the spread up to its maximum each draw.
        private mutating func rollPair(_ draw: ItemRoll.Draw) {
            let minimum = draw.field + "Min"
            let maximum = draw.field + "Max"
            let chance = draw.field + "Chance"

            if draw.store == .flat, base.text["Class"]?.hasPrefix("Weapon") == true,
                    draw.field == "offensivePhysical" {
                return  // a weapon's own damage is written, not rolled
            }
            if draw.store == .slowFlat, isOffhand { return }
            if draw.store == .slowFlat, base.has(minimum), !base.has(draw.field + "DurationMin") { return }

            guard everySource.contains(where: { $0.table.has(minimum) || $0.table.has(maximum) }) else { return }

            drawEarlySkill()
            var total = 0.0
            var spread = 0.0
            var drew = false

            for (index, source) in everySource.enumerated() {
                let table = source.table
                guard table.has(minimum) || table.has(maximum) else { continue }

                // An off-hand takes nothing from its affixes here.
                if draw.store == .flat, index > 0, isOffhand { continue }

                let low = ItemRoll.jitterChar(table.value(minimum), source.jitter, &random)
                let width = ItemRoll.jitterChar(
                    max(0, table.value(maximum) - table.value(minimum)),
                    source.jitter,
                    &random
                )
                // A line that carries a chance is a proc of its own, not part of the total. Records
                // declare the field whether or not they use it, so the value is what decides.
                if hasAffix, table.value(chance) > 0 { continue }

                drew = true
                total += low
                spread += width
            }

            guard drew else { return }

            if draw.store == .retaliationFlat {
                result[minimum] = total.rounded(.towardZero)
                result[maximum] = (total + spread).rounded(.towardZero)
                return
            }
            let scaled = ItemRoll.applyScale(total, scale)
            result[minimum] = scaled.rounded(.towardZero)
            result[maximum] = (scaled + spread).rounded(.towardZero)
        }

        /// A line drawn once, whose duration and chance are read rather than rolled.
        private mutating func rollWithComponents(_ draw: ItemRoll.Draw) {
            let minimum = draw.field + "Min"
            guard everySource.contains(where: { $0.table.has(minimum) }) else { return }

            drawEarlySkill()
            var total = 0.0
            for source in everySource where source.table.has(minimum) {
                total += ItemRoll.jitterChar(source.table.value(minimum), source.jitter, &random)
            }

            result[minimum] = draw.store == .retaliationReflex ? total : ItemRoll.roundAway(total)
            let components = draw.store == .retaliationDuration ? [ "DurationMin", "Chance" ] : [ "Chance" ]
            for component in components { echo(draw.field + component) }
        }

        private mutating func rollSlow(_ draw: ItemRoll.Draw) {
            let minimum = draw.field + "Min"
            guard everySource.contains(where: { $0.table.has(minimum) }) else { return }

            drawEarlySkill()
            var total = 0.0
            for source in everySource where source.table.has(minimum) {
                total += ItemRoll.jitterChar(source.table.value(minimum), source.jitter, &random)
            }

            result[minimum] = draw.scales ? ItemRoll.applyScale(total, scale) : ItemRoll.roundAway(total)
            for component in [ "DurationMin", "Chance" ] { echo(draw.field + component) }
        }

        private mutating func rollReduction(_ draw: ItemRoll.Draw) {
            let minimum = draw.field + "Min"
            guard everySource.contains(where: { $0.table.has(minimum) }) else { return }

            drawEarlySkill()
            var total = 0.0
            for source in everySource where source.table.has(minimum) {
                total += ItemRoll.jitterChar(source.table.value(minimum), source.jitter, &random)
            }

            result[minimum] = total
            echo(draw.field + "DurationMin")
        }

        private mutating func rollLeech(_ draw: ItemRoll.Draw) {
            let minimum = draw.field + "Min"
            guard everySource.contains(where: { $0.table.has(minimum) }) else { return }

            drawEarlySkill()
            var total = 0.0
            for source in everySource where source.table.has(minimum) {
                total += ItemRoll.jitterChar(source.table.value(minimum), source.jitter, &random)
            }
            result[minimum] = total
        }

        /// A conversion is only valid with a type to convert from, and rolls on a float factor.
        private mutating func rollConversion(_ draw: ItemRoll.Draw) {
            let suffixIndex = draw.field.hasSuffix("2") ? "2" : ""
            var total = 0.0
            var found = false

            for source in everySource {
                let amount = source.table.value(draw.field)
                guard
                    let incoming = source.table.text["conversionInType" + suffixIndex],
                    !incoming.isEmpty,
                    amount != 0
                else { continue }

                drawEarlySkill()
                found = true
                total += ItemRoll.jitterConversion(amount, source.jitter, &random)
            }

            if found { result[draw.field] = total }
        }

        /// The plain stores: one value per source, summed.
        private mutating func rollScalar(_ draw: ItemRoll.Draw) {
            let field = draw.field
            guard everySource.contains(where: { $0.table.has(field) }) else { return }

            if draw.store != .char { drawEarlySkill() }
            if draw.store == .damage, handledDuration.contains(field) { return }

            if draw.store == .damage, field.hasPrefix("offensiveSlow"), field.hasSuffix("Modifier"),
                    !field.hasSuffix("DurationModifier") {
                let duration = String(field.dropLast("Modifier".count)) + "DurationModifier"
                if everySource.contains(where: { $0.table.has(duration) }) {
                    rollDurationPair(field: field, duration: duration, scales: draw.scales)
                    return
                }
            }

            var rolled = [Double]()
            if draw.store == .skill {
                // An affix's skill reduction is drawn early and stored there and then; the sum below
                // would write a zero over it.
                guard let drawn = rollSkill(field: field) else { return }

                rolled = drawn
            } else if draw.store == .damage || draw.store == .defence
                    || draw.store == .retaliationModifier {
                // These draw the item's own record before its affixes.
                rolled = [ ItemRoll.jitterChar(base.value(field), baseJitter, &random) ]
                rolled += affixes.map { ItemRoll.jitterChar($0.table.value(field), $0.jitter, &random) }
            } else {
                rolled = affixes.map { ItemRoll.jitterChar($0.table.value(field), $0.jitter, &random) }
                rolled.append(jitterChar(base.value(field), baseJitter, &random))
            }

            if ItemRoll.chanceSplitFields.contains(field), hasAffix {
                let chance = field + "Chance"
                let ordered = orderedSources(for: draw.store)
                var total = 0.0
                var any = false
                for (source, value) in zip(ordered, rolled) {
                    guard source.table.has(field) else { continue }

                    // A chance-bearing source is a proc line of its own.
                    if source.table.value(chance) > 0 { continue }

                    any = true
                    total += value
                }
                if any { result[field] = draw.scales ? ItemRoll.applyScale(total, scale) : total }
                return
            }

            let total = rolled.reduce(0, +)
            result[field] = draw.scales ? ItemRoll.applyScale(total, scale) : total
        }

        /// A slow's magnitude and its duration draw together, one source at a time.
        private mutating func rollDurationPair(field: String, duration: String, scales: Bool) {
            var value = 0.0
            var length = 0.0
            for source in everySource {
                value += ItemRoll.jitterChar(source.table.value(field), source.jitter, &random)
                length += ItemRoll.jitterChar(source.table.value(duration), source.jitter, &random)
            }

            result[field] = scales ? ItemRoll.applyScale(value, scale) : value
            result[duration] = ItemRoll.applyScale(length, scale)
            handledDuration.insert(duration)
        }

        /// The values this field draws, or nothing when the early path has already stored the total.
        private mutating func rollSkill(field: String) -> [Double]? {
            if ItemRoll.earlySkillFields.contains(field), prefixHasSkill || suffixHasSkill {
                let fromModifier = modifier.map { ItemRoll.jitterSkill($0.value(field), modifierJitter, &random) } ?? 0
                let fromBase = ItemRoll.jitterSkill(base.value(field), baseJitter, &random)
                result[field] = (earlySkill[field] ?? 0) + fromModifier + fromBase
                return nil
            }

            var rolled = affixes.map { ItemRoll.jitterSkill($0.table.value(field), $0.jitter, &random) }
            rolled.append(jitterSkill(base.value(field), baseJitter, &random))
            return rolled
        }

        /// The sources in the order this store draws them, so a rolled value can be traced back.
        private func orderedSources(for store: ItemRoll.Store) -> [(table: Table, jitter: Double)] {
            switch store {
                case .damage, .defence, .retaliationModifier: [ (base, baseJitter) ] + affixes
                default: affixes + [ (base, baseJitter) ]
            }
        }

        /// A skill reduction an affix carries is drawn before the store that first needs the stream.
        private mutating func drawEarlySkill() {
            guard !earlySkillDone else { return }

            earlySkillDone = true
            for (table, jitter) in [ (prefix, prefixJitter), (suffix, suffixJitter) ] {
                guard let table else { continue }

                for field in ItemRoll.skillFields where ItemRoll.earlySkillFields.contains(field) {
                    guard table.has(field) else { continue }

                    earlySkill[field, default: 0] += ItemRoll.jitterSkill(table.value(field), jitter, &random)
                }
            }
        }

        /// A value the game reads rather than rolls is taken from the first source that carries it.
        private mutating func echo(_ field: String) {
            guard result[field] == nil else { return }

            for source in everySource where source.table.has(field) {
                result[field] = source.table.value(field)
                return
            }
        }

        private mutating func echoFixedFields() {
            for source in everySource {
                for field in source.table.values.keys where result[field] == nil {
                    guard
                        ItemRoll.isFixed(field),
                        ItemRoll.statPrefixes.contains(where: { field.hasPrefix($0) })
                    else { continue }

                    echo(field)
                }
            }
        }
    }
}
