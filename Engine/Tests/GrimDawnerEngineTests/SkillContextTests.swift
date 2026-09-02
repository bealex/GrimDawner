// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation
import Testing

@testable import GrimDawnerEngine

/// Whether a `+N` line gives the wearer anything, by what the line reaches.
///
/// A mastery bonus carries the mastery's record path, which no set of learned skills contains — read
/// against `learned` it grayed out "+1 to all skills in Arcanist" on an Arcanist.
struct SkillContextTests {
    private let arcanist = "records/skills/playerclass02/class02_mastery.dbr"
    private let learnedSkill = "records/skills/playerclass02/skill_01.dbr"

    private var context: SkillContext {
        SkillContext(
            own: [ learnedSkill, "records/skills/playerclass02/skill_02.dbr" ],
            learned: [ learnedSkill ],
            masteries: [ arcanist ]
        )
    }

    @Test
    func skillRankLandsOnlyWithAPointInTheSkill() {
        #expect(context.benefits(fromRankAt: learnedSkill, reach: .skill))
        #expect(!context.benefits(fromRankAt: "records/skills/playerclass02/skill_02.dbr", reach: .skill))
        #expect(!context.benefits(fromRankAt: "records/skills/playerclass05/skill_09.dbr", reach: .skill))
    }

    @Test
    func masteryRankLandsOnTheCharactersOwnMastery() {
        #expect(context.benefits(fromRankAt: arcanist, reach: .mastery))
        #expect(context.benefits(fromRankAt: arcanist.uppercased(), reach: .mastery))
        #expect(!context.benefits(fromRankAt: "records/skills/playerclass05/class05_mastery.dbr", reach: .mastery))
    }

    @Test
    func rankToEverySkillAlwaysLands() {
        #expect(context.benefits(fromRankAt: "", reach: .everySkill))
    }
}
