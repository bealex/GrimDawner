// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation
import simd

/// A Grim Dawn model, read out of a `.msh` file.
///
/// The format is Titan Quest's, undocumented and reverse-engineered here: four magic bytes, then a flat
/// list of chunks, each an id, a byte count and that many bytes. What a chunk means is its id — the
/// vertices, the triangles, the bounding box, the materials, the skeleton. Vertices are stored in the
/// bind pose, so a still draws without the skeleton being posed at all.
public struct MshFile: Sendable {
    /// One vertex, in the game's own coordinates.
    ///
    /// `bones` are slots of the group's own bone list rather than of the skeleton, and a slot whose
    /// weight is zero holds no bone at all.
    public struct Vertex: Sendable {
        public let position: SIMD3<Float>
        public let normal: SIMD3<Float>
        public let texture: SIMD2<Float>
        public let bones: SIMD4<UInt8>
        public let weights: SIMD4<Float>
    }

    /// A joint of the skeleton the model hangs off.
    ///
    /// The hierarchy is written as runs: a bone's children are the `childCount` bones starting at
    /// `firstChild`, which makes every bone's parent the one that claims it.
    public struct Bone: Sendable {
        public let name: String
        /// Where the bone sits in its parent, in the bind pose.
        public let transform: simd_float4x4
        public let firstChild: Int
        public let childCount: Int
    }

    /// What the model is painted with. A mesh names its shader and the textures that go into it.
    public struct Material: Sendable {
        public let shader: String
        /// Texture paths by the name the shader gives them — `diffuseTexture`, `bumpTexture`, `specTexture`.
        public let textures: [String: String]

        /// The skin, which a mesh names as either of two slots depending on its shader.
        public var diffuse: String? { textures["baseTexture"] ?? textures["diffuseTexture"] }
    }

    /// A run of triangles painted with one material. A creature is usually two or three of these — its
    /// body, its vines, the crystal growing out of it — and painting them all with the first material is
    /// what puts one part's skin on another.
    public struct Group: Sendable {
        public let material: Int
        public let firstTriangle: Int
        public let triangleCount: Int
        /// The skeleton bones this group's vertices hang off, which is what a vertex's four bone slots
        /// index: the game gives each group its own short list rather than indexing the whole skeleton.
        public let bones: [Int]
    }

    /// A point on the model the game hangs something off — an effect, a sound, a blow. The animations
    /// name these rather than bones: a fire breath is spawned at `Mouth`, a spawning cloud at `Target`.
    public struct Attachment: Sendable {
        public let name: String
        /// The bone it hangs from, empty for one that stands in the model itself.
        public let parent: String
        /// Where it sits in that bone.
        public let transform: simd_float4x4
    }

    public let vertices: [Vertex]
    /// Triangles, three indices each, in the order the file lists them.
    public let indices: [UInt16]
    public let groups: [Group]
    public let materials: [Material]
    public let bones: [Bone]
    public let attachments: [Attachment]
    public let bounds: (minimum: SIMD3<Float>, maximum: SIMD3<Float>)

    public var triangleCount: Int { indices.count / 3 }

    /// True when the model can be posed: it has a skeleton and its vertices name bones of it.
    public var isSkinned: Bool { !bones.isEmpty && !groups.contains { $0.bones.isEmpty } }

    /// Each bone's parent, or `nil` for the root the hierarchy hangs from.
    public var boneParents: [Int?] {
        var parents = [Int?](repeating: nil, count: bones.count)
        for (index, bone) in bones.enumerated() {
            for child in bone.firstChild ..< (bone.firstChild + bone.childCount) where child < bones.count {
                parents[child] = index
            }
        }
        return parents
    }

    /// Where every bone sits in the model itself, which is the pose the vertices are written in.
    public func boneBindTransforms() -> [simd_float4x4] {
        let parents = boneParents
        var world = [simd_float4x4](repeating: matrix_identity_float4x4, count: bones.count)
        for index in bones.indices {
            // A bone is written after its parent, so one pass down the list is enough.
            world[index] = parents[index].map { world[$0] * bones[index].transform } ?? bones[index].transform
        }
        return world
    }

    /// True for the game's invisible blockers: a model that states no vertices and draws nothing.
    public var isEmpty: Bool { vertices.isEmpty || indices.isEmpty }

    public enum Failure: LocalizedError {
        case notAMesh
        case truncated(chunk: UInt32)
        case unreadableVertices

        public var errorDescription: String? {
            switch self {
                case .notAMesh: "Not a Grim Dawn mesh: the file does not start with MSH."
                case let .truncated(chunk): "The mesh ends inside chunk \(chunk)."
                case .unreadableVertices: "The mesh's vertex block is not laid out as any known format."
            }
        }
    }

    /// The chunks this reader knows. Everything else — the skeleton among them — is stepped over.
    private enum Chunk: UInt32 {
        case bounds = 10
        case vertices = 4
        case indices = 5
        case bones = 6
        case materials = 7
        case attachments = 3
    }

    /// What each element of a vertex declaration is, and how many bytes it takes. The declaration lists
    /// them in the order they are written, so an element's offset is what the ones before it take.
    private enum Element: UInt32 {
        case position = 0
        case normal = 1
        case tangent = 2
        case bitangent = 3
        case texture = 4
        /// Four weights, one per bone the vertex hangs off.
        case boneWeights = 5
        /// Those four bones, a byte each — which is why reading them as a float gives nonsense.
        case boneIndices = 6
        /// A second set of texture coordinates, which a handful of models carry and nothing here reads.
        case secondTexture = 7
        /// Colour painted on the vertex, four bytes of it.
        case colour = 14

        var size: Int {
            switch self {
                case .position, .normal, .tangent, .bitangent: 12
                case .texture, .secondTexture: 8
                case .boneIndices, .colour: 4
                case .boneWeights: 16
            }
        }
    }

    public init(_ bytes: [UInt8]) throws {
        guard bytes.count > 8, bytes[0] == 0x4D, bytes[1] == 0x53, bytes[2] == 0x48 else { throw Failure.notAMesh }

        var vertices = [Vertex]()
        var indices = [UInt16]()
        var groups = [Group]()
        var materials = [Material]()
        var bones = [Bone]()
        var attachments = [Attachment]()
        var bounds = (minimum: SIMD3<Float>.zero, maximum: SIMD3<Float>.zero)
        let reader = Reader(bytes)

        var offset = 4
        while offset + 8 <= bytes.count {
            let id = reader.word(offset)
            let size = Int(reader.word(offset + 4))
            let start = offset + 8
            guard size >= 0, start + size <= bytes.count else { throw Failure.truncated(chunk: id) }

            switch Chunk(rawValue: id) {
                case .bounds:
                    bounds = (
                        SIMD3(reader.float(start), reader.float(start + 4), reader.float(start + 8)),
                        SIMD3(reader.float(start + 12), reader.float(start + 16), reader.float(start + 20))
                    )

                case .vertices:
                    vertices = try Self.vertices(reader, at: start, size: size)

                case .indices:
                    let read = Self.indices(reader, at: start, size: size)
                    indices = read.indices
                    groups = read.groups

                case .bones:
                    bones = Self.bones(reader, at: start, size: size)

                case .materials:
                    materials = Self.materials(reader, at: start, size: size)

                case .attachments:
                    attachments = Self.attachments(
                        in: String(decoding: bytes[start ..< (start + size)], as: UTF8.self)
                    )

                case nil:
                    break
            }
            offset = start + size
        }

        self.vertices = vertices
        self.indices = indices
        // A model that names no groups is one group of everything it holds.
        self.groups = groups.isEmpty
            ? [ Group(material: 0, firstTriangle: 0, triangleCount: indices.count / 3, bones: []) ]
            : groups
        self.materials = materials
        self.bones = bones
        self.attachments = attachments
        self.bounds = bounds
    }

    /// The vertex block: a format, the bytes one vertex takes, how many there are, then a declaration of
    /// what each vertex holds, then the vertices themselves.
    private static func vertices(_ reader: Reader, at start: Int, size: Int) throws -> [Vertex] {
        guard size >= 12 else { throw Failure.unreadableVertices }

        let stride = Int(reader.word(start + 4))
        let count = Int(reader.word(start + 8))
        // A model with no vertices is one of the game's invisible blockers, which is a model all the same.
        guard count > 0 else { return [] }
        guard stride > 0, count * stride <= size else { throw Failure.unreadableVertices }

        // Whatever is between the counts and the vertex data is the declaration, one word per element.
        let declaration = (size - count * stride - 12) / 4
        guard declaration > 0 else { throw Failure.unreadableVertices }

        var offsets = [Element: Int]()
        var running = 0
        for index in 0 ..< declaration {
            guard let element = Element(rawValue: reader.word(start + 12 + index * 4)) else {
                throw Failure.unreadableVertices
            }

            offsets[element] = running
            running += element.size
        }
        guard running == stride, let position = offsets[.position] else { throw Failure.unreadableVertices }

        let data = start + 12 + declaration * 4
        return (0 ..< count).map { index in
            let base = data + index * stride
            let weights = offsets[.boneWeights].map { offset in
                SIMD4((0 ..< 4).map { reader.float(base + offset + $0 * 4) })
            } ?? .zero
            let bones = offsets[.boneIndices].map { offset in
                SIMD4((0 ..< 4).map { reader.byte(base + offset + $0) })
            } ?? .zero

            return Vertex(
                position: reader.vector(base + position),
                normal: offsets[.normal].map { reader.vector(base + $0) } ?? SIMD3(0, 1, 0),
                texture: offsets[.texture].map {
                    SIMD2(reader.float(base + $0), reader.float(base + $0 + 4))
                } ?? .zero,
                bones: bones,
                weights: weights
            )
        }
    }

    /// The triangle block: how many triangles, how many groups they fall into, three indices each, and
    /// then a description of every group.
    ///
    /// A group is a material, the triangle it starts at and how many it covers, a bounding box, and the
    /// bones it hangs off — the bones being what makes the blocks different lengths.
    private static func indices(_ reader: Reader, at start: Int, size: Int)
        -> (indices: [UInt16], groups: [Group]) {
        guard size >= 8 else { return ([], []) }

        let triangles = Int(reader.word(start))
        let count = Int(reader.word(start + 4))
        guard triangles > 0, 8 + triangles * 6 <= size else { return ([], []) }

        let indices = (0 ..< triangles * 3).map { reader.half(start + 8 + $0 * 2) }
        var groups = [Group]()
        var offset = start + 8 + triangles * 6

        for _ in 0 ..< count {
            guard offset + 44 <= start + size else { break }

            let bones = Int(reader.word(offset + 40))
            groups.append(Group(
                material: Int(reader.word(offset)),
                firstTriangle: Int(reader.word(offset + 4)),
                triangleCount: Int(reader.word(offset + 8)),
                bones: (0 ..< bones).map { Int(reader.word(offset + 44 + $0 * 4)) }
            ))
            offset += 44 + bones * 4
        }
        return (indices, groups)
    }

    /// The skeleton block: how many bones, then each as a 32-byte name, the run of children it claims,
    /// and where it sits in its parent — three rows of a rotation and then the translation.
    private static func bones(_ reader: Reader, at start: Int, size: Int) -> [Bone] {
        guard size >= 4 else { return [] }

        let count = Int(reader.word(start))
        guard count > 0, 4 + count * 88 <= size else { return [] }

        return (0 ..< count).map { index in
            let base = start + 4 + index * 88
            let rows = (0 ..< 4).map { reader.vector(base + 32 + 8 + $0 * 12) }

            return Bone(
                name: reader.name(base, length: 32),
                // The rows are the transform's basis vectors, which are its columns.
                transform: simd_float4x4(
                    SIMD4(rows[0], 0), SIMD4(rows[1], 0), SIMD4(rows[2], 0), SIMD4(rows[3], 1)
                ),
                firstChild: Int(reader.word(base + 32)),
                childCount: Int(reader.word(base + 36))
            )
        }
    }

    /// The attachment block, which the file writes as text:
    ///
    ///     AttachPoint { name = "Mouth" parent = "Bip01 Head" origin = (…) xAxis = (…) yAxis, zAxis }
    private static func attachments(in text: String) -> [Attachment] {
        text.components(separatedBy: "AttachPoint").dropFirst().compactMap { block in
            guard let name = block.firstMatch(between: "name   = \"", and: "\"") else { return nil }

            func vector(_ field: String) -> SIMD3<Float> {
                guard let text = block.firstMatch(between: "\(field)  = (", and: ")")
                    ?? block.firstMatch(between: "\(field) = (", and: ")")
                else { return .zero }

                let numbers = text.split(separator: ",").compactMap {
                    Float($0.trimmingCharacters(in: .whitespaces))
                }
                return numbers.count == 3 ? SIMD3(numbers[0], numbers[1], numbers[2]) : .zero
            }

            return Attachment(
                name: name,
                parent: block.firstMatch(between: "parent = \"", and: "\"") ?? "",
                transform: simd_float4x4(
                    SIMD4(vector("xAxis"), 0), SIMD4(vector("yAxis"), 0), SIMD4(vector("zAxis"), 0),
                    SIMD4(vector("origin"), 1)
                )
            )
        }
    }

    /// The material block: a shader and the slots it fills, each a name and then a value.
    ///
    /// A value is a path for a texture and a number for anything else — a specular colour, a glow
    /// strength — and nothing in the block says which. So this reads the strings and pairs a slot whose
    /// name ends in `Texture` with the path that follows it, stepping over the numbers between.
    private static func materials(_ reader: Reader, at start: Int, size: Int) -> [Material] {
        let strings = reader.strings(in: start ..< (start + size))
        var materials = [Material]()
        var shader = ""
        var textures = [String: String]()

        func close() {
            guard !shader.isEmpty else { return }

            materials.append(Material(shader: shader, textures: textures))
            textures = [:]
        }

        var index = 0
        while index < strings.count {
            let text = strings[index]
            if text.lowercased().hasSuffix(".ssh") {
                close()
                shader = text
            } else if
                text.lowercased().hasSuffix("texture"),
                index + 1 < strings.count,
                strings[index + 1].contains("/"),
                // An empty slot is followed by the next material's shader, and swallowing that would
                // fold two materials into one.
                !strings[index + 1].lowercased().hasSuffix(".ssh") {
                textures[text] = strings[index + 1]
                index += 1
            }
            index += 1
        }
        close()
        return materials
    }

    /// Little-endian reads over the file's bytes.
    private struct Reader {
        let bytes: [UInt8]

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        func word(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16
                | UInt32(bytes[offset + 3]) << 24
        }

        func half(_ offset: Int) -> UInt16 { UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8 }

        func byte(_ offset: Int) -> UInt8 { bytes[offset] }

        /// A fixed-width name, which the file pads with zeroes.
        func name(_ offset: Int, length: Int) -> String {
            String(decoding: bytes[offset ..< (offset + length)].prefix { $0 != 0 }, as: UTF8.self)
        }

        func float(_ offset: Int) -> Float { Float(bitPattern: word(offset)) }

        func vector(_ offset: Int) -> SIMD3<Float> {
            SIMD3(float(offset), float(offset + 4), float(offset + 8))
        }

        /// Every length-prefixed string in a stretch of the file, in the order it holds them.
        ///
        /// A run reads as a string when its length is sane and its bytes are all printable, which is
        /// enough to tell a name from the numbers packed around it.
        func strings(in range: Range<Int>) -> [String] {
            var found = [String]()
            var offset = range.lowerBound

            while offset + 4 <= range.upperBound {
                let length = Int(word(offset))
                guard
                    length > 2,
                    length < 256,
                    offset + 4 + length <= range.upperBound,
                    bytes[(offset + 4) ..< (offset + 4 + length)].allSatisfy({ $0 >= 32 && $0 < 127 })
                else {
                    // The fields are word-aligned, and stepping a byte at a time finds false strings
                    // inside the numbers — one of which swallows the material that follows it.
                    offset += 4
                    continue
                }

                found.append(String(decoding: bytes[(offset + 4) ..< (offset + 4 + length)], as: UTF8.self))
                offset += 4 + length
            }
            return found
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
