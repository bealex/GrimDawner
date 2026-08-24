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

    /// The skeleton: names, the run of children each bone claims, and where it sits in its parent.
    @Test
    func readsASkeleton() throws {
        func word(_ value: UInt32) -> [UInt8] {
            [ UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 24 & 0xFF) ]
        }
        func float(_ value: Float) -> [UInt8] { word(value.bitPattern) }
        func padded(_ text: String) -> [UInt8] { Array(text.utf8) + [UInt8](repeating: 0, count: 32 - text.utf8.count) }

        // A root with one child, which stands a unit above it.
        var bones = word(2)
        bones += padded("Target_CTRL") + word(1) + word(1)
        bones += float(1) + float(0) + float(0) + float(0) + float(1) + float(0) + float(0) + float(0) + float(1)
        bones += float(0) + float(0) + float(0)
        bones += padded("BN_Root") + word(2) + word(0)
        bones += float(1) + float(0) + float(0) + float(0) + float(1) + float(0) + float(0) + float(0) + float(1)
        bones += float(0) + float(1) + float(0)

        let bytes: [UInt8] = Array("MSH".utf8) + [ 3 ] + word(6) + word(UInt32(bones.count)) + bones
        let mesh = try MshFile(bytes)
        #expect(mesh.bones.map(\.name) == [ "Target_CTRL", "BN_Root" ])
        #expect(mesh.boneParents == [ nil, 0 ])
        #expect(mesh.boneBindTransforms()[1].columns.3.y == 1)
    }

    @Test
    func refusesWhatIsNotAMesh() {
        #expect(throws: MshFile.Failure.self) { try MshFile(Array("GDCX".utf8)) }
    }
}
