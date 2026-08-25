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
            SectionCard(title: summon.name, subtitle: SummonView.subtitle(of: summon)) {
                SummonView(summon: summon)
            }
        }
    }
}
