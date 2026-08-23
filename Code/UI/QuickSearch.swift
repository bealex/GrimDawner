// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import SwiftUI

private struct QuickSearchKey: EnvironmentKey {
    static let defaultValue = QuickSearch()
}

extension EnvironmentValues {
    /// The current query, so every row and card can answer for itself.
    var quickSearch: QuickSearch {
        get { self[QuickSearchKey.self] }
        set { self[QuickSearchKey.self] = newValue }
    }
}

extension View {
    /// Colours a matching line and lets the rest recede. Text reads better coloured than boxed.
    @ViewBuilder
    func quickSearchText(_ emphasis: QuickSearch.Emphasis) -> some View {
        switch emphasis {
            case .neutral: self
            case .match: foregroundStyle(Theme.match).fontWeight(.semibold)
            case .faded: opacity(0.25)
        }
    }

    /// Rings a match, for the tiles of artwork a colour change would not show on.
    ///
    /// A tile that recedes is darkened rather than faded: artwork turned transparent shows whatever the
    /// panel draws behind it, which on a skill tree is the connectors between the skills.
    func quickSearch(_ emphasis: QuickSearch.Emphasis, cornerRadius: CGFloat = 6) -> some View {
        colorMultiply(emphasis == .faded ? Color(white: 0.35) : .white)
            .background {
                if emphasis == .match {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Theme.match.opacity(0.22))
                        .stroke(Theme.match, lineWidth: 1)
                        .padding(-3)
                }
            }
            .animation(.easeOut(duration: 0.12), value: emphasis)
    }
}

extension StatBlock {
    /// The stat names a search matches against.
    var titles: [String] {
        catalogued().flatMap { group in group.lines.map(\.definition.title) }
    }
}
