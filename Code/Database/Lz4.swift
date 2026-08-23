// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation

/// LZ4 block-format decompression, the encoding used inside `.arz` records and `.arc` file parts.
///
/// This is the bare block format — no frame header, no checksum — so the caller must already know the
/// decompressed size.
///
/// The inner loop runs over unsafe buffers and copies whole runs at a time: a single constellation texture
/// is two thirds of a megabyte, and a byte-at-a-time loop over that is visible as a stall on screen.
enum Lz4 {
    enum Failure: LocalizedError {
        case corrupt(String)

        var errorDescription: String? {
            switch self {
                case let .corrupt(detail): "Corrupt LZ4 block: \(detail)."
            }
        }
    }

    static func decompress(_ input: [UInt8], decompressedSize: Int) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: decompressedSize)

        let written = try input.withUnsafeBufferPointer { source in
            try output.withUnsafeMutableBufferPointer { target in
                try expand(source, into: target)
            }
        }

        guard
            written == decompressedSize
        else {
            throw Failure.corrupt("produced \(written) of \(decompressedSize) bytes")
        }

        return output
    }

    private static func expand(
        _ source: UnsafeBufferPointer<UInt8>,
        into target: UnsafeMutableBufferPointer<UInt8>
    ) throws -> Int {
        var readIndex = 0
        var writeIndex = 0

        /// Lengths above 14 continue in 255-valued bytes until one falls short.
        func readLength(_ initial: Int) -> Int {
            var length = initial
            guard length == 15 else { return length }

            while readIndex < source.count {
                let byte = Int(source[readIndex])
                readIndex += 1
                length += byte
                if byte != 255 { break }
            }
            return length
        }

        while readIndex < source.count {
            let token = Int(source[readIndex])
            readIndex += 1

            let literals = readLength(token >> 4)
            guard
                readIndex + literals <= source.count,
                writeIndex + literals <= target.count
            else {
                throw Failure.corrupt("literal run overruns the buffer")
            }

            copy(from: source, at: readIndex, to: target, at: writeIndex, count: literals)
            readIndex += literals
            writeIndex += literals

            // A block ends on its literal run: there is no match after the last token.
            if readIndex >= source.count { break }

            guard readIndex + 2 <= source.count else { throw Failure.corrupt("truncated match offset") }

            let offset = Int(source[readIndex]) | (Int(source[readIndex + 1]) << 8)
            readIndex += 2
            guard offset > 0, offset <= writeIndex else { throw Failure.corrupt("match offset \(offset)") }

            let length = readLength(token & 0x0F) + 4
            guard
                writeIndex + length <= target.count
            else {
                throw Failure.corrupt("match overruns the buffer")
            }

            writeIndex = repeatMatch(in: target, at: writeIndex, offset: offset, length: length)
        }

        return writeIndex
    }

    private static func copy(
        from source: UnsafeBufferPointer<UInt8>,
        at readIndex: Int,
        to target: UnsafeMutableBufferPointer<UInt8>,
        at writeIndex: Int,
        count: Int
    ) {
        guard count > 0 else { return }

        target.baseAddress!.advanced(by: writeIndex)
            .update(from: source.baseAddress!.advanced(by: readIndex), count: count)
    }

    /// Copies a run already present in the output, returning the new write position.
    private static func repeatMatch(
        in target: UnsafeMutableBufferPointer<UInt8>,
        at writeIndex: Int,
        offset: Int,
        length: Int
    ) -> Int {
        var write = writeIndex
        var read = writeIndex - offset

        guard
            offset < length
        else {
            // The run does not overlap what it is writing, so it can move in one go.
            target.baseAddress!.advanced(by: write)
                .update(from: target.baseAddress!.advanced(by: read), count: length)
            return write + length
        }

        // Overlapping matches are how LZ4 encodes runs; they must be copied byte by byte.
        for _ in 0 ..< length {
            target[write] = target[read]
            write += 1
            read += 1
        }
        return write
    }
}
