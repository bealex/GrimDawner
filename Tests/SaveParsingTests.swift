// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation
import Testing

@testable import GrimDawner

/// Structural checks against a real save, when one is present in the untracked `Resources/save`.
///
/// The assertions cover shape rather than content: the save is a player's own file, so the test must not
/// depend on the character in it, and it skips when the folder is absent.
struct SaveParsingTests {
    private static var playerFiles: [URL] {
        // Tests/… → repository root → Resources/save
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let saves = root.appending(path: "Resources/save")
        guard FileManager.default.fileExists(atPath: saves.path(percentEncoded: false)) else { return [] }

        return SaveFolder.characters(in: saves).map(\.playerFile)
    }

    /// Every save the folder holds that the current format covers. A folder can also hold a character
    /// from an old game version, whose preamble this parser rejects on purpose, so a file that fails to
    /// parse is passed over rather than failing the run.
    @Test
    func parsesEveryByteOfARealSave() throws {
        for url in Self.playerFiles {
            guard let save = try? Gdc.Parser.parse(try Data(contentsOf: url)) else { continue }

            #expect(!save.header.name.isEmpty)
            #expect(save.header.level > 0)
            #expect(save.biography.level == save.header.level)
            #expect(save.biography.physique > 0)
            #expect(save.inventory.equipment.count == 12)
            #expect(save.inventory.weaponSet1.count == 2)
            #expect(save.inventory.weaponSet2.count == 2)
            #expect(!save.skills.skills.isEmpty)
            #expect(!save.factions.isEmpty)
        }
    }

    @Test
    func rejectsDataThatIsNotASave() {
        let junk = Data([UInt8](repeating: 0xAB, count: 512))

        #expect(throws: (any Error).self) { try Gdc.Parser.parse(junk) }
    }

    @Test
    func rejectsAnEmptyFile() {
        #expect(throws: (any Error).self) { try Gdc.Parser.parse(Data()) }
    }
}
