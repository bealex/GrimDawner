// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// One `.dbr` record out of an `.arz` database: its path, its record class, and its fields.
public struct ArzRecord: Sendable {
    public let path: String
    public let recordClass: String
    public let fields: [String: ArzValue]
    /// The order the record stores its fields in, which is the order the game walks them.
    public let fieldOrder: [String]

    public subscript(key: String) -> ArzValue? { fields[key] }

    public func number(_ key: String) -> Double { fields[key]?.number ?? 0 }

    public func text(_ key: String) -> String { fields[key]?.text ?? "" }

    public func integer(_ key: String) -> Int { Int(fields[key]?.number ?? 0) }
}

/// A `.dbr` field value. Multi-valued fields keep every element; scalars are the single-element case.
public enum ArzValue: Sendable {
    case integer([Int32])
    case real([Float])
    case text([String])
    case flag([Bool])

    public var number: Double {
        switch self {
            case let .integer(values): values.first.map(Double.init) ?? 0
            case let .real(values): values.first.map(Double.init) ?? 0
            case let .flag(values): (values.first ?? false) ? 1 : 0
            case .text: 0
        }
    }

    public var text: String {
        switch self {
            case let .text(values): values.first ?? ""
            default: ""
        }
    }

    public var numbers: [Double] {
        switch self {
            case let .integer(values): values.map(Double.init)
            case let .real(values): values.map(Double.init)
            case let .flag(values): values.map { $0 ? 1 : 0 }
            case .text: []
        }
    }

    public var texts: [String] {
        switch self {
            case let .text(values): values
            default: []
        }
    }

    public var isZero: Bool {
        switch self {
            case let .integer(values): values.allSatisfy { $0 == 0 }
            case let .real(values): values.allSatisfy { $0 == 0 }
            case let .flag(values): values.allSatisfy { !$0 }
            case let .text(values): values.allSatisfy(\.isEmpty)
        }
    }
}

/// Reader for a Grim Dawn `.arz` database file.
///
/// Records are decompressed lazily: the constructor only reads the string and record tables, so opening
/// the retail database is cheap and callers pay per record they actually decode.
public struct ArzDatabase: Sendable {
    public enum Failure: LocalizedError {
        case badHeader(magic: UInt16, version: UInt16)
        case truncated
        case unknownValueType(UInt16)

        public var errorDescription: String? {
            switch self {
                case let .badHeader(magic, version):
                    "Not a Grim Dawn database (magic \(magic), version \(version))."
                case .truncated: "Database file is truncated."
                case let .unknownValueType(type): "Unknown database value type \(type)."
            }
        }
    }

    private struct Entry {
        public let recordClass: String
        public let offset: Int
        public let compressedSize: Int
        public let decompressedSize: Int
    }

    private static let headerSize = 24

    private let bytes: ByteView
    private let strings: [String]
    private let entries: [String: Entry]

    public var recordPaths: some Collection<String> { entries.keys }
    public var recordCount: Int { entries.count }

    public init(contentsOf url: URL) throws {
        try self.init(ByteView(contentsOf: url))
    }

    public init(_ bytes: ByteView) throws {
        self.bytes = bytes

        let magic = try bytes.uint16(0)
        let version = try bytes.uint16(2)
        guard magic == 2, version == 3 else { throw Failure.badHeader(magic: magic, version: version) }

        let recordTableStart = Int(try bytes.uint32(4))
        let recordCount = Int(try bytes.uint32(12))
        let stringTableStart = Int(try bytes.uint32(16))

        strings = try Self.readStringTable(bytes, at: stringTableStart)

        var table = [String: Entry](minimumCapacity: recordCount)
        var position = recordTableStart
        for _ in 0 ..< recordCount {
            let nameIndex = Int(try bytes.uint32(position))
            let classLength = Int(try bytes.uint32(position + 4))
            position += 8

            let recordClass = try bytes.text(at: position, count: classLength)
            position += classLength

            let entry = Entry(
                recordClass: recordClass,
                offset: Int(try bytes.uint32(position)),
                compressedSize: Int(try bytes.uint32(position + 4)),
                decompressedSize: Int(try bytes.uint32(position + 8))
            )
            position += 12 + 8  // three sizes plus a u64 file time

            guard nameIndex < strings.count else { throw Failure.truncated }

            table[strings[nameIndex]] = entry
        }
        entries = table
    }

    public func record(at path: String) throws -> ArzRecord? {
        guard let entry = entries[path] else { return nil }

        let start = Self.headerSize + entry.offset
        let payload = try Lz4.decompress(
            try bytes.bytes(at: start, count: entry.compressedSize),
            decompressedSize: entry.decompressedSize
        )
        let decoded = try decodeFields(payload)
        return ArzRecord(path: path, recordClass: entry.recordClass, fields: decoded.fields, fieldOrder: decoded.order)
    }

    private func decodeFields(_ payload: [UInt8]) throws -> (fields: [String: ArzValue], order: [String]) {
        var fields = [String: ArzValue]()
        var order = [String]()
        var position = 0

        while position + 8 <= payload.count {
            let valueType = try Self.uint16(payload, position)
            let valueCount = Int(try Self.uint16(payload, position + 2))
            let keyIndex = Int(try Self.uint32(payload, position + 4))
            position += 8

            guard
                position + 4 * valueCount <= payload.count,
                keyIndex < strings.count
            else {
                throw Failure.truncated
            }

            var raw = [UInt32]()
            raw.reserveCapacity(valueCount)
            for index in 0 ..< valueCount {
                raw.append(try Self.uint32(payload, position + 4 * index))
            }
            position += 4 * valueCount

            let key = strings[keyIndex]
            if fields[key] == nil { order.append(key) }
            fields[key] = try value(ofType: valueType, raw: raw)
        }

        return (fields, order)
    }

    private func value(ofType valueType: UInt16, raw: [UInt32]) throws -> ArzValue {
        switch valueType {
            case 0: .integer(raw.map { Int32(bitPattern: $0) })
            case 1: .real(raw.map { Float(bitPattern: $0) })
            case 2: .text(raw.map { Int($0) < strings.count ? strings[Int($0)] : "" })
            case 3: .flag(raw.map { $0 != 0 })
            default: throw Failure.unknownValueType(valueType)
        }
    }

    // MARK: - Byte access

    /// Record payloads are already decompressed into an array, so they get their own small accessors.
    private static func uint16(_ payload: [UInt8], _ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= payload.count else { throw Failure.truncated }

        return UInt16(payload[offset]) | (UInt16(payload[offset + 1]) << 8)
    }

    private static func uint32(_ payload: [UInt8], _ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= payload.count else { throw Failure.truncated }

        return UInt32(payload[offset])
            | (UInt32(payload[offset + 1]) << 8)
            | (UInt32(payload[offset + 2]) << 16)
            | (UInt32(payload[offset + 3]) << 24)
    }

    private static func readStringTable(_ bytes: ByteView, at start: Int) throws -> [String] {
        let count = Int(try bytes.uint32(start))
        var position = start + 4
        var values = [String]()
        values.reserveCapacity(count)

        for _ in 0 ..< count {
            let length = Int(try bytes.uint32(position))
            position += 4
            values.append(try bytes.text(at: position, count: length))
            position += length
        }

        return values
    }
}
