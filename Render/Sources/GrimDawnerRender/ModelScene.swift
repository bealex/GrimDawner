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
    /// How brightly the model is lit. The game's own art is painted dark, so a plain three-point rig
    /// leaves it in the murk; this scales the whole rig at once.
    public var exposure: CGFloat = 2.2

    public init() {}
}

/// Builds a SceneKit scene from one of the game's models.
///
/// The game's models are Y-up and stand at the origin, and their vertices are already in the bind pose,
/// so a still needs neither the skeleton nor an animation.
public struct ModelScene {
    public init(configuration: SceneConfiguration = SceneConfiguration()) {
        self.configuration = configuration
    }

    public let configuration: SceneConfiguration

    public func scene(for mesh: MshFile, texture: CGImage?) -> SCNScene {
        scene(for: [ (mesh, [ texture ]) ])
    }

    /// Several models drawn together: a human is a head plus what it wears, all in one bind pose. Each
    /// model brings one skin per material it names.
    public func scene(for models: [(mesh: MshFile, textures: [CGImage?])]) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents =
            configuration.background.map {
                NSColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: 1)
            } ?? NSColor.clear

        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

        for model in models where !model.mesh.isEmpty {
            scene.rootNode.addChildNode(SCNNode(geometry: geometry(for: model.mesh, textures: model.textures)))
            minimum = SIMD3(
                Swift.min(minimum.x, model.mesh.bounds.minimum.x),
                Swift.min(minimum.y, model.mesh.bounds.minimum.y),
                Swift.min(minimum.z, model.mesh.bounds.minimum.z)
            )
            maximum = SIMD3(
                Swift.max(maximum.x, model.mesh.bounds.maximum.x),
                Swift.max(maximum.y, model.mesh.bounds.maximum.y),
                Swift.max(maximum.z, model.mesh.bounds.maximum.z)
            )
        }
        guard minimum.x <= maximum.x else { return scene }

        let centre = (minimum + maximum) / 2
        let size = maximum - minimum
        let radius = max(max(size.x, size.y), size.z) / 2

        scene.rootNode.addChildNode(camera(around: centre, radius: max(radius, 0.001)))
        for light in lights(around: centre, radius: max(radius, 0.001)) { scene.rootNode.addChildNode(light) }
        if configuration.castsShadow {
            scene.rootNode.addChildNode(ground(under: centre, minimum: minimum.y, radius: radius))
        }
        return scene
    }

    /// One geometry, drawn as one element per group so each part wears its own skin.
    private func geometry(for mesh: MshFile, textures: [CGImage?]) -> SCNGeometry {
        let positions = mesh.vertices.map { SCNVector3($0.position.x, $0.position.y, $0.position.z) }
        let normals = mesh.vertices.map { SCNVector3($0.normal.x, $0.normal.y, $0.normal.z) }
        let coordinates = mesh.vertices.map {
            CGPoint(
                x: CGFloat($0.texture.x),
                y: configuration.flipsTexture ? CGFloat(1 - $0.texture.y) : CGFloat($0.texture.y)
            )
        }

        var elements = [SCNGeometryElement]()
        var materials = [SCNMaterial]()

        for group in mesh.groups {
            let first = group.firstTriangle * 3
            let end = min(first + group.triangleCount * 3, mesh.indices.count)
            guard first < end else { continue }

            elements.append(SCNGeometryElement(
                indices: mesh.indices[first ..< end].map { Int32($0) },
                primitiveType: .triangles
            ))
            materials.append(material(with: textures.indices.contains(group.material)
                ? textures[group.material] : textures.first ?? nil))
        }
        guard !elements.isEmpty else {
            return SCNGeometry(sources: [ SCNGeometrySource(vertices: positions) ], elements: [])
        }

        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: positions),
                SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: coordinates),
            ],
            elements: elements
        )
        geometry.materials = materials
        return geometry
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

    private func camera(around centre: SIMD3<Float>, radius: Float) -> SCNNode {
        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 0.01
        camera.zFar = Double(radius) * 40
        camera.wantsHDR = false

        let distance = radius / tan(Float(camera.fieldOfView / 2) * .pi / 180) * configuration.margin
        let turn = configuration.turn * .pi / 180
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
