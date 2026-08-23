// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation
import GrimDawnerEngine
import GrimDawnerMesh
import Testing

@testable import GrimDawnerRender

/// The renderer against the installed game, whose folder is machine-specific: set `GRIM_DAWN_FOLDER`
/// to run these, and they skip without it.
struct ModelRendererTests {
    private static var gameFolder: URL? {
        ProcessInfo.processInfo.environment["GRIM_DAWN_FOLDER"].map { URL(fileURLWithPath: $0) }
    }

    /// Every model the creatures' archive holds, read from end to end. A format the reader does not
    /// know shows up here rather than as a hole in the gallery.
    @Test
    func readsEveryCreatureModel() throws {
        guard let folder = Self.gameFolder else { return }

        let renderer = ModelRenderer(gameFolder: folder)
        var read = 0

        for name in try Self.modelNames(in: folder) {
            let mesh = try renderer.mesh(at: "creatures/\(name)")
            guard !mesh.isEmpty else { continue }

            read += 1
            #expect(mesh.triangleCount > 0, "\(name) has no triangles")
            #expect(mesh.indices.allSatisfy { Int($0) < mesh.vertices.count }, "\(name) points past its vertices")
        }
        #expect(read > 400, "read \(read) models")
    }

    /// One model drawn, which is the whole pipeline: archive, mesh, texture, scene, image.
    @MainActor
    @Test
    func drawsAModel() throws {
        guard let folder = Self.gameFolder else { return }

        let renderer = ModelRenderer(gameFolder: folder)
        guard let name = try Self.modelNames(in: folder).first else { return }

        let image = try renderer.image(meshAt: "creatures/\(name)", size: CGSize(width: 64, height: 64))
        #expect(image.width == 64)
        #expect(image.height == 64)
    }

    private static func modelNames(in folder: URL) throws -> [String] {
        let archive = try ArcArchive(contentsOf: folder.appending(path: "resources/Creatures.arc"))
        return archive.entryNames.filter { $0.hasSuffix(".msh") }.sorted()
    }
}
