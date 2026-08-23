// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// What the search field is looking for.
///
/// Matching ignores case, spaces and punctuation, so `twinfangs` finds "Twin Fangs" and `firere` finds
/// "Fire Resistance". Nothing is hidden: a match is lifted and everything else recedes.
public struct QuickSearch: Equatable, Sendable {
    /// How prominent a view should be under the current query.
    public enum Emphasis {
        case neutral
        case match
        case faded
    }

    private let needle: String

    public init(_ text: String = "") {
        needle = Self.folded(text)
    }

    public var isActive: Bool { !needle.isEmpty }

    public func matches(_ candidates: String?...) -> Bool {
        matches(candidates.compactMap { $0 })
    }

    public func matches(_ candidates: [String]) -> Bool {
        guard isActive else { return false }

        return candidates.contains { Self.folded($0).contains(needle) }
    }

    public func emphasis(matching candidates: String?...) -> Emphasis {
        emphasis(isMatch: matches(candidates.compactMap { $0 }))
    }

    public func emphasis(matching candidates: [String]) -> Emphasis {
        emphasis(isMatch: matches(candidates))
    }

    public func emphasis(isMatch: Bool) -> Emphasis {
        guard isActive else { return .neutral }

        return isMatch ? .match : .faded
    }

    /// Colours a match and leaves everything else as it is, for lines that must stay readable whatever
    /// is being searched for.
    public func highlight(matching candidates: String?...) -> Emphasis {
        matches(candidates.compactMap { $0 }) ? .match : .neutral
    }

    /// Whole blocks recede when nothing inside them matches, but are never coloured as one.
    public func fade(unless isMatch: Bool) -> Emphasis {
        isActive && !isMatch ? .faded : .neutral
    }

    /// Matches text that is already folded, for lists long enough that folding each time would show.
    public func matchesFolded(_ text: String) -> Bool {
        isActive && text.contains(needle)
    }

    public static func folded(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
