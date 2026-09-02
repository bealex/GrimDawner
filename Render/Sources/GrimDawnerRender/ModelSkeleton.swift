// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation
import GrimDawnerMesh
import SceneKit
import simd

/// The skeleton several models share, as SceneKit nodes.
///
/// A human is drawn from a head, a body and every piece of armour on it, and each of those carries its
/// own copy of the same rig — the same bones, under the same names, in a different order and often only
/// some of them. So the bones are merged by name into one hierarchy, and every part is skinned to it:
/// move a shoulder and the pauldron on it moves too.
final class ModelSkeleton {
    /// What the whole rig hangs from. Held apart from the models so posing it moves all of them.
    let root = SCNNode()

    private(set) var bones = [SCNNode]()
    private(set) var inverseBindTransforms = [NSValue]()
    private var indices = [String: Int]()
    /// Where each bone sits in its parent when nothing is playing, which is what an animation's own
    /// transforms are measured against.
    private var bindTransforms = [simd_float4x4]()
    /// Where each bone stands in the model, which is the pose the vertices are written in.
    private var bindWorld = [simd_float4x4]()

    init(meshes: [MshFile]) {
        for mesh in meshes { add(mesh) }
        carrier = trunk().flatMap { node in bones.firstIndex { $0 === node } }
    }

    /// The bone the body hangs from, which is the one whose own travel is drawn. Worked out once,
    /// since posing asks for it on every key.
    private var carrier: Int?

    var isEmpty: Bool { bones.isEmpty }

    /// The rig, or nothing at all when the models carry no bones.
    var nonEmpty: ModelSkeleton? { isEmpty ? nil : self }

    /// Where an attachment of a model stands, as a node of the rig: a point the game hangs an effect on.
    /// One with no bone stands in the model itself, which is the scene's own space.
    func node(for attachment: MshFile.Attachment) -> (parent: SCNNode, transform: simd_float4x4) {
        guard
            !attachment.parent.isEmpty,
            let index = indices[attachment.parent]
        else { return (root, attachment.transform) }

        return (bones[index], attachment.transform)
    }

    /// One bone by name.
    func bone(named name: String) -> SCNNode? {
        indices[name].map { bones[$0] } ?? bones.first { $0.name?.lowercased() == name.lowercased() }
    }

    /// The bone the body hangs from: the first one that branches, which on every rig is the hips.
    /// A creature centres what it casts on itself, and this is where itself is.
    func trunk() -> SCNNode? {
        var walking = bones.first
        while let node = walking, node.childNodes.count == 1 { walking = node.childNodes.first }

        return walking ?? bones.first
    }

    /// The bone a weapon hangs off, which every rig names differently: `Bip01 R Weapon` on a human,
    /// `BN_LWeapon`, `Weapon_Joint_R0_0_jnt`, or a lone `Bone_Weapon` on a creature that holds one thing.
    ///
    /// The side is a token of the name rather than a position in it, so it is read as one: a bone with no
    /// side at all is the main hand's.
    func hand(_ hand: ModelAssembly.Hand) -> SCNNode? {
        let candidates = bones.filter { node in
            guard let name = node.name?.lowercased() else { return false }

            return name.contains("weapon") && !name.contains("parent")
        }
        let wanted = hand == .right ? "r" : "l"
        let sided = candidates.first { side(of: $0.name ?? "") == wanted }

        return sided ?? (hand == .right ? candidates.first { side(of: $0.name ?? "") == nil } : nil)
    }

    /// `Bip01 R Weapon` and `Weapon_Joint_R0_0_jnt` are both right; `Bone_Weapon` is neither.
    private func side(of name: String) -> String? {
        let tokens = name.lowercased()
            .replacingOccurrences(of: "weapon", with: " ")
            .split { !$0.isLetter && !$0.isNumber }

        for token in tokens where token.first == "r" || token.first == "l" {
            guard token.dropFirst().allSatisfy(\.isNumber) else { continue }

            return String(token.prefix(1))
        }
        return nil
    }

    /// Where a part's own bones stand, which is the pose its vertices are written against.
    ///
    /// A head, a helmet and a breastplate each carry their own copy of the rig, and they do not always
    /// agree: a fifth of the assembled monsters hold a part whose bones stand somewhere else, by as much
    /// as a whole bone's length. Skinning such a part against the rig's own bind pose puts it on
    /// backwards, so each part is skinned against its own and only the posing is shared.
    func inverseBindTransforms(of mesh: MshFile) -> [NSValue] {
        var transforms = inverseBindTransforms
        let world = mesh.boneBindTransforms()
        for (index, bone) in mesh.bones.enumerated() {
            guard let slot = indices[bone.name], transforms.indices.contains(slot) else { continue }

            transforms[slot] = NSValue(caTransform3D: SCNMatrix4(world[index].inverse))
        }
        return transforms
    }

    /// Where a model's bones sit in this rig, in the order the model's own list has them.
    func skeletonIndices(of palette: [Int], in mesh: MshFile) -> [Int] {
        palette.map { bone in
            guard mesh.bones.indices.contains(bone) else { return 0 }

            return indices[mesh.bones[bone].name] ?? 0
        }
    }

    /// Plays an animation over the rig, looping for as long as the scene is shown. `speed` is a share of
    /// the rate the game plays it at, so a half is half as fast.
    func play(_ animation: AnmFile, speed: Double = 1) {
        guard animation.frameCount > 1, animation.duration > 0, speed > 0 else { return }

        for track in animation.tracks {
            guard let index = indices[track.bone] else { continue }

            let pose = CAKeyframeAnimation(keyPath: "transform")
            pose.values = track.keys.map { NSValue(caTransform3D: SCNMatrix4(posed($0, of: index))) }
            pose.duration = animation.duration / speed
            pose.repeatCount = .infinity
            pose.calculationMode = .linear
            pose.isRemovedOnCompletion = false
            bones[index].addAnimation(pose, forKey: "pose")
        }
    }

    /// Where one key puts one bone: laid over the bind pose, turning it without moving it.
    ///
    /// A skeleton is rigid, so every bone keeps the distance from its parent the mesh gives it — except
    /// the trunk, which carries the body's own placement and so takes a dying creature into the ground.
    /// The root above the trunk holds the ground the creature covers, which is not drawn.
    private func posed(_ key: AnmFile.Key, of index: Int) -> simd_float4x4 {
        let transform = bindTransforms[index] * key.transform
        guard index != carrier else { return transform }

        var held = transform
        held.columns.3 = bindTransforms[index].columns.3
        return held
    }

    /// Holds the rig on one frame of an animation, which is how a still of a pose is taken.
    func pose(_ animation: AnmFile, at frame: Int) {
        for track in animation.tracks {
            guard let index = indices[track.bone], let key = track.keys[safe: frame] ?? track.keys.first
            else { continue }

            bones[index].simdTransform = posed(key, of: index)
        }
    }

    /// Where the rig stands once posed — the span of the bones, not of the skin over them, which is
    /// enough to aim a camera at.
    func posedBounds() -> (minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for bone in bones {
            let column = simd_float4x4(bone.worldTransform).columns.3
            let at = SIMD3(column.x, column.y, column.z)
            minimum = simd_min(minimum, at)
            maximum = simd_max(maximum, at)
        }
        return (minimum, maximum)
    }

    /// How far the pose has turned the creature about the vertical, in radians.
    ///
    /// Measured off the head, not the body: a stance twists the hips while the head stays on the enemy.
    /// A creature with no head bone is measured by the turn that best carries its bind rig onto the posed.
    func turn() -> Float {
        if let head = bones.firstIndex(where: { ($0.name ?? "").lowercased().contains("head") }) {
            return yaw(from: bindWorld[head], to: simd_float4x4(bones[head].worldTransform))
        }

        var centre = (bind: SIMD2<Float>.zero, posed: SIMD2<Float>.zero)
        var places = [(bind: SIMD2<Float>, posed: SIMD2<Float>)]()
        for (index, node) in bones.enumerated() {
            let bind = bindWorld[index].columns.3
            let posed = simd_float4x4(node.worldTransform).columns.3
            places.append((SIMD2(bind.x, bind.z), SIMD2(posed.x, posed.z)))
            centre.bind += SIMD2(bind.x, bind.z) / Float(bones.count)
            centre.posed += SIMD2(posed.x, posed.z) / Float(bones.count)
        }

        var across = Float(0)
        var along = Float(0)
        for place in places {
            let bind = place.bind - centre.bind
            let posed = place.posed - centre.posed
            across += bind.y * posed.x - bind.x * posed.y
            along += bind.x * posed.x + bind.y * posed.y
        }
        return along == 0 && across == 0 ? 0 : atan2(across, along)
    }

    /// The turn about the vertical that carries one frame's axes onto another's.
    private func yaw(from bind: simd_float4x4, to posed: simd_float4x4) -> Float {
        var across = Float(0)
        var along = Float(0)
        for axis in 0 ..< 3 {
            let was = SIMD2(bind[axis].x, bind[axis].z)
            let now = SIMD2(posed[axis].x, posed[axis].z)
            across += was.y * now.x - was.x * now.y
            along += was.x * now.x + was.y * now.y
        }
        return along == 0 && across == 0 ? 0 : atan2(across, along)
    }

    private func add(_ mesh: MshFile) {
        guard !mesh.bones.isEmpty else { return }

        let parents = mesh.boneParents
        let world = mesh.boneBindTransforms()
        for (index, bone) in mesh.bones.enumerated() where indices[bone.name] == nil {
            let node = SCNNode()
            node.name = bone.name
            node.simdTransform = bone.transform

            let parent = parents[index].flatMap { self.indices[mesh.bones[$0].name] }.map { bones[$0] }
            (parent ?? root).addChildNode(node)
            indices[bone.name] = bones.count
            bones.append(node)
            bindTransforms.append(bone.transform)
            bindWorld.append(world[index])
            inverseBindTransforms.append(NSValue(caTransform3D: SCNMatrix4(world[index].inverse)))
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
