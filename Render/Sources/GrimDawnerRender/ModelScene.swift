// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation
import GrimDawnerEngine
import GrimDawnerMesh
import SceneKit

/// How a model is lit and framed. One configuration renders the whole roster, so a wisp and a colossus
/// come out looking like they belong to the same book.
public struct SceneConfiguration: Sendable {
    /// Where the camera sits, in degrees around the model and above it.
    public var turn: Float = 35
    public var pitch: Float = 12
    /// How much room to leave around the model, as a share of its own size.
    public var margin: Float = 1.06
    /// How much wider to frame a model that is moving. An animation reaches well outside the bounds the
    /// model is stored with — a swing, a leap, a slam — and framing it as a still cuts the arm off.
    public var movingMargin: Float = 1.5
    /// What the model stands against. Nothing, by default: an image with a transparent background drops
    /// into whatever panel shows it, and a floor would come with it.
    public var background: (red: Double, green: Double, blue: Double)?
    /// Whether the ground catches a shadow. A shadow needs a floor to fall on, and a floor is the one
    /// thing a transparent background cannot have.
    public var castsShadow = false
    /// Whether to turn texture coordinates upside down. Nothing needs it: the decoder hands SceneKit an
    /// image whose first row is its top, and SceneKit reads it from there, so the game's own coordinates
    /// land as written. It is here because a face upside down is the first thing a wrong guess looks
    /// like, and this is the knob that says so.
    public var flipsTexture = false
    /// Whether an effect is emitted as a drift of particles or held as one picture. Particles need a
    /// view that keeps drawing to emit at all — a still taken in one pass would catch none of them — so
    /// a live view turns this on and an offline render leaves it off.
    public var emitsEffects = false
    /// How far the frame may grow to take in an effect, in multiples of the creature's own size. A nova
    /// covers seven units around a creature two tall, and framing all of it would leave the creature a
    /// speck, so the frame opens this far and anything bigger spills out of it.
    public var effectMargin: Float = 1.6
    /// How brightly the model is lit. The game's own art is painted dark, so a plain three-point rig
    /// leaves it in the murk; this scales the whole rig at once.
    public var exposure: CGFloat = 2.2

    public init() {}
}

/// A model ready to be drawn: what it is made of, what it is painted with, and — for a weapon — the hand
/// it is held in rather than a place of its own.
/// A model ready to draw: the mesh, and one skin per material it names.
///
/// Unchecked because a `CGImage` is not `Sendable` on paper; the pictures here are decoded once and
/// never written to again.
public struct DrawnModel: @unchecked Sendable {
    public let mesh: MshFile
    /// One skin per material the model names.
    public let textures: [CGImage?]
    public let hand: ModelAssembly.Hand?

    public init(mesh: MshFile, textures: [CGImage?], hand: ModelAssembly.Hand? = nil) {
        self.mesh = mesh
        self.textures = textures
        self.hand = hand
    }
}

/// Builds a SceneKit scene from one of the game's models.
///
/// The game's models are Y-up and stand at the origin, and their vertices are already in the bind pose,
/// so a still needs neither the skeleton nor an animation. Hand it an animation and the models are
/// skinned to one merged rig and posed by it instead.
public struct ModelScene {
    public init(configuration: SceneConfiguration = SceneConfiguration()) {
        self.configuration = configuration
    }

    public let configuration: SceneConfiguration

    public func scene(for mesh: MshFile, texture: CGImage?) -> SCNScene {
        scene(for: [ DrawnModel(mesh: mesh, textures: [ texture ]) ])
    }

    /// Several models drawn together: a human is a head plus what it wears, all in one bind pose. Each
    /// model brings one skin per material it names, and an animation moves the lot of them.
    /// An animation given a frame holds that pose and stands still, which is what a picture of it is;
    /// given none it loops, which is what a view of it is.
    public func scene(
        for models: [DrawnModel],
        playing animation: AnmFile? = nil,
        at frame: Int? = nil,
        speed: Double = 1,
        showing effects: [ModelEffect] = []
    ) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents =
            configuration.background.map {
                NSColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: 1)
            } ?? NSColor.clear

        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

        let drawn = models.filter { !$0.mesh.isEmpty }
        // The rig is needed to pose the models and to hang a weapon off a hand; a still with neither
        // draws every vertex where it already stands, and building one would change nothing.
        let rigged = animation != nil || drawn.contains { $0.hand != nil } || !effects.isEmpty
        let skeleton = rigged
            ? ModelSkeleton(meshes: drawn.filter { $0.hand == nil }.map(\.mesh)).nonEmpty
            : nil
        if let skeleton { scene.rootNode.addChildNode(skeleton.root) }

        for model in drawn {
            let held = model.hand.flatMap { skeleton?.hand($0) }
            // A weapon that has no hand to hang from would lie at the model's feet, so it is not drawn.
            if model.hand != nil, held == nil { continue }

            for node in nodes(for: model.mesh, textures: model.textures, skeleton: held == nil ? skeleton : nil) {
                (held ?? scene.rootNode).addChildNode(node)
                node.skinner?.skeleton = skeleton?.root
            }

            let placement = held.map { simd_float4x4($0.worldTransform) } ?? matrix_identity_float4x4
            for corner in corners(of: model.mesh.bounds) {
                let placed = (placement * SIMD4(corner, 1)).xyz
                minimum = SIMD3(
                    Swift.min(minimum.x, placed.x), Swift.min(minimum.y, placed.y), Swift.min(minimum.z, placed.z)
                )
                maximum = SIMD3(
                    Swift.max(maximum.x, placed.x), Swift.max(maximum.y, placed.y), Swift.max(maximum.z, placed.z)
                )
            }
        }
        guard minimum.x <= maximum.x else { return scene }

        var turned = Float(0)
        if let skeleton, let animation {
            // Posed first whatever happens: an animation is written facing wherever the game had the
            // creature facing, and the camera has to be told how far that is from the model's own.
            skeleton.pose(animation, at: frame ?? 0)
            turned = skeleton.turn()
            // A pose carries the creature away from where it stands in the bind: The Dread rears up to
            // smash, and framing the bind pose leaves it drawn above the picture. The posed bones say
            // where it has gone, so they are what the frame is taken from.
            let posed = skeleton.posedBounds()
            if posed.minimum.x <= posed.maximum.x {
                let padding = (maximum - minimum) * 0.15
                minimum = simd_min(minimum, posed.minimum - padding)
                maximum = simd_max(maximum, posed.maximum + padding)
            }
            if frame == nil { skeleton.play(animation, speed: speed) }
        }

        let body = max(max(maximum.x - minimum.x, maximum.y - minimum.y), maximum.z - minimum.z) / 2
        var reached = Float(0)
        var aimed: (minimum: SIMD3<Float>, maximum: SIMD3<Float>)?
        if !effects.isEmpty {
            let attachments = drawn.flatMap { $0.mesh.attachments }
            for effect in effects {
                guard effect.isDrawable else { continue }

                // A fired thing crosses the world rather than hanging on the rig, so its copies are
                // built apart and parented to the scene itself.
                if let flight = effect.flight {
                    for node in launched(
                        effect, flying: flight, among: attachments, of: skeleton, models: drawn,
                        animation: animation, frame: frame, speed: speed, facing: turned
                    ) {
                        scene.rootNode.addChildNode(node)
                    }
                    continue
                }

                let placed = place(effect, among: attachments, of: skeleton)
                let reach = self.reach(of: effect, on: drawn)
                reached = max(reached, reach)
                var at = placed?.transform ?? middle(of: drawn)
                // A wave sweeps out from where it hangs rather than sitting on it, so it is carried
                // half its own reach along the way the point it hangs on already leans.
                if effect.isWave {
                    at = swept(at, on: placed?.parent, by: reach)
                    // Aimed away from the creature, so the frame has to take in where it lands: a sweep
                    // drawn off the edge of the picture says nothing about where the creature swept it.
                    let parent = placed.map { simd_float4x4($0.parent.worldTransform) } ?? matrix_identity_float4x4
                    let centre = (parent * at).columns.3.xyz
                    aimed = (
                        simd_min(aimed?.minimum ?? centre, centre - reach),
                        simd_max(aimed?.maximum ?? centre, centre + reach)
                    )
                }
                let node =
                    effect.model.map {
                        thrown($0, of: effect, at: at, frame: frame, speed: speed)
                    }
                    ?? effect.image.map {
                        spark($0, at: at, of: effect, in: animation, reach: reach, frame: frame, speed: speed)
                    }
                guard let node else { continue }

                (placed?.parent ?? scene.rootNode).addChildNode(node)
            }
        }
        if let aimed {
            minimum = simd_min(minimum, aimed.minimum)
            maximum = simd_max(maximum, aimed.maximum)
        }

        let centre = (minimum + maximum) / 2
        let size = maximum - minimum
        // An effect that radiates around the creature opens the frame only so far — past that the
        // creature costs more than the effect is worth. One aimed somewhere is already in the bounds.
        let framed = max(size.x, max(size.y, size.z)) / 2
        let radius = min(max(body, reached), max(body * configuration.effectMargin, framed))
            * (animation == nil ? 1 : configuration.movingMargin)

        scene.rootNode.addChildNode(camera(around: centre, radius: max(radius, 0.001), turned: turned))
        for light in lights(around: centre, radius: max(radius, 0.001)) { scene.rootNode.addChildNode(light) }
        if configuration.castsShadow {
            scene.rootNode.addChildNode(ground(under: centre, minimum: minimum.y, radius: radius))
        }
        return scene
    }

    /// Where an effect hangs.
    ///
    /// The name it carries is a point of the model or a bone of the rig, and an effect that names
    /// neither is one the game centres on the creature — which is not the middle of its bounding box: a
    /// tail or a wing drags that well off the body. The models themselves say where their middle is,
    /// and a creature that does not is held by the bone the rest of it hangs from.
    private func place(
        _ effect: ModelEffect,
        among attachments: [MshFile.Attachment],
        of skeleton: ModelSkeleton?
    ) -> (parent: SCNNode, transform: simd_float4x4)? {
        func attachment(_ name: String) -> (parent: SCNNode, transform: simd_float4x4)? {
            guard
                let found = attachments.first(where: { $0.name.lowercased() == name.lowercased() })
            else { return nil }

            return skeleton?.node(for: found)
        }

        if !effect.attachment.isEmpty {
            if let found = attachment(effect.attachment) { return found }
            if let bone = skeleton?.bone(named: effect.attachment) {
                return (bone, matrix_identity_float4x4)
            }
        }
        for name in [ "FXCentered", "FXUnParentedCenter", "Upper Body", "Target" ] {
            if let found = attachment(name) { return found }
        }
        return skeleton?.trunk().map { ($0, matrix_identity_float4x4) }
    }

    /// The middle of the models, where an effect that names no point of its own is shown.
    private func middle(of models: [DrawnModel]) -> simd_float4x4 {
        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for model in models where model.hand == nil {
            minimum = simd_min(minimum, model.mesh.bounds.minimum)
            maximum = simd_max(maximum, model.mesh.bounds.maximum)
        }
        guard minimum.x <= maximum.x else { return matrix_identity_float4x4 }

        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4((minimum + maximum) / 2, 1)
        return transform
    }

    /// The same placement carried forward by a wave's reach.
    ///
    /// The game hangs a wave off a point that already stands out in front of the caster — `FXForward` —
    /// so which way is forward is the way that point stands from the creature's own middle, along the
    /// ground. The step has to be taken in the world and put back into the bone's own frame, since
    /// inside a bone "forward" is whichever way that bone happens to point. A point standing over the
    /// creature rather than in front of it says nothing about direction and is left where it is.
    private func swept(_ transform: simd_float4x4, on parent: SCNNode?, by reach: Float) -> simd_float4x4 {
        let toWorld = parent.map { simd_float4x4($0.worldTransform) } ?? matrix_identity_float4x4
        let place = (toWorld * transform).columns.3.xyz
        let along = SIMD3(place.x, 0, place.z)
        guard simd_length(along) > 0.001 else { return transform }

        var world = toWorld * transform
        world.columns.3 = SIMD4(place + simd_normalize(along) * reach, 1)
        return toWorld.inverse * world
    }

    /// How far an effect reaches, which is what it is drawn across.
    ///
    /// The skill that throws it says so, and a model is in the same units — a creature stands a couple
    /// of them tall and a nova reaches seven — so one cast reads as bigger than another because it is.
    /// Nothing in the records states the reach of an aura or of what an animation puffs out — the
    /// particle system holds that, and it is a binary format this does not read — so those are measured
    /// against the creature instead: the whole of it for one centred on it, a limb's worth for one hung
    /// off a limb.
    private func reach(of effect: ModelEffect, on models: [DrawnModel]) -> Float {
        if let radius = effect.radius { return max(radius, 0.05) }

        let span = span(of: models)
        return (Self.isCentred(effect.attachment) ? span : span / 3) / 2
    }

    /// Whether an attachment means the creature itself rather than a point on it.
    ///
    /// The game's own vocabulary, counted across `records/fx`: `FXCentered` on 376 records and
    /// `FXUnParentedCenter` on 221 wrap the whole creature, where `HeadFXUP`, `R Hand` and the rest name
    /// a place to hang something off. Reading a centred one as a point is what made an aura a puff on
    /// the chest.
    private static func isCentred(_ attachment: String) -> Bool {
        guard !attachment.isEmpty else { return true }

        let name = attachment.lowercased()
        return name.contains("center") || name.contains("aura")
    }

    /// How big the models are, which is what an effect the game does not size is sized against.
    private func span(of models: [DrawnModel]) -> Float {
        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for model in models where model.hand == nil {
            minimum = simd_min(minimum, model.mesh.bounds.minimum)
            maximum = simd_max(maximum, model.mesh.bounds.maximum)
        }
        guard minimum.x <= maximum.x else { return 1 }

        let size = maximum - minimum
        return max(max(size.x, max(size.y, size.z)), 0.1)
    }

    /// What a skill fires, sent on its way: the stated number of copies leave the launch point, fan
    /// across the stated arc, and each crosses the stated distance at the stated speed, gone when it
    /// arrives. They fly through the world rather than riding the rig — a launched thing does not
    /// follow the mouth that spat it — and the flight starts on the animation's hit callback, which is
    /// the frame the game itself lets go on.
    private func launched(
        _ effect: ModelEffect,
        flying flight: ModelEffect.Flight,
        among attachments: [MshFile.Attachment],
        of skeleton: ModelSkeleton?,
        models: [DrawnModel],
        animation: AnmFile?,
        frame: Int?,
        speed: Double,
        facing turned: Float
    ) -> [SCNNode] {
        // The launch point and the facing are both read with the rig posed on the launch frame, since
        // that is where the mouth stands and where the head aims when the game lets go. Setting the
        // pose only writes the bones' resting values, so a playing animation carries on over it
        // untouched.
        var launch = middle(of: models).columns.3.xyz
        var yaw = turned
        if let placed = place(effect, among: attachments, of: skeleton) {
            if let skeleton, let animation, let starts = effect.frame {
                skeleton.pose(animation, at: starts)
                launch = (simd_float4x4(placed.parent.worldTransform) * placed.transform).columns.3.xyz
                yaw = skeleton.turn()
                skeleton.pose(animation, at: frame ?? 0)
            } else {
                launch = (simd_float4x4(placed.parent.worldTransform) * placed.transform).columns.3.xyz
            }
        }

        // Which way is out: wherever the creature is facing as it lets go. The models face +Z in the
        // bind pose — every forward point sits at positive Z — and the pose's yaw carries that round,
        // measured off the head where there is one, which is what aims a spit.
        let forward = SIMD3<Float>(sin(yaw), 0, cos(yaw))

        let arc = flight.arc * .pi / 180
        let time = Double(flight.distance / max(flight.velocity, 0.1))
        return (0 ..< flight.count).map { index in
            // A full circle spaces the copies evenly all the way round; anything less is a fan centred
            // on the way out.
            let yaw: Float =
                arc >= 2 * .pi * 0.99
                ? 2 * .pi * Float(index) / Float(flight.count)
                : (flight.count > 1 ? arc * (Float(index) / Float(flight.count - 1) - 0.5) : 0)
            let direction = SIMD3<Float>(
                forward.x * cos(yaw) + forward.z * sin(yaw), 0,
                -forward.x * sin(yaw) + forward.z * cos(yaw)
            )
            return one(effect, from: launch, along: direction, over: time,
                       flying: flight, models: models, animation: animation, frame: frame, speed: speed)
        }
    }

    /// One copy of a fired thing: its own model where the record names one, its flight texture riding
    /// along, moving out from the launch point and gone when it arrives.
    private func one(
        _ effect: ModelEffect,
        from launch: SIMD3<Float>,
        along direction: SIMD3<Float>,
        over time: Double,
        flying flight: ModelEffect.Flight,
        models: [DrawnModel],
        animation: AnmFile?,
        frame: Int?,
        speed: Double
    ) -> SCNNode {
        let node = SCNNode()
        if let model = effect.model {
            for part in nodes(for: model.mesh, textures: model.textures, skeleton: nil) {
                part.simdScale = SIMD3(repeating: effect.scale)
                node.addChildNode(part)
            }
            // Pointed the way it flies: a bolt or a spike is modelled along an axis, and standing
            // still sideways it reads as debris.
            node.simdOrientation = simd_quatf(angle: atan2(direction.x, direction.z), axis: SIMD3(0, 1, 0))
        }
        if let image = effect.image {
            // The record's radius is the thing's physics, not its picture, and the picture is what is
            // being stood in for — so it never draws smaller than can be seen.
            let half = flight.size > 0 ? max(flight.size, 0.3) : min(max(span(of: models) * 0.15, 0.4), 1.6)
            let rider = SCNNode(geometry: sprite(image, reach: half))
            rider.constraints = [ SCNBillboardConstraint() ]
            rider.renderingOrder = 10
            node.addChildNode(rider)
        }
        node.position = SCNVector3(launch.x, launch.y, launch.z)

        let landing = launch + direction * flight.distance

        // Held on one frame: the copy stands as far along as the flight had got by then.
        if let frame {
            let rate = Double(max(animation?.framesPerSecond ?? 30, 1))
            let since = Double(frame - (effect.frame ?? 0)) / rate
            if since < 0 || since > time {
                node.opacity = 0
            } else {
                let gone = launch + direction * flight.velocity * Float(since)
                node.position = SCNVector3(gone.x, gone.y, gone.z)
            }
            return node
        }

        // Playing alongside an animation: launched on its frame, timed against the same clock the
        // skeleton loops on, so the copy leaves when the blow lands every time round.
        if let animation, animation.duration > 0 {
            let rate = Double(max(animation.framesPerSecond, 1))
            let start = min(Double(effect.frame ?? 0) / rate / animation.duration, 1)
            let end = min(start + time / animation.duration, 1)
            let covered = direction * flight.velocity * Float((end - start) * animation.duration)
            let target = launch + covered

            let moving = CAKeyframeAnimation(keyPath: "position")
            moving.values = [
                SCNVector3(launch.x, launch.y, launch.z), SCNVector3(launch.x, launch.y, launch.z),
                SCNVector3(target.x, target.y, target.z), SCNVector3(target.x, target.y, target.z),
            ]
            moving.keyTimes = [ 0, NSNumber(value: start), NSNumber(value: end), 1 ]
            moving.duration = animation.duration / speed
            moving.repeatCount = .infinity
            moving.calculationMode = .linear
            moving.isRemovedOnCompletion = false
            node.addAnimation(moving, forKey: "flight")

            let step = min(0.02, max((end - start) / 4, 0.001))
            let showing = CAKeyframeAnimation(keyPath: "opacity")
            showing.values = [ 0, 0, 1, 1, 0, 0 ]
            showing.keyTimes = [
                0, NSNumber(value: start), NSNumber(value: start + step),
                NSNumber(value: max(end - step, start + step)), NSNumber(value: end), 1,
            ]
            showing.duration = animation.duration / speed
            showing.repeatCount = .infinity
            showing.calculationMode = .linear
            showing.isRemovedOnCompletion = false
            node.opacity = 0
            node.addAnimation(showing, forKey: "showing")
            return node
        }

        // On a still creature the flight loops on a clock of its own: out, gone, back, again.
        node.opacity = 0
        let delta = landing - launch
        node.runAction(.repeatForever(.sequence([
            .fadeOpacity(to: 1, duration: 0.05),
            .move(by: SCNVector3(delta.x, delta.y, delta.z), duration: time / speed),
            .fadeOpacity(to: 0, duration: 0.1),
            .move(to: SCNVector3(launch.x, launch.y, launch.z), duration: 0),
            .wait(duration: 0.5),
        ])))
        return node
    }

    /// The effect itself: the texture its particles are drawn with, facing the camera at the point the
    /// game spawns it, lit up on the frame it is called for and gone again a moment later.
    private func spark(
        _ image: CGImage,
        at transform: simd_float4x4,
        of effect: ModelEffect,
        in animation: AnmFile?,
        reach: Float,
        frame: Int?,
        speed: Double
    ) -> SCNNode {
        // An effect with no frame of its own holds for as long as it is shown — the aura a passive
        // carries — and holding still is not what an effect does, so a view that keeps drawing emits it.
        guard let starts = effect.frame, let animation else {
            guard configuration.emitsEffects else {
                let node = SCNNode(geometry: sprite(image, reach: reach))
                node.simdTransform = transform
                node.constraints = [ SCNBillboardConstraint() ]
                node.renderingOrder = 10
                return node
            }

            let node = SCNNode()
            node.simdTransform = transform
            node.addParticleSystem(cloud(image, reach: reach))
            return node
        }

        let node = SCNNode(geometry: sprite(image, reach: reach))
        node.simdTransform = transform
        node.constraints = [ SCNBillboardConstraint() ]
        node.renderingOrder = 10

        // A still shows what is up at that moment; a playing scene lights it as the frame comes round.
        guard frame == nil else {
            node.opacity = abs(frame! - starts) <= 2 ? 1 : 0
            return node
        }

        let showing = CAKeyframeAnimation(keyPath: "opacity")
        showing.values = (0 ..< animation.frameCount).map { frame -> NSNumber in
            let since = frame - starts
            return NSNumber(value: since < 0 || since > 8 ? 0 : 1 - Double(since) / 8)
        }
        showing.duration = animation.duration / speed
        showing.repeatCount = .infinity
        showing.calculationMode = .linear
        showing.isRemovedOnCompletion = false
        node.opacity = 0
        node.addAnimation(showing, forKey: "spark")
        return node
    }

    /// A model an effect throws — the chunks a stomp breaks the ground into — placed where the game
    /// hangs it and drawn at the size its record states.
    ///
    /// It is a model like the creature's own rather than a picture, so it is built the same way and
    /// simply put where the effect points. Its own animation is not played: an `FxMesh` names one, and
    /// what that does to the model is its own business rather than the creature's.
    private func thrown(
        _ model: DrawnModel,
        of effect: ModelEffect,
        at transform: simd_float4x4,
        frame: Int?,
        speed: Double
    ) -> SCNNode {
        let node = SCNNode()
        // A rig of its own: the effect's animation drives its own bones, not the creature's.
        let skeleton = ModelSkeleton(meshes: [ model.mesh ]).nonEmpty
        if let skeleton { node.addChildNode(skeleton.root) }

        for part in nodes(for: model.mesh, textures: model.textures, skeleton: skeleton) {
            node.addChildNode(part)
            part.skinner?.skeleton = skeleton?.root
        }

        if let skeleton, let motion = effect.motion {
            if let frame {
                // The creature's animation is held on one frame, so the effect is held as far into its
                // own as it had got by then — it starts on the frame that spawned it, not on frame nought.
                skeleton.pose(motion, at: max(0, frame - (effect.frame ?? 0)))
            } else {
                skeleton.pose(motion, at: 0)
                skeleton.play(motion, speed: speed)
            }
        }

        node.simdTransform = transform
        node.simdScale = SIMD3(repeating: effect.scale)
        return node
    }

    /// One picture of an effect, facing the camera and lit rather than lying flat. A still has only the
    /// one picture to say how far the effect goes with, so it is drawn across the whole of it.
    private func sprite(_ image: CGImage, reach: Float) -> SCNPlane {
        let plane = SCNPlane(width: CGFloat(reach * 2), height: CGFloat(reach * 2))
        plane.firstMaterial?.diffuse.contents = image
        plane.firstMaterial?.lightingModel = .constant
        plane.firstMaterial?.blendMode = .add
        plane.firstMaterial?.isDoubleSided = true
        plane.firstMaterial?.writesToDepthBuffer = false
        // Drawn over the creature rather than inside it: an effect centred on a body sits in its chest,
        // and the game's own are added over what they cover.
        plane.firstMaterial?.readsFromDepthBuffer = false
        return plane
    }

    /// An effect as the game shows it: not one picture pinned in place but a drift of them, rising and
    /// fading from the point it hangs on. The particles the game itself emits are a format of their own,
    /// so the shape of the drift is this app's, and only the picture is the game's.
    private func cloud(_ image: CGImage, reach: Float) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.particleImage = image
        // The reach is how far the drift spreads, not how big one spark in it is: a nova that covers
        // seven units is a great many small sparks over that ground rather than a few half-its-size —
        // sized past a unit they read as playing cards and an area effect whites the frame out.
        let spark = min(max(reach * 0.18, 0.2), 0.9)
        system.particleSize = CGFloat(spark)
        system.particleSizeVariation = CGFloat(spark * 0.35)
        // A wider drift needs more of them to read as one cloud rather than as a scattering — but only
        // just. These are drawn additively over one another, so a rate that reads as lively on one
        // effect blows out to a white smear once a cast throws six at once.
        system.birthRate = CGFloat(10 + 5 * min(reach, 8))
        system.particleLifeSpan = 0.7
        system.particleLifeSpanVariation = 0.25
        system.emitterShape = SCNSphere(radius: CGFloat(reach * 0.7))
        system.birthLocation = .volume
        system.emittingDirection = SCNVector3(0, 1, 0)
        system.spreadingAngle = 35
        // A shimmer over the ground it covers rather than a column climbing off it.
        system.particleVelocity = CGFloat(reach * 0.12)
        system.particleVelocityVariation = CGFloat(reach * 0.08)
        system.acceleration = SCNVector3(0, reach * 0.05, 0)
        system.particleAngularVelocity = 18
        system.particleAngularVelocityVariation = 40
        system.blendMode = .additive
        system.isLightingEnabled = false
        system.isAffectedByGravity = false
        system.sortingMode = .none
        system.loops = true
        // Fades in as it is born and out as it dies, so nothing pops.
        let fading = CAKeyframeAnimation(keyPath: "opacity")
        fading.values = [ 0, 0.55, 0.45, 0 ]
        fading.keyTimes = [ 0, 0.15, 0.6, 1 ]
        fading.duration = 1
        let controller = SCNParticlePropertyController(animation: fading)
        system.propertyControllers = [ .opacity: controller ]
        return system
    }

    /// The eight corners of a box, which is what a part hung off a bone has to be measured by: it is
    /// modelled at the origin, and where it ends up is wherever the hand holding it is.
    private func corners(of bounds: (minimum: SIMD3<Float>, maximum: SIMD3<Float>)) -> [SIMD3<Float>] {
        [ bounds.minimum.x, bounds.maximum.x ].flatMap { x in
            [ bounds.minimum.y, bounds.maximum.y ].flatMap { y in
                [ bounds.minimum.z, bounds.maximum.z ].map { z in SIMD3(x, y, z) }
            }
        }
    }

    /// One node per group, so a part wears its own skin and hangs off its own bones.
    ///
    /// A group's four bone slots index a list of its own rather than the skeleton, so its vertices are
    /// compacted into a buffer of their own — the same vertex in two groups is written twice, which is
    /// what keeps each copy pointing at the right bones.
    private func nodes(for mesh: MshFile, textures: [CGImage?], skeleton: ModelSkeleton?) -> [SCNNode] {
        mesh.groups.compactMap { group in
            let first = group.firstTriangle * 3
            let end = min(first + group.triangleCount * 3, mesh.indices.count)
            guard first < end else { return nil }

            var order = [Int]()
            var places = [Int32](repeating: -1, count: mesh.vertices.count)
            var indices = [Int32]()
            for index in mesh.indices[first ..< end] {
                let vertex = Int(index)
                guard mesh.vertices.indices.contains(vertex) else { continue }

                if places[vertex] < 0 {
                    places[vertex] = Int32(order.count)
                    order.append(vertex)
                }
                indices.append(places[vertex])
            }
            guard !indices.isEmpty else { return nil }

            let vertices = order.map { mesh.vertices[$0] }

            let geometry = SCNGeometry(
                sources: [
                    SCNGeometrySource(vertices: vertices.map { SCNVector3($0.position.x, $0.position.y, $0.position.z) }),
                    SCNGeometrySource(normals: vertices.map { SCNVector3($0.normal.x, $0.normal.y, $0.normal.z) }),
                    SCNGeometrySource(textureCoordinates: vertices.map {
                        CGPoint(
                            x: CGFloat($0.texture.x),
                            y: configuration.flipsTexture ? CGFloat(1 - $0.texture.y) : CGFloat($0.texture.y)
                        )
                    }),
                ],
                elements: [ SCNGeometryElement(indices: indices, primitiveType: .triangles) ]
            )
            geometry.materials = [ material(with: textures.indices.contains(group.material)
                ? textures[group.material] : textures.first ?? nil) ]

            let node = SCNNode(geometry: geometry)
            if let skeleton, !group.bones.isEmpty {
                node.skinner = skin(vertices, to: skeleton.skeletonIndices(of: group.bones, in: mesh),
                                    of: skeleton, boundTo: mesh, geometry: geometry)
            }
            return node
        }
    }

    /// Ties one group's vertices to the shared rig: each names four bones of the group's own list and
    /// how much each of them pulls, and a slot that pulls nothing names no bone at all.
    private func skin(
        _ vertices: [MshFile.Vertex],
        to palette: [Int],
        of skeleton: ModelSkeleton,
        boundTo mesh: MshFile,
        geometry: SCNGeometry
    ) -> SCNSkinner {
        var bones = [Int16]()
        var weights = [Float]()
        for vertex in vertices {
            for slot in 0 ..< 4 {
                let weight = vertex.weights[slot]
                let bone = Int(vertex.bones[slot])
                weights.append(weight)
                bones.append(weight > 0 && palette.indices.contains(bone) ? Int16(palette[bone]) : 0)
            }
        }

        let skinner = SCNSkinner(
            baseGeometry: geometry,
            bones: skeleton.bones,
            boneInverseBindTransforms: skeleton.inverseBindTransforms(of: mesh),
            boneWeights: SCNGeometrySource(
                data: Data(bytes: weights, count: weights.count * MemoryLayout<Float>.size),
                semantic: .boneWeights,
                vectorCount: vertices.count,
                usesFloatComponents: true,
                componentsPerVector: 4,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: MemoryLayout<Float>.size * 4
            ),
            boneIndices: SCNGeometrySource(
                data: Data(bytes: bones, count: bones.count * MemoryLayout<Int16>.size),
                semantic: .boneIndices,
                vectorCount: vertices.count,
                usesFloatComponents: false,
                componentsPerVector: 4,
                bytesPerComponent: MemoryLayout<Int16>.size,
                dataOffset: 0,
                dataStride: MemoryLayout<Int16>.size * 4
            )
        )
        return skinner
    }

    private func material(with texture: CGImage?) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = texture ?? NSColor(white: 0.6, alpha: 1)
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        // The game's own art is painted to be lit flatly rather than shaded physically: a physical
        // model reads every creature as wet stone.
        material.lightingModel = .lambert
        // A creature's skin is drawn on both sides of a wing or a cloak, and the game's models rely on it.
        material.isDoubleSided = true
        return material
    }

    private func camera(around centre: SIMD3<Float>, radius: Float, turned: Float = 0) -> SCNNode {
        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 0.01
        camera.zFar = Double(radius) * 40
        camera.wantsHDR = false

        let distance = radius / tan(Float(camera.fieldOfView / 2) * .pi / 180) * configuration.margin
        let turn = configuration.turn * .pi / 180 + turned
        let pitch = configuration.pitch * .pi / 180

        let node = SCNNode()
        node.camera = camera
        node.position = SCNVector3(
            centre.x + distance * sin(turn) * cos(pitch),
            centre.y + distance * sin(pitch),
            centre.z + distance * cos(turn) * cos(pitch)
        )
        node.look(at: SCNVector3(centre.x, centre.y, centre.z))
        return node
    }

    /// A key light over the shoulder, a cooler fill opposite it, a rim behind, and enough ambient that
    /// nothing reads as a silhouette.
    ///
    /// Every one of them is directional: a lamp placed near a model this small sits inside the frame and
    /// burns a hot spot into the ground.
    private func lights(around centre: SIMD3<Float>, radius: Float) -> [SCNNode] {
        let distance = radius * 6

        func light(_ colour: NSColor, _ intensity: CGFloat, from offset: SIMD3<Float>, shadows: Bool = false)
            -> SCNNode {
            let light = SCNLight()
            light.type = .directional
            light.color = colour
            light.intensity = intensity
            light.castsShadow = shadows && configuration.castsShadow
            light.shadowMode = .deferred
            light.shadowRadius = 8
            light.shadowSampleCount = 16
            light.shadowColor = NSColor(white: 0, alpha: 0.5)
            light.orthographicScale = Double(radius * 2.6)
            light.zNear = 0.01
            light.zFar = Double(distance * 4)

            let node = SCNNode()
            node.light = light
            node.position = SCNVector3(
                centre.x + offset.x * distance,
                centre.y + offset.y * distance,
                centre.z + offset.z * distance
            )
            node.look(at: SCNVector3(centre.x, centre.y, centre.z))
            return node
        }

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = NSColor(red: 0.78, green: 0.8, blue: 0.86, alpha: 1)
        ambient.intensity = 1100 * configuration.exposure
        let ambientNode = SCNNode()
        ambientNode.light = ambient

        return [
            light(
                NSColor(red: 1, green: 0.97, blue: 0.93, alpha: 1),
                2400 * configuration.exposure,
                from: SIMD3(0.6, 0.7, 0.55),
                shadows: true
            ),
            light(
                NSColor(red: 0.72, green: 0.79, blue: 0.95, alpha: 1),
                1500 * configuration.exposure,
                from: SIMD3(-0.8, 0.3, 0.4)
            ),
            light(
                NSColor(red: 0.95, green: 0.72, blue: 0.6, alpha: 1),
                1300 * configuration.exposure,
                from: SIMD3(-0.1, 0.35, -0.95)
            ),
            // Straight up from below, or a four-legged creature is a black underside.
            light(NSColor(white: 0.85, alpha: 1), 700 * configuration.exposure, from: SIMD3(0.1, -0.8, 0.3)),
            ambientNode,
        ]
    }

    private func ground(under centre: SIMD3<Float>, minimum: Float, radius: Float) -> SCNNode {
        let plane = SCNFloor()
        plane.reflectivity = 0
        plane.firstMaterial?.diffuse.contents = NSColor(white: 0.045, alpha: 1)
        plane.firstMaterial?.lightingModel = .lambert
        plane.firstMaterial?.lightingModel = .physicallyBased

        let node = SCNNode(geometry: plane)
        node.position = SCNVector3(centre.x, minimum, centre.z)
        return node
    }
}

private extension SIMD4<Float> {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
