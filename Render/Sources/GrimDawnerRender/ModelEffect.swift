// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import CoreGraphics
import Foundation
import GrimDawnerEngine
import GrimDawnerMesh

/// Something an animation spawns while it plays: a fire breath at the mouth, a cloud at the feet.
///
/// The animation names a record and a point of the model to hang it on; the record names a particle
/// system, and that names the texture the particles are drawn with. The particles themselves are a
/// format of their own and are not read, so what is drawn is that texture, where and when the game
/// spawns it — enough to tell one cast from another.
public struct ModelEffect: Sendable, Identifiable {
    public var id: String { "\(recordPath)|\(attachment)|\(frame ?? -1)" }
    public let name: String
    /// The frame of the animation it starts on, or nothing for one that simply holds — the aura a
    /// passive carries, or a skill's own effect shown on its own.
    public let frame: Int?
    /// The attachment of the model it hangs from — `Mouth`, `HeadFXUP`, `FXCentered`. Empty for one the
    /// game centres on the creature.
    public let attachment: String
    public let recordPath: String
    public let image: CGImage?
}

public extension ModelRenderer {
    /// What an animation spawns, in the order the animation calls for it.
    func effects(of animation: AnmFile, in database: GameDatabase?) -> [ModelEffect] {
        animation.events.compactMap { event in
            guard event.kind == .entity else { return nil }

            let path = event.name.replacingOccurrences(of: "\\", with: "/").lowercased()
            let particles = database?.record(path)?.text("effectFile") ?? ""

            return ModelEffect(
                name: Self.readableName(of: path),
                frame: event.frame,
                attachment: event.attachment,
                recordPath: path,
                image: particles.isEmpty ? nil : image(ofParticles: particles)
            )
        }
    }

    /// What a skill looks like on the creature that has it.
    ///
    /// A passive carries its aura in `charFxPakSelfNames`, a pack that names both the points of the model
    /// to hang effects on and the effects themselves. What a cast throws is `particleEffectName1…N`, and
    /// what it fires is a projectile whose own flight effect is named inside it. Each of those ends at an
    /// `EffectEntity`, and that names the particle system whose texture is what can be drawn.
    func effects(ofSkillAt path: String, in database: GameDatabase) -> [ModelEffect] {
        guard let skill = database.record(path) else { return [] }

        var found = [ModelEffect]()
        for pack in skill["charFxPakSelfNames"]?.texts ?? [] {
            found += effects(inside: pack, at: "", in: database, depth: 0)
        }
        for key in skill.fieldOrder where key.hasPrefix("particleEffectName") || key == "radiusEffectName" {
            found += effects(inside: skill.text(key), at: "", in: database, depth: 0)
        }
        if let projectile = database.record(skill.text("skillProjectileName")) {
            for key in [ "projectileFlightFX", "projectileExplodingImpactFX" ] {
                found += effects(inside: projectile.text(key), at: "", in: database, depth: 0)
            }
        }

        var seen = Set<String>()
        return found.filter { seen.insert($0.id).inserted }
    }

    /// One record's effects, following a pack of them down to the particle systems inside it.
    private func effects(
        inside path: String,
        at attachment: String,
        in database: GameDatabase,
        depth: Int
    ) -> [ModelEffect] {
        guard depth < 4, !path.isEmpty, let record = database.record(path.lowercased()) else { return [] }

        let particles = record.text("effectFile")
        if !particles.isEmpty {
            return [
                ModelEffect(
                    name: Self.readableName(of: path),
                    frame: nil,
                    attachment: attachment.isEmpty ? Self.bone(named: record) : attachment,
                    recordPath: path.lowercased(),
                    image: image(ofParticles: particles)
                ),
            ]
        }

        // A pack names its effects, and — when it hangs them off the creature — where each one goes.
        let names = record["particleEffectNames"]?.texts ?? []
        let points = record["particleEffectAttachPoints"]?.texts ?? []
        return names.enumerated().flatMap { index, name in
            effects(
                inside: name,
                at: points.indices.contains(index) ? points[index] : (points.first ?? attachment),
                in: database,
                depth: depth + 1
            )
        }
    }

    /// The texture a particle system draws with. A `.pfx` is binary, and the paths in it are written as
    /// a length and then the bytes, so they are read the way a mesh's material paths are.
    private func image(ofParticles path: String) -> CGImage? {
        guard let bytes = try? data(at: path) else { return nil }

        var candidates = [String]()
        var offset = 0
        while offset + 4 <= bytes.count {
            let length = Int(
                UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                    | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
            )
            guard
                length > 4, length < 256, offset + 4 + length <= bytes.count,
                bytes[(offset + 4) ..< (offset + 4 + length)].allSatisfy({ $0 >= 32 && $0 < 127 })
            else {
                offset += 1
                continue
            }

            let text = String(decoding: bytes[(offset + 4) ..< (offset + 4 + length)], as: UTF8.self)
            offset += 4 + length
            if text.lowercased().hasSuffix(".tex") { candidates.append(text) }
        }

        // A particle system names what it draws with and what it warps the picture behind it by. The
        // second is a map rather than a picture — flat grey where nothing bends — so it is taken last.
        let drawn = candidates.filter { name in
            ![ "distort", "_nml", "_norm", "mask" ].contains { name.lowercased().contains($0) }
        }
        for candidate in drawn + candidates {
            if let image = textures.image(at: candidate.replacingOccurrences(of: "\\", with: "/")) {
                return Self.glowing(image)
            }
        }
        return nil
    }

    /// The same picture, see-through where it is dark.
    ///
    /// The game's particle textures carry no transparency of their own: they are painted on black and
    /// added to what is behind them. Drawn as they are, an effect is a black square with a spark in it,
    /// so the picture's own brightness is made its transparency.
    private static func glowing(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return image }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixels = context.data else { return image }

        let bytes = pixels.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for index in stride(from: 0, to: width * height * 4, by: 4) {
            let brightest = max(bytes[index], bytes[index + 1], bytes[index + 2])
            // Already painted with transparency of its own: leave it alone.
            if bytes[index + 3] < 250 { return image }

            bytes[index + 3] = brightest
        }
        return context.makeImage() ?? image
    }

    /// The bone an effect record hangs itself off, when it names one worth having.
    ///
    /// `boneList` is filled in on 4,077 of the game's 4,733 effect records, and 3,886 of those say the
    /// same thing — the pair of weapon bones a creature usually has neither of. That is a stamp rather
    /// than a decision, so it is ignored; what is left is a real placement.
    private static func bone(named record: ArzRecord) -> String {
        (record["boneList"]?.texts ?? [])
            .first { ![ "bone_r_weapon", "bone_l_weapon" ].contains($0.lowercased()) } ?? ""
    }

    /// `records/fx/skillsother/itemskills/firebreathfx01.dbr` reads as *Fire Breath*.
    static func readableName(of path: String) -> String {
        var name = path.split(separator: "/").last.map(String.init) ?? path
        name = name.replacingOccurrences(of: ".dbr", with: "")
        for suffix in [ "_fx01", "_fx02", "_fx", "fx01", "fx02", "fx" ] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
            break
        }
        return name
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
