// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import CoreGraphics
import Foundation
import GrimDawnerEngine
import GrimDawnerMesh
import simd

/// The ribbon a swung weapon leaves behind it.
///
/// A mechanism apart from the particle systems: the weapon record names a `WeaponTrail` in
/// `weaponTrail`, the blade carries an `Anchor1` and `Anchor2` the ribbon is strung between, and the
/// animation's own `SwipeLeft` / `SwipeRight` callbacks say when it is drawn.
/// [GameData.md](../../../Documentation/GameData.md#effects) has the engine's own path.
public struct WeaponTrail: Sendable {
    /// Which hand swung it, which is the callback the animation calls out.
    public let hand: ModelAssembly.Hand
    /// The blade's two ends, in the weapon's own space.
    public let from: SIMD3<Float>
    public let to: SIMD3<Float>
    /// The picture the ribbon is drawn with.
    public let image: CGImage?
    /// What the record paints it, each out of 255.
    public let red: Float
    public let green: Float
    public let blue: Float
    public let alpha: Float
    /// Whether it adds its light to the scene, out of `trailadditive` against `trailcombine`.
    public let isAdded: Bool
    /// Seconds it takes to fade once the swing is over, the record's `MSFadeTime`.
    public let fades: Double
    /// The frames it is drawn between.
    public let opens: Int
    public let closes: Int
}

public extension ModelRenderer {
    /// The trails an animation swings, one per stroke the weapons make.
    ///
    /// A stroke runs from a `Swipe…` callback to the `Swipe…Off` that ends it, or for `stroke` frames
    /// where the animation calls out no end.
    func trails(
        of animation: AnmFile,
        wearing assembly: ModelAssembly,
        in database: GameDatabase
    ) -> [WeaponTrail] {
        var found = [WeaponTrail]()
        for part in assembly.parts {
            guard
                let hand = part.hand,
                let weapon = database.record(part.record),
                case let path = weapon.text("weaponTrail"), !path.isEmpty,
                let trail = database.record(path),
                let mesh = try? mesh(at: part.mesh)
            else { continue }

            func anchor(_ name: String) -> SIMD3<Float>? {
                mesh.attachments.first { $0.name.lowercased() == name }
                    .map { $0.transform.columns.3.xyz }
            }
            guard let from = anchor("anchor1"), let to = anchor("anchor2") else { continue }

            let image = textures.image(at: trail.text("Texture")).flatMap { Self.glowing($0) }
            for stroke in Self.strokes(in: animation, of: hand) {
                found.append(WeaponTrail(
                    hand: hand,
                    from: from,
                    to: to,
                    image: image,
                    red: Float(trail.number("Red256")) / 255,
                    green: Float(trail.number("Green256")) / 255,
                    blue: Float(trail.number("Blue256")) / 255,
                    alpha: Float(trail.number("Alpha256")) / 255,
                    isAdded: trail.text("Shader").lowercased().contains("additive"),
                    fades: max(trail.number("MSFadeTime"), 1) / 1000,
                    opens: stroke.opens,
                    closes: stroke.closes
                ))
            }
        }
        return found
    }

    /// How long a stroke lasts where the animation names no end for it.
    private static let stroke = 12

    /// The frames each of a hand's strokes runs between.
    private static func strokes(in animation: AnmFile, of hand: ModelAssembly.Hand)
        -> [(opens: Int, closes: Int)] {
        let side = hand == .right ? "right" : "left"
        var swung = [(opens: Int, closes: Int)]()
        for event in animation.events.sorted(by: { $0.frame < $1.frame }) {
            let name = event.name.lowercased()
            guard event.kind == .callback, name.hasPrefix("swipe"), name.contains(side) else { continue }

            if name.hasSuffix("off") {
                if !swung.isEmpty { swung[swung.count - 1].closes = event.frame }
            } else {
                swung.append((event.frame, min(event.frame + stroke, animation.frameCount - 1)))
            }
        }
        return swung.filter { $0.closes > $0.opens }
    }
}

private extension SIMD4<Float> {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
