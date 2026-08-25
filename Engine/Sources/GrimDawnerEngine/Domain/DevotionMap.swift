// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import CoreGraphics
import Foundation
import SwiftUI

/// A colour the devotion window paints something in, with the strength it paints at.
public struct DevotionTint: Sendable {
    public let color: Color
    public let opacity: Double

    public static let clear = DevotionTint(color: .clear, opacity: 0)
}

/// One star of a constellation: a devotion point, taken or not.
public struct DevotionStar: Identifiable, Sendable {
    public let id = UUID()
    /// Top-left of the star sprite, in the map's own coordinates.
    public let position: CGPoint
    public let skill: ResolvedSkill
    public let isTaken: Bool
    /// True for a star granting a celestial power rather than a passive bonus.
    public let isPower: Bool
    public let sprite: String
    /// The star this one is drawn connected to, as an index into its constellation's stars.
    public let linkedTo: Int?
}

/// A devotion constellation: its stars, its place in the sky, and what completing it grants.
public struct ResolvedConstellation: Identifiable, Sendable {
    public struct Affinity: Sendable, Hashable {
        public let name: String
        public let amount: Int
    }

    public let id = UUID()
    public let name: String
    public let description: String
    public let iconPath: String
    /// Top-left of the constellation's artwork, in the map's own coordinates.
    public let position: CGPoint
    public let stars: [DevotionStar]
    public let affinityGiven: [Affinity]
    public let affinityRequired: [Affinity]
    /// Stats from the stars actually taken.
    public let bonuses: StatBlock
    /// Whether the character's affinity meets what this constellation asks for.
    public let isAvailable: Bool

    /// The three tints the game paints a constellation in, by whether it is taken, open, or out of reach.
    public let takenTint: DevotionTint
    public let availableTint: DevotionTint
    public let lockedTint: DevotionTint

    /// The patch of sky it covers: every star of it, with room for the sprite each is drawn as. A star's
    /// position is the top-left of that sprite, so the box has to grow past the last of them.
    public var bounds: CGRect {
        let points = stars.map(\.position)
        guard let first = points.first else { return CGRect(origin: position, size: .zero) }

        var box = points.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
            $0.union(CGRect(origin: $1, size: .zero))
        }
        box = box.insetBy(dx: -Self.starRoom, dy: -Self.starRoom)
        return box
    }

    /// How much room to leave around the outermost stars, which is a star sprite's own size over.
    private static let starRoom: CGFloat = 96

    public var takenStars: Int { stars.count { $0.isTaken } }
    public var totalStars: Int { stars.count }
    public var isComplete: Bool { takenStars == totalStars }
    public var isStarted: Bool { takenStars > 0 }

    public var tint: DevotionTint {
        if isStarted { return takenTint }

        return isAvailable ? availableTint : lockedTint
    }
}

/// The devotion window: every constellation, the sky behind them, and the affinity earned so far.
public struct DevotionMap: Sendable {
    /// One of the coloured clouds the map paints behind the constellations.
    public struct Nebula: Identifiable, Sendable {
        public let id = UUID()
        public let bitmap: String
        public let position: CGPoint
    }

    /// One of the five affinities, with how much of it completed constellations have granted.
    public struct Affinity: Identifiable, Sendable {
        public let name: String
        public let icon: String
        public let color: Color
        public let earned: Int

        public var id: String { name }
    }

    /// The art the window draws a link between two stars with, by whether that link is taken.
    public struct Links: Sendable {
        public let active: String
        public let inactive: String
        public let locked: String
        public let width: CGFloat

        public static let none = Links(active: "", inactive: "", locked: "", width: 1)
    }

    public let constellations: [ResolvedConstellation]
    public let nebulas: [Nebula]
    /// The star-field tile repeated behind everything.
    public let tile: String
    public let links: Links
    public let affinities: [Affinity]
    /// The extent of the sky, as the devotion window sizes it.
    public let bounds: CGRect

    /// Roughly where the constellations sit, so the map can open on the part of the sky that holds them.
    public var starBounds: CGRect {
        let positions = constellations.flatMap { $0.stars.map(\.position) }
        guard let first = positions.first else { return bounds }

        var rect = CGRect(origin: first, size: .zero)
        for position in positions.dropFirst() { rect = rect.union(CGRect(origin: position, size: .zero)) }
        return rect.insetBy(dx: -Self.starMargin, dy: -Self.starMargin)
    }

    /// How far a constellation's artwork reaches past its outermost star.
    private static let starMargin: CGFloat = 300

    public var takenStars: Int { constellations.reduce(0) { $0 + $1.takenStars } }
    public var startedConstellations: [ResolvedConstellation] { constellations.filter(\.isStarted) }

    public static let empty = DevotionMap(
        constellations: [],
        nebulas: [],
        tile: "",
        links: .none,
        affinities: [],
        bounds: .zero
    )
}
