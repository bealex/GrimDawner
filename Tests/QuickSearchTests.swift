// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Testing

@testable import GrimDawner

/// The quick-search field's matching rules, which every tab highlights by.
struct QuickSearchTests {
    @Test
    func matchesIgnoringCaseSpacingAndPunctuation() {
        let search = QuickSearch("emberfang")

        #expect(search.matches("Ember Fang"))
        #expect(search.matches("EMBER-FANG"))
        #expect(search.matches("the ember, fang of dust"))
        #expect(!search.matches("Fang Ember"))
    }

    @Test
    func matchesAnyCandidate() {
        let search = QuickSearch("frost")

        #expect(search.matches([ "Warding Sigil", "Frostbite Resistance" ]))
        #expect(!search.matches([ "Warding Sigil", "Ember Resistance" ]))
    }

    @Test
    func anEmptyQueryMatchesNothingAndEmphasisesNothing() {
        let search = QuickSearch("   ")

        #expect(!search.isActive)
        #expect(!search.matches("Ember Fang"))
        #expect(search.emphasis(matching: "Ember Fang") == .neutral)
    }

    @Test
    func anActiveQueryLiftsMatchesAndFadesTheRest() {
        let search = QuickSearch("ember")

        #expect(search.emphasis(matching: "Ember Fang") == .match)
        #expect(search.emphasis(matching: "Warding Sigil") == .faded)
    }
}
