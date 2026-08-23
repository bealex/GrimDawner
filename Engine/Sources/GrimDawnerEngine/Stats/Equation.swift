// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// Evaluator for the arithmetic formulas Grim Dawn stores as text in its database.
///
/// The game keeps its combat maths in `records/game/combatformulas.dbr` — for example
/// `(offensiveAbilityDV + (characterLevelDV * 12) + ((dexterityDV + bonusDV) * 0.5)) * (1 + …) + 53` —
/// and item records carry smaller ones such as `itemLevel/4+1`. Reading them instead of hardcoding the
/// numbers keeps the engine correct across game patches.
///
/// Grammar: numbers, identifiers, `+ - * /`, `^` (right-associative), unary minus and parentheses.
/// Unknown identifiers evaluate to zero, which matches how the game treats an absent variable.
public struct Equation {
    public enum Failure: LocalizedError {
        case malformed(String)

        public var errorDescription: String? {
            switch self {
                case let .malformed(source): "Cannot parse the game formula \"\(source)\"."
            }
        }
    }

    private enum Token: Equatable {
        case number(Double)
        case identifier(String)
        case symbol(Character)
    }

    private let tokens: [Token]
    private let source: String

    public init(_ source: String) throws {
        self.source = source
        tokens = try Self.tokenise(source)

        guard !tokens.isEmpty else { throw Failure.malformed(source) }
    }

    /// Evaluates with the given variables; names are matched case-insensitively.
    public func value(_ variables: [String: Double]) throws -> Double {
        var lowercased = [String: Double](minimumCapacity: variables.count)
        for (name, value) in variables { lowercased[name.lowercased()] = value }

        var parser = Parser(tokens: tokens, variables: lowercased, source: source)
        let result = try parser.expression()

        guard parser.isAtEnd else { throw Failure.malformed(source) }

        return result
    }

    // MARK: - Lexing

    private static func tokenise(_ source: String) throws -> [Token] {
        var tokens = [Token]()
        let characters = Array(source)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character.isWhitespace {
                index += 1
            } else if character.isNumber || (character == "." && index + 1 < characters.count) {
                var text = ""
                while index < characters.count, characters[index].isNumber || characters[index] == "." {
                    text.append(characters[index])
                    index += 1
                }
                guard let number = Double(text) else { throw Failure.malformed(source) }

                tokens.append(.number(number))
            } else if character.isLetter || character == "_" {
                var text = ""
                while index < characters.count,
                        characters[index].isLetter
                            || characters[index].isNumber || characters[index] == "_" {
                    text.append(characters[index])
                    index += 1
                }
                tokens.append(.identifier(text.lowercased()))
            } else if "+-*/^()".contains(character) {
                tokens.append(.symbol(character))
                index += 1
            } else {
                throw Failure.malformed(source)
            }
        }

        return tokens
    }

    // MARK: - Parsing

    private struct Parser {
        public let tokens: [Token]
        public let variables: [String: Double]
        public let source: String
        public var index = 0

        public var isAtEnd: Bool { index >= tokens.count }

        private func peek() -> Token? { index < tokens.count ? tokens[index] : nil }

        private mutating func match(_ symbol: Character) -> Bool {
            guard peek() == .symbol(symbol) else { return false }

            index += 1
            return true
        }

        public mutating func expression() throws -> Double {
            var result = try term()

            while let token = peek(), token == .symbol("+") || token == .symbol("-") {
                index += 1
                let right = try term()
                result = token == .symbol("+") ? result + right : result - right
            }

            return result
        }

        private mutating func term() throws -> Double {
            var result = try power()

            while let token = peek(), token == .symbol("*") || token == .symbol("/") {
                index += 1
                let right = try power()
                if token == .symbol("*") {
                    result *= right
                } else {
                    guard right != 0 else { throw Failure.malformed(source) }

                    result /= right
                }
            }

            return result
        }

        private mutating func power() throws -> Double {
            let base = try unary()
            guard match("^") else { return base }

            return pow(base, try power())
        }

        private mutating func unary() throws -> Double {
            if match("-") { return -(try unary()) }
            if match("+") { return try unary() }

            return try primary()
        }

        private mutating func primary() throws -> Double {
            guard let token = peek() else { throw Failure.malformed(source) }

            switch token {
                case let .number(value):
                    index += 1
                    return value
                case let .identifier(name):
                    index += 1
                    return variables[name] ?? 0
                case .symbol("("):
                    index += 1
                    let inner = try expression()
                    guard match(")") else { throw Failure.malformed(source) }

                    return inner
                default:
                    throw Failure.malformed(source)
            }
        }
    }
}
