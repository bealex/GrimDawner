// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation
import simd

/// One of the game's animations, read out of an `.anm` file.
///
/// The format is flat rather than chunked: `ANM`, a version byte, how many bones move, how many frames
/// they move over and how many of those go by in a second. Then comes one track per bone — its name,
/// then a transform for every frame, so the file is read straight through.
///
/// A track holds a bone's whole local transform rather than a change to it, so playing an animation
/// replaces the bind pose the mesh carries. The bones are named rather than numbered, and their order
/// is not the mesh's: an animation is bound to a skeleton by name.
///
/// What follows the tracks is plain text: the callback points the game hangs sounds, particles and the
/// moment a blow lands on.
public struct AnmFile: Sendable {
    /// Where a bone sits in its parent on one frame.
    public struct Key: Sendable {
        public let translation: SIMD3<Float>
        public let rotation: simd_quatf
        public let scale: SIMD3<Float>

        public var transform: simd_float4x4 {
            var matrix = simd_float4x4(rotation)
            matrix.columns.0 *= scale.x
            matrix.columns.1 *= scale.y
            matrix.columns.2 *= scale.z
            matrix.columns.3 = SIMD4(translation, 1)
            return matrix
        }
    }

    /// One bone's frames, in the order the file writes them.
    public struct Track: Sendable {
        public let bone: String
        public let keys: [Key]
    }

    /// A frame the animation calls something out on: a point the game hangs a sound or the moment a
    /// blow lands on — `RightHandHit`, `ShowRightHand` — or an effect it spawns at a point of the rig.
    public struct Event: Sendable {
        public enum Kind: Sendable, Equatable {
            case callback
            case entity
        }

        public let kind: Kind
        /// The callback's own name, or the record of the effect that is spawned.
        public let name: String
        public let frame: Int
        /// Where a spawned effect hangs — `HeadEffect`, `Target`. Empty for a callback.
        public let attachment: String
    }

    public let tracks: [Track]
    public let events: [Event]
    public let frameCount: Int
    public let framesPerSecond: Int

    public var duration: TimeInterval {
        framesPerSecond > 0 ? TimeInterval(frameCount) / TimeInterval(framesPerSecond) : 0
    }

    public enum Failure: LocalizedError {
        case notAnAnimation
        case truncated

        public var errorDescription: String? {
            switch self {
                case .notAnAnimation: "Not a Grim Dawn animation: the file does not start with ANM."
                case .truncated: "The animation ends inside a bone's track."
            }
        }
    }

    /// One frame of one bone: where it is, two quaternions that together are how it is turned, and how
    /// it is scaled.
    private static let keySize = 14 * 4

    public init(_ bytes: [UInt8]) throws {
        guard
            bytes.count > 16, bytes[0] == 0x41, bytes[1] == 0x4E, bytes[2] == 0x4D
        else { throw Failure.notAnAnimation }

        let reader = Reader(bytes)
        let boneCount = Int(reader.word(4))
        frameCount = Int(reader.word(8))
        framesPerSecond = Int(reader.word(12))
        guard boneCount > 0, frameCount > 0 else { throw Failure.truncated }

        var tracks = [Track]()
        var offset = 16
        for _ in 0 ..< boneCount {
            guard offset + 4 <= bytes.count else { throw Failure.truncated }

            let length = Int(reader.word(offset))
            guard length > 0, length < 256, offset + 4 + length + frameCount * Self.keySize <= bytes.count else {
                throw Failure.truncated
            }

            let name = String(decoding: bytes[(offset + 4) ..< (offset + 4 + length)], as: UTF8.self)
            offset += 4 + length
            let keys = (0 ..< frameCount).map { frame -> Key in
                let base = offset + frame * Self.keySize
                // A key holds the turn in two parts, and the bone's turn is the second laid over the
                // first. Nearly every bone writes the second as an identity, which is why it reads as
                // spare until a creature that uses it — a wight's spine — jumps ninety degrees between
                // one frame and the next.
                let first = simd_quatf(
                    ix: reader.float(base + 12), iy: reader.float(base + 16),
                    iz: reader.float(base + 20), r: reader.float(base + 24)
                )
                let second = simd_quatf(
                    ix: reader.float(base + 40), iy: reader.float(base + 44),
                    iz: reader.float(base + 48), r: reader.float(base + 52)
                )

                return Key(
                    translation: reader.vector(base),
                    // Turned the other way round: the file states how the bone's own frame moves under
                    // the pose, which is the reverse of how the pose moves the bone. Read as written, a
                    // knee bends forwards and an elbow backwards.
                    rotation: (second * first).conjugate,
                    scale: reader.vector(base + 28)
                )
            }
            tracks.append(Track(bone: name, keys: keys))
            offset += frameCount * Self.keySize
        }
        self.tracks = tracks
        events = Self.events(in: String(decoding: bytes[offset...], as: UTF8.self))
    }

    /// The events, which the file writes as text after the tracks:
    ///
    ///     CallbackPoint { name = "RightHandHit" frame = 11 }
    ///     CreateEntity  { frame = 1 entity = "records/fx/…_FX01.dbr" attach = "Target" }
    ///     RemoveEntity  { frame = 1 entity = "records/fx/…_FX01.dbr" }
    ///
    /// **The block's own word is what says which it is.** A `RemoveEntity` names an entity exactly as a
    /// `CreateEntity` does, and taking the name alone as a spawn puts the thing on the model at the very
    /// moment the game takes it off: the yeti animations remove a boulder they were carrying on frame 1
    /// of every walk and idle, which drew as an ice block in its hand while it stood still. Of the events
    /// the monsters' animations hold, 1,014 create and 46 remove.
    private static func events(in text: String) -> [Event] {
        text.components(separatedBy: "}").compactMap { block in
            let frame = block.range(of: "frame = ")
                .map { Int(block[$0.upperBound...].prefix { $0.isNumber }) ?? 0 } ?? 0

            if let name = block.firstMatch(between: "name = \"", and: "\"") {
                return Event(kind: .callback, name: name, frame: frame, attachment: "")
            }
            guard
                block.contains("CreateEntity"),
                let entity = block.firstMatch(between: "entity = \"", and: "\"")
            else { return nil }

            return Event(
                kind: .entity,
                name: entity,
                frame: frame,
                attachment: block.firstMatch(between: "attach = \"", and: "\"") ?? ""
            )
        }
    }

    private struct Reader {
        let bytes: [UInt8]

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        func word(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16
                | UInt32(bytes[offset + 3]) << 24
        }

        func float(_ offset: Int) -> Float { Float(bitPattern: word(offset)) }

        func vector(_ offset: Int) -> SIMD3<Float> {
            SIMD3(float(offset), float(offset + 4), float(offset + 8))
        }
    }
}

private extension String {
    func firstMatch(between opening: String, and closing: String) -> String? {
        guard
            let start = range(of: opening),
            let end = range(of: closing, range: start.upperBound ..< endIndex)
        else { return nil }

        return String(self[start.upperBound ..< end.lowerBound])
    }
}
