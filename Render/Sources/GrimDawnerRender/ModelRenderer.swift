// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import CoreGraphics
import Foundation
import GrimDawnerEngine
import GrimDawnerMesh
import ImageIO
import SceneKit
import UniformTypeIdentifiers

/// Draws the game's own models: reads a mesh out of the archives, dresses it in its texture, and renders
/// it offscreen to an image.
public struct ModelRenderer {
    public init(gameFolder: URL, configuration: SceneConfiguration = SceneConfiguration()) {
        self.gameFolder = gameFolder
        textures = TextureStore(gameFolder: gameFolder)
        scene = ModelScene(configuration: configuration)
        var opened = [(root: String, archive: ArcArchive)]()
        for (root, name) in ModelRenderer.archiveRoots {
            for folder in ModelRenderer.expansionFolders {
                let url = gameFolder.appending(path: "\(folder)resources/\(name)")
                guard
                    FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
                    let archive = try? ArcArchive(contentsOf: url)
                else { continue }

                opened.append((root, archive))
            }
        }
        archives = opened
    }

    public let gameFolder: URL

    private let textures: TextureStore
    private let scene: ModelScene
    private let archives: [(root: String, archive: ArcArchive)]

    /// Which archive each path root lives in, the way the game's own paths are written: a record names
    /// `creatures/enemies/…` and the archive holds `enemies/…`, rooted at its own folder.
    private static let archiveRoots = [
        "creatures": "Creatures.arc",
        "items": "Items.arc",
        "fx": "FX.arc",
        "level art": "Level Art.arc",
    ]

    /// The expansions ship their own copies; the newest one that has a model wins.
    private static let expansionFolders = [ "gdx3/", "gdx2/", "gdx1/", "" ]

    public enum Failure: LocalizedError {
        case noSuchModel(String)
        case renderFailed

        public var errorDescription: String? {
            switch self {
                case let .noSuchModel(path): "No model at \(path) in any archive."
                case .renderFailed: "SceneKit produced no image."
            }
        }
    }

    /// Reads one model out of the archives, whichever holds it. A record names a model by its root —
    /// `creatures/enemies/…` — and the archive that root belongs to holds it without that first step.
    public func mesh(at path: String) throws -> MshFile {
        let key = path.lowercased().replacingOccurrences(of: "\\", with: "/")
        guard let separator = key.firstIndex(of: "/") else { throw Failure.noSuchModel(path) }

        let root = String(key[key.startIndex ..< separator])
        let entry = String(key[key.index(after: separator)...])

        for opened in archives where opened.root == root && opened.archive.contains(entry) {
            return try MshFile(try opened.archive.data(named: entry))
        }
        throw Failure.noSuchModel(path)
    }

    /// Which texture a model is dressed in.
    ///
    /// The record names one, or the mesh's own material does, or neither does and the game takes the
    /// texture sitting beside the model under the same name — `humanmale05b.msh` wears
    /// `humanmale05b_dif.tex`. A variant model falls back to its parent's skin, since
    /// `aetherialabomination01a_phase1.msh` has none of its own.
    public func skin(for mesh: MshFile, at path: String, preferring texture: String?)
        -> (path: String, image: CGImage)? {
        var candidates = ([ texture ] + mesh.materials.map(\.diffuse)).compactMap { $0 }
        var stem = path.replacingOccurrences(of: ".msh", with: "")

        while true {
            candidates.append("\(stem)_dif.tex")
            guard
                let underscore = stem.lastIndex(of: "_"),
                stem.distance(from: stem.startIndex, to: underscore) > 0
            else { break }

            stem = String(stem[stem.startIndex ..< underscore])
        }

        for candidate in candidates {
            guard let image = textures.image(at: candidate) else { continue }

            return (candidate, image)
        }
        return nil
    }

    /// Everything a monster is drawn from, read and dressed — one skin per material each model names.
    public func models(of assembly: ModelAssembly) -> [(mesh: MshFile, textures: [CGImage?])] {
        assembly.parts.compactMap { part in
            guard let mesh = try? mesh(at: part.mesh), !mesh.isEmpty else { return nil }

            return (mesh, skins(for: mesh, at: part.mesh, preferring: part.texture))
        }
    }

    /// The skin of every material a model names, in the order the model names them.
    public func skins(for mesh: MshFile, at path: String, preferring texture: String?) -> [CGImage?] {
        guard !mesh.materials.isEmpty else { return [ skin(for: mesh, at: path, preferring: texture)?.image ] }

        return mesh.materials.enumerated().map { index, material in
            // The record's own texture speaks for the first material only: it is the creature's skin,
            // not the vines growing out of it.
            let preferred = index == 0 ? texture : nil
            if let path = material.diffuse, let image = textures.image(at: path) { return image }

            return skin(for: mesh, at: path, preferring: preferred)?.image
        }
    }

    /// A whole monster, drawn at the size asked for.
    @MainActor
    public func image(of assembly: ModelAssembly, size: CGSize) throws -> CGImage {
        let models = models(of: assembly)
        guard !models.isEmpty else { throw Failure.noSuchModel(assembly.parts.first?.mesh ?? "") }

        return try render(scene.scene(for: models), size: size)
    }

    /// One model, drawn at the size asked for.
    @MainActor
    public func image(meshAt path: String, texture: String? = nil, size: CGSize) throws -> CGImage {
        let mesh = try mesh(at: path)

        return try render(
            scene.scene(for: [ (mesh, skins(for: mesh, at: path, preferring: texture)) ]),
            size: size
        )
    }

    @MainActor
    private func render(_ built: SCNScene, size: CGSize) throws -> CGImage {
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = built
        renderer.autoenablesDefaultLighting = false

        let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        guard let rendered = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw Failure.renderFailed
        }
        return rendered
    }

    /// Writes an image out as a PNG, which is what the offline run produces.
    public static func write(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else { throw Failure.renderFailed }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.renderFailed }
    }
}
