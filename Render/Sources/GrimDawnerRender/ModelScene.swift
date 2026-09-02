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
    /// Whether to draw a faint checked floor under the model. It is a ruler as much as a ground: the
    /// squares are a world unit each, so how far an effect reaches can be read off it.
    public var showsFloor = false
    /// Whether to turn texture coordinates upside down. Nothing needs it; it is the knob to reach for
    /// when a face comes out upside down.
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
    /// How far a bright effect blooms past its own geometry, the way the game's own glow does. Nothing
    /// turns it off, which is what an offline still wants.
    public var bloom: Float = 0

    public init() {}
}

/// A model ready to draw: the mesh, one skin per material it names, and — for a weapon — the hand it
/// hangs from. Unchecked because a `CGImage` is not `Sendable` on paper; these are never written to.
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
/// Vertices come in the bind pose, so a still needs no skeleton; an animation skins them to one merged
/// rig instead.
public struct ModelScene {
    public init(configuration: SceneConfiguration = SceneConfiguration()) {
        self.configuration = configuration
    }

    public let configuration: SceneConfiguration

    public func scene(for mesh: MshFile, texture: CGImage?) -> SCNScene {
        scene(for: [ DrawnModel(mesh: mesh, textures: [ texture ]) ])
    }

    /// Several models drawn together: a human is a head plus what it wears, and one animation moves the
    /// lot. Given a frame it holds that pose; given none it loops.
    public func scene(
        for models: [DrawnModel],
        playing animation: AnmFile? = nil,
        at frame: Int? = nil,
        speed: Double = 1,
        showing effects: [ModelEffect] = [],
        swinging trails: [WeaponTrail] = []
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
                    Swift.min(minimum.x, placed.x),
                    Swift.min(minimum.y, placed.y),
                    Swift.min(minimum.z, placed.z)
                )
                maximum = SIMD3(
                    Swift.max(maximum.x, placed.x),
                    Swift.max(maximum.y, placed.y),
                    Swift.max(maximum.z, placed.z)
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

                // A fired thing crosses the world rather than riding the rig.
                if let flight = effect.flight {
                    let fired = launched(
                        effect,
                        flying: flight,
                        among: attachments,
                        of: skeleton,
                        models: drawn,
                        animation: animation,
                        frame: frame,
                        speed: speed,
                        facing: turned
                    )
                    for node in fired.nodes { scene.rootNode.addChildNode(node) }
                    // What a thing is thrown at belongs in the frame as much as the thrower.
                    if let covered = fired.covered {
                        aimed = (
                            simd_min(aimed?.minimum ?? covered.minimum, covered.minimum),
                            simd_max(aimed?.maximum ?? covered.maximum, covered.maximum)
                        )
                        // Past the cap an effect merely wrapping the creature is held to.
                        reached = max(reached, simd_length(covered.maximum - covered.minimum) / 2)
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
        let radius =
            min(max(body, reached), max(body * configuration.effectMargin, framed))
            * (animation == nil ? 1 : configuration.movingMargin)

        scene.rootNode.addChildNode(camera(around: centre, radius: max(radius, 0.001), turned: turned))
        for light in lights(around: centre, radius: max(radius, 0.001)) { scene.rootNode.addChildNode(light) }
        if configuration.castsShadow {
            scene.rootNode.addChildNode(ground(under: centre, minimum: minimum.y, radius: radius))
        }
        if let skeleton, let animation, frame == nil {
            for trail in trails {
                guard let node = swung(trail, on: skeleton, playing: animation, speed: speed) else { continue }

                scene.rootNode.addChildNode(node)
            }
            skeleton.pose(animation, at: 0)
        }

        // The model's own feet, not the frame's floor: the bounds grow to take in an effect thrown
        // downward, and standing the creature on that would leave it in the air.
        if configuration.showsFloor {
            let feet = drawn.filter { $0.hand == nil }.map { $0.mesh.bounds.minimum.y }.min() ?? minimum.y
            scene.rootNode.addChildNode(floor(under: feet))
        }
        return scene
    }

    /// Where an effect hangs: a point of the model, a bone of the rig, or — naming neither — the
    /// creature's own middle, which the models state and is not the middle of the bounding box.
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

    /// The same placement carried forward by a wave's reach, along the way its attach point leans from
    /// the creature. Stepped in the world and put back into the bone's frame, since a bone's own
    /// "forward" is whichever way it happens to point.
    private func swept(_ transform: simd_float4x4, on parent: SCNNode?, by reach: Float) -> simd_float4x4 {
        let toWorld = parent.map { simd_float4x4($0.worldTransform) } ?? matrix_identity_float4x4
        let place = (toWorld * transform).columns.3.xyz
        let along = SIMD3(place.x, 0, place.z)
        guard simd_length(along) > 0.001 else { return transform }

        var world = toWorld * transform
        world.columns.3 = SIMD4(place + simd_normalize(along) * reach, 1)
        return toWorld.inverse * world
    }

    /// How far an effect reaches, in the model's own units: the skill states it where there is one, and
    /// where nothing does it is measured against the creature.
    private func reach(of effect: ModelEffect, on models: [DrawnModel]) -> Float {
        if let radius = effect.radius { return max(radius, 0.05) }

        let span = span(of: models)
        return (Self.isCentred(effect.attachment) ? span : span / 3) / 2
    }

    /// Whether an attachment means the whole creature rather than a point on it: `FXCentered` and
    /// `FXUnParentedCenter` wrap it, where `HeadFXUP` and `R Hand` name a place to hang something.
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

    /// What a skill fires: the stated copies leave the launch point, fan across the stated arc, and
    /// each is aimed at a target the skill's own range in front of the creature.
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
    ) -> (nodes: [SCNNode], covered: (minimum: SIMD3<Float>, maximum: SIMD3<Float>)?) {
        // Both read with the rig posed on the launch frame. Posing writes only the bones' resting
        // values, so a playing animation carries on over it untouched.
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

        // The ground the target stands on, which is the creature's own: the engine aims at the target
        // entity's coordinates, and an entity stands at its feet.
        let ground =
            models.filter { $0.hand == nil }
            .map { $0.mesh.bounds.minimum.y }.min() ?? launch.y

        let arc = flight.arc * .pi / 180
        var nodes = [SCNNode]()
        var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var high = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for index in 0 ..< flight.count {
            // A full circle spaces the copies evenly all the way round; anything less is a fan centred
            // on the way out.
            let yaw: Float =
                arc >= 2 * .pi * 0.99
                ? 2 * .pi * Float(index) / Float(flight.count)
                : (flight.count > 1 ? arc * (Float(index) / Float(flight.count - 1) - 0.5) : 0)
            let direction = SIMD3<Float>(
                forward.x * cos(yaw) + forward.z * sin(yaw),
                0,
                -forward.x * sin(yaw) + forward.z * cos(yaw)
            )
            let path = flown(flight, from: launch, along: direction, onto: ground)
            for place in path.places {
                low = simd_min(low, place)
                high = simd_max(high, place)
            }
            nodes.append(
                one(
                    effect,
                    along: path,
                    flying: flight,
                    models: models,
                    animation: animation,
                    frame: frame,
                    speed: speed
                )
            )
        }
        return (nodes, low.x <= high.x ? (low, high) : nil)
    }

    /// The flight sampled evenly in time, from the launch until it arrives.
    ///
    /// Every projectile is aimed at its target rather than into the distance: a straight one flies at it
    /// with gravity off, a thrown one leaves at `launchAngle` at the speed that arc needs to land on it
    /// — `v = √(d²g / 2cos²θ(d·tanθ − Δh))` — and falls from there. See
    /// [AttackPipeline.md](../../../Documentation/AttackPipeline.md#how-a-projectile-flies).
    func flown(
        _ flight: ModelEffect.Flight,
        from launch: SIMD3<Float>,
        along direction: SIMD3<Float>,
        onto ground: Float
    ) -> (places: [SIMD3<Float>], headings: [simd_quatf], seconds: Double) {
        let reach = max(min(flight.range, flight.distance), 0.1)
        let target = SIMD3(launch.x + direction.x * reach, ground, launch.z + direction.z * reach)
        let toTarget = target - launch
        let aim = simd_length(toTarget) > 0.001 ? simd_normalize(toTarget) : SIMD3<Float>(0, 0, 1)

        let gravity = flight.isThrown ? ModelEffect.Flight.gravity : 0
        var heading = aim
        var speed = max(flight.velocity, 0.1)
        if flight.isThrown {
            let angle = flight.launchAngle * .pi / 180
            // The launch angle is measured off the ground, which is what makes the solved speed land the
            // arc on the target rather than somewhere short of it.
            heading = SIMD3(direction.x * cos(angle), sin(angle), direction.z * cos(angle))

            let bracket = 2 * cos(angle) * cos(angle) * (reach * tan(angle) - toTarget.y)
            let solved = bracket > 0 ? sqrt(reach * reach * gravity / bracket) : 0
            speed = min(max(solved, ModelEffect.Flight.slowestThrow), max(flight.velocity, 0.1))
        }

        let velocity = heading * speed
        // Done when it lands, or when it has covered all the record lets it, whichever comes first.
        var seconds = Double(reach / max(simd_length(SIMD3(velocity.x, 0, velocity.z)), 0.01))
        if gravity > 0, velocity.y > 0 || launch.y > ground {
            let discriminant = velocity.y * velocity.y + 2 * gravity * (launch.y - ground)
            if discriminant > 0 { seconds = Double((velocity.y + sqrt(discriminant)) / gravity) }
        }
        seconds = min(max(seconds, 0.05), Double(flight.distance / max(speed, 0.1)))

        let steps = 48
        var places = [SIMD3<Float>]()
        var headings = [simd_quatf]()
        for step in 0 ... steps {
            let time = Float(seconds) * Float(step) / Float(steps)
            places.append(launch + velocity * time - SIMD3(0, gravity * time * time / 2, 0))
            let moving = velocity - SIMD3(0, gravity * time, 0)
            // Pointed the way it is going: a bolt or a spike is modelled along an axis, and carried
            // sideways down an arc it reads as debris.
            headings.append(simd_quatf(from: SIMD3(0, 0, 1), to: simd_normalize(moving)))
        }
        return (places, headings, seconds)
    }

    /// One copy of a fired thing: its own model where the record names one, its flight texture riding
    /// along, following the flight the game's physics give it and gone when it arrives.
    private func one(
        _ effect: ModelEffect,
        along path: (places: [SIMD3<Float>], headings: [simd_quatf], seconds: Double),
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
        }
        if let image = effect.image {
            // `actorRadius` is the thing's physics, not its picture. What it looks like is its flight
            // effect's own particle system, and that says how big and what colour — so the radius is
            // only the fallback for a system that could not be read.
            let half = flight.size > 0 ? max(flight.size, 0.3) : min(max(span(of: models) * 0.15, 0.4), 1.6)
            let rider = SCNNode()
            if frame == nil, configuration.emitsEffects, let emission = effect.emission {
                // A trail, not a sticker: the emitter is carried down the flight and leaves its
                // particles along it, in the colour and at the size the game states for them — and at
                // a rate that follows how fast it is carried.
                let flown = simd_length((path.places.last ?? .zero) - (path.places.first ?? .zero))
                let carried = path.seconds > 0.001 ? flown / Float(path.seconds) : 0
                rider.addParticleSystem(cloud(image, reach: half, emitting: emission, carriedAt: carried))
            } else {
                rider.geometry = sprite(image, reach: half)
                rider.constraints = [ SCNBillboardConstraint() ]
                rider.renderingOrder = 10
            }
            node.addChildNode(rider)
        }
        node.simdPosition = path.places[0]
        node.simdOrientation = path.headings[0]

        // Held on one frame: the copy stands as far along as the flight had got by then.
        if let frame {
            let rate = Double(max(animation?.framesPerSecond ?? 30, 1))
            let since = Double(frame - (effect.frame ?? 0)) / rate
            guard
                since >= 0,
                since <= path.seconds
            else {
                node.opacity = 0
                return node
            }

            let step = min(Int((since / path.seconds * Double(path.places.count - 1)).rounded()), path.places.count - 1)
            node.simdPosition = path.places[step]
            node.simdOrientation = path.headings[step]
            node.simdScale = SIMD3(repeating: grown(flight, after: since))
            return node
        }

        // Timed against whole turns of the animation, so it leaves when the blow lands and still flies
        // at its own speed when the flight outlasts one turn.
        let rate = Double(max(animation?.framesPerSecond ?? 30, 1))
        let turn = animation.map { $0.duration > 0 ? $0.duration : path.seconds + 0.5 } ?? (path.seconds + 0.5)
        let leaves = animation == nil ? 0 : Double(effect.frame ?? 0) / rate
        let loop = turn * Double(max(Int(((leaves + path.seconds) / max(turn, 0.001)).rounded(.up)), 1))
        let start = min(leaves / max(loop, 0.001), 1)
        let end = min(start + path.seconds / loop, 1)

        let shares = (0 ..< path.places.count).map { index in
            start + (end - start) * Double(index) / Double(path.places.count - 1)
        }
        node.addAnimation(
            looping(
                "position",
                over: loop / speed,
                values: path.places.map { SCNVector3($0.x, $0.y, $0.z) },
                at: shares
            ),
            forKey: "flight"
        )
        node.addAnimation(
            looping(
                "orientation",
                over: loop / speed,
                values: path.headings.map { SCNQuaternion($0.vector.x, $0.vector.y, $0.vector.z, $0.vector.w) },
                at: shares
            ),
            forKey: "aim"
        )
        if flight.growth > 0 {
            node.addAnimation(
                looping(
                    "scale",
                    over: loop / speed,
                    values: shares.indices.map { index -> SCNVector3 in
                        let size = grown(flight, after: path.seconds * Double(index) / Double(shares.count - 1))
                        return SCNVector3(size, size, size)
                    },
                    at: shares
                ),
                forKey: "growth"
            )
        }

        // Lit as it leaves and gone as it arrives, so nothing stands about at either end.
        let blink = min(0.02, max((end - start) / 4, 0.001))
        node.opacity = 0
        node.addAnimation(
            looping(
                "opacity",
                over: loop / speed,
                values: [ 0, 0, 1, 1, 0, 0 ],
                at: [ 0, start, start + blink, max(end - blink, start + blink), end, 1 ]
            ),
            forKey: "showing"
        )
        return node
    }

    /// How much bigger a fired thing has grown: the engine ramps its scale to `1 + projectileScaleFactor`
    /// over the first second of flight and holds it there.
    private func grown(_ flight: ModelEffect.Flight, after seconds: Double) -> Float {
        1 + flight.growth * Float(min(max(seconds, 0), 1))
    }

    /// The emitter's rate curve laid across the animation's loop, as shares of it. A window running off
    /// the end wraps to the start rather than being cut short.
    private func throwing(
        _ curve: PfxFile.Curve,
        from opens: Double,
        over span: Double,
        steady: CGFloat
    ) -> (values: [CGFloat], shares: [Double]) {
        // A hair of silence either side, so the window does not bleed into the rest of the loop.
        let edge = 0.0005
        var points = [(share: Double, rate: CGFloat)]()
        points.append((opens - edge, 0))
        if curve.domain > 0, curve.keys.count > 1 {
            for key in curve.keys {
                points.append((opens + span * Double(key.time / curve.domain), CGFloat(max(key.value, 0))))
            }
        } else {
            points.append((opens, steady))
            points.append((opens + span, steady))
        }
        points.append(((points.last?.share ?? opens) + edge, 0))

        // What runs past the end of the loop comes round to its start, and is written there first so
        // the key times still climb.
        let wrapped = points.filter { $0.share > 1 }.map { (share: $0.share - 1, rate: $0.rate) }
        var values = [CGFloat]()
        var shares = [Double]()
        for point in wrapped + points.filter({ $0.share <= 1 }) {
            shares.append(min(max(point.share, shares.last ?? 0), 1))
            values.append(point.rate)
        }
        return (values, shares)
    }

    /// One property walked through the given values at the given shares of a loop, over and over.
    ///
    /// Core Animation wants key times inside the loop, never going backwards, and the whole of it
    /// covered, so a run starting partway through holds its ends.
    private func looping(
        _ path: String,
        over duration: TimeInterval,
        values: [Any],
        at shares: [Double]
    ) -> CAKeyframeAnimation {
        var times = [Double]()
        for share in shares { times.append(min(max(share, times.last ?? 0), 1)) }
        var values = values
        if let first = times.first, first > 0, let held = values.first {
            times.insert(0, at: 0)
            values.insert(held, at: 0)
        }
        if let last = times.last, last < 1, let held = values.last {
            times.append(1)
            values.append(held)
        }

        let animation = CAKeyframeAnimation(keyPath: path)
        animation.values = values
        animation.keyTimes = times.map { NSNumber(value: $0) }
        animation.duration = max(duration, 0.001)
        animation.repeatCount = .infinity
        animation.calculationMode = .linear
        animation.isRemovedOnCompletion = false
        return animation
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
        guard
            let starts = effect.frame,
            let animation
        else {
            guard
                configuration.emitsEffects
            else {
                let node = SCNNode(geometry: sprite(image, reach: reach))
                node.simdTransform = transform
                node.constraints = [ SCNBillboardConstraint() ]
                node.renderingOrder = 10
                return node
            }

            let node = SCNNode()
            node.simdTransform = transform
            node.addParticleSystem(cloud(image, reach: reach, emitting: effect.emission))
            return node
        }

        // What the animation spawns is a burst of the game's own particles, not one picture flashed on
        // for a moment — an attack's effects are all of this kind, and drawing them as a billboard is
        // what kept them looking nothing like the game while an aura already did.
        if frame == nil, configuration.emitsEffects, let emission = effect.emission {
            let node = SCNNode()
            node.simdTransform = transform
            let cloud = cloud(image, reach: reach, emitting: emission)
            node.addParticleSystem(cloud)

            // It throws to its own rate curve as its frame comes round, and is quiet the rest of the loop.
            let rate = Double(max(animation.framesPerSecond, 1))
            let loop = animation.duration / speed
            let opens = min(Double(starts) / rate / max(animation.duration, 0.001), 1)
            let span = Double(max(emission.duration, 0.05)) / max(animation.duration, 0.001)
            let throwing = throwing(
                emission.shapes.rate, from: opens, over: span, steady: cloud.birthRate
            )
            cloud.addAnimation(
                looping("birthRate", over: loop, values: throwing.values, at: throwing.shares),
                forKey: "throwing"
            )
            return node
        }

        let node = SCNNode(geometry: sprite(image, reach: reach))
        node.simdTransform = transform
        node.constraints = [ SCNBillboardConstraint() ]
        node.renderingOrder = 10

        // A still shows what is up at that moment; a playing scene lights it as the frame comes round.
        guard
            frame == nil
        else {
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
    /// hangs it, at the size its record states, driven by its own animation rather than the creature's.
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

    /// An effect as a drift of particles rather than one picture pinned in place.
    ///
    /// Every figure is the game's where it states one, and the app's only where the system could not be
    /// read — except the variation, which no file states.
    private func cloud(
        _ image: CGImage,
        reach: Float,
        emitting: ModelEffect.Emission?,
        carriedAt carried: Float = 0
    ) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.particleImage = image
        // A size of nothing is a slot not yet read rather than a small particle, so it falls back to
        // the reach, which is how far the drift spreads and not how big one spark is.
        let stated = emitting.map { min(max($0.size, 0), 40) } ?? 0
        let spark = stated > 0.01 ? stated : min(max(reach * 0.18, 0.2), 0.9)
        // SceneKit measures a particle from its middle, so a `particleSize` of one draws two units
        // across, and a size controller multiplies that again rather than replacing it.
        system.particleSize = CGFloat(spark / 2)
        system.particleLifeSpan = emitting.map { CGFloat(min(max($0.lifetime, 0.05), 8)) } ?? 0.7
        // The game's rate, unbounded — how many are in the air at once follows from it and the lifetime.
        // A carried emitter throws per unit travelled, so its rate is multiplied by how fast it goes.
        let throwing = emitting.map { min(max($0.rate, 0), 500) } ?? Float(10 + 5 * min(reach, 8))
        system.birthRate = CGFloat(carried > 0.01 ? min(throwing * carried, 2000) : throwing)
        // Where a new particle is born, which on most systems is very nearly a point.
        let extent = emitting.map { simd_min(abs($0.extent), SIMD3(repeating: 24)) }
        if let extent, emitting?.isFlat == true {
            // Thrown flat, at any bearing: the side of a thin upright cylinder faces outward all the
            // way round, so a particle born on it leaves along the ground the way the engine's own
            // direction does once its vertical is taken out.
            system.emitterShape = SCNCylinder(
                radius: CGFloat(max(max(extent.x, extent.z), 0.01)),
                height: CGFloat(max(extent.y * 2, 0.02))
            )
            system.birthLocation = .surface
            system.birthDirection = .surfaceNormal
        } else if let extent, extent.max() > 0.01 {
            system.emitterShape = SCNBox(
                width: CGFloat(max(extent.x, 0.001) * 2),
                height: CGFloat(max(extent.y, 0.001) * 2),
                length: CGFloat(max(extent.z, 0.001) * 2),
                chamferRadius: 0
            )
            system.birthLocation = .volume
        } else if extent == nil {
            system.emitterShape = SCNSphere(radius: CGFloat(reach * 0.7))
            system.birthLocation = .volume
        }
        // Straight up, which is where the engine's own elevation starts before its cone tilts it.
        system.emittingDirection = SCNVector3(0, 1, 0)
        // The cone it throws into, which the game states in degrees.
        system.spreadingAngle = emitting.map { CGFloat(min(max($0.spread, 0), 180)) } ?? 35
        // A shimmer over the ground it covers rather than a column climbing off it.
        system.particleVelocity = emitting.map { CGFloat(min(max($0.speed, 0), 40)) }
            ?? CGFloat(reach * 0.12)
        // The game pulls a particle down by its own curve rather than by the world's gravity, and the
        // curve runs both ways: a spark that drifts upward is one with a gravity below nothing.
        system.acceleration = emitting.map { SCNVector3(0, -min(max($0.gravity, -60), 60), 0) }
            ?? SCNVector3(0, reach * 0.05, 0)
        system.particleAngularVelocity = emitting.map { CGFloat(min(max($0.spin, -720), 720)) } ?? 18
        // Nothing in a `.pfx` says how far a particle may stray from its own curves, so where the system
        // was read every particle follows them exactly and only a fallback drifts.
        if emitting == nil {
            system.particleSizeVariation = system.particleSize * 0.35
            system.particleLifeSpanVariation = system.particleLifeSpan * 0.35
            system.particleVelocityVariation = system.particleVelocity * 0.4
            system.particleAngularVelocityVariation = 20
        }
        // What the game's own colour curves put on the particle. A curve handed over multiplies this
        // rather than setting it, so where there is one the particle starts white and it alone decides.
        let paintsColour = emitting.map {
            $0.shapes.red.isShape || $0.shapes.green.isShape || $0.shapes.blue.isShape
        } ?? false
        let paintsAlpha = emitting?.shapes.alpha.isShape ?? false
        if let emitting, emitting.red + emitting.green + emitting.blue > 0.01 {
            system.particleColor = NSColor(
                red: paintsColour ? 1 : CGFloat(min(emitting.red, 1)),
                green: paintsColour ? 1 : CGFloat(min(emitting.green, 1)),
                blue: paintsColour ? 1 : CGFloat(min(emitting.blue, 1)),
                alpha: paintsAlpha ? 1 : CGFloat(min(max(emitting.alpha, 0.05), 1))
            )
        }
        // The system's own shader says which. A particle painted dark reads as rubble laid over the
        // ground and as nothing added to it.
        let adds = emitting?.shading.isAdded ?? true
        system.blendMode = adds ? .additive : .alpha
        system.isLightingEnabled = false
        system.isAffectedByGravity = false
        // Adding is order-free; laying one picture over another is not.
        system.sortingMode = adds ? .none : .distance
        system.loops = true

        // What each property does over a particle's life is a curve in the file, and SceneKit takes a
        // curve. Where the game states one, it is handed over whole rather than reduced to a figure.
        var controllers = [SCNParticleSystem.ParticleProperty: SCNParticlePropertyController]()
        if let shapes = emitting?.shapes {
            if let over = walk(shapes.alpha) { controllers[.opacity] = over }
            // A share of the curve's own peak, since the controller multiplies the size rather than
            // setting it: the shape is the game's, the units are already in `particleSize`.
            if let over = walk(shapes.size, scale: 1 / max(shapes.size.keys.map(\.value).max() ?? 1, 0.001)) {
                controllers[.size] = over
            }
            // Curve 4 is the speed a particle turns at, not the angle it is at — and like size, a
            // share of its own peak, since the controller multiplies `particleAngularVelocity`.
            let turning = shapes.spin.keys.map(\.value).max { abs($0) < abs($1) } ?? 0
            if abs(turning) > 0.001, let over = walk(shapes.spin, scale: 1 / turning) {
                controllers[.angularVelocity] = over
            }
            if let over = colouring(shapes) { controllers[.color] = over }
        }
        if controllers[.opacity] == nil {
            // Nothing stated, so it fades in as it is born and out as it dies and nothing pops.
            let fading = CAKeyframeAnimation(keyPath: "opacity")
            fading.values = [ 0, 0.55, 0.45, 0 ]
            fading.keyTimes = [ 0, 0.15, 0.6, 1 ]
            fading.duration = 1
            controllers[.opacity] = SCNParticlePropertyController(animation: fading)
        }
        system.propertyControllers = controllers
        return system
    }

    /// One of the game's curves as SceneKit takes it: the same shape, laid across the particle's life.
    private func walk(_ curve: PfxFile.Curve, scale: Float = 1) -> SCNParticlePropertyController? {
        guard curve.isShape else { return nil }

        let animation = CAKeyframeAnimation()
        animation.values = curve.keys.map { $0.value * scale }
        animation.keyTimes = curve.keys.map {
            NSNumber(value: min(max($0.time / curve.domain, 0), 1))
        }
        animation.duration = 1
        return SCNParticlePropertyController(animation: animation)
    }

    /// The three colour curves read together, since a colour moves as one thing.
    private func colouring(_ shapes: ModelEffect.Emission.Shapes) -> SCNParticlePropertyController? {
        let curves = [ shapes.red, shapes.green, shapes.blue ]
        guard curves.contains(where: \.isShape) else { return nil }

        let span = curves.map(\.domain).max() ?? 1
        guard span > 0 else { return nil }

        let steps = 8
        let animation = CAKeyframeAnimation()
        animation.values = (0 ... steps).map { step -> NSColor in
            let time = span * Float(step) / Float(steps)
            return NSColor(
                red: CGFloat(min(max(shapes.red.value(at: time), 0), 1)),
                green: CGFloat(min(max(shapes.green.value(at: time), 0), 1)),
                blue: CGFloat(min(max(shapes.blue.value(at: time), 0), 1)),
                alpha: 1
            )
        }
        animation.keyTimes = (0 ... steps).map { NSNumber(value: Double($0) / Double(steps)) }
        animation.duration = 1
        return SCNParticlePropertyController(animation: animation)
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
    /// A group's bone slots index a list of its own, so its vertices are compacted into their own
    /// buffer: a vertex in two groups is written twice, each copy pointing at the right bones.
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
                    SCNGeometrySource(
                        vertices: vertices.map { SCNVector3($0.position.x, $0.position.y, $0.position.z) }
                    ),
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
            geometry.materials = [
                material(
                    with: textures.indices.contains(group.material)
                        ? textures[group.material] : textures.first ?? nil
                )
            ]

            let node = SCNNode(geometry: geometry)
            if let skeleton, !group.bones.isEmpty {
                node.skinner = skin(
                    vertices,
                    to: skeleton.skeletonIndices(of: group.bones, in: mesh),
                    of: skeleton,
                    boundTo: mesh,
                    geometry: geometry
                )
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
        // The game blooms what it draws brightly, and an additive effect is mostly bloom: without it a
        // crescent that fills the screen there is a smudge the size of its own geometry here.
        camera.wantsHDR = configuration.bloom > 0
        camera.bloomIntensity = CGFloat(configuration.bloom)
        camera.bloomThreshold = 0.75
        camera.bloomBlurRadius = 12
        camera.exposureOffset = 0

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

    /// A key light over the shoulder, a cooler fill opposite, a rim behind, and enough ambient that
    /// nothing reads as a silhouette. All directional: a lamp this close burns a hot spot.
    private func lights(around centre: SIMD3<Float>, radius: Float) -> [SCNNode] {
        let distance = radius * 6

        func light(_ colour: NSColor, _ intensity: CGFloat, from offset: SIMD3<Float>, shadows: Bool = false)
            -> SCNNode
        {
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

    /// The ribbon a stroke leaves: the blade's two ends sampled every frame it is swung, joined into a
    /// strip, and faded out behind the edge so the tail thins away.
    private func swung(
        _ trail: WeaponTrail,
        on skeleton: ModelSkeleton,
        playing animation: AnmFile,
        speed: Double
    ) -> SCNNode? {
        guard
            let image = trail.image,
            let hand = skeleton.hand(trail.hand),
            trail.closes > trail.opens
        else { return nil }

        var leading = [SCNVector3]()
        var trailing = [SCNVector3]()
        for frame in trail.opens ... trail.closes {
            skeleton.pose(animation, at: frame)
            let held = simd_float4x4(hand.worldTransform)
            leading.append((held * SIMD4(trail.from, 1)).xyz.vector)
            trailing.append((held * SIMD4(trail.to, 1)).xyz.vector)
        }
        guard leading.count > 1 else { return nil }

        // Two vertices a frame — the edge and the hilt — walked into one strip.
        var vertices = [SCNVector3]()
        var coordinates = [CGPoint]()
        var colours = [SIMD4<Float>]()
        var indices = [Int32]()
        for step in leading.indices {
            let along = Double(step) / Double(leading.count - 1)
            vertices.append(leading[step])
            vertices.append(trailing[step])
            coordinates.append(CGPoint(x: 1 - along, y: 0))
            coordinates.append(CGPoint(x: 1 - along, y: 1))
            // The oldest end of a stroke is the faintest, which is what makes it read as a tail.
            let fading = Float(along) * trail.alpha
            colours.append(SIMD4(trail.red, trail.green, trail.blue, fading))
            colours.append(SIMD4(trail.red, trail.green, trail.blue, fading))
            guard step > 0 else { continue }

            let base = Int32((step - 1) * 2)
            indices += [ base, base + 1, base + 2, base + 1, base + 3, base + 2 ]
        }

        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: vertices),
                SCNGeometrySource(textureCoordinates: coordinates),
                SCNGeometrySource(
                    data: Data(bytes: colours, count: colours.count * MemoryLayout<SIMD4<Float>>.size),
                    semantic: .color,
                    vectorCount: colours.count,
                    usesFloatComponents: true,
                    componentsPerVector: 4,
                    bytesPerComponent: MemoryLayout<Float>.size,
                    dataOffset: 0,
                    dataStride: MemoryLayout<SIMD4<Float>>.size
                ),
            ],
            elements: [ SCNGeometryElement(indices: indices, primitiveType: .triangles) ]
        )
        let material = geometry.firstMaterial
        material?.diffuse.contents = image
        material?.lightingModel = .constant
        material?.blendMode = trail.isAdded ? .add : .alpha
        material?.isDoubleSided = true
        material?.writesToDepthBuffer = false

        let node = SCNNode(geometry: geometry)
        node.renderingOrder = 5
        node.opacity = 0

        // Lit as the stroke runs and gone over the record's own fade.
        let rate = Double(max(animation.framesPerSecond, 1))
        let loop = animation.duration / speed
        let opens = min(Double(trail.opens) / rate / max(animation.duration, 0.001), 1)
        let closes = min(Double(trail.closes) / rate / max(animation.duration, 0.001), 1)
        let gone = min(closes + trail.fades / max(animation.duration, 0.001), 1)
        node.addAnimation(
            looping(
                "opacity",
                over: loop,
                values: [ 0, 0, 1, 1, 0, 0 ],
                at: [ 0, opens, min(opens + 0.005, closes), closes, gone, 1 ]
            ),
            forKey: "swinging"
        )
        return node
    }

    /// A faint check for the model to stand on, one square to the world unit, so it says how big things
    /// are as well as where the ground is.
    private func floor(under feet: Float) -> SCNNode {
        // Big enough that no creature or effect reaches its edge, and laid flat. A plane of a stated
        // size rather than `SCNFloor`, since its own texture coordinates are what put a square on
        // every world unit.
        let side: CGFloat = 44
        let plane = SCNPlane(width: side, height: side)
        plane.firstMaterial?.diffuse.contents = Self.check
        plane.firstMaterial?.diffuse.wrapS = .repeat
        plane.firstMaterial?.diffuse.wrapT = .repeat
        // The picture is two squares across, so this many turns of it across the plane is one square
        // to the unit.
        plane.firstMaterial?.diffuse.contentsTransform = SCNMatrix4MakeScale(side / 2, side / 2, 1)
        plane.firstMaterial?.lightingModel = .constant
        // A fifth opaque. It goes on the material rather than into the picture: a texture carrying its
        // own premultiplied alpha drops out of an unlit material altogether.
        plane.firstMaterial?.transparency = 0.2
        // Writes no depth but is tested against what does, and is drawn after the creature, so anything
        // sinking below it reads as under it.
        plane.firstMaterial?.writesToDepthBuffer = false
        plane.firstMaterial?.readsFromDepthBuffer = true
        plane.firstMaterial?.isDoubleSided = true

        let node = SCNNode(geometry: plane)
        node.position = SCNVector3(0, feet, 0)
        node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        // After the creature, before anything an effect throws.
        node.renderingOrder = 1
        return node
    }

    /// Two squares by two of light grey, which repeated is the check. Opaque: how faint it is drawn is
    /// the material's business.
    private static let check: CGImage = {
        let side = 64
        let alpha: CGFloat = 1
        let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        let half = CGFloat(side / 2)
        context?.setFillColor(CGColor(red: 0.82, green: 0.84, blue: 0.88, alpha: alpha))
        context?.fill(CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side)))
        context?.setFillColor(CGColor(red: 0.42, green: 0.45, blue: 0.52, alpha: alpha))
        context?.fill(CGRect(x: 0, y: 0, width: half, height: half))
        context?.fill(CGRect(x: half, y: half, width: half, height: half))
        return context?.makeImage() ?? CGImage(
            width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: CGDataProvider(data: Data([ 255, 255, 255, 255 ]) as CFData)!,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }()

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

private extension SIMD3<Float> {
    var vector: SCNVector3 { SCNVector3(x, y, z) }
}
