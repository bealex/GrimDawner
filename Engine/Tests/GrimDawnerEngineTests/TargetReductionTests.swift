// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation
import Testing

@testable import GrimDawnerEngine

/// The order the game applies resistance reduction in, checked against the worked example the Dawn
/// Index publishes: <https://grimdawn.info/mechanics/resistance-reduction>.
///
/// Nothing in the database states the order, and it matters: the same three reductions in the wrong
/// order come to half as much.
struct TargetReductionTests {
    @Test
    func appliesTheDebuffsThenTheShareThenTheFlatSubtraction() {
        var reduction = TargetReduction()
        // Two stacking debuffs, and the largest of two sources of each of the other kinds.
        reduction.debuff[.aether] = 45
        reduction.percent[.aether] = 20
        reduction.flat[.aether] = 10

        // 80 − 45 = 35, then 35 × 0.8 = 28, then 28 − 10 = 18.
        #expect(reduction.applied(to: 80, of: .aether).rounded() == 18)
    }

    @Test
    func deepensAHoleRatherThanFillingItIn() {
        var reduction = TargetReduction()
        reduction.debuff[.fire] = 60
        reduction.percent[.fire] = 50

        // The debuffs leave −10, and a share of a hole makes it deeper: −10 × 1.5.
        #expect(reduction.applied(to: 50, of: .fire).rounded() == -15)
    }

    @Test
    func takesNothingWhereTheBuildCarriesNone() {
        #expect(TargetReduction().applied(to: 81, of: .aether) == 81)
    }

    /// Reduction is taken off the whole figure, overcap and all, and only then is the cap laid over the
    /// result. It is what makes an overcap worth carrying: a hundred and ten against a thirty leaves the
    /// cap untouched, where capping first would have cost the lot.
    ///
    /// <https://forums.crateentertainment.com/t/how-much-value-is-there-now-in-resist-overcap/132369>
    @Test
    func spendsTheOvercapBeforeTheCapGives() {
        var reduction = TargetReduction()
        reduction.debuff[.lightning] = 30

        let cap = 80.0
        #expect(min(reduction.applied(to: 110, of: .lightning), cap) == 80)
        // The same debuff against no overcap at all costs every point of it.
        #expect(min(reduction.applied(to: 80, of: .lightning), cap) == 50)
    }
}
