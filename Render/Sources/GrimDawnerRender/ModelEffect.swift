// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import CoreGraphics
import Foundation
import GrimDawnerEngine
import GrimDawnerMesh

/// Something an animation spawns while it plays: a fire breath at the mouth, a cloud at the feet.
///
/// The animation names a record and a point of the model to hang it on; the record names the particle
/// system that says what is drawn.
public struct ModelEffect: Sendable, Identifiable {
    public var id: String { "\(recordPath)|\(attachment)|\(frame ?? -1)" }

    /// True where there is something to draw at all. A record the app can read neither the particles
    /// nor the model of is still listed, since knowing the game calls for it is worth something.
    public var isDrawable: Bool { image != nil || model != nil }
    public let name: String
    /// The frame of the animation it starts on, or nothing for one that simply holds — the aura a
    /// passive carries, or a skill's own effect shown on its own.
    public var frame: Int?
    /// The attachment of the model it hangs from — `Mouth`, `HeadFXUP`, `FXCentered`. Empty for one the
    /// game centres on the creature.
    public let attachment: String
    public let recordPath: String
    /// The picture its particles are drawn with, for the effects that are particles.
    public var image: CGImage?
    /// The model it is, for the effects that are one rather than a picture — the chunks a stomp throws
    /// up. Loaded here, since the scene draws what it is handed rather than reading the game itself.
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
    /// Set on something the skill fires rather than wears: the projectile leaves the launch point and
    /// crosses the world, and this is the flight the game's own records state for it.
    public var flight: Flight?
    /// What the game's own particle system says the drift is made of, for the slots read out of the
    /// engine's emitter. Nothing where the system could not be read.
    public var emission: Emission?

    /// One `.pfx` emitter, each figure the furthest its curve reaches from nothing.
    ///
    /// [GameData.md](../../../Documentation/GameData.md#effects) has the slot table and which nine run
    /// both ways; everything here is already put back on zero.
    public struct Emission: Sendable {
        /// Particles a second at its busiest.
        public let rate: Float
        /// Seconds one lives.
        public let lifetime: Float
        /// Seconds the emitter runs for, which is its rate curve's domain.
        public let duration: Float
        public let size: Float
        /// How fast a particle leaves.
        public let speed: Float
        /// The cone it is thrown into, in degrees.
        public let spread: Float
        /// How far the emitter reaches on each axis, which is where a particle is born.
        public let extent: SIMD3<Float>
        /// Degrees a second the emitter turns on each axis.
        public let turn: SIMD3<Float>
        /// What pulls a particle down over its life.
        public let gravity: Float
        /// Degrees a second it turns on the spot.
        public let spin: Float
        /// What is left of its speed each frame.
        public let drag: Float
        /// Over 1 asks for more light than the picture carries.
        public let red: Float
        public let green: Float
        public let blue: Float
        public let alpha: Float
        public let shading: Shading
        /// Whether the emitter throws flat: `EmitParticle` zeroes the vertical of every direction it
        /// builds when `flag[5]` is set, leaving a burst that radiates across the ground.
        public let isFlat: Bool
        /// How many particles `EmitAnchoredParticle` trails along a sweep — `integer[1]`. Nothing on a
        /// system that simply drifts; 16 on most of the game's claw swipes.
        public let anchored: Int
        /// The curves themselves, for the properties that take a shape rather than a figure.
        public let shapes: Shapes

        /// How a particle goes over what is behind it, out of the shader the system names.
        public enum Shading: Sendable {
            case adding
            /// Laid over the scene by the picture's own transparency. Combine, soft combine and lit.
            case blending
            /// The game bends what is behind it; here the picture is laid over instead.
            case distorting

            init(shader: String) {
                let name = shader.lowercased()
                self =
                    if name.contains("distort") { .distorting }
                    else if name.contains("combine") || name.contains("lit") { .blending }
                    else { .adding }
            }

            public var isAdded: Bool { self == .adding }
        }

        /// What moves while the system runs: the emitter's own rate, and the rest over a particle's life.
        public struct Shapes: Sendable {
            /// Particles a second as the emitter's clock runs; a burst is open for a fraction of it.
            public let rate: PfxFile.Curve
            public let size: PfxFile.Curve
            public let alpha: PfxFile.Curve
            public let red: PfxFile.Curve
            public let green: PfxFile.Curve
            public let blue: PfxFile.Curve
            public let spin: PfxFile.Curve
        }
    }

    /// How a fired thing crosses the world: how many leave at once, across what spread, how fast, and
    /// under what physics. The engine's own launch, decompiled in
    /// [AttackPipeline.md](../../../Documentation/AttackPipeline.md).
    public struct Flight: Sendable {
        /// The world's own downward pull — `PhysicsEngine2::kGravity`, 14 world units a second squared.
        /// It acts on a thrown projectile and on nothing else: the engine turns gravity off for one it
        /// sends in a straight line.
        public static let gravity: Float = 14
        /// The slowest the engine will throw one, whatever the arc works out to.
        public static let slowestThrow: Float = 5

        public let count: Int
        /// The spread the copies fan across, in degrees — a ring is the whole circle.
        public let arc: Float
        /// World units a second, the record's own `projectileVelocity`. A thrown one leaves at whatever
        /// the arc to the target calls for, up to this.
        public let velocity: Float
        /// How far one flies before it is done, the record's own `projectileDistance`.
        public let distance: Float
        /// How big the thing in flight is, the record's own `actorRadius` — what its picture is drawn
        /// across when the model itself is the game's invisible stand-in.
        public let size: Float
        /// How far off what it is aimed at stands, out of the skill's own `distanceProfile`. The engine
        /// aims every projectile at a target rather than firing it into the distance, so this is what
        /// the flight is solved against.
        public let range: Float
        /// Degrees above the line to that target it leaves at, the record's own `launchAngle`.
        public let launchAngle: Float
        /// Whether the engine gives it the arc rather than the straight line: a `ProjectileGrenade`
        /// always, a `ProjectileExploding` where `useTrajectory` says so, nothing else.
        public let isThrown: Bool
        /// How much wider it grows over its first second of flight, the record's `projectileScaleFactor`
        /// — the engine ramps the actor's scale to `1 + factor` and holds it there.
        public let growth: Float
    }
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
        -> [ModelEffect]
    {
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

    /// What a skill looks like on the creature that has it: the aura a passive wears, a cast's own
    /// flash, and what it spreads around itself.
    ///
    /// What it *fires* is left out — that belongs to the thing in flight. A buff skill carries no effect
    /// of its own, so `buffSkillName` is followed and what the buff wears is the answer.
    func effects(ofSkillAt path: String, in database: GameDatabase) -> [ModelEffect] {
        guard let skill = database.record(path) else { return [] }

        var found = own(skill, in: database)
        let buff = skill.text("buffSkillName").replacingOccurrences(of: "\\", with: "/").lowercased()
        if buff != path.lowercased(), let record = database.record(buff) {
            found += own(record, in: database)
        }

        var seen = Set<String>()
        return found.filter { seen.insert($0.id).inserted }
    }

    /// One record's own effects: the pack a passive wears, the flash of a cast, and what it spreads.
    private func own(_ skill: ArzRecord, in database: GameDatabase) -> [ModelEffect] {
        // What the skill covers is what its effect is drawn the size of. A passive that simply sits on
        // the creature states none, and is sized against the creature instead.
        let reach = SkillReach(skill)

        var found = [ModelEffect]()
        for pack in skill["charFxPakSelfNames"]?.texts ?? [] {
            found += effects(inside: pack, at: "", reaching: reach, in: database, depth: 0)
        }
        for key in skill.fieldOrder
        where key.hasPrefix("particleEffectName") || key == "radiusEffectName" || key == "warmUpEffectName" {
            // The record pairs each cast effect with the point of the model it hangs on:
            // `particleEffectName2` goes with `particleEffectAttachPoint2`, and the warm-up with
            // `warmUpEffectAttachPoint`.
            let attach = key.hasPrefix("particleEffectName")
                ? skill.text("particleEffectAttachPoint" + key.dropFirst("particleEffectName".count))
                : (key == "warmUpEffectName" ? skill.text("warmUpEffectAttachPoint") : "")
            found += effects(inside: skill.text(key), at: attach, reaching: reach, in: database, depth: 0)
        }
        return found
    }

    /// What a skill fires, as something to draw in flight.
    ///
    /// `skillProjectileName` names a creature-like record holding the mesh, the flight effect and the
    /// physics; the skill states how many leave at once and across what spread. It starts on the
    /// animation's hit callback, which is when the engine lets go.
    func emitted(
        bySkillAt path: String,
        level: Int,
        launchFrame: Int?,
        calledOut: String = "",
        in database: GameDatabase
    ) -> [ModelEffect] {
        guard let skill = database.record(path) else { return [] }

        let projectilePath = skill.text("skillProjectileName")
            .replacingOccurrences(of: "\\", with: "/").lowercased()
        guard !projectilePath.isEmpty, let projectile = database.record(projectilePath) else { return [] }

        let counts = skill["projectileLaunchNumber"]?.numbers ?? []
        let count = counts.isEmpty ? 1 : Int(counts[min(max(level - 1, 0), counts.count - 1)])
        let stated = Float(skill.number("projectileLaunchRotation"))
        // A ring says its spread outright; a burst of several without one is read as a narrow fan.
        let arc = stated > 0 ? stated : (count > 1 ? 45 : 0)
        let velocity = Float(projectile.number("projectileVelocity"))
        let distance = Float(projectile.number("projectileDistance"))
        let reach = SkillReach(skill)
        // Where the thing it is aimed at stands. The skill names a range of the game's own and the
        // engine record says how far that is; a skill that names none is read against how far the
        // projectile can go at all.
        let range = Float(GameRanges(database).distance(ofSkill: skill) ?? Double(distance))

        // What flies is drawn as the effect riding it, or the trail it lays: `projectileFlightFX`
        // first, and where a crawler carries none, the pak it drops on the ground as it goes —
        // the fault line's eruptions are `inflightGroundFxPakName` and its spark is invisible.
        var picture: CGImage?
        var drift: ModelEffect.Emission?
        let flightPath = projectile.text("projectileFlightFX")
            .replacingOccurrences(of: "\\", with: "/").lowercased()
        if !flightPath.isEmpty, case let file = database.record(flightPath)?.text("effectFile") ?? "",
                !file.isEmpty {
            // The emitter as well as the picture: a thing in flight is drawn by its own system.
            let read = particles(at: file)
            picture = read.image
            drift = read.emission
        }
        if picture == nil {
            let trail = effects(
                inside: projectile.text("inflightGroundFxPakName"),
                at: "",
                reaching: reach,
                in: database,
                depth: 0
            )
            picture = trail.compactMap(\.image).first
            drift = trail.compactMap(\.emission).first
        }

        let named = skill.text("launchAttachPointName")
        var effect = ModelEffect(
            name: Self.readableName(of: projectilePath),
            frame: launchFrame,
            attachment: named.isEmpty ? Self.launchPoint(calledOut: calledOut) : named,
            recordPath: projectilePath,
            image: picture,
            radius: nil
        )
        effect.emission = drift
        let flown = distance > 0 ? distance : (reach.radius.map { $0 * 2 } ?? 12)
        effect.flight = ModelEffect.Flight(
            count: max(count, 1),
            arc: arc,
            velocity: velocity > 0 ? velocity : 8,
            distance: flown,
            size: Float(projectile.number("actorRadius")),
            range: min(range > 0 ? range : flown, flown),
            launchAngle: Float(projectile.number("launchAngle")),
            isThrown: projectile.recordClass == "ProjectileGrenade"
                || (projectile.recordClass == "ProjectileExploding" && projectile.number("useTrajectory") > 0),
            growth: Float(projectile.number("projectileScaleFactor"))
        )
        // The model is the projectile's own — unless it wears the game's invisible stand-in, which is
        // the record's way of saying the effect is the whole look.
        if case let mesh = projectile.text("mesh"), !mesh.isEmpty, let loaded = try? self.mesh(at: mesh),
                !loaded.materials.allSatisfy({ $0.diffuse?.lowercased().contains("invisible") == true }) {
            effect.model = DrawnModel(mesh: loaded, textures: skins(for: loaded, at: mesh, preferring: nil))
            let scale = Float(projectile.number("scale"))
            effect.scale = scale > 0 ? scale : 1
        }
        return effect.isDrawable ? [ effect ] : []
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
                )
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
            image: nil,
            radius: radius,
            isWave: isWave
        )
        if case let file = record?.text("effectFile") ?? "", !file.isEmpty {
            let read = particles(at: file)
            effect.image = read.image
            effect.emission = read.emission
        }

        if case let mesh = record?.text("meshName") ?? "", !mesh.isEmpty, let loaded = try? self.mesh(at: mesh) {
            effect.model = DrawnModel(mesh: loaded, textures: skins(for: loaded, at: mesh, preferring: nil))
            // A record that states no scale draws its model as it was built.
            let stated = Float(record?.number("scale") ?? 0)
            effect.scale = stated > 0 ? stated : 1
            effect.motion = (record?.text("animationName")).flatMap { $0.isEmpty ? nil : try? animation(at: $0) }
        }
        return effect
    }

    /// What one particle system is: the picture it draws with, and the part of the emitter whose
    /// meaning is known.
    ///
    /// `PfxFile` takes the file apart the way the engine's own reader does. A system that will not parse
    /// — the handful the engine sends to its older reader — falls back to scanning the bytes for a
    /// texture path, which is all the app could do before the format was read.
    private func particles(at path: String) -> (image: CGImage?, emission: ModelEffect.Emission?) {
        guard let bytes = try? data(at: path) else { return (nil, nil) }
        guard let system = try? PfxFile(bytes) else { return (image(ofParticles: bytes), nil) }

        let named = system.strings.first { $0.lowercased().hasSuffix(".tex") }
        let image =
            named.flatMap { textures.image(at: $0.replacingOccurrences(of: "\\", with: "/")) }
            .flatMap { Self.glowing($0) } ?? image(ofParticles: bytes)

        // One curve as the emitter reads it, a centred slot put back on nothing first.
        func shape(_ index: Int) -> PfxFile.Curve {
            guard
                system.curves.indices.contains(index)
            else {
                return PfxFile.Curve(domain: 0, range: 0, keys: [])
            }

            let curve = system.curves[index]
            guard Curve.centred.contains(index) else { return curve }

            let nothing = curve.range / 2
            return PfxFile.Curve(
                domain: curve.domain,
                range: curve.range,
                keys: curve.keys.map { ($0.time, $0.value - nothing) }
            )
        }

        // The furthest from nothing, keeping its sign: a curve that pulls upward peaks upward.
        func peak(_ index: Int) -> Float {
            shape(index).keys.map(\.value).max { abs($0) < abs($1) } ?? 0
        }

        let rate = peak(Curve.rate)
        let lifetime = system.floats.first ?? 0
        guard rate > 0 || lifetime > 0 else { return (image, nil) }

        return (
            image,
            ModelEffect.Emission(
                rate: rate,
                lifetime: lifetime,
                duration: system.curves.indices.contains(Curve.rate)
                    ? system.curves[Curve.rate].domain : 0,
                size: max(peak(Curve.size), peak(Curve.sizeOverLife)),
                speed: peak(Curve.speed),
                spread: peak(Curve.spread),
                extent: SIMD3(peak(Curve.extentX), peak(Curve.extentY), peak(Curve.extentZ)),
                turn: SIMD3(peak(Curve.turnX), peak(Curve.turnY), peak(Curve.turnZ)),
                gravity: peak(Curve.gravity),
                spin: peak(Curve.spin),
                drag: peak(Curve.drag),
                red: peak(Curve.red),
                green: peak(Curve.green),
                blue: peak(Curve.blue),
                alpha: peak(Curve.alpha),
                shading: ModelEffect.Emission.Shading(
                    shader: system.strings.count > 1 ? system.strings[1] : ""
                ),
                isFlat: system.flags.count > 5 && system.flags[5],
                anchored: system.integers.count > 1 ? Int(max(system.integers[1], 0)) : 0,
                shapes: ModelEffect.Emission.Shapes(
                    rate: shape(Curve.rate),
                    size: shape(Curve.sizeOverLife),
                    alpha: shape(Curve.alpha),
                    red: shape(Curve.red),
                    green: shape(Curve.green),
                    blue: shape(Curve.blue),
                    spin: shape(Curve.spin)
                )
            )
        )
    }

    /// Which slot of an emitter is which, traced to where `Engine.dll` reads it. Every one of the 26 is
    /// accounted for; slots 12 and 13 are the two the emitter never touches and have no name here.
    private enum Curve {
        /// The slots that run both ways, whose nothing is half their own range rather than zero.
        static let centred: Set<Int> = [
            spin, gravity, extentX, extentY, extentZ, swirl, turnX, turnY, turnZ,
        ]

        /// Written into the particle's colour by `Emitter::UpdateParticles` @ `0x18006c6c0`, alpha last.
        static let alpha = 0
        static let red = 1
        static let green = 2
        static let blue = 3
        /// Added to the particle's own angle every frame.
        static let spin = 4
        /// Scaled by the emitter's scale into the particle's size.
        static let sizeOverLife = 5
        static let rate = 6
        static let speed = 7
        /// Taken off the particle's velocity every frame.
        static let gravity = 8
        /// `Emitter::Update` keeps these three as the emitter's own reach, and `EmitParticle` offsets a
        /// new particle by them.
        static let extentX = 9
        static let extentY = 10
        static let extentZ = 11
        /// The cone a particle is thrown into, in degrees.
        static let spread = 14
        static let size = 15
        /// Turns the particle's velocity about the upright, which is what makes a drift swirl.
        static let swirl = 16
        /// The particle's second size, beside the first. Nothing in most systems.
        static let stretch = 17
        /// Degrees a second the emitter itself turns, through `IncrementXRot` and its two siblings.
        static let turnX = 18
        static let turnY = 19
        static let turnZ = 20
        /// What is left of the velocity each frame.
        static let drag = 21
        /// The light the emitter casts, which `Emitter::UpdateLight` @ `0x18006b670` writes straight
        /// into the light's own colour and radius.
        static let lightRed = 22
        static let lightGreen = 23
        static let lightBlue = 24
        static let lightRadius = 25
    }

    /// The texture a particle system draws with, found by scanning the file. Only a system the reader
    /// cannot take apart needs this: the paths are written as a length and then the bytes, so they are
    /// read the way a mesh's material paths are.
    private func image(ofParticles bytes: [UInt8]) -> CGImage? {
        var candidates = [String]()
        var offset = 0
        while offset + 4 <= bytes.count {
            let length = Int(
                UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                    | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
            )
            guard
                length > 4,
                length < 256,
                offset + 4 + length <= bytes.count,
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
    static func glowing(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
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

    /// Where a projectile leaves from when the skill does not say, out of the limb the animation calls
    /// out on the frame it lets go. Empty for a callback naming no side, which falls back as before.
    static func launchPoint(calledOut name: String) -> String {
        let called = name.lowercased().replacingOccurrences(of: " ", with: "")
        guard called.contains("hand") else { return "" }

        if called.contains("left") { return "L Hand" }
        if called.contains("right") { return "R Hand" }
        return ""
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
        return
            name
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
