// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// Reader for a Grim Dawn `.arc` archive — the localisation bundles and every texture the game ships.
///
/// Texture archives run to hundreds of megabytes, so only the table of contents is read up front and file
/// bodies are decompressed on demand.
public struct ArcArchive: Sendable {
    public enum Failure: LocalizedError {
        case badHeader
        case missingEntry(String)

        public var errorDescription: String? {
            switch self {
                case .badHeader: "Not a Grim Dawn archive."
                case let .missingEntry(name): "The archive has no entry named \(name)."
            }
        }
    }

    private struct TableEntry {
        public let partCount: Int
        public let firstPartIndex: Int
    }

    private static let tableEntrySize = 44
    private static let partEntrySize = 12
    private static let magic: [UInt8] = [ 0x41, 0x52, 0x43, 0x00 ]  // "ARC\0"

    private let bytes: ByteView
    private let partsOffset: Int
    private let entries: [String: TableEntry]

    public var entryNames: some Collection<String> { entries.keys }

    public init(contentsOf url: URL) throws {
        try self.init(ByteView(contentsOf: url))
    }

    public init(_ bytes: ByteView) throws {
        self.bytes = bytes

        guard bytes.matches(Self.magic, at: 0), try bytes.uint32(4) == 3 else { throw Failure.badHeader }

        let fileCount = Int(try bytes.uint32(8))
        let partsTableSize = Int(try bytes.uint32(16))
        let stringTableSize = Int(try bytes.uint32(20))
        let footerOffset = Int(try bytes.uint32(24))

        partsOffset = footerOffset
        let stringsOffset = partsOffset + partsTableSize
        let tableOffset = stringsOffset + stringTableSize

        var built = [String: TableEntry](minimumCapacity: fileCount)
        for index in 0 ..< fileCount {
            // Entry layout: type, offset, sizes, an unused word, a 64-bit file time, then these four.
            let base = tableOffset + index * Self.tableEntrySize
            let partCount = Int(try bytes.uint32(base + 28))
            let firstPartIndex = Int(try bytes.uint32(base + 32))
            let nameLength = Int(try bytes.uint32(base + 36))
            let nameOffset = stringsOffset + Int(try bytes.uint32(base + 40))

            let name = try bytes.text(at: nameOffset, count: nameLength)
            built[name.lowercased()] = TableEntry(partCount: partCount, firstPartIndex: firstPartIndex)
        }
        entries = built
    }

    public func contains(_ name: String) -> Bool { entries[name.lowercased()] != nil }

    /// Every file the archive holds, by the name it stores them under.
    public var names: some Collection<String> { entries.keys }

    public func data(named name: String) throws -> [UInt8] {
        guard let entry = entries[name.lowercased()] else { throw Failure.missingEntry(name) }

        return try data(for: entry)
    }

    /// Reads every `.txt` file in the archive and merges its `key=value` lines; later files win.
    public func textTags() throws -> [String: String] {
        var tags = [String: String]()

        for name in entries.keys where name.hasSuffix(".txt") {
            // swiftlint:disable:next optional_data_string_conversion
            let contents = String(decoding: try data(named: name), as: UTF8.self)
            // Splitting on "\n" would never match: Swift treats a CRLF pair as a single grapheme.
            for line in contents.split(whereSeparator: \.isNewline) {
                guard let separator = line.firstIndex(of: "=") else { continue }

                let key = line[line.startIndex ..< separator].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty, !key.hasPrefix("//") else { continue }

                let value = line[line.index(after: separator)...]
                tags[key] = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return tags
    }

    private func data(for entry: TableEntry) throws -> [UInt8] {
        var output = [UInt8]()

        for index in entry.firstPartIndex ..< entry.firstPartIndex + entry.partCount {
            let base = partsOffset + index * Self.partEntrySize
            let partOffset = Int(try bytes.uint32(base))
            let compressedSize = Int(try bytes.uint32(base + 4))
            let decompressedSize = Int(try bytes.uint32(base + 8))

            let chunk = try bytes.bytes(at: partOffset, count: compressedSize)
            if compressedSize == decompressedSize {
                output += chunk
            } else {
                output += try Lz4.decompress(chunk, decompressedSize: decompressedSize)
            }
        }

        return output
    }
}
