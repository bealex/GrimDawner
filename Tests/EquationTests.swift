// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Testing

@testable import GrimDawner

struct EquationTests {
    @Test
    func evaluatesArithmeticWithPrecedence() throws {
        #expect(try Equation("2 + 3 * 4").value([:]) == 14)
        #expect(try Equation("(2 + 3) * 4").value([:]) == 20)
        #expect(try Equation("10 / 4").value([:]) == 2.5)
        #expect(try Equation("-3 + 5").value([:]) == 2)
    }

    @Test
    func exponentIsRightAssociative() throws {
        #expect(try Equation("2 ^ 3 ^ 2").value([:]) == 512)
    }

    @Test
    func resolvesVariablesCaseInsensitively() throws {
        let equation = try Equation("itemLevel/4+1")
        #expect(try equation.value([ "itemlevel": 92 ]) == 24)
        #expect(try equation.value([ "ItemLevel": 92 ]) == 24)
    }

    @Test
    func treatsUnknownVariablesAsZero() throws {
        #expect(try Equation("missingValue + 7").value([:]) == 7)
    }

    @Test
    func evaluatesTheShippedAbilityFormula() throws {
        let source =
            "(offensiveAbilityDV + (characterLevelDV * 12) + ((dexterityDV + bonusDV) *0.5))"
            + " * (1 + (offensiveAbilityModifierDV / 100))+53"
        let value = try Equation(source).value([
            "offensiveAbilityDV": 100,
            "characterLevelDV": 100,
            "dexterityDV": 200,
            "bonusDV": 0,
            "offensiveAbilityModifierDV": 50,
        ])

        // (100 + 1200 + 100) * 1.5 + 53
        #expect(value == 2153)
    }

    @Test
    func rejectsMalformedInput() {
        #expect(throws: (any Error).self) { try Equation("2 +").value([:]) }
        #expect(throws: (any Error).self) { try Equation("(2 + 3").value([:]) }
        #expect(throws: (any Error).self) { try Equation("").value([:]) }
    }
}
