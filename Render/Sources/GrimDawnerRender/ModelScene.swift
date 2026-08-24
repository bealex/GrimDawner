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
    /// How brightly the model is lit. The game's own art is painted dark, so a plain three-point rig
    /// leaves it in the murk; this scales the whole rig at once.
    public var exposure: CGFloat = 2.2

    public init() {}
}

/// A model ready to be drawn: what it is made of, what it is painted with, and — for a weapon — the hand
/// it is held in rather than a place of its own.
public struct DrawnModel {
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
        let rigged = animation != nil || drawn.contains { $0.hand != nil }
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
            if frame == nil { skeleton.play(animation, speed: speed) }
        }

        if !effects.isEmpty {
            let attachments = drawn.flatMap { $0.mesh.attachments }
            for effect in effects {
                guard let image = effect.image else { continue }

                let attachment = attachments.first { $0.name.lowercased() == effect.attachment.lowercased() }
                // A point of the model when the effect names one, and the middle of the creature when
                // it does not: what a cast throws is centred on whoever throws it.
                let placed = attachment.flatMap { skeleton?.node(for: $0) }
                let node = spark(
                    image,
                    at: placed?.transform ?? middle(of: drawn),
                    of: effect,
                    in: animation,
                    size: radius(of: drawn),
                    frame: frame,
                    speed: speed
                )
                (placed?.parent ?? scene.rootNode).addChildNode(node)
            }
        }

        let centre = (minimum + maximum) / 2
        let size = maximum - minimum
        let radius = max(max(size.x, size.y), size.z) / 2
            * (animation == nil ? 1 : configuration.movingMargin)

        scene.rootNode.addChildNode(camera(around: centre, radius: max(radius, 0.001), turned: turned))
        for light in lights(around: centre, radius: max(radius, 0.001)) { scene.rootNode.addChildNode(light) }
        if configuration.castsShadow {
            scene.rootNode.addChildNode(ground(under: centre, minimum: minimum.y, radius: radius))
        }
        return scene
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

    /// How big the models are, which is what an effect is sized against.
    private func radius(of models: [DrawnModel]) -> Float {
        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for model in models where model.hand == nil {
            minimum = simd_min(minimum, model.mesh.bounds.minimum)
            maximum = simd_max(maximum, model.mesh.bounds.maximum)
        }
        guard minimum.x <= maximum.x else { return 1 }

        return max(simd_length(maximum - minimum) / 4, 0.1)
    }

    /// The effect itself: the texture its particles are drawn with, facing the camera at the point the
    /// game spawns it, lit up on the frame it is called for and gone again a moment later.
    private func spark(
        _ image: CGImage,
        at transform: simd_float4x4,
        of effect: ModelEffect,
        in animation: AnmFile?,
        size: Float,
        frame: Int?,
        speed: Double
    ) -> SCNNode {
        // An effect with no frame of its own holds for as long as it is shown — the aura a passive
        // carries — and holding still is not what an effect does, so a view that keeps drawing emits it.
        guard let starts = effect.frame, let animation else {
            guard configuration.emitsEffects else {
                let node = SCNNode(geometry: sprite(image, size: size))
                node.simdTransform = transform
                node.constraints = [ SCNBillboardConstraint() ]
                node.renderingOrder = 10
                return node
            }

            let node = SCNNode()
            node.simdTransform = transform
            node.addParticleSystem(cloud(image, size: size))
            return node
        }

        let node = SCNNode(geometry: sprite(image, size: size))
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

    /// One picture of an effect, facing the camera and lit rather than lying flat.
    private func sprite(_ image: CGImage, size: Float) -> SCNPlane {
        let plane = SCNPlane(width: CGFloat(size), height: CGFloat(size))
        plane.firstMaterial?.diffuse.contents = image
        plane.firstMaterial?.lightingModel = .constant
        plane.firstMaterial?.blendMode = .add
        plane.firstMaterial?.isDoubleSided = true
        plane.firstMaterial?.writesToDepthBuffer = false
        plane.firstMaterial?.readsFromDepthBuffer = true
        return plane
    }

    /// An effect as the game shows it: not one picture pinned in place but a drift of them, rising and
    /// fading from the point it hangs on. The particles the game itself emits are a format of their own,
    /// so the shape of the drift is this app's, and only the picture is the game's.
    private func cloud(_ image: CGImage, size: Float) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.particleImage = image
        system.particleSize = CGFloat(size * 0.7)
        system.particleSizeVariation = CGFloat(size * 0.25)
        system.birthRate = 14
        system.particleLifeSpan = 1.1
        system.particleLifeSpanVariation = 0.4
        system.emitterShape = SCNSphere(radius: CGFloat(size * 0.16))
        system.birthLocation = .volume
        system.emittingDirection = SCNVector3(0, 1, 0)
        system.spreadingAngle = 35
        system.particleVelocity = CGFloat(size * 0.35)
        system.particleVelocityVariation = CGFloat(size * 0.2)
        system.acceleration = SCNVector3(0, size * 0.12, 0)
        system.particleAngularVelocity = 18
        system.particleAngularVelocityVariation = 40
        system.blendMode = .additive
        system.isLightingEnabled = false
        system.isAffectedByGravity = false
        system.sortingMode = .none
        system.loops = true
        // Fades in as it is born and out as it dies, so nothing pops.
        let fading = CAKeyframeAnimation(keyPath: "opacity")
        fading.values = [ 0, 1, 0.9, 0 ]
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
