// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation
import Testing

@testable import GrimDawnerMesh

struct AnmFileTests {
    /// An animation built by hand, so the reader is exercised without the game installed.
    @Test
    func readsAnAnimationItIsGiven() throws {
        func word(_ value: UInt32) -> [UInt8] {
            [ UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 24 & 0xFF) ]
        }
        func float(_ value: Float) -> [UInt8] { word(value.bitPattern) }
        func name(_ text: String) -> [UInt8] { word(UInt32(text.utf8.count)) + Array(text.utf8) }

        // Two bones over three frames, the second sliding a unit along x as they go.
        var bytes: [UInt8] = Array("ANM".utf8) + [ 2 ] + word(2) + word(3) + word(30)
        for bone in 0 ..< 2 {
            bytes += name(bone == 0 ? "Target_CTRL" : "BN_Root")
            for frame in 0 ..< 3 {
                bytes += float(bone == 1 ? Float(frame) : 0) + float(0) + float(0)
                bytes += float(0) + float(0) + float(0) + float(1)
                bytes += float(1) + float(1) + float(1)
                bytes += float(0) + float(0) + float(0) + float(1)
            }
        }
        bytes += Array("CallbackPoint\r\n{\r\n\tname = \"RightHandHit\"\r\n\tframe = 2\r\n}\r\n".utf8)

        let animation = try AnmFile(bytes)
        #expect(animation.frameCount == 3)
        #expect(animation.framesPerSecond == 30)
        #expect(animation.duration == 0.1)
        #expect(animation.tracks.map(\.bone) == [ "Target_CTRL", "BN_Root" ])
        #expect(animation.tracks[1].keys[2].translation.x == 2)
        // The rotation is turned the other way round as it is read, so an identity stays an identity.
        #expect(animation.tracks[0].keys[0].rotation.real == 1)
        #expect(animation.tracks[0].keys.count == 3)
        #expect(animation.events.map(\.name) == [ "RightHandHit" ])
        #expect(animation.events.first?.frame == 2)
    }

    @Test
    func refusesWhatIsNotAnAnimation() {
        #expect(throws: AnmFile.Failure.self) { try AnmFile(Array("MSH\u{2}aaaaaaaaaaaaaaaa".utf8)) }
    }
}
