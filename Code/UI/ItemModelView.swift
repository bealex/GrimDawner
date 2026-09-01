// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import GrimDawnerRender
import SceneKit
import SwiftUI

/// A world object drawn from the game's own model: a chest, a breakable, anything that is never carried.
///
/// These records hold a mesh where an item holds an inventory icon, so the model is the only picture of
/// them the game has. Dragging turns it, scrolling moves in. A model that cannot be read leaves the box
/// empty rather than failing.
struct ItemModelView: NSViewRepresentable {
    let meshPath: String
    let texturePath: String
    let renderer: ModelRenderer?

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .clear
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        let shown = "\(meshPath)|\(texturePath)"
        guard context.coordinator.shown != shown else { return }

        context.coordinator.shown = shown
        view.scene = scene()
        view.pointOfView = view.scene?.rootNode.childNodes.first { $0.camera != nil }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var shown: String?
    }

    private func scene() -> SCNScene? {
        guard let renderer, !meshPath.isEmpty else { return nil }

        let models = renderer.models(of: ModelAssembly(parts: [ .init(mesh: meshPath, texture: texturePath) ]))
        guard !models.isEmpty else { return nil }

        var configuration = SceneConfiguration()
        configuration.background = (0.07, 0.07, 0.08)
        return ModelScene(configuration: configuration).scene(for: models)
    }
}
