// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// Random-access little-endian reader over a file's bytes.
///
/// The game's texture archives run to hundreds of megabytes each, so the data is memory-mapped and read
/// in place: nothing is copied until a caller asks for a specific range.
public struct ByteView: Sendable {
    public enum Failure: LocalizedError {
        case outOfBounds(offset: Int, count: Int, available: Int)

        public var errorDescription: String? {
            switch self {
                case let .outOfBounds(offset, count, available):
                    "Read of \(count) bytes at \(offset) runs past the end of a \(available)-byte file."
            }
        }
    }

    private let data: Data

    public var count: Int { data.count }

    public init(_ data: Data) {
        // Normalising to a zero-based index keeps every offset in this file relative to the file itself.
        self.data = data.startIndex == 0 ? data : Data(data)
    }

    public init(contentsOf url: URL) throws {
        self.init(try Data(contentsOf: url, options: .mappedIfSafe))
    }

    public func byte(_ offset: Int) throws -> UInt8 {
        try check(offset, 1)
        return data[offset]
    }

    public func uint16(_ offset: Int) throws -> UInt16 {
        try check(offset, 2)
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    public func uint32(_ offset: Int) throws -> UInt32 {
        try check(offset, 4)
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    public func bytes(at offset: Int, count length: Int) throws -> [UInt8] {
        try check(offset, length)
        return [UInt8](data[offset ..< offset + length])
    }

    public func slice(at offset: Int, count length: Int) throws -> Data {
        try check(offset, length)
        return data[offset ..< offset + length]
    }

    /// Decodes a run of bytes as text, replacing anything invalid rather than failing.
    ///
    /// Record paths and archive entry names are game data; a stray byte must not stop the file loading.
    public func text(at offset: Int, count length: Int) throws -> String {
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: try slice(at: offset, count: length), as: UTF8.self)
    }

    public func matches(_ ascii: [UInt8], at offset: Int) -> Bool {
        guard offset >= 0, offset + ascii.count <= data.count else { return false }

        return zip(ascii.indices, ascii).allSatisfy { data[offset + $0.0] == $0.1 }
    }

    private func check(_ offset: Int, _ length: Int) throws {
        guard
            offset >= 0,
            length >= 0,
            offset + length <= data.count
        else {
            throw Failure.outOfBounds(offset: offset, count: length, available: data.count)
        }
    }
}
