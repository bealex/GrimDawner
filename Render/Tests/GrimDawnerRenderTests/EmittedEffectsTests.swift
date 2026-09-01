// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation
import GrimDawnerEngine
import Testing

@testable import GrimDawnerRender

/// What an attack fires, read the way the engine launches it: the projectile record behind
/// `skillProjectileName`, leaving `launchAttachPointName`, `projectileLaunchNumber` at a time across
/// `projectileLaunchRotation` degrees. It needs the installed game: set `GRIM_DAWN_FOLDER`, and it
/// skips without it.
struct EmittedEffectsTests {
    /// The Dread's ravine: ten invisible sparks in a full circle, each drawn as the ground eruptions
    /// it drops along the way — the mesh wears the game's invisible stand-in and must not be drawn.
    @Test
    func readsARingOfCrawlersAsTheirTrail() throws {
        guard let folder = ProcessInfo.processInfo.environment["GRIM_DAWN_FOLDER"] else { return }

        let gameFolder = URL(fileURLWithPath: folder)
        let database = try GameDatabase(gameFolder: gameFolder)
        let renderer = ModelRenderer(gameFolder: gameFolder)
        let emitted = renderer.emitted(
            bySkillAt: "records/skills/nonplayerskillsgdx3/bossskills/nemesis/thedread_stompdarkravine.dbr",
            level: 26,
            launchFrame: 65,
            in: database
        )
        let ravine = try #require(emitted.first)
        let flight = try #require(ravine.flight)
        #expect(flight.count == 10)
        #expect(flight.arc == 360)
        #expect(flight.velocity == 11)
        #expect(flight.distance == 18)
        #expect(ravine.attachment == "FX_ForwardGround")
        #expect(ravine.frame == 65)
        #expect(ravine.image != nil)
        #expect(ravine.model == nil)
    }

    /// The Dread's screech orb: one homing ball from the mouth, drawn as its flight effect.
    @Test
    func readsAHomingOrbFromTheMouth() throws {
        guard let folder = ProcessInfo.processInfo.environment["GRIM_DAWN_FOLDER"] else { return }

        let gameFolder = URL(fileURLWithPath: folder)
        let database = try GameDatabase(gameFolder: gameFolder)
        let renderer = ModelRenderer(gameFolder: gameFolder)
        let emitted = renderer.emitted(
            bySkillAt: "records/skills/nonplayerskillsgdx3/bossskills/nemesis/thedread_screechorb.dbr",
            level: 26,
            launchFrame: nil,
            in: database
        )
        let orb = try #require(emitted.first)
        let flight = try #require(orb.flight)
        #expect(flight.count == 1)
        #expect(flight.velocity == 9)
        #expect(flight.distance == 45)
        #expect(flight.size == 1)
        #expect(orb.attachment == "Mouth")
        #expect(orb.image != nil)
    }
}
