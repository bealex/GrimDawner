// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import CoreGraphics
import Foundation
import SceneKit
import simd
import GrimDawnerEngine
import GrimDawnerMesh
import Testing

@testable import GrimDawnerRender

/// The renderer against the installed game, whose folder is machine-specific: set `GRIM_DAWN_FOLDER`
/// to run these, and they skip without it.
struct ModelRendererTests {
    private static var gameFolder: URL? {
        ProcessInfo.processInfo.environment["GRIM_DAWN_FOLDER"].map { URL(fileURLWithPath: $0) }
    }

    /// Every model the creatures' archive holds, read from end to end. A format the reader does not
    /// know shows up here rather than as a hole in the gallery.
    @Test
    func readsEveryCreatureModel() throws {
        guard let folder = Self.gameFolder else { return }

        let renderer = ModelRenderer(gameFolder: folder)
        var read = 0

        for name in try Self.modelNames(in: folder) {
            let mesh = try renderer.mesh(at: "creatures/\(name)")
            guard !mesh.isEmpty else { continue }

            read += 1
            #expect(mesh.triangleCount > 0, "\(name) has no triangles")
            #expect(mesh.indices.allSatisfy { Int($0) < mesh.vertices.count }, "\(name) points past its vertices")
        }
        #expect(read > 400, "read \(read) models")
    }

    /// One model drawn, which is the whole pipeline: archive, mesh, texture, scene, image.
    @MainActor
    @Test
    func drawsAModel() throws {
        guard let folder = Self.gameFolder else { return }

        let renderer = ModelRenderer(gameFolder: folder)
        guard let name = try Self.modelNames(in: folder).first else { return }

        let image = try renderer.image(meshAt: "creatures/\(name)", size: CGSize(width: 64, height: 64))
        #expect(image.width == 64)
        #expect(image.height == 64)
    }

    /// Every animation the game ships, read end to end. The tracks are sized from the header, so a file
    /// that does not add up is a format this reader has wrong rather than one it merely skipped.
    @Test
    func readsEveryAnimation() throws {
        guard let folder = Self.gameFolder else { return }

        var read = 0
        for name in [ "Creatures.arc", "Items.arc", "Level Art.arc", "FX.arc" ] {
            let archive = try ArcArchive(contentsOf: folder.appending(path: "resources/\(name)"))
            for entry in archive.entryNames where entry.hasSuffix(".anm") {
                let bytes = try archive.data(named: entry)
                let animation = try AnmFile(bytes)
                read += 1

                let tracks = animation.tracks.reduce(16) { $0 + 4 + $1.bone.utf8.count + animation.frameCount * 56 }
                #expect(animation.tracks.allSatisfy { $0.keys.count == animation.frameCount }, "\(entry)")
                // What is left over is the events, and a handful of files end in a blank line instead.
                #expect(
                    bytes.count - tracks < 4 || !animation.events.isEmpty,
                    "\(entry) leaves \(bytes.count - tracks) bytes unread"
                )
                #expect(animation.events.allSatisfy { !$0.name.isEmpty }, "\(entry)")
            }
        }
        #expect(read > 1500, "read \(read) animations")
    }

    /// A model posed by an animation is not the model standing still, which is the whole of what the
    /// skeleton, the skin weights and the animation's own transforms are for.
    @MainActor
    @Test
    func posesAModelWithItsAnimation() throws {
        guard let folder = Self.gameFolder else { return }

        let renderer = ModelRenderer(gameFolder: folder)
        let path = "creatures/enemies/yeti/yeti01a.msh"
        let mesh = try renderer.mesh(at: path)
        #expect(mesh.isSkinned)
        #expect(mesh.bones.contains { $0.name == "Target_CTRL" })

        let animation = try renderer.animation(at: "creatures/enemies/yeti/anm/yeti_walk_a01.anm")
        #expect(animation.frameCount > 1)
        #expect(animation.tracks.allSatisfy { track in mesh.bones.contains { $0.name == track.bone } })

        let assembly = ModelAssembly(parts: [ .init(mesh: path, texture: "") ])
        let size = CGSize(width: 96, height: 96)
        let still = try renderer.image(of: assembly, size: size)
        let posed = try renderer.image(of: assembly, size: size, playing: animation, at: animation.frameCount / 2)
        #expect(posed.width == 96)
        #expect(Self.pixels(of: posed) != Self.pixels(of: still))
    }

    /// An armed monster holds something, and it hangs off the hand its rig names.
    @MainActor
    @Test
    func armsAMonsterFromItsOwnTables() throws {
        guard let folder = Self.gameFolder else { return }

        let database = try GameDatabase(gameFolder: folder)
        let skills = SkillResolver(database: database)
        let resolver = MonsterResolver(
            database: database, skills: skills, items: ItemResolver(database: database, skills: skills)
        )
        let renderer = ModelRenderer(gameFolder: folder)
        guard let monster = resolver.monster(at: "records/creatures/enemies/skeleton_a01.dbr", level: 50) else {
            return
        }

        let assembly = ModelAssembly.of(monster, in: database)
        let held = assembly.parts.filter { $0.hand != nil }
        #expect(held.count == 1, "held \(held.map(\.mesh))")
        #expect(held.first?.hand == .right)
        // The roll is primed from the record's own path, so the same monster keeps the same weapon.
        #expect(ModelAssembly.of(monster, in: database).parts.map(\.mesh) == assembly.parts.map(\.mesh))

        let skeleton = ModelSkeleton(meshes: [ try renderer.mesh(at: monster.meshPath) ])
        #expect(skeleton.hand(.right)?.name?.lowercased().contains("weapon") == true)

        let armed = try renderer.image(of: assembly, size: CGSize(width: 96, height: 96))
        let bare = try renderer.image(
            of: ModelAssembly(parts: assembly.parts.filter { $0.hand == nil }),
            size: CGSize(width: 96, height: 96)
        )
        #expect(Self.pixels(of: armed) != Self.pixels(of: bare))
    }

    /// A pose turns bones; it never lengthens them. Reading a key's translation as an offset to the
    /// bone's own stretched skeletons by as much as four times, which is what this pins.
    @MainActor
    @Test
    func posesWithoutStretchingTheSkeleton() throws {
        guard let folder = Self.gameFolder else { return }

        let renderer = ModelRenderer(gameFolder: folder)
        for (model, played) in [
            ("creatures/enemies/woollyrhino/woollyrhino01a.msh",
             "creatures/enemies/woollyrhino/anm/woollyrhino_idle_a01.anm"),
            ("creatures/pc/hero_00_body_noarmor.msh", "creatures/pc/anm/hero01_sword1h_idlecombat.anm"),
            ("creatures/enemies/yeti/yeti01a.msh", "creatures/enemies/yeti/anm/yeti_walk_a01.anm"),
        ] {
            let mesh = try renderer.mesh(at: model)
            let animation = try renderer.animation(at: played)
            let bind = mesh.boneBindTransforms()
            let parents = mesh.boneParents
            let skeleton = ModelSkeleton(meshes: [ mesh ])

            for frame in [ 0, animation.frameCount / 2, animation.frameCount - 1 ] {
                skeleton.pose(animation, at: frame)
                for (index, bone) in mesh.bones.enumerated() {
                    guard let parent = parents[index],
                          let node = skeleton.bones.first(where: { $0.name == bone.name }),
                          let above = skeleton.bones.first(where: { $0.name == mesh.bones[parent].name })
                    else { continue }

                    let was = simd_length(bind[index].columns.3 - bind[parent].columns.3)
                    guard was > 0.05 else { continue }

                    let now = simd_length(
                        simd_float4x4(node.worldTransform).columns.3
                            - simd_float4x4(above.worldTransform).columns.3
                    )
                    #expect(abs(now / was - 1) < 0.01, "\(model) · \(bone.name) on frame \(frame)")
                }
            }
        }
    }

    /// The parts of one monster do not always agree about where a bone stands — 148 of the game's 432
    /// assembled monsters hold one that does not — so each is skinned against its own bind pose. Sharing
    /// the rig's puts a head on backwards.
    @MainActor
    @Test
    func skinsEachPartAgainstItsOwnBindPose() throws {
        guard let folder = Self.gameFolder else { return }

        let renderer = ModelRenderer(gameFolder: folder)
        let troll = try renderer.mesh(at: "creatures/enemies/troll/half-troll_corrupted_01a_bramble.msh")
        let helmet = try renderer.mesh(at: "items/gearhead/head_019_02a.msh")
        let skeleton = ModelSkeleton(meshes: [ troll, helmet ])

        guard
            let head = helmet.bones.firstIndex(where: { $0.name == "Bip01 Head" }),
            let slot = skeleton.bones.firstIndex(where: { $0.name == "Bip01 Head" })
        else { return }

        // The two meshes disagree about this bone by most of its own length.
        let own = helmet.boneBindTransforms()[head]
        let shared = simd_float4x4(skeleton.inverseBindTransforms[slot].caTransform3DValue).inverse
        #expect(simd_length(own.columns.3 - shared.columns.3) > 0.1)

        // What the helmet is skinned with is its own, not the rig's.
        let used = simd_float4x4(skeleton.inverseBindTransforms(of: helmet)[slot].caTransform3DValue)
        #expect(simd_length(used.columns.3 - own.inverse.columns.3) < 0.001)
    }

    /// The camera follows the head, not the shoulders: a fighting stance turns the body most of a
    /// quarter-turn while the head stays where it was looking, and following the body hides the face.
    @MainActor
    @Test
    func followsTheHeadRatherThanTheShoulders() throws {
        guard let folder = Self.gameFolder else { return }

        let renderer = ModelRenderer(gameFolder: folder)
        let mesh = try renderer.mesh(at: "creatures/npcs/humanmale03a.msh")
        let animation = try renderer.animation(at: "creatures/pc/anm/hero01_sword1h_idlecombat.anm")
        let skeleton = ModelSkeleton(meshes: [ mesh ])
        skeleton.pose(animation, at: 0)

        func yaw(of name: String) -> Float {
            guard
                let index = mesh.bones.firstIndex(where: { $0.name == name }),
                let node = skeleton.bones.first(where: { $0.name == name })
            else { return 0 }

            let bind = mesh.boneBindTransforms()[index].columns.2
            let posed = simd_float4x4(node.worldTransform).columns.2
            return abs(atan2(
                bind.z * posed.x - bind.x * posed.z,
                bind.x * posed.x + bind.z * posed.z
            )) * 180 / .pi
        }

        #expect(yaw(of: "Bip01 Spine1") > 30, "the stance should turn the shoulders")
        #expect(yaw(of: "Bip01 Head") < 15, "the head should keep looking where it was")
        #expect(abs(skeleton.turn()) * 180 / .pi < 15, "the camera should follow the head")
    }

    /// A knee bends backwards and an elbow forwards, in every animation a human plays. This is what
    /// says a key's rotation is read the right way round: read as written, every joint bends the other
    /// way, which looks plausible in a still and wrong the moment it moves.
    @MainActor
    @Test
    func bendsJointsTheWayAJointBends() throws {
        guard let folder = Self.gameFolder else { return }

        let renderer = ModelRenderer(gameFolder: folder)
        let mesh = try renderer.mesh(at: "creatures/npcs/humanmale03a.msh")
        let skeleton = ModelSkeleton(meshes: [ mesh ])

        func place(_ name: String) -> SIMD3<Float> {
            guard let node = skeleton.bones.first(where: { $0.name == name }) else { return .zero }

            let matrix = simd_float4x4(node.worldTransform).columns.3
            return SIMD3(matrix.x, matrix.y, matrix.z)
        }
        /// Which way the limb below swings out of line with the limb above, along the way it faces.
        func bend(_ above: String, _ joint: String, _ below: String) -> Float {
            let along = place(joint) - place(above)
            let next = place(below) - place(joint)
            return (next - along * (simd_dot(next, along) / simd_dot(along, along))).z
        }

        for file in [ "hero01_walk_a01", "hero01_sword1h_idlecombat" ] {
            let animation = try renderer.animation(at: "creatures/pc/anm/\(file).anm")
            for frame in stride(from: 0, to: animation.frameCount, by: 5) {
                skeleton.pose(animation, at: frame)
                #expect(bend("Bip01 L Thigh", "Bip01 L Calf", "Bip01 L Foot") < 0.01, "\(file) frame \(frame)")
                #expect(bend("Bip01 L UpperArm", "Bip01 L Forearm", "Bip01 L Hand") > -0.01, "\(file) frame \(frame)")
            }
        }
    }

    /// What an animation spawns, where it hangs it, and the picture its particles are drawn with.
    @MainActor
    @Test
    func readsWhatAnAnimationSpawns() throws {
        guard let folder = Self.gameFolder else { return }

        let database = try GameDatabase(gameFolder: folder)
        let renderer = ModelRenderer(gameFolder: folder)
        let animation = try renderer.animation(at: "creatures/enemies/yeti/anm/yeti_attack_tripleswipe.anm")

        let effects = renderer.effects(of: animation, in: database)
        #expect(effects.count == 3)
        #expect(effects.allSatisfy { $0.attachment == "FXForward" })
        #expect(effects.allSatisfy { $0.image != nil }, "each should carry the texture its particles use")
        #expect(effects.compactMap(\.frame) == effects.compactMap(\.frame).sorted())

        // and the model names the point they hang from
        let mesh = try renderer.mesh(at: "creatures/enemies/yeti/yeti01a.msh")
        #expect(mesh.attachments.contains { $0.name == "FXForward" })
        #expect(mesh.attachments.contains { $0.name == "L Hand" && $0.parent == "BN_LHand" })
    }

    /// Motion at thirty frames a second is smooth. A key holds its turn in two quaternions, and reading
    /// only the first leaves a wight's spine jumping ninety degrees between one frame and the next —
    /// legs walking calmly under a torso having a fit.
    @Test
    func readsBothHalvesOfAKeysTurn() throws {
        guard let folder = Self.gameFolder else { return }

        let renderer = ModelRenderer(gameFolder: folder)
        let animation = try renderer.animation(at: "creatures/enemies/wight/anm/wight02a_run_01a.anm")

        var biggest = Float(0)
        var offender = ""
        for track in animation.tracks {
            for frame in 1 ..< track.keys.count {
                let dot = abs(simd_dot(
                    simd_normalize(track.keys[frame - 1].rotation).vector,
                    simd_normalize(track.keys[frame].rotation).vector
                ))
                let step = 2 * acos(min(dot, 1)) * 180 / .pi
                if step > biggest { biggest = step; offender = track.bone }
            }
        }
        #expect(biggest < 40, "\(offender) turns \(Int(biggest))° in one frame")
    }

    /// What a skill puts on the creature that has it: a passive's aura hangs off a point of the model,
    /// and a cast's own effects are centred on it.
    @MainActor
    @Test
    func readsWhatASkillPutsOnACreature() throws {
        guard let folder = Self.gameFolder else { return }

        let database = try GameDatabase(gameFolder: folder)
        let skills = SkillResolver(database: database)
        let resolver = MonsterResolver(
            database: database, skills: skills, items: ItemResolver(database: database, skills: skills)
        )
        let renderer = ModelRenderer(gameFolder: folder)
        guard
            let monster = resolver.monster(
                at: "records/creatures/enemies/boss&quest/wight_scarstone_02.dbr", level: 50
            )
        else { return }

        let passive = monster.abilities
            .filter { $0.role == .passive }
            .flatMap { renderer.effects(ofSkillAt: $0.skill.recordPath, in: database) }
        #expect(passive.contains { $0.attachment == "HeadFXUP" }, "the rune it carries hangs over its head")
        #expect(passive.allSatisfy { $0.frame == nil }, "an aura holds rather than starting on a frame")
        #expect(passive.contains { $0.image != nil })

        let cast = monster.abilities
            .filter { $0.role != .passive }
            .flatMap { renderer.effects(ofSkillAt: $0.skill.recordPath, in: database) }
        #expect(cast.count > 3)
        #expect(cast.contains { $0.image != nil })
    }

    /// An effect that names no point of its own is centred on the creature, which is not the middle of
    /// its bounding box: N'erfatal's tail drags that six units behind it, and what it channels was hung
    /// out there in the air.
    @MainActor
    @Test
    func centresAnEffectOnTheCreatureRatherThanItsBox() throws {
        guard let folder = Self.gameFolder else { return }

        let database = try GameDatabase(gameFolder: folder)
        let skills = SkillResolver(database: database)
        let resolver = MonsterResolver(
            database: database, skills: skills, items: ItemResolver(database: database, skills: skills)
        )
        let renderer = ModelRenderer(gameFolder: folder)
        let monster = try #require(
            resolver.monster(at: "records/creatures/enemies/special/beaver_01.dbr", level: 100)
        )
        let channel = try #require(monster.animations.first { $0.title == "Channel" })

        let effects = monster.abilities
            .filter { $0.animation?.path == channel.path }
            .flatMap { renderer.effects(ofSkillAt: $0.skill.recordPath, in: database) }
        #expect(effects.contains { $0.attachment.isEmpty }, "this one names no point of its own")

        let models = renderer.models(of: ModelAssembly.of(monster, in: database))
        let scene = ModelScene().scene(for: models, playing: try renderer.animation(at: channel.path), at: 0,
                                       showing: effects)

        func planes(_ node: SCNNode) -> [SIMD3<Float>] {
            let own = node.geometry is SCNPlane
                ? [ SIMD3(node.simdWorldTransform.columns.3.x, node.simdWorldTransform.columns.3.y,
                          node.simdWorldTransform.columns.3.z) ]
                : []
            return own + node.childNodes.flatMap { planes($0) }
        }
        let drawn = planes(scene.rootNode)
        #expect(!drawn.isEmpty, "the effect should be somewhere")

        let mesh = try renderer.mesh(at: monster.meshPath)
        let box = (mesh.bounds.minimum + mesh.bounds.maximum) / 2
        for place in drawn {
            // The body stands around the origin; the box's middle is dragged back by the tail.
            #expect(abs(place.z) < abs(box.z), "hung at \(place), the box's middle is \(box)")
        }
    }

    private static func pixels(of image: CGImage) -> Data {
        image.dataProvider?.data as Data? ?? Data()
    }

    private static func modelNames(in folder: URL) throws -> [String] {
        let archive = try ArcArchive(contentsOf: folder.appending(path: "resources/Creatures.arc"))
        return archive.entryNames.filter { $0.hasSuffix(".msh") }.sorted()
    }
}
