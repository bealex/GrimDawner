// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// One of the game's particle systems, read from a `.pfx`.
///
/// The layout is `EmitterData::InternalBinaryRead` @ `Engine.dll:0x1800682c0`, which the engine exports
/// by name: the magic `PFX1`, eight bytes it steps over, then five counted blocks — strings, flags,
/// integers, floats and curves. Everything the emitter is made of is in those five, and the emitter
/// reads them **by index** (`GetString`, `GetBoolean`, `GetInteger`, `GetFloat`, `GetCurve` all take
/// one), so the meaning of a slot lives in the code that asks for it rather than in the file.
///
/// A file written before the magic existed falls to `OldBinaryRead` in the engine; this reads only the
/// current shape and says so rather than guessing.
public struct PfxFile: Sendable {
    /// A value that moves over the life of a particle or of the emitter, as
    /// `CurveData::BinaryRead` @ `Engine.dll:0x180184a40` writes it.
    public struct Curve: Sendable {
        public let domain: Float
        public let range: Float
        /// The points it is drawn through, in the file's own order. Their times run across the domain.
        public let keys: [(time: Float, value: Float)]

        public init(domain: Float, range: Float, keys: [(time: Float, value: Float)]) {
            self.domain = domain
            self.range = range
            self.keys = keys
        }

        /// True where there is a shape to draw rather than one figure held flat.
        public var isShape: Bool { keys.count > 1 && domain > 0 }

        /// What the curve reads at a point, walking its own key times and taking the straight line
        /// between the two it falls between. Outside the keys it holds the nearest one.
        public func value(at time: Float) -> Float {
            guard let first = keys.first else { return 0 }
            guard time > first.time else { return first.value }
            guard let last = keys.last, time < last.time else { return keys.last?.value ?? 0 }

            for (left, right) in zip(keys, keys.dropFirst()) where time <= right.time {
                let span = right.time - left.time
                guard span > 0 else { return right.value }

                return left.value + (right.value - left.value) * (time - left.time) / span
            }
            return last.value
        }
    }

    public enum Failure: LocalizedError {
        case notAParticleSystem
        case truncated

        public var errorDescription: String? {
            switch self {
                case .notAParticleSystem: "No PFX1 particle system in this file."
                case .truncated: "The particle system ends part way through."
            }
        }
    }

    /// The pictures and shaders it names. The emitter asks for these by index too, so which is which is
    /// the caller's business — in every file read so far the texture leads and the shader follows.
    public let strings: [String]
    public let flags: [Bool]
    public let integers: [Int32]
    public let floats: [Float]
    public let curves: [Curve]

    public init(_ bytes: [UInt8]) throws {
        guard let start = Self.magic(in: bytes) else { throw Failure.notAParticleSystem }

        // The four of the magic and the eight the engine steps over.
        var cursor = start + 12
        strings = try Self.read(&cursor, in: bytes) { cursor in
            let length = try Self.integer(&cursor, in: bytes)
            guard length >= 0, cursor + Int(length) <= bytes.count else { throw Failure.truncated }

            let text = String(decoding: bytes[cursor ..< cursor + Int(length)], as: UTF8.self)
            cursor += Int(length)
            return text
        }
        flags = try Self.read(&cursor, in: bytes) { try Self.integer(&$0, in: bytes) != 0 }
        integers = try Self.read(&cursor, in: bytes) { try Self.integer(&$0, in: bytes) }
        floats = try Self.read(&cursor, in: bytes) { try Self.real(&$0, in: bytes) }
        curves = try Self.read(&cursor, in: bytes) { cursor in
            let domain = try Self.real(&cursor, in: bytes)
            let range = try Self.real(&cursor, in: bytes)
            var keys = [(time: Float, value: Float)]()
            let count = try Self.integer(&cursor, in: bytes)
            guard count >= 0, count < 100_000 else { throw Failure.truncated }

            for _ in 0 ..< count {
                keys.append((try Self.real(&cursor, in: bytes), try Self.real(&cursor, in: bytes)))
            }
            return Curve(domain: domain, range: range, keys: keys)
        }
    }

    /// Where the particle system starts. A `.pfx` opens with a version and the emitter's name, and the
    /// engine's reader is handed the file already positioned at the magic, so the magic is what is
    /// looked for rather than a header shape that nothing states.
    private static func magic(in bytes: [UInt8]) -> Int? {
        let wanted: [UInt8] = Array("PFX1".utf8)
        guard bytes.count >= wanted.count else { return nil }

        for start in 0 ... min(bytes.count - wanted.count, 4096)
        where Array(bytes[start ..< start + wanted.count]) == wanted {
            return start
        }
        return nil
    }

    /// One counted block: how many, then that many of whatever the block holds.
    private static func read<Value>(
        _ cursor: inout Int,
        in bytes: [UInt8],
        each: (inout Int) throws -> Value
    ) throws -> [Value] {
        let count = try integer(&cursor, in: bytes)
        guard count >= 0, count < 1_000_000 else { throw Failure.truncated }

        var found = [Value]()
        found.reserveCapacity(Int(count))
        for _ in 0 ..< count { found.append(try each(&cursor)) }
        return found
    }

    private static func integer(_ cursor: inout Int, in bytes: [UInt8]) throws -> Int32 {
        guard cursor + 4 <= bytes.count else { throw Failure.truncated }

        let value =
            UInt32(bytes[cursor]) | UInt32(bytes[cursor + 1]) << 8
            | UInt32(bytes[cursor + 2]) << 16 | UInt32(bytes[cursor + 3]) << 24
        cursor += 4
        return Int32(bitPattern: value)
    }

    private static func real(_ cursor: inout Int, in bytes: [UInt8]) throws -> Float {
        Float(bitPattern: UInt32(bitPattern: try integer(&cursor, in: bytes)))
    }
}
