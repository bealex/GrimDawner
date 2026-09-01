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

/// A challenge area — the "Dangerous Domain" banner over a gdx3 endgame zone. The game lays the
/// area's stated adjustment over every monster inside, one column per difficulty like its own, and
/// rolls the area's mutators besides; the mutators are that run's alone and beyond a save's reach.
public struct ChallengeArea: Sendable, Identifiable, Hashable {
    /// The adjustment pak the resolver folds in.
    public let adjustment: String
    /// The banner's word for it: Dangerous, Treacherous or Forbidden Domain.
    public let name: String

    public var id: String { adjustment }

    /// The named areas the game defines, mildest first. Several records share one banner and one
    /// adjustment, differing only in mutator count, so each adjustment appears once.
    public static func all(in database: GameDatabase) -> [ChallengeArea] {
        var named = [String: ChallengeArea]()
        var severity = [String: Double]()
        database.sweep(prefix: "records/game/challengeareas/") { _, record in
            guard record.text("Class") == "ChallengeArea" else { return }

            let adjustment = record.text("difficultyAdjustment").lowercased()
            guard
                !adjustment.isEmpty,
                let name = database.localised(record.text("nameTag")),
                let scaling = database.record(adjustment)
            else { return }

            named[adjustment] = ChallengeArea(adjustment: adjustment, name: name)
            severity[adjustment] = scaling["characterLifeModifier"]?.numbers.max() ?? 0
        }
        return named.values.sorted { (severity[$0.adjustment] ?? 0) < (severity[$1.adjustment] ?? 0) }
    }
}
