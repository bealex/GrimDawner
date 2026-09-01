// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// The four ways a monster is met: the game's three difficulties, and the ascendant mode laid over
/// Ultimate.
///
/// Ascendant is not a difficulty the save records — a character is on Ultimate either way — but a
/// second adjustment the game lays over every enemy in it, so it belongs beside the three rather than
/// inside them.
public enum MonsterMode: String, CaseIterable, Sendable, Identifiable {
    case normal
    case elite
    case ultimate
    case ascendant

    public var id: String { rawValue }

    public var difficulty: Difficulty {
        switch self {
            case .normal: .normal
            case .elite: .elite
            case .ultimate, .ascendant: .ultimate
        }
    }

    public var isAscendant: Bool { self == .ascendant }

    public var title: String {
        switch self {
            case .normal: "Normal"
            case .elite: "Elite"
            case .ultimate: "Ultimate"
            case .ascendant: "Ascendant"
        }
    }

    public init(difficulty: Difficulty, isAscendant: Bool = false) {
        switch (difficulty, isAscendant) {
            case (.normal, _): self = .normal
            case (.elite, _): self = .elite
            case (.ultimate, true): self = .ascendant
            case (.ultimate, false): self = .ultimate
        }
    }
}
