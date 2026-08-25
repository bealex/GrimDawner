// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import CoreGraphics
import Foundation
import GrimDawnerEngine
import Testing

@testable import GrimDawnerRender

/// The player's own model, assembled from a real save against the installed game.
///
/// The assertions cover shape rather than content: the save is a player's own file, so nothing here may
/// depend on the character in it. It needs both the game — set `GRIM_DAWN_FOLDER` — and a save under the
/// untracked `Resources/save`, and skips without either.
struct CharacterModelTests {
    private static var gameFolder: URL? {
        ProcessInfo.processInfo.environment["GRIM_DAWN_FOLDER"].map { URL(fileURLWithPath: $0) }
    }

    private static var characters: [CharacterFile] {
        // Render/Tests/GrimDawnerRenderTests/… → repository root → Resources/save
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let saves = root.appending(path: "Resources/save")
        guard FileManager.default.fileExists(atPath: saves.path(percentEncoded: false)) else { return [] }

        return SaveFolder.characters(in: saves)
    }

    /// Every character the save folder holds, assembled and drawn: the body, the gear it wears, the
    /// weapons of each set, and the idle the game's own character window plays.
    @MainActor
    @Test
    func assemblesTheCharacterFromWhatItWears() throws {
        guard let folder = Self.gameFolder else { return }

        let database = try GameDatabase(gameFolder: folder)
        let renderer = ModelRenderer(gameFolder: folder)
        let builder = CharacterBuilder(database: database)

        for file in Self.characters {
            guard let save = try? Gdc.Parser.parse(try Data(contentsOf: file.playerFile)) else { continue }

            let character = builder.build(save, file: file)
            for set in character.weaponSets {
                let model = try #require(CharacterModel.of(character, holding: set, in: database))

                // The body comes first, since everything else is worn over it, and it is skinned to the
                // rig the gear and the animation both move.
                let body = try #require(model.assembly.parts.first)
                #expect(body.hand == nil)
                #expect(!body.texture.isEmpty)
                #expect(try renderer.mesh(at: body.mesh).isSkinned)

                // Every part reads, and neither hand holds two things.
                for part in model.assembly.parts {
                    #expect(try !renderer.mesh(at: part.mesh).isEmpty, "\(part.mesh)")
                }
                let hands = model.assembly.parts.compactMap(\.hand)
                #expect(Set(hands).count == hands.count)

                let played = try renderer.animation(at: try #require(model.animation))
                #expect(played.frameCount > 1)

                let image = try renderer.image(
                    of: model.assembly, size: CGSize(width: 64, height: 96), playing: played, at: 0
                )
                #expect(image.width == 64)
            }
        }
    }
}
