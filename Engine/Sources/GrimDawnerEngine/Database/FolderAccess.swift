// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// Remembers a user-granted folder across launches via an app-scoped security bookmark.
///
/// The sandbox only lets the app read a folder the user picked, and only while the returned handle is
/// alive — callers must hold the `Access` for as long as they read from the folder.
public struct FolderAccess {
    public init(defaultsKey: String) { self.defaultsKey = defaultsKey }

    /// A resolved folder plus its sandbox permission; releasing it revokes access.
    public final class Access {
        public let url: URL
        private let needsRelease: Bool

        public init(url: URL, needsRelease: Bool) {
            self.url = url
            self.needsRelease = needsRelease
        }

        deinit {
            if needsRelease { url.stopAccessingSecurityScopedResource() }
        }
    }

    public enum Failure: LocalizedError {
        case noStoredFolder
        case bookmarkUnusable

        public var errorDescription: String? {
            switch self {
                case .noStoredFolder: "No folder has been chosen yet."
                case .bookmarkUnusable: "The saved folder is no longer reachable — choose it again."
            }
        }
    }

    public let defaultsKey: String

    public func store(_ url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: defaultsKey)
    }

    public func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    public var hasStoredFolder: Bool { UserDefaults.standard.data(forKey: defaultsKey) != nil }

    public func resolve() throws -> Access {
        guard
            let bookmark = UserDefaults.standard.data(forKey: defaultsKey)
        else {
            throw Failure.noStoredFolder
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        guard url.startAccessingSecurityScopedResource() else { throw Failure.bookmarkUnusable }

        if isStale { try? store(url) }

        return Access(url: url, needsRelease: true)
    }
}
