// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import SwiftUI

/// What the search field is looking for.
///
/// Matching ignores case, spaces and punctuation, so `twinfangs` finds "Twin Fangs" and `firere` finds
/// "Fire Resistance". Nothing is hidden: a match is lifted and everything else recedes.
struct QuickSearch: Equatable {
    /// How prominent a view should be under the current query.
    enum Emphasis {
        case neutral
        case match
        case faded
    }

    private let needle: String

    init(_ text: String = "") {
        needle = Self.folded(text)
    }

    var isActive: Bool { !needle.isEmpty }

    func matches(_ candidates: String?...) -> Bool {
        matches(candidates.compactMap { $0 })
    }

    func matches(_ candidates: [String]) -> Bool {
        guard isActive else { return false }

        return candidates.contains { Self.folded($0).contains(needle) }
    }

    func emphasis(matching candidates: String?...) -> Emphasis {
        emphasis(isMatch: matches(candidates.compactMap { $0 }))
    }

    func emphasis(matching candidates: [String]) -> Emphasis {
        emphasis(isMatch: matches(candidates))
    }

    func emphasis(isMatch: Bool) -> Emphasis {
        guard isActive else { return .neutral }

        return isMatch ? .match : .faded
    }

    /// Colours a match and leaves everything else as it is, for lines that must stay readable whatever
    /// is being searched for.
    func highlight(matching candidates: String?...) -> Emphasis {
        matches(candidates.compactMap { $0 }) ? .match : .neutral
    }

    /// Whole blocks recede when nothing inside them matches, but are never coloured as one.
    func fade(unless isMatch: Bool) -> Emphasis {
        isActive && !isMatch ? .faded : .neutral
    }

    /// Matches text that is already folded, for lists long enough that folding each time would show.
    func matchesFolded(_ text: String) -> Bool {
        isActive && text.contains(needle)
    }

    static func folded(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

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
