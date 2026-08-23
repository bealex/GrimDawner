// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import CoreGraphics
import Foundation
import SwiftUI

/// A colour the devotion window paints something in, with the strength it paints at.
struct DevotionTint: Sendable {
    let color: Color
    let opacity: Double

    static let clear = DevotionTint(color: .clear, opacity: 0)
}

/// One star of a constellation: a devotion point, taken or not.
struct DevotionStar: Identifiable, Sendable {
    let id = UUID()
    /// Top-left of the star sprite, in the map's own coordinates.
    let position: CGPoint
    let skill: ResolvedSkill
    let isTaken: Bool
    /// True for a star granting a celestial power rather than a passive bonus.
    let isPower: Bool
    let sprite: String
    /// The star this one is drawn connected to, as an index into its constellation's stars.
    let linkedTo: Int?
}

/// A devotion constellation: its stars, its place in the sky, and what completing it grants.
struct ResolvedConstellation: Identifiable, Sendable {
    struct Affinity: Sendable, Hashable {
        let name: String
        let amount: Int
    }

    let id = UUID()
    let name: String
    let description: String
    let iconPath: String
    /// Top-left of the constellation's artwork, in the map's own coordinates.
    let position: CGPoint
    let stars: [DevotionStar]
    let affinityGiven: [Affinity]
    let affinityRequired: [Affinity]
    /// Stats from the stars actually taken.
    let bonuses: StatBlock
    /// Whether the character's affinity meets what this constellation asks for.
    let isAvailable: Bool

    /// The three tints the game paints a constellation in, by whether it is taken, open, or out of reach.
    let takenTint: DevotionTint
    let availableTint: DevotionTint
    let lockedTint: DevotionTint

    var takenStars: Int { stars.count { $0.isTaken } }
    var totalStars: Int { stars.count }
    var isComplete: Bool { takenStars == totalStars }
    var isStarted: Bool { takenStars > 0 }

    var tint: DevotionTint {
        if isStarted { return takenTint }

        return isAvailable ? availableTint : lockedTint
    }
}

/// The devotion window: every constellation, the sky behind them, and the affinity earned so far.
struct DevotionMap: Sendable {
    /// One of the coloured clouds the map paints behind the constellations.
    struct Nebula: Identifiable, Sendable {
        let id = UUID()
        let bitmap: String
        let position: CGPoint
    }

    /// One of the five affinities, with how much of it completed constellations have granted.
    struct Affinity: Identifiable, Sendable {
        let name: String
        let icon: String
        let color: Color
        let earned: Int

        var id: String { name }
    }

    /// The art the window draws a link between two stars with, by whether that link is taken.
    struct Links: Sendable {
        let active: String
        let inactive: String
        let locked: String
        let width: CGFloat

        static let none = Links(active: "", inactive: "", locked: "", width: 1)
    }

    let constellations: [ResolvedConstellation]
    let nebulas: [Nebula]
    /// The star-field tile repeated behind everything.
    let tile: String
    let links: Links
    let affinities: [Affinity]
    /// The extent of the sky, as the devotion window sizes it.
    let bounds: CGRect

    /// Roughly where the constellations sit, so the map can open on the part of the sky that holds them.
    var starBounds: CGRect {
        let positions = constellations.flatMap { $0.stars.map(\.position) }
        guard let first = positions.first else { return bounds }

        var rect = CGRect(origin: first, size: .zero)
        for position in positions.dropFirst() { rect = rect.union(CGRect(origin: position, size: .zero)) }
        return rect.insetBy(dx: -Self.starMargin, dy: -Self.starMargin)
    }

    /// How far a constellation's artwork reaches past its outermost star.
    private static let starMargin: CGFloat = 300

    var takenStars: Int { constellations.reduce(0) { $0 + $1.takenStars } }
    var startedConstellations: [ResolvedConstellation] { constellations.filter(\.isStarted) }

    static let empty = DevotionMap(
        constellations: [],
        nebulas: [],
        tile: "",
        links: .none,
        affinities: [],
        bounds: .zero
    )
}
