// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import CoreGraphics
import Foundation

/// Decoder for the game's `.tex` images.
///
/// A `.tex` is a twelve-byte wrapper around a DDS file whose magic reads `DDSR` rather than `DDS `. Almost
/// every icon is stored uncompressed at 32 bits per pixel; a handful use BC1 or BC3 block compression.
public enum Texture {
    public enum Failure: LocalizedError {
        case notATexture
        case unsupportedFormat(String)
        case truncated

        public var errorDescription: String? {
            switch self {
                case .notATexture: "Not a Grim Dawn texture."
                case let .unsupportedFormat(detail): "Unsupported texture format: \(detail)."
                case .truncated: "Texture data is truncated."
            }
        }
    }

    /// One decoded pixel; block compression needs to pass these around and interpolate between them.
    private struct Colour {
        public var red: UInt8
        public var green: UInt8
        public var blue: UInt8
        public var alpha: UInt8 = 255

        public static let transparent = Colour(red: 0, green: 0, blue: 0, alpha: 0)

        /// Mixes towards `other` in thirds, which is how BC blocks derive their two middle colours.
        public func blended(towards other: Colour, thirds weight: Int) -> Colour {
            func interpolate(_ from: UInt8, _ towards: UInt8) -> UInt8 {
                UInt8((Int(from) * (3 - weight) + Int(towards) * weight) / 3)
            }

            return Colour(
                red: interpolate(red, other.red),
                green: interpolate(green, other.green),
                blue: interpolate(blue, other.blue)
            )
        }

        public func midpoint(_ other: Colour) -> Colour {
            Colour(
                red: UInt8((Int(red) + Int(other.red)) / 2),
                green: UInt8((Int(green) + Int(other.green)) / 2),
                blue: UInt8((Int(blue) + Int(other.blue)) / 2)
            )
        }
    }

    private enum Layout {
        case uncompressed(bitsPerPixel: Int)
        case blockCompressed(hasAlphaBlock: Bool)
    }

    private static let wrapperSize = 12
    private static let ddsHeaderSize = 128  // four-byte magic plus a 124-byte header

    /// Decodes a `.tex` payload into an image, dropping any mipmaps below the full-size level.
    public static func image(from raw: [UInt8]) throws -> CGImage {
        guard
            raw.count > wrapperSize,
            raw[0] == 0x54,
            raw[1] == 0x45,
            raw[2] == 0x58
        else {
            throw Failure.notATexture
        }

        let header = wrapperSize
        guard
            raw.count > header + ddsHeaderSize,
            raw[header] == 0x44,
            raw[header + 1] == 0x44,
            raw[header + 2] == 0x53
        else { throw Failure.notATexture }

        let height = Int(try uint32(raw, header + 12))
        let width = Int(try uint32(raw, header + 16))
        guard
            width > 0,
            height > 0,
            width <= 8192,
            height <= 8192
        else {
            throw Failure.unsupportedFormat("\(width)x\(height)")
        }

        let pixelFormatFlags = try uint32(raw, header + 4 + 76)
        let fourCC = try uint32(raw, header + 4 + 80)
        let bitsPerPixel = Int(try uint32(raw, header + 4 + 84))

        let body = header + ddsHeaderSize
        let layout = try layout(pixelFormatFlags: pixelFormatFlags, fourCC: fourCC, bitsPerPixel: bitsPerPixel)
        // The game writes its mipmaps smallest first, so a texture that carries them keeps its full-size
        // level at the end of the file rather than at the start. Reading from the front instead gives a
        // montage of the small levels with the top of the real image below them.
        let level = levelSize(width: width, height: height, layout: layout)
        let start = raw.count - body > level ? raw.count - level : body
        let pixels = try decode(raw, at: start, width: width, height: height, layout: layout)

        return try makeImage(pixels, width: width, height: height)
    }

    /// What one mip level of this size takes: whole pixels, or four-by-four blocks of them.
    private static func levelSize(width: Int, height: Int, layout: Layout) -> Int {
        switch layout {
            case let .uncompressed(bitsPerPixel):
                width * height * bitsPerPixel / 8
            case let .blockCompressed(hasAlphaBlock):
                ((width + 3) / 4) * ((height + 3) / 4) * (hasAlphaBlock ? 16 : 8)
        }
    }

    private static func layout(pixelFormatFlags: UInt32, fourCC: UInt32, bitsPerPixel: Int) throws -> Layout {
        // DDPF_FOURCC
        if pixelFormatFlags & 0x4 != 0 {
            switch fourCC {
                case 0x3154_5844: return .blockCompressed(hasAlphaBlock: false)  // "DXT1"
                case 0x3354_5844, 0x3554_5844: return .blockCompressed(hasAlphaBlock: true)  // "DXT3"/"DXT5"
                default: throw Failure.unsupportedFormat("FourCC \(fourCC)")
            }
        }

        guard
            bitsPerPixel == 32 || bitsPerPixel == 24
        else {
            throw Failure.unsupportedFormat("\(bitsPerPixel) bits per pixel")
        }

        return .uncompressed(bitsPerPixel: bitsPerPixel)
    }

    /// Produces straight RGBA, one byte per channel.
    private static func decode(
        _ raw: [UInt8],
        at offset: Int,
        width: Int,
        height: Int,
        layout: Layout
    ) throws -> [UInt8] {
        switch layout {
            case let .uncompressed(bitsPerPixel):
                try readUncompressed(raw, at: offset, width: width, height: height, bitsPerPixel: bitsPerPixel)
            case let .blockCompressed(hasAlphaBlock):
                try readBlockCompressed(raw, at: offset, width: width, height: height, hasAlpha: hasAlphaBlock)
        }
    }

    /// The game stores uncompressed pixels in Direct3D's `A8R8G8B8`, which is byte order B, G, R, A.
    ///
    /// The swizzle and the alpha premultiply happen in one pass over unsafe buffers; some of these
    /// textures run to tens of thousands of pixels and a checked per-channel loop is far too slow.
    private static func readUncompressed(
        _ raw: [UInt8],
        at offset: Int,
        width: Int,
        height: Int,
        bitsPerPixel: Int
    ) throws -> [UInt8] {
        let stride = bitsPerPixel / 8
        let count = width * height
        guard offset + count * stride <= raw.count else { throw Failure.truncated }

        var pixels = [UInt8](repeating: 255, count: count * 4)
        raw.withUnsafeBufferPointer { source in
            pixels.withUnsafeMutableBufferPointer { target in
                for index in 0 ..< count {
                    let read = offset + index * stride
                    let write = index * 4
                    let alpha = stride == 4 ? Int(source[read + 3]) : 255
                    if alpha == 255 {
                        target[write] = source[read + 2]
                        target[write + 1] = source[read + 1]
                        target[write + 2] = source[read]
                    } else {
                        target[write] = UInt8(Int(source[read + 2]) * alpha / 255)
                        target[write + 1] = UInt8(Int(source[read + 1]) * alpha / 255)
                        target[write + 2] = UInt8(Int(source[read]) * alpha / 255)
                    }
                    target[write + 3] = UInt8(alpha)
                }
            }
        }
        return pixels
    }

    // MARK: - Block compression

    private static func readBlockCompressed(
        _ raw: [UInt8],
        at offset: Int,
        width: Int,
        height: Int,
        hasAlpha: Bool
    ) throws -> [UInt8] {
        let blockSize = hasAlpha ? 16 : 8
        let blocksAcross = (width + 3) / 4
        let blocksDown = (height + 3) / 4
        guard offset + blocksAcross * blocksDown * blockSize <= raw.count else { throw Failure.truncated }

        var pixels = [UInt8](repeating: 255, count: width * height * 4)

        for blockY in 0 ..< blocksDown {
            for blockX in 0 ..< blocksAcross {
                let base = offset + (blockY * blocksAcross + blockX) * blockSize
                let colourBase = hasAlpha ? base + 8 : base
                let colours = try palette(raw, at: colourBase, opaqueOnly: hasAlpha)
                let indices = try uint32(raw, colourBase + 4)
                let alpha = hasAlpha ? try alphaValues(raw, at: base) : nil

                for line in 0 ..< 4 {
                    for column in 0 ..< 4 {
                        let x = blockX * 4 + column
                        let y = blockY * 4 + line
                        guard x < width, y < height else { continue }

                        let cell = line * 4 + column
                        let colour = colours[Int((indices >> UInt32(cell * 2)) & 0b11)]
                        let opacity = Int(alpha?[cell] ?? colour.alpha)
                        let target = (y * width + x) * 4
                        pixels[target] = UInt8(Int(colour.red) * opacity / 255)
                        pixels[target + 1] = UInt8(Int(colour.green) * opacity / 255)
                        pixels[target + 2] = UInt8(Int(colour.blue) * opacity / 255)
                        pixels[target + 3] = UInt8(opacity)
                    }
                }
            }
        }

        return pixels
    }

    /// The four-colour palette a BC block interpolates between.
    private static func palette(_ raw: [UInt8], at offset: Int, opaqueOnly: Bool) throws -> [Colour] {
        let first = try uint16(raw, offset)
        let second = try uint16(raw, offset + 2)
        let lower = expand565(first)
        let upper = expand565(second)

        // In BC1 a first <= second block encodes one transparent slot instead of a fourth colour.
        guard
            opaqueOnly || first > second
        else {
            return [ lower, upper, lower.midpoint(upper), .transparent ]
        }

        return [
            lower,
            upper,
            lower.blended(towards: upper, thirds: 1),
            lower.blended(towards: upper, thirds: 2),
        ]
    }

    private static func expand565(_ value: UInt16) -> Colour {
        Colour(
            red: UInt8((Int((value >> 11) & 0x1F) * 255 + 15) / 31),
            green: UInt8((Int((value >> 5) & 0x3F) * 255 + 31) / 63),
            blue: UInt8((Int(value & 0x1F) * 255 + 15) / 31)
        )
    }

    /// BC3's alpha block: two endpoints and sixteen three-bit selectors.
    private static func alphaValues(_ raw: [UInt8], at offset: Int) throws -> [UInt8] {
        let first = try byte(raw, offset)
        let second = try byte(raw, offset + 1)

        var ramp = [ first, second ]
        if first > second {
            for step in 1 ... 6 {
                ramp.append(UInt8((Int(first) * (7 - step) + Int(second) * step) / 7))
            }
        } else {
            for step in 1 ... 4 {
                ramp.append(UInt8((Int(first) * (5 - step) + Int(second) * step) / 5))
            }
            ramp.append(0)
            ramp.append(255)
        }

        var bits: UInt64 = 0
        for index in 0 ..< 6 { bits |= UInt64(try byte(raw, offset + 2 + index)) << (8 * index) }

        return (0 ..< 16).map { ramp[Int((bits >> UInt64($0 * 3)) & 0b111)] }
    }

    // MARK: - Image construction

    /// Pixels arrive already premultiplied, which is what Core Graphics wants for this format.
    private static func makeImage(_ pixels: [UInt8], width: Int, height: Int) throws -> CGImage {
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard
            let provider = CGDataProvider(data: Data(pixels) as CFData),
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: info,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        else { throw Failure.unsupportedFormat("could not build an image") }

        return image
    }

    // MARK: - Byte access

    private static func byte(_ raw: [UInt8], _ offset: Int) throws -> UInt8 {
        guard offset >= 0, offset < raw.count else { throw Failure.truncated }

        return raw[offset]
    }

    private static func uint16(_ raw: [UInt8], _ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= raw.count else { throw Failure.truncated }

        return UInt16(raw[offset]) | (UInt16(raw[offset + 1]) << 8)
    }

    private static func uint32(_ raw: [UInt8], _ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= raw.count else { throw Failure.truncated }

        return UInt32(raw[offset])
            | (UInt32(raw[offset + 1]) << 8)
            | (UInt32(raw[offset + 2]) << 16)
            | (UInt32(raw[offset + 3]) << 24)
    }
}
