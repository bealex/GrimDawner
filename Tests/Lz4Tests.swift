// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Testing

@testable import GrimDawner

struct Lz4Tests {
    /// A single literal run: one token with a 5-literal length and no match.
    @Test
    func decodesLiteralsOnly() throws {
        let payload: [UInt8] = [ 0x41, 0x42, 0x43, 0x44, 0x45 ]
        let block: [UInt8] = [ 0x50 ] + payload

        #expect(try Lz4.decompress(block, decompressedSize: 5) == payload)
    }

    /// One literal, then a back-reference that overlaps itself — the run-length case.
    @Test
    func decodesOverlappingMatches() throws {
        let block: [UInt8] = [
            0x1F,  // 1 literal, match length 15 + 4 = 19
            0x5A,  // the literal "Z"
            0x01, 0x00,  // match offset 1
            0x00,  // trailing empty literal run
        ]

        #expect(try Lz4.decompress(block, decompressedSize: 20) == [UInt8](repeating: 0x5A, count: 20))
    }

    @Test
    func decodesExtendedLiteralLengths() throws {
        let payload = [UInt8](repeating: 0x2A, count: 20)
        let block: [UInt8] = [ 0xF0, 0x05 ] + payload

        #expect(try Lz4.decompress(block, decompressedSize: 20) == payload)
    }

    @Test
    func rejectsAnOffsetPointingBeforeTheOutput() {
        let block: [UInt8] = [ 0x10, 0x41, 0x05, 0x00, 0x00 ]

        #expect(throws: (any Error).self) { try Lz4.decompress(block, decompressedSize: 8) }
    }

    @Test
    func rejectsASizeMismatch() {
        let block: [UInt8] = [ 0x20, 0x41, 0x42 ]

        #expect(throws: (any Error).self) { try Lz4.decompress(block, decompressedSize: 9) }
    }
}
