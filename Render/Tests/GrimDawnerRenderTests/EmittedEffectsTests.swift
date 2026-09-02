// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation
import GrimDawnerEngine
import Testing
import simd

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
        // A homing orb is sent straight at what it is aimed at, which stands at the skill's own `Long`.
        #expect(!flight.isThrown)
        #expect(flight.launchAngle == 0)
        #expect(flight.range == 15)
    }

    /// The Bone Grinder's glacier: a grenade, which the engine throws in an arc rather than sending
    /// straight — `records/game/gameengine.dbr` says its `Long` target stands 15 away.
    @Test
    func readsAThrownGrenadeAsAnArc() throws {
        guard let folder = ProcessInfo.processInfo.environment["GRIM_DAWN_FOLDER"] else { return }

        let gameFolder = URL(fileURLWithPath: folder)
        let database = try GameDatabase(gameFolder: gameFolder)
        let renderer = ModelRenderer(gameFolder: gameFolder)
        let emitted = renderer.emitted(
            bySkillAt: "records/skills/nonplayerskillsgdx3/bossskills/bonegrinder_throwglacier.dbr",
            level: 20,
            launchFrame: 30,
            in: database
        )
        let glacier = try #require(emitted.first)
        let flight = try #require(glacier.flight)
        #expect(flight.isThrown)
        #expect(flight.launchAngle == 25)
        #expect(flight.velocity == 15)
        #expect(flight.distance == 22)
        #expect(flight.range == 15)

        // Thrown from chest height at a target 15 away on the ground: it rises well above where it
        // left and comes back down to the target's own height.
        let path = ModelScene().flown(
            flight, from: SIMD3(0, 2, 0), along: SIMD3(0, 0, 1), onto: 0
        )
        let apex = path.places.map(\.y).max() ?? 0
        let landing = try #require(path.places.last)
        #expect(apex > 3.2)
        #expect(abs(landing.y) < 0.2)
        #expect(abs(landing.z - 15) < 0.5)
        #expect(path.seconds > 1 && path.seconds < 1.5)
    }

    /// Nine of an emitter's curves are centred, their nothing sitting at half their own range.
    ///
    /// The yeti's claws are a mirrored pair, so off their centre they must spin against each other.
    @Test
    func readsAnEmittersCentredCurvesOffTheirCentre() throws {
        guard let folder = ProcessInfo.processInfo.environment["GRIM_DAWN_FOLDER"] else { return }

        let gameFolder = URL(fileURLWithPath: folder)
        let database = try GameDatabase(gameFolder: gameFolder)
        let renderer = ModelRenderer(gameFolder: gameFolder)
        let animation = try renderer.animation(at: "creatures/enemies/yeti/anm/yeti_attack_tripleswipe.anm")
        let swipes = renderer.effects(of: animation, in: database)
        let right = try #require(swipes.first { $0.name.hasSuffix(" R") }?.emission)
        let left = try #require(swipes.first { $0.name.hasSuffix(" L") }?.emission)

        #expect(right.spin > 60 && right.spin < 70)
        #expect(left.spin < -65 && left.spin > -75)
        for claw in [ right, left ] {
            #expect(claw.gravity == 0)
            #expect(simd_length(claw.turn) < 1)
            #expect(claw.extent.x == 0 && claw.extent.z == 0)
            #expect(abs(claw.extent.y) < 1)
            // And what is not centred is unchanged: it throws 149 a second, for the thirtieth of a
            // second its rate curve is open — three or four billboards nine units across.
            #expect(claw.rate > 148 && claw.rate < 150)
            let busy = claw.shapes.rate.keys.filter { $0.value > 0 }
            #expect((busy.last?.time ?? 0) - (busy.first?.time ?? 0) < 0.05)
        }
    }

    /// A swung weapon leaves a ribbon, which is a mechanism apart from the particle systems: the weapon
    /// names a `WeaponTrail`, the blade carries the two anchors it is strung between, and the animation's
    /// own `Swipe…` callbacks say when it runs.
    @Test
    func readsTheTrailASwungWeaponLeaves() throws {
        guard let folder = ProcessInfo.processInfo.environment["GRIM_DAWN_FOLDER"] else { return }

        let gameFolder = URL(fileURLWithPath: folder)
        let database = try GameDatabase(gameFolder: gameFolder)
        let skills = SkillResolver(database: database)
        let renderer = ModelRenderer(gameFolder: gameFolder)
        let resolver = MonsterResolver(
            database: database, skills: skills, items: ItemResolver(database: database, skills: skills)
        )
        let monster = try #require(
            resolver.monster(at: "records/creatures/enemies/skeleton_a01.dbr", level: 50)
        )
        // The weapon is named rather than rolled, so the trail read is this one's own.
        let assembly = ModelAssembly.of(
            monster,
            in: database,
            holding: ModelAssembly.Hands(right: "records/items/enemygear/d307c_dagger.dbr")
        )
        let played = try #require(monster.animations.first { $0.action == "Attack" })
        let animation = try renderer.animation(at: played.path)
        let trail = try #require(
            renderer.trails(of: animation, wearing: assembly, in: database).first
        )

        #expect(trail.hand == .right)
        #expect(trail.image != nil)
        #expect(trail.closes > trail.opens)
        #expect(trail.fades > 0 && trail.fades < 5)
        // The two anchors are the blade's own ends, so they stand apart along it.
        #expect(simd_length(trail.from - trail.to) > 0.2)
    }

    /// A monster's aura lives on the buff its skill points at, never on the skill: read without
    /// following `buffSkillName` the Wight's reaper aura shows nothing at all.
    @Test
    func readsAnAuraOffTheBuffTheSkillPointsAt() throws {
        guard let folder = ProcessInfo.processInfo.environment["GRIM_DAWN_FOLDER"] else { return }

        let gameFolder = URL(fileURLWithPath: folder)
        let database = try GameDatabase(gameFolder: gameFolder)
        let renderer = ModelRenderer(gameFolder: gameFolder)
        let effects = renderer.effects(
            ofSkillAt: "records/skills/nonplayerskillsgdx3/buff/wight_reaperaura.dbr", in: database
        )
        #expect(effects.contains { $0.isDrawable })
    }
}
