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
    /// The artwork of the thing the card is named after, drawn before its name. A card titled with an
    /// item wears that item's own icon there rather than repeating the picture inside itself.
    var iconPath: String?
    @ViewBuilder
    var content: Content

    @Environment(\.quickSearch)
    private var search

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if let iconPath, !iconPath.isEmpty {
                    GameIcon(path: iconPath, size: 20, fallbackSymbol: "shippingbox")
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                }
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
        // A type's over-time name is the same type: Internal Trauma is physical, Burn is fire.
        ("Physical", [ "Physical", "Internal Trauma" ], DamageType.physical.color),
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

    /// The damage type a line's own name says, as the token the icons are kept under.
    ///
    /// Read off the name rather than the stat key so that every line about a type wears that type's
    /// mark, whoever built the line and whether or not it knew its own key. The words are the game's
    /// own: *Burn* is fire, *Frostburn* cold, *Electrocute* lightning.
    static func damageToken(inTitle title: String) -> String? {
        // A conversion names two types and is about neither until it lands, so it wears the mark of what
        // it turns into: everything to the left of the arrow is what is being spent.
        let named = title.range(of: convertsTo).map { String(title[$0.upperBound...]) } ?? title
        return typesNamed(in: named).first?.token
    }

    /// Every damage type a line's own name says, in the order it says them.
    static func damageAccents(inTitle title: String) -> [Accent] {
        typesNamed(in: title).map { Accent(word: $0.word, color: $0.tint) }
    }

    /// A damage type a piece of text names, and the word it names it with.
    private struct NamedType {
        let place: String.Index
        let token: String
        let word: String
        let tint: Color
    }

    /// The types a piece of text names, earliest first. Ordering by where each word falls keeps a line
    /// naming two of them out of the hands of whatever order this table happens to be written in.
    private static func typesNamed(in text: String) -> [NamedType] {
        damageTokens
            .compactMap { token -> NamedType? in
                let found = token.words
                    .compactMap { word in
                        text.range(of: word, options: .caseInsensitive).map { (place: $0.lowerBound, word: word) }
                    }
                    .min { $0.place < $1.place }
                guard let found else { return nil }

                return NamedType(place: found.place, token: token.token, word: found.word, tint: token.tint)
            }
            .sorted { $0.place < $1.place }
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
    /// The words of the title that name a damage type, each in that type's colour. Left empty, the line
    /// finds them in its own name, so the same stat reads the same colour wherever it is shown.
    var accents: [Theme.Accent] = []
    /// A symbol standing for what the line is about, drawn at the end of it with the type's own mark.
    var icon: String?
    /// The game's own mark for the damage type this line names, drawn at the end of the line. Left
    /// unset, the line finds its own from the type its name says, so the same stat wears the same mark
    /// wherever it is shown.
    var iconPath: String?
    /// The artwork of the thing the line is named after, drawn before its name — an item's own icon.
    var titleIconPath: String?
    /// The band the value may roll in, for the stats an item rolls from its seed.
    var range: String?
    /// False where an enclosing row already answers for the search, so a match is ringed once.
    var highlights = true
    /// True where the line is named after a thing rather than after a statistic. A name is its own: an
    /// item called *Screams of the Aether* is not a line about aether, so a named line takes neither the
    /// damage colour nor the mark that a stat's name earns.
    var isNamed = false

    @Environment(\.quickSearch)
    private var search
    @Environment(\.damageIcons)
    private var damageIcons

    private var emphasis: QuickSearch.Emphasis {
        highlights ? search.emphasis(matching: title) : .neutral
    }

    /// The mark this line wears: the one it was given, or the one its own name asks for.
    private var mark: String? {
        if let iconPath, !iconPath.isEmpty { return iconPath }
        guard !isNamed else { return nil }

        return Theme.damageToken(inTitle: title).flatMap { damageIcons[$0] }
    }

    /// The colours this line reads in: the ones it was given, or the ones its own name asks for.
    private var tints: [Theme.Accent] {
        guard accents.isEmpty else { return accents }

        return isNamed ? [] : Theme.damageAccents(inTitle: title)
    }

    /// The title with each accented word in its damage type's colour, and the rest left alone.
    private var titleText: Text {
        let tints = tints
        guard emphasis != .match, !tints.isEmpty else { return Text(title) }

        var text = Text("")
        var rest = Substring(title)
        for accent in tints {
            guard let range = rest.range(of: accent.word, options: .caseInsensitive) else { continue }

            text = text + Text(rest[..<range.lowerBound]) + Text(rest[range]).foregroundStyle(accent.color)
            rest = rest[range.upperBound...]
        }
        return text + Text(rest)
    }

    var body: some View {
        // The figure leads, the way the game's own tooltips word a bonus: "+86% Aether Damage". The
        // number keeps its own width and the name takes the slack, so a long name truncates only when
        // it has run out of room.
        HStack(spacing: 8) {
            Text(value)
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .fixedSize()
            if let titleIconPath, !titleIconPath.isEmpty {
                GameIcon(path: titleIconPath, size: 18, fallbackSymbol: "shippingbox")
            }
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
            if let icon {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                    .accessibilityHidden(true)
            }
            if let mark, !mark.isEmpty {
                GameIcon(path: mark, size: 13, fallbackSymbol: "circle.fill")
                    .accessibilityHidden(true)
            }
        }
        .font(.callout)
        .opacity(emphasis == .faded ? 0.25 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(title)")
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
