// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// One character found on disk: its save directory and the `player.gdc` inside it.
public struct CharacterFile: Identifiable, Hashable, Sendable {
    /// The save folder name without the underscore the game prefixes to every character directory.
    public let folderName: String
    public let directory: URL
    public let playerFile: URL

    public var id: URL { playerFile }
    public var displayName: String { folderName.hasPrefix("_") ? String(folderName.dropFirst()) : folderName }
}

/// Finds the characters inside a Grim Dawn save folder.
///
/// Accepts either the `save` folder itself or its `main` subfolder, since both are what people reach for.
public enum SaveFolder {
    public static func characters(in folder: URL) -> [CharacterFile] {
        let roots = [ folder, folder.appending(path: "main") ]
        var found = [URL: CharacterFile]()

        for root in roots {
            for character in scan(root) { found[character.playerFile] = character }
        }

        return found.values.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private static func scan(_ root: URL) -> [CharacterFile] {
        let manager = FileManager.default
        guard
            let entries = try? manager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [ .isDirectoryKey ],
                options: [ .skipsHiddenFiles ]
            )
        else { return [] }

        return entries.compactMap { directory in
            let isDirectory = (try? directory.resourceValues(forKeys: [ .isDirectoryKey ]))?.isDirectory
            guard isDirectory == true else { return nil }

            let player = directory.appending(path: "player.gdc")
            guard manager.fileExists(atPath: player.path(percentEncoded: false)) else { return nil }

            return CharacterFile(folderName: directory.lastPathComponent, directory: directory, playerFile: player)
        }
    }
}
