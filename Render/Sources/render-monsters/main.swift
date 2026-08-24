// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import Foundation
import GrimDawnerEngine
import GrimDawnerRender

/// Renders the game's monsters to PNGs, one per model, or to animated PNGs of what they do.
///
/// Usage: render-monsters <game folder> <output folder> [--limit N] [--size 512] [--name <substring>]
///        [--animations] — one animated PNG per attack a monster has an animation for, in a folder of
///        its own, rather than one still.
@MainActor
func run() async throws {
    var arguments = Array(CommandLine.arguments.dropFirst())

    func option(_ name: String) -> String? {
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }

        let value = arguments[index + 1]
        arguments.removeSubrange(index ... index + 1)
        return value
    }

    let limit = option("--limit").flatMap(Int.init)
    let size = option("--size").flatMap(Double.init) ?? 512
    let filter = option("--name")?.lowercased()
    let verbose = arguments.contains("--verbose")
    let exposure = option("--exposure").flatMap(Double.init)
    let onBlack = arguments.contains("--background")
    let animated = arguments.contains("--animations")

    guard arguments.count >= 2 else {
        print("usage: render-monsters <game folder> <output folder> [--limit N] [--size 512] [--name text]")
        exit(2)
    }
    let gameFolder = URL(fileURLWithPath: arguments[0])
    let output = URL(fileURLWithPath: arguments[1])

    let database = try GameDatabase(gameFolder: gameFolder)
    var configuration = SceneConfiguration()
    if let exposure { configuration.exposure = exposure }
    if onBlack {
        configuration.background = (0.05, 0.05, 0.06)
        configuration.castsShadow = true
    }
    let renderer = ModelRenderer(gameFolder: gameFolder, configuration: configuration)

    // One picture per monster that is drawn differently: a human is its head plus what it wears, so two
    // monsters sharing a head are still two pictures.
    let skills = SkillResolver(database: database)
    let resolver = MonsterResolver(
        database: database,
        skills: skills,
        items: ItemResolver(database: database, skills: skills)
    )
    var wanted = [(name: String, path: String)]()
    var seen = Set<String>()

    database.sweep(prefix: "records/creatures/enemies/") { path, record in
        guard
            record.text("Class") == "Monster",
            !record.text("mesh").isEmpty,
            let name = database.localised(record.text("description")),
            !name.isEmpty,
            filter == nil || name.lowercased().contains(filter ?? "")
        else { return }

        // Records drawn the same way are one picture; a region's copy of a monster is not another one.
        let signature = ([ name, record.text("mesh"), record.text("baseTexture") ]
            + ModelAssembly.wornFields.map { record.text("default\($0)Piece") + record.text("loot\($0)Item1") }
            + ModelAssembly.heldFields.map { record.text("loot\($0.field)Item1") })
            .joined(separator: "|")
        guard seen.insert(signature).inserted else { return }

        wanted.append((name, path))
    }

    wanted.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    if let limit { wanted = Array(wanted.prefix(limit)) }

    print("rendering \(wanted.count) monsters at \(Int(size))px into \(output.path(percentEncoded: false))")
    let started = Date()
    var drawn = 0
    var failed = [String]()

    for monster in wanted {
        guard let resolved = resolver.monster(at: monster.path, level: 100) else { continue }

        let assembly = ModelAssembly.of(resolved, in: database)
        let name = Naming.fileName(for: monster.name, mesh: resolved.meshPath)
        do {
            if animated {
                for animation in Naming.attackAnimations(of: resolved) {
                    let played = try renderer.animation(at: animation.path)
                    let frames = try renderer.frames(
                        of: assembly, size: CGSize(width: size, height: size), playing: played
                    )
                    try ModelRenderer.write(
                        frames,
                        to: output.appending(path: "\(name)/\(animation.title).png"),
                        framesPerSecond: played.framesPerSecond
                    )
                    drawn += 1
                    if verbose { print("  \(monster.name) · \(animation.title): \(frames.count) frames") }
                }
            } else {
                let image = try renderer.image(of: assembly, size: CGSize(width: size, height: size))
                try ModelRenderer.write(image, to: output.appending(path: "\(name).png"))
                drawn += 1
                if verbose { print("  \(monster.name): \(assembly.parts.map(\.mesh).joined(separator: ", "))") }
            }
        } catch {
            failed.append("\(monster.name): \(error.localizedDescription)")
        }
    }

    print("drawn \(drawn) \(animated ? "animations" : "monsters") in \(Int(-started.timeIntervalSinceNow))s, \(failed.count) failed")
    for failure in failed.prefix(20) { print("  \(failure)") }
}

/// A file name that says which monster and which model, since several monsters share one.
enum Naming {
    static func fileName(for name: String, mesh: String) -> String {
        let stem = mesh.split(separator: "/").last?.replacingOccurrences(of: ".msh", with: "") ?? "model"
        let readable = name.replacingOccurrences(of: "/", with: "-")
        return "\(readable) · \(stem)"
    }

    /// What to draw a monster doing: every animation one of its attacks asks for by name, and the first
    /// of its own, which is it standing about.
    static func attackAnimations(of monster: ResolvedMonster) -> [MonsterAnimation] {
        var found = monster.animations.prefix(1).map { $0 }
        for animation in monster.attacks.compactMap(\.animation) where !found.contains(animation) {
            found.append(animation)
        }
        return found
    }
}

try await run()
