// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import CryptoKit
import Foundation
import Synchronization

/// The game's records and display strings, merged across the base game and every installed expansion.
///
/// Later archives override earlier ones for the same record path or tag, which is the load order the
/// game itself uses.
public final class GameDatabase: Sendable {
    /// Database and localisation archives in load order; missing ones are skipped.
    private static let databasePaths = [
        "database/database.arz",
        "gdx1/database/GDX1.arz",
        "gdx2/database/GDX2.arz",
        "gdx3/database/GDX3.arz",
        "survivalmode1/database/SurvivalMode1.arz",
        "survivalmode2/database/SurvivalMode2.arz",
        "survivalmode3/database/SurvivalMode3.arz",
    ]

    private static let textPaths = [
        "resources/Text_EN.arc",
        "gdx1/resources/Text_EN.arc",
        "gdx2/resources/Text_EN.arc",
        "gdx3/resources/Text_EN.arc",
        "survivalmode1/resources/Text_EN.arc",
        "survivalmode2/resources/Text_EN.arc",
        "survivalmode3/resources/Text_EN.arc",
    ]

    /// Databases in reverse load order, so the first hit is the winning override.
    private let databases: [ArzDatabase]
    private let tags: [String: String]
    private let cache: RecordCache

    /// Decoded icons for the records this database serves.
    public let textures: TextureStore

    public let installedArchiveCount: Int
    /// Identifies the installed database, so what is derived from it can be cached across launches.
    public let fingerprint: String

    public init(gameFolder: URL) throws {
        var loaded = [ArzDatabase]()
        var stamps = [String]()
        for relative in Self.databasePaths {
            let url = gameFolder.appending(path: relative)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { continue }

            loaded.append(try ArzDatabase(contentsOf: url))
            stamps.append(Self.stamp(of: url, named: relative))
        }
        fingerprint = Self.digest(of: stamps)

        guard !loaded.isEmpty else { throw Failure.noDatabaseFound(gameFolder) }

        installedArchiveCount = loaded.count
        databases = loaded.reversed()

        var merged = [String: String]()
        for relative in Self.textPaths {
            let url = gameFolder.appending(path: relative)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { continue }
            guard let archive = try? ArcArchive(contentsOf: url) else { continue }

            merged.merge(try archive.textTags()) { _, later in later }
        }
        tags = merged
        cache = RecordCache()
        textures = TextureStore(gameFolder: gameFolder)
    }

    public enum Failure: LocalizedError {
        case noDatabaseFound(URL)

        public var errorDescription: String? {
            switch self {
                case let .noDatabaseFound(url):
                    "No database.arz under \(url.path(percentEncoded: false)) — is that the Grim Dawn folder?"
            }
        }
    }

    /// Looks up a record by its `.dbr` path. Paths are matched case-insensitively, as the save writes them.
    public func record(_ path: String) -> ArzRecord? {
        guard !path.isEmpty else { return nil }

        let key = path.lowercased()
        if let cached = cache.value(for: key) { return cached.record }

        var found: ArzRecord?
        for database in databases {
            guard let record = try? database.record(at: key) else { continue }

            found = record
            break
        }

        cache.store(found, for: key)
        return found
    }

    /// Resolves a `tag*` key to its display string, falling back to the key when the archive has no entry.
    public func text(_ tagKey: String) -> String {
        guard !tagKey.isEmpty else { return "" }

        return localised(tagKey) ?? tagKey
    }

    /// Resolves a tag only when it exists, so callers can distinguish "no name" from "unknown tag".
    public func localised(_ tagKey: String) -> String? {
        guard !tagKey.isEmpty, let text = tags[tagKey] else { return nil }

        return Self.stripped(text)
    }

    /// Reads every record under a path prefix, newest archive first and each path only once.
    ///
    /// These records go nowhere near the memo: a sweep of the item tree is 26,000 of them, and keeping
    /// them all would cost far more memory than re-reading the handful that are looked at again.
    public func sweep(prefix: String, _ body: (String, ArzRecord) -> Void) {
        var seen = Set<String>()
        for database in databases {
            for path in database.recordPaths where path.hasPrefix(prefix) {
                guard seen.insert(path).inserted, let record = try? database.record(at: path) else { continue }

                body(path, record)
            }
        }
    }

    /// A stamp that changes whenever the game is patched: the archive's size and when it was written.
    private static func stamp(of url: URL, named name: String) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

        return "\(name):\(size):\(Int(modified))"
    }

    /// Hashed with SHA-256 rather than `Hasher`, whose seed changes from launch to launch and would
    /// leave anything cached under it unreadable next time.
    private static func digest(of stamps: [String]) -> String {
        let digest = SHA256.hash(data: Data(stamps.joined(separator: "\n").utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Resolves a UI record that names a texture, which the game reaches through a nested bitmap record.
    public func bitmap(inRecordAt path: String) -> String {
        guard !path.isEmpty, let record = record(path) else { return "" }

        return record.text("bitmapName")
    }

    /// Removes the game's inline colour codes — a caret followed by one letter, as in `^kPrismatic Diamond`.
    private static func stripped(_ text: String) -> String {
        guard text.contains("^") else { return text }

        var output = ""
        var characters = text.makeIterator()
        while let character = characters.next() {
            guard
                character == "^"
            else {
                output.append(character)
                continue
            }

            // Drop the code letter that follows the caret; a trailing caret is left as-is.
            if let code = characters.next(), !code.isLetter { output.append(code) }
        }
        return output
    }

    /// Memo of decompressed records; the same handful get read repeatedly while building a character,
    /// and decompression dominates lookup cost.
    private final class RecordCache: Sendable {
        /// A miss is cached too, so a missing record costs one lookup rather than one per call.
        public struct Entry: Sendable { let record: ArzRecord? }

        private let storage = Mutex<[String: Entry]>([:])

        public func value(for key: String) -> Entry? {
            storage.withLock { $0[key] }
        }

        public func store(_ record: ArzRecord?, for key: String) {
            storage.withLock { $0[key] = Entry(record: record) }
        }
    }
}
