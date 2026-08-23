// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import SwiftUI

/// Shared look for the character sheet: the parchment-and-iron palette the game uses, adapted to both
/// light and dark appearances.
enum Theme {
    static let cardCornerRadius: CGFloat = 10

    static var accent: Color { Color(red: 0.85, green: 0.68, blue: 0.33) }

    static var panel: Color { Color(nsColor: .controlBackgroundColor) }

    static var subtleBorder: Color { Color.primary.opacity(0.12) }

    /// What a quick-search hit is ringed in.
    static var match: Color { Color(red: 1, green: 0.62, blue: 0.2) }

    /// Positive numbers read as gains, negatives as losses, on a character sheet.
    static func valueColor(_ value: Double) -> Color {
        if value > 0 { return Color.green.opacity(0.9) }
        if value < 0 { return Color.red.opacity(0.9) }
        return .secondary
    }
}

/// A titled card, the unit every panel on the sheet is built from.
struct SectionCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder
    var content: Content

    @Environment(\.quickSearch)
    private var search

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                    .quickSearchText(search.matches(title) ? .match : .neutral)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .accessibilityElement(children: .combine)

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: .rect(cornerRadius: Theme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }
}

/// A label-and-value row, the standard way a single statistic is shown.
extension Theme {
    /// How a damage conversion reads: "Chaos ➠ Aether".
    static let convertsTo = "\u{27A0}"

    /// What stands above a cap, which counts for nothing until the cap itself is raised: "↑7%".
    static func overCap(_ value: Double) -> String {
        "\u{2191}\(Int(value.rounded()))%"
    }

    /// What one line's figures read as: a damage range where the record writes a pair, the flat and
    /// percentage variants joined where it writes both, and a lone figure otherwise.
    static func figures(_ parts: [(definition: StatDefinition, value: Double)]) -> String {
        if let low = parts.first(where: { $0.definition.key.hasSuffix("Min") }),
                let high = parts.first(where: { $0.definition.key.hasSuffix("Max") }),
                high.value > low.value {
            let rest = parts.filter { $0.definition.key != low.definition.key }
                .filter { $0.definition.key != high.definition.key }
                .map { $0.definition.unit.format($0.value) }
            let range =
                "\(low.definition.unit.format(low.value))"
                + "–\(high.definition.unit.format(high.value, signed: false))"
            return ([ range ] + rest).joined(separator: " & ")
        }

        return
            parts
            .filter { !$0.definition.key.hasSuffix("Max") || $0.value != 0 }
            .map { $0.definition.unit.format($0.value) }
            .joined(separator: " & ")
    }

    /// One word of a line's title, coloured for the damage type it names.
    struct Accent: Equatable {
        let word: String
        let color: Color
    }

    /// Which damage family a stat key names, and the words a title says it with. Longest token first,
    /// so `Lightning` never reads as `Light`.
    private static let damageTokens: [(token: String, words: [String], tint: Color)] = [
        ("Physical", [ "Physical" ], DamageType.physical.color),
        ("Pierce", [ "Pierce" ], DamageType.pierce.color),
        ("Bleeding", [ "Bleeding" ], ResistanceKind.bleeding.color),
        ("Fire", [ "Fire", "Burn" ], DamageType.fire.color),
        ("Cold", [ "Cold", "Frostburn" ], DamageType.cold.color),
        ("Lightning", [ "Lightning", "Electrocute" ], DamageType.lightning.color),
        ("Poison", [ "Poison", "Acid" ], DamageType.acid.color),
        ("Life", [ "Vitality", "Life" ], DamageType.vitality.color),
        ("Aether", [ "Aether" ], DamageType.aether.color),
        ("Chaos", [ "Chaos" ], DamageType.chaos.color),
        ("Elemental", [ "Elemental" ], DamageType.elemental.color),
    ]

    /// The families whose keys name a damage type; `characterLife` is a health pool, not vitality.
    private static let damageFamilies = [ "offensive", "defensive", "retaliation" ]

    /// The word of a stat's title that names its damage type, coloured — "Fire" of "Fire Resistance",
    /// leaving the rest of the line alone. Nothing for a stat that names no type.
    static func damageAccent(forStatKey key: String, in title: String) -> Accent? {
        guard
            damageFamilies.contains(where: { key.hasPrefix($0) }),
            let match = damageTokens.first(where: { key.contains($0.token) }),
            let word = match.words.first(where: { title.localizedCaseInsensitiveContains($0) })
        else { return nil }

        return Accent(word: word, color: match.tint)
    }

    /// The damage type a stat key names, as the token the icons are kept under.
    static func damageToken(forStatKey key: String) -> String? {
        guard damageFamilies.contains(where: { key.hasPrefix($0) }) else { return nil }

        return damageTokens.first { key.contains($0.token) }?.token
    }

    /// The colour a damage type reads in, for a line that is nothing but the type's name.
    static func damageTint(forStatKey key: String) -> Color? {
        guard damageFamilies.contains(where: { key.hasPrefix($0) }) else { return nil }

        return damageTokens.first { key.contains($0.token) }?.tint
    }
}

struct StatRow: View {
    let title: String
    let value: String
    var valueColor: Color = .primary
    /// The words of the title that name a damage type, each in that type's colour.
    var accents: [Theme.Accent] = []
    var icon: String?
    /// The game's own mark for the damage type this line names, drawn beside the figure rather than
    /// beside the name: the mark is about the number.
    var iconPath: String?
    /// The band the value may roll in, for the stats an item rolls from its seed.
    var range: String?
    /// False where an enclosing row already answers for the search, so a match is ringed once.
    var highlights = true

    @Environment(\.quickSearch)
    private var search

    private var emphasis: QuickSearch.Emphasis {
        highlights ? search.emphasis(matching: title) : .neutral
    }

    /// The title with each accented word in its damage type's colour, and the rest left alone.
    private var titleText: Text {
        guard emphasis != .match, !accents.isEmpty else { return Text(title) }

        var text = Text("")
        var rest = Substring(title)
        for accent in accents {
            guard let range = rest.range(of: accent.word, options: .caseInsensitive) else { continue }

            text = text + Text(rest[..<range.lowerBound]) + Text(rest[range]).foregroundStyle(accent.color)
            rest = rest[range.upperBound...]
        }
        return text + Text(rest)
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                    .accessibilityHidden(true)
            }
            // The name takes the slack and the number keeps its own width, so a long name truncates
            // only when it has run out of room rather than whenever the number is short.
            titleText
                .foregroundStyle(emphasis == .match ? Theme.match : Color.secondary)
                .fontWeight(emphasis == .match ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let range {
                Text(range)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
            if let iconPath, !iconPath.isEmpty {
                GameIcon(path: iconPath, size: 13, fallbackSymbol: "circle.fill")
                    .accessibilityHidden(true)
            }
            Text(value)
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .fixedSize()
        }
        .font(.callout)
        .opacity(emphasis == .faded ? 0.25 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

/// A horizontal meter, for how far a standing has come through its tier.
struct MeterBar: View {
    let value: Double
    let maximum: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let fraction = maximum > 0 ? min(max(value / maximum, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
