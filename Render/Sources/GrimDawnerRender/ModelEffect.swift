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

    /// True where there is something to draw at all. A record the app can read neither the particles
    /// nor the model of is still listed, since knowing the game calls for it is worth something.
    public var isDrawable: Bool { image != nil || model != nil }
    public let name: String
    /// The frame of the animation it starts on, or nothing for one that simply holds — the aura a
    /// passive carries, or a skill's own effect shown on its own.
    public let frame: Int?
    /// The attachment of the model it hangs from — `Mouth`, `HeadFXUP`, `FXCentered`. Empty for one the
    /// game centres on the creature.
    public let attachment: String
    public let recordPath: String
    /// The picture its particles are drawn with, for the effects that are particles.
    public let image: CGImage?
    /// The model it is, for the effects that are one rather than a picture — the chunks a stomp throws
    /// up, the wall a shield puts down. Loaded here the way the picture is, since the scene draws what
    /// it is handed rather than reading the game itself.
    public var model: DrawnModel?
    /// What the record multiplies its model by. One where the record says nothing.
    public var scale: Float = 1
    /// The model's own animation, which is what spreads it: a stomp's chunks are one rigged mesh whose
    /// spikes are driven apart by this, so without it every chunk sits on top of the others.
    public var motion: AnmFile?
    /// How far the effect reaches, in the model's own units, where the skill that throws it says so.
    /// Nothing for one nothing sizes — an animation's own puff, or an aura a passive simply carries.
    public let radius: Float?
    /// Whether it runs forward from where it hangs rather than sitting on it. A wave skill — a breath, a
    /// flame arc — states how far it sweeps, and drawn on the caster it is a spark in a fist instead.
    public var isWave = false
}

/// How far a skill throws what it shows, and whether it sweeps forward.
///
/// An area skill states the ground it covers in `skillTargetRadius`. A wave states its sweep instead —
/// `waveDistance` out and `waveStartWidth` across — and nothing else in the record says how big it is.
struct SkillReach {
    let radius: Float?
    let isWave: Bool

    init(_ skill: ArzRecord) {
        let wave = Float(skill["waveDistance"]?.numbers.max() ?? 0)
        if wave > 0 {
            radius = wave / 2
            isWave = true
            return
        }

        let area = Float(skill["skillTargetRadius"]?.numbers.max() ?? 0)
        radius = area > 0 ? area : nil
        isWave = false
    }
}

public extension ModelRenderer {
    /// What an animation spawns, in the order the animation calls for it.
    ///
    /// The animation says what to spawn and where, never how big: only the skill that plays it knows
    /// that. Given the skill being watched, what it spawns is drawn the size that skill states.
    func effects(of animation: AnmFile, in database: GameDatabase?, thrownBy skill: String? = nil)
        -> [ModelEffect] {
        let thrown = skill.flatMap { database?.record($0) }.map(SkillReach.init)

        var seen = Set<String>()
        return animation.events.compactMap { event -> ModelEffect? in
            guard event.kind == .entity else { return nil }

            let path = event.name.replacingOccurrences(of: "\\", with: "/").lowercased()
            // A wave belongs to the point the game hangs it out in front on; the flash in the hand that
            // threw it is a flash in a hand, and sizing that to the sweep fills the frame with it.
            let reach = thrown.flatMap {
                !$0.isWave || event.attachment.lowercased().contains("forward") ? $0 : nil
            }

            // An animation often calls for the same effect twice on the same frame and point — the game
            // spreads the copies around the impact, and drawn on top of one another they are one effect
            // at twice the brightness.
            guard seen.insert("\(path)|\(event.attachment)|\(event.frame)").inserted else { return nil }

            return drawn(
                at: path,
                named: Self.readableName(of: path),
                frame: event.frame,
                attachment: event.attachment,
                radius: reach?.radius,
                isWave: reach?.isWave ?? false,
                in: database
            )
        }
    }

    /// What a skill looks like **on the creature that has it**.
    ///
    /// A passive carries its aura in `charFxPakSelfNames`, a pack that names both the points of the model
    /// to hang effects on and the effects themselves; a cast's own flash is `particleEffectName1…N` and
    /// what it spreads around itself is `radiusEffectName`. Each of those ends at an `EffectEntity`, and
    /// that names the particle system whose texture is what can be drawn.
    ///
    /// What a skill *fires* is left out. `skillProjectileName` names a projectile, and its flight and
    /// impact effects belong to the thing in flight rather than to the creature that threw it: hung on
    /// the caster they read as a swarm of meteors circling a beast that is merely standing there.
    func effects(ofSkillAt path: String, in database: GameDatabase) -> [ModelEffect] {
        guard let skill = database.record(path) else { return [] }

        // What the skill covers is what its effect is drawn the size of. A passive that simply sits on
        // the creature states none, and is sized against the creature instead.
        let reach = SkillReach(skill)

        var found = [ModelEffect]()
        for pack in skill["charFxPakSelfNames"]?.texts ?? [] {
            found += effects(inside: pack, at: "", reaching: reach, in: database, depth: 0)
        }
        for key in skill.fieldOrder where key.hasPrefix("particleEffectName") || key == "radiusEffectName" {
            found += effects(inside: skill.text(key), at: "", reaching: reach, in: database, depth: 0)
        }

        var seen = Set<String>()
        return found.filter { seen.insert($0.id).inserted }
    }

    /// One record's effects, following a pack of them down to the particle systems inside it.
    private func effects(
        inside path: String,
        at attachment: String,
        reaching reach: SkillReach,
        in database: GameDatabase,
        depth: Int
    ) -> [ModelEffect] {
        guard depth < 4, !path.isEmpty, let record = database.record(path.lowercased()) else { return [] }

        if !record.text("effectFile").isEmpty || !record.text("meshName").isEmpty {
            return [
                drawn(
                    at: path.lowercased(),
                    named: Self.readableName(of: path),
                    frame: nil,
                    attachment: attachment.isEmpty ? Self.bone(named: record) : attachment,
                    radius: reach.radius,
                    isWave: reach.isWave,
                    in: database
                ),
            ].compactMap { $0 }
        }

        // A pack names its effects, and — when it hangs them off the creature — where each one goes.
        // The models it throws are named apart from the particles, and are effects just the same.
        let names = (record["particleEffectNames"]?.texts ?? []) + (record["meshEffectNames"]?.texts ?? [])
        let points = record["particleEffectAttachPoints"]?.texts ?? []
        return names.enumerated().flatMap { index, name in
            effects(
                inside: name,
                at: points.indices.contains(index) ? points[index] : (points.first ?? attachment),
                reaching: reach,
                in: database,
                depth: depth + 1
            )
        }
    }

    /// One effect record read as something to draw: the picture its particles use, or the model it is.
    ///
    /// `EffectEntity` names a particle system in `effectFile`; `FxMesh` names a model in `meshName`,
    /// with the `scale` to draw it at. A record naming neither is still returned, so what the game calls
    /// for is listed even where nothing can be drawn for it.
    private func drawn(
        at path: String,
        named name: String,
        frame: Int?,
        attachment: String,
        radius: Float?,
        isWave: Bool,
        in database: GameDatabase?
    ) -> ModelEffect? {
        let record = database?.record(path)
        var effect = ModelEffect(
            name: name,
            frame: frame,
            attachment: attachment,
            recordPath: path,
            image: (record?.text("effectFile")).flatMap { $0.isEmpty ? nil : image(ofParticles: $0) },
            radius: radius,
            isWave: isWave
        )

        if case let mesh = record?.text("meshName") ?? "", !mesh.isEmpty, let loaded = try? self.mesh(at: mesh) {
            effect.model = DrawnModel(mesh: loaded, textures: skins(for: loaded, at: mesh, preferring: nil))
            // A record that states no scale draws its model as it was built.
            let stated = Float(record?.number("scale") ?? 0)
            effect.scale = stated > 0 ? stated : 1
            effect.motion = (record?.text("animationName")).flatMap { $0.isEmpty ? nil : try? animation(at: $0) }
        }
        return effect
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
