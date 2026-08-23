// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

public enum Gdc {}

public extension Gdc {
    /// Sequential reader over a Grim Dawn save stream, undoing the rolling-XOR obfuscation as it goes.
    ///
    /// Every read both decodes a value and advances the key over the *encrypted* bytes it consumed, so
    /// values must be read in exactly the order the game wrote them. `peekInt` is the one exception: it
    /// consumes four bytes without advancing the key, which is how block lengths and terminators are stored.
    public struct Reader {
        public enum Failure: LocalizedError {
            case truncated(offset: Int, wanted: Int)
            case unexpectedValue(String)
            case blockLengthMismatch(expected: Int, actual: Int)
            case implausibleLength(Int, offset: Int)

            public var errorDescription: String? {
                switch self {
                    case let .truncated(offset, wanted):
                        "Save file ends mid-value: wanted \(wanted) bytes at offset \(offset)."
                    case let .unexpectedValue(what):
                        "Unexpected value in save file: \(what)."
                    case let .blockLengthMismatch(expected, actual):
                        "Block ended at \(actual) but its length says \(expected)."
                    case let .implausibleLength(length, offset):
                        "Implausible length \(length) at offset \(offset)."
                }
            }
        }

        /// A block's payload boundary: the offset its body must end at.
        public struct Block {
            public let id: UInt32
            public let endOffset: Int
        }

        private let bytes: [UInt8]
        private var key: UInt32
        private let table: [UInt32]

        private(set) var offset: Int

        public var isAtEnd: Bool { offset >= bytes.count }
        public var remaining: Int { bytes.count - offset }

        public init(_ data: Data) throws {
            bytes = [UInt8](data)

            guard bytes.count >= 4 else { throw Failure.truncated(offset: 0, wanted: 4) }

            var seed = UInt32(littleEndian: bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
            seed ^= 0x5555_5555
            key = seed

            var built = [UInt32]()
            built.reserveCapacity(256)
            for _ in 0 ..< 256 {
                seed = (seed >> 1) | (seed << 31)
                seed = seed &* 39_916_801
                built.append(seed)
            }
            table = built
            offset = 4
        }

        // MARK: - Primitives

        private mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
            guard offset + count <= bytes.count else { throw Failure.truncated(offset: offset, wanted: count) }

            let slice = bytes[offset ..< offset + count]
            offset += count
            return slice
        }

        private mutating func advanceKey(over slice: ArraySlice<UInt8>) {
            for byte in slice { key ^= table[Int(byte)] }
        }

        public mutating func byte() throws -> UInt8 {
            let slice = try take(1)
            let value = slice[slice.startIndex] ^ UInt8(truncatingIfNeeded: key)
            advanceKey(over: slice)
            return value
        }

        public mutating func flag() throws -> Bool { try byte() != 0 }

        public mutating func integer() throws -> UInt32 {
            let slice = try take(4)
            let raw = Self.loadUInt32(slice)
            let value = raw ^ key
            advanceKey(over: slice)
            return value
        }

        public mutating func float() throws -> Float { Float(bitPattern: try integer()) }

        /// Reads four bytes without folding them into the key — the encoding used for block lengths.
        public mutating func peekInt() throws -> UInt32 {
            let slice = try take(4)
            return Self.loadUInt32(slice) ^ key
        }

        private static func loadUInt32(_ slice: ArraySlice<UInt8>) -> UInt32 {
            var raw: UInt32 = 0
            for (index, byte) in slice.enumerated() { raw |= UInt32(byte) << (8 * index) }
            return raw
        }

        // MARK: - Strings

        public mutating func string() throws -> String {
            let length = try count(limit: 4096)
            var scalars = [UInt8]()
            scalars.reserveCapacity(length)
            for _ in 0 ..< length { scalars.append(try byte()) }
            // Character-authored text: decode leniently rather than failing the whole save.
            // swiftlint:disable:next optional_data_string_conversion
            return String(decoding: scalars, as: UTF8.self)
        }

        /// UTF-16LE string; each half is read as a separate key-advancing byte, exactly as the game writes it.
        public mutating func wideString() throws -> String {
            let length = try count(limit: 4096)
            var units = [UInt16]()
            units.reserveCapacity(length)
            for _ in 0 ..< length {
                let lowByte = UInt16(try byte())
                let highByte = UInt16(try byte())
                units.append(lowByte | (highByte << 8))
            }
            return String(decoding: units, as: UTF16.self)
        }

        public mutating func uniqueId() throws -> [UInt8] {
            var value = [UInt8]()
            value.reserveCapacity(16)
            for _ in 0 ..< 16 { value.append(try byte()) }
            return value
        }

        // MARK: - Collections

        /// Reads a length prefix, rejecting values that cannot be a real count for this file.
        public mutating func count(limit: Int = 1 << 20) throws -> Int {
            let raw = try integer()
            guard
                raw <= UInt32(limit),
                Int(raw) <= remaining + 4
            else {
                throw Failure.implausibleLength(Int(raw), offset: offset - 4)
            }

            return Int(raw)
        }

        public mutating func array<Element>(_ element: (inout Reader) throws -> Element) throws -> [Element] {
            let length = try count()
            var values = [Element]()
            values.reserveCapacity(length)
            for _ in 0 ..< length { values.append(try element(&self)) }
            return values
        }

        // MARK: - Blocks

        public mutating func blockStart(expecting expected: UInt32? = nil) throws -> Block {
            let id = try integer()

            if let expected, id != expected {
                throw Failure.unexpectedValue("block id \(id), expected \(expected)")
            }

            let length = try peekInt()
            guard Int(length) <= remaining else { throw Failure.implausibleLength(Int(length), offset: offset) }

            return Block(id: id, endOffset: offset + Int(length))
        }

        public mutating func blockEnd(_ block: Block) throws {
            guard
                offset == block.endOffset
            else {
                throw Failure.blockLengthMismatch(expected: block.endOffset, actual: offset)
            }
            guard try peekInt() == 0 else { throw Failure.unexpectedValue("block terminator") }
        }

        /// Consumes whatever is left of a block's body, keeping the key in step.
        ///
        /// Only valid for blocks with no nested blocks: a nested block's length and terminator are stored
        /// without advancing the key, so a flat skip over them would desynchronise it.
        public mutating func skipToEnd(of block: Block) throws {
            guard
                offset <= block.endOffset
            else {
                throw Failure.blockLengthMismatch(expected: block.endOffset, actual: offset)
            }

            let slice = try take(block.endOffset - offset)
            advanceKey(over: slice)
        }

        /// Reads the remaining bytes of a block's body as opaque data, for fields this app does not model.
        public mutating func trailingBytes(of block: Block) throws -> [UInt8] {
            var values = [UInt8]()
            while offset < block.endOffset { values.append(try byte()) }
            return values
        }
    }
}
