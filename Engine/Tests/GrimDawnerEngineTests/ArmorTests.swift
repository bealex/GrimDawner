// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation
import Testing

@testable import GrimDawnerEngine

/// The armour equations, checked against the three worked examples Crate publishes.
///
/// <https://www.grimdawn.com/guide/gameplay/combat/> states them outright, which makes them the one
/// reference for a formula the game itself never shows a number for. It needs the installed game, whose
/// folder is machine-specific: set `GRIM_DAWN_FOLDER` to run it, and it skips when that is absent.
struct ArmorTests {
    private static var engine: EncounterEngine? {
        guard let folder = ProcessInfo.processInfo.environment["GRIM_DAWN_FOLDER"] else { return nil }
        guard let database = try? GameDatabase(gameFolder: URL(fileURLWithPath: folder)) else { return nil }

        return EncounterEngine(database: database)
    }

    @Test
    func takesTheWholeHitPastTheArmourAndAbsorbsWhatIsUnderIt() throws {
        guard let engine = Self.engine else { return }

        // "100 damage to the torso with 50 armor" — 50 goes straight through, and 30% of the rest.
        #expect(engine.throughArmor(100, armor: 50, absorption: 70).rounded() == 65)
    }

    @Test
    func absorbsSeventyOfAHitTheArmourCovers() throws {
        guard let engine = Self.engine else { return }

        // "100 damage to the head with 124 armor" — armour over the hit still lets 30% through.
        #expect(engine.throughArmor(100, armor: 124, absorption: 70).rounded() == 30)
    }

    @Test
    func scalesAbsorptionByWhatTheGearAdds() throws {
        guard let engine = Self.engine else { return }

        // The same blow with "+20% armor absorption": the guide reads that as 70% × 1.2, not 90%.
        #expect(engine.throughArmor(100, armor: 124, absorption: 70 * 1.2).rounded() == 16)
    }
}
