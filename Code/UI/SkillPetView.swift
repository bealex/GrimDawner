// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import SwiftUI

/// What a skill does for pets: what it adds to the ones already out, and what it puts on the field.
///
/// Both are as much a part of a skill as its own numbers — a summon that says nothing about what it
/// summons describes half of itself.
struct SkillPetView: View {
    let skill: ResolvedSkill

    var body: some View {
        if !skill.petBonus.hasNothingToShow {
            SectionCard(title: "Bonus to All Pets") {
                StatBlockView(block: skill.petBonus)
            }
        }

        if let summon = skill.summon {
            SectionCard(title: summon.name, subtitle: Self.subtitle(of: summon)) {
                VStack(alignment: .leading, spacing: 10) {
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
                                Text(ability.parameters.map { "\($0.name) \($0.value)" }.joined(separator: " · "))
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
        }
    }

    /// Reads as "6 at once · 24s", leaving out whichever the record does not limit.
    private static func subtitle(of summon: ResolvedSummon) -> String? {
        let parts = [
            summon.limit > 0 ? "\(summon.limit) at once" : nil,
            summon.timeToLive > 0 ? "\(Int(summon.timeToLive))s" : nil,
        ]
        .compactMap { $0 }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
