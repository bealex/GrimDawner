// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

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
struct StatRow: View {
    let title: String
    let value: String
    var valueColor: Color = .primary
    var icon: String?
    /// The band the value may roll in, for the stats an item rolls from its seed.
    var range: String?
    /// False where an enclosing row already answers for the search, so a match is ringed once.
    var highlights = true

    @Environment(\.quickSearch)
    private var search

    private var emphasis: QuickSearch.Emphasis {
        highlights ? search.emphasis(matching: title) : .neutral
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
            Text(title)
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

/// A horizontal meter, used for resistances and mastery progress.
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
