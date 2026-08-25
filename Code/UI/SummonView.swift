// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import SwiftUI

/// What a skill puts on the field: the pet's own sheet and every ability it fights with.
///
/// A summon that says only what it is called describes half of itself — what matters is what the thing
/// standing there can take and what it can do. The same block reads under a character's skill and under
/// a monster's, so both say the same amount about the same pet.
struct SummonView: View {
    let summon: ResolvedSummon
    /// Opens the summoned creature as a monster of its own, where there is somewhere to open it.
    var openMonster: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if summon.isMonster, let openMonster {
                Button("Open \(summon.name) as a monster") { openMonster(summon.recordPath) }
                    .buttonStyle(.link)
                    .font(.caption)
                    .pointerStyle(.link)
                    .help("Reads \(summon.name) at its own level, with its stats, its loot and its model")
            }
            if !summon.stats.hasNothingToShow {
                StatBlockView(block: summon.stats)
            }
            ForEach(summon.skills) { ability in
                VStack(alignment: .leading, spacing: 4) {
                    Text(ability.name)
                        .font(.caption.weight(.semibold))
                    if !ability.description.isEmpty {
                        Text(ability.description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !ability.parameters.isEmpty {
                        Text(ability.parameters.map { "\($0.value) \($0.name)" }.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !ability.stats.hasNothingToShow {
                        StatBlockView(block: ability.stats)
                    }
                }
            }
        }
    }

    /// Reads as "6 at once · 24s", leaving out whichever the record does not limit.
    static func subtitle(of summon: ResolvedSummon) -> String? {
        let parts = [
            summon.limit > 0 ? "\(summon.limit) at once" : nil,
            summon.timeToLive > 0 ? "\(Int(summon.timeToLive))s" : nil,
        ]
        .compactMap { $0 }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
