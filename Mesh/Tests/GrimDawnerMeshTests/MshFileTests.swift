// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation
import Testing

@testable import GrimDawnerMesh

struct MshFileTests {
    /// A mesh built by hand, so the reader is exercised without the game installed.
    @Test
    func readsAMeshItIsGiven() throws {
        func word(_ value: UInt32) -> [UInt8] {
            [ UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 24 & 0xFF) ]
        }
        func float(_ value: Float) -> [UInt8] { word(value.bitPattern) }

        var bytes: [UInt8] = Array("MSH".utf8) + [ 3 ]

        // Three vertices of position and texture alone, and the one triangle they make.
        var vertices = word(5) + word(20) + word(3) + word(0) + word(4)
        for index in 0 ..< 3 {
            vertices += float(Float(index)) + float(0) + float(0) + float(0.5) + float(0.25)
        }
        bytes += word(4) + word(UInt32(vertices.count)) + vertices

        let indices = word(1) + word(1) + [ 0, 0, 1, 0, 2, 0 ]
        bytes += word(5) + word(UInt32(indices.count)) + indices

        let mesh = try MshFile(bytes)
        #expect(mesh.vertices.count == 3)
        #expect(mesh.triangleCount == 1)
        #expect(mesh.vertices[2].position.x == 2)
        #expect(mesh.vertices[0].texture == SIMD2(0.5, 0.25))
    }

    @Test
    func refusesWhatIsNotAMesh() {
        #expect(throws: MshFile.Failure.self) { try MshFile(Array("GDCX".utf8)) }
    }
}
