// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import CoreGraphics
import Foundation
import Synchronization

/// Resolves the texture paths stored in `.dbr` records to decoded images.
///
/// Records name a texture by a path whose first component is the archive it lives in — `ui/skills/...`
/// comes from `UI.arc`, `items/...` from `Items.arc` — and the entry inside that archive drops that first
/// component. Expansions ship their own archives that override the base game's, so they are searched first.
final class TextureStore: Sendable {
    /// Which archive each path root lives in, and the load order within it (later overrides earlier).
    private static let archiveRoots = [
        "ui": "UI.arc",
        "items": "Items.arc",
        "creatures": "Creatures.arc",
        "fx": "FX.arc",
    ]

    private static let expansionFolders = [ "", "gdx1/", "gdx2/", "gdx3/" ]

    private let gameFolder: URL
    /// Archives keyed by path root, in override order; opened on first use because each holds a large map.
    private let archives = Mutex<[String: [ArcArchive]]>([:])
    private let images = Mutex<[String: CGImage?]>([:])

    init(gameFolder: URL) {
        self.gameFolder = gameFolder
    }

    /// Decodes the texture at a record's bitmap path, or nil when it is absent or unreadable.
    ///
    /// A missing icon is never worth failing over, so every error resolves to nil and is cached as such.
    func image(at path: String) -> CGImage? {
        guard !path.isEmpty else { return nil }

        let key = path.lowercased().replacingOccurrences(of: "\\", with: "/")
        if let cached = images.withLock({ $0[key] }) { return cached }

        let decoded = load(key)
        images.withLock { $0[key] = decoded }
        return decoded
    }

    /// The pixel size of a texture, which is the layout unit the game's UI records are measured in.
    func size(at path: String) -> CGSize? {
        guard let image = image(at: path) else { return nil }

        return CGSize(width: image.width, height: image.height)
    }

    /// Decodes a set of paths ahead of the views that will ask for them.
    ///
    /// Icon decoding is cheap but not free, and a mastery panel asks for dozens at once; doing that work
    /// while the character loads keeps the first paint of a tab from stalling.
    func prewarm(_ paths: some Sequence<String>) {
        for path in paths { _ = image(at: path) }
    }

    private func load(_ path: String) -> CGImage? {
        guard let separator = path.firstIndex(of: "/") else { return nil }

        let root = String(path[path.startIndex ..< separator])
        let entry = String(path[path.index(after: separator)...])

        for archive in archives(for: root) {
            guard archive.contains(entry), let raw = try? archive.data(named: entry) else { continue }

            return try? Texture.image(from: raw)
        }
        return nil
    }

    private func archives(for root: String) -> [ArcArchive] {
        if let opened = archives.withLock({ $0[root] }) { return opened }

        var opened = [ArcArchive]()
        if let fileName = Self.archiveRoots[root] {
            // Reversed so the newest expansion that ships this archive is searched first.
            for folder in Self.expansionFolders.reversed() {
                let url = gameFolder.appending(path: "\(folder)resources/\(fileName)")
                guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { continue }
                guard let archive = try? ArcArchive(contentsOf: url) else { continue }

                opened.append(archive)
            }
        }

        archives.withLock { $0[root] = opened }
        return opened
    }
}
