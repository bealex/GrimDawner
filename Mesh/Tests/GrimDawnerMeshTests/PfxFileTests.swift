// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation
import Testing

@testable import GrimDawnerMesh

/// The `.pfx` particle system, against bytes laid out the way the engine's own reader takes them —
/// `EmitterData::InternalBinaryRead`, five counted blocks after the magic. Written here rather than
/// read from the game, so it runs with nothing installed.
struct PfxFileTests {
    /// One file built by hand, so every block is known before it is read back.
    private static var bytes: [UInt8] {
        var bytes = [UInt8]()

        func integer(_ value: Int32) {
            let raw = UInt32(bitPattern: value)
            bytes += [ UInt8(raw & 0xFF), UInt8(raw >> 8 & 0xFF), UInt8(raw >> 16 & 0xFF), UInt8(raw >> 24 & 0xFF) ]
        }
        func real(_ value: Float) { integer(Int32(bitPattern: value.bitPattern)) }
        func text(_ value: String) {
            let utf8 = Array(value.utf8)
            integer(Int32(utf8.count))
            bytes += utf8
        }

        // The version and the emitter's own name, which the engine reads before it hands the reader on.
        integer(101)
        text("Test Emitter")
        bytes += Array("PFX1".utf8)
        integer(0)
        integer(956)

        integer(2)
        text("FX\\textures\\spark.tex")
        text("Shaders\\particle\\particlecombine.ssh")

        integer(3)
        for flag in [ 1, 0, 1 ] { integer(Int32(flag)) }

        integer(2)
        integer(7)
        integer(-1)

        integer(2)
        real(0.6)
        real(12.5)

        integer(2)
        // A curve of two keys, then one of none.
        real(0.6)
        real(1)
        integer(2)
        real(0)
        real(10)
        real(1)
        real(20)
        real(2)
        real(3)
        integer(0)

        return bytes
    }

    @Test
    func readsEveryBlockTheEngineWrites() throws {
        let file = try PfxFile(Self.bytes)

        #expect(file.strings == [ "FX\\textures\\spark.tex", "Shaders\\particle\\particlecombine.ssh" ])
        #expect(file.flags == [ true, false, true ])
        #expect(file.integers == [ 7, -1 ])
        #expect(file.floats == [ 0.6, 12.5 ])
        #expect(file.curves.count == 2)

        let curve = try #require(file.curves.first)
        #expect(curve.domain == 0.6)
        #expect(curve.range == 1)
        #expect(curve.keys.map(\.time) == [ 0, 1 ])
        #expect(curve.keys.map(\.value) == [ 10, 20 ])

        // A curve nothing was written into still reads, and reads as nothing.
        #expect(file.curves[1].keys.isEmpty)
        #expect(file.curves[1].value(at: 0.5) == 0)
    }

    /// The straight line between the two keys a point falls between, and the nearest key outside them.
    @Test
    func readsACurveBetweenItsKeys() throws {
        let curve = try #require(try PfxFile(Self.bytes).curves.first)

        #expect(curve.value(at: 0) == 10)
        #expect(curve.value(at: 1) == 20)
        #expect(abs(curve.value(at: 0.25) - 12.5) < 0.001)
        #expect(curve.value(at: -1) == 10)
        #expect(curve.value(at: 5) == 20)
    }

    /// A file the engine would send to its own older reader is not guessed at.
    @Test
    func refusesAFileWithoutTheMagic() {
        #expect(throws: PfxFile.Failure.self) { try PfxFile(Array("not a particle system".utf8)) }
    }
}
