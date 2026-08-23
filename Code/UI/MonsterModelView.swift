// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import GrimDawnerMesh
import GrimDawnerRender
import SceneKit
import SwiftUI

/// The monster itself, drawn from the game's own model.
///
/// The scene is built once per model and handed to SceneKit, which draws it live: dragging turns the
/// creature, scrolling moves in. A model that cannot be read leaves the box empty rather than failing.
struct MonsterModelView: NSViewRepresentable {
    let monster: ResolvedMonster
    let renderer: ModelRenderer?
    /// The records, for the gear a human is drawn from: its own record names only its head.
    var database: GameDatabase?

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .clear
        view.rendersContinuously = false
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        guard context.coordinator.shown != monster.path else { return }

        context.coordinator.shown = monster.path
        view.scene = scene()
        view.pointOfView = view.scene?.rootNode.childNodes.first { $0.camera != nil }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var shown: String?
    }

    private func scene() -> SCNScene? {
        guard let renderer else { return nil }

        let assembly =
            database.map { ModelAssembly.of(monster, in: $0) }
            ?? ModelAssembly(parts: [ .init(mesh: monster.meshPath, texture: monster.texturePath) ])
        let models = renderer.models(of: assembly)
        guard !models.isEmpty else { return nil }

        var configuration = SceneConfiguration()
        configuration.background = (0.07, 0.07, 0.08)
        return ModelScene(configuration: configuration).scene(for: models)
    }
}
