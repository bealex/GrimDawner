// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import GrimDawnerRender
import SceneKit
import SwiftUI

/// The character itself, drawn from the game's own model: dressed in the gear it is wearing, holding the
/// weapons of the set the doll shows, and playing the idle the game's character window plays.
///
/// The game frames it head-on and close, so this does too. A model that cannot be read leaves the box
/// empty rather than failing, which is what the panel showed before there was one.
struct CharacterModelView: NSViewRepresentable {
    let character: ResolvedCharacter
    /// The set the doll is showing, whose weapons the character holds.
    let weaponSet: WeaponSet?
    let renderer: ModelRenderer?
    let database: GameDatabase?

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .clear
        // The idle loops for as long as the panel is up, which needs a view that keeps drawing.
        view.rendersContinuously = true
        view.isPlaying = true
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        guard context.coordinator.shown != shown else { return }

        context.coordinator.shown = shown
        view.scene = scene()
        view.pointOfView = view.scene?.rootNode.childNodes.first { $0.camera != nil }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var shown: String?
    }

    /// What the model is drawn from: rebuilt when the character changes, or when it swaps hands.
    private var shown: String {
        ([ character.file.playerFile.path(percentEncoded: false), "\(weaponSet?.index ?? -1)" ]
            + character.equipment.map { $0.item?.raw.baseName ?? "" }).joined(separator: "|")
    }

    private func scene() -> SCNScene? {
        guard
            let renderer,
            let database,
            let built = CharacterModel.of(character, holding: weaponSet, in: database)
        else { return nil }

        let models = renderer.models(of: built.assembly)
        guard !models.isEmpty else { return nil }

        var configuration = SceneConfiguration()
        // Head-on and filling the box, the way the game's own character window holds it. An idle sways
        // rather than swings, so it needs none of the room an attack does.
        configuration.turn = 0
        configuration.pitch = 6
        configuration.movingMargin = 1.05
        return ModelScene(configuration: configuration).scene(
            for: models,
            playing: built.animation.flatMap { try? renderer.animation(at: $0) }
        )
    }
}

/// The character's own model where the game renders it, over the backdrop the game renders it against.
struct PortraitView: View {
    let backdrop: String
    let size: CGSize
    /// Ringed while the sidebar is reading the character rather than a piece of gear.
    var isSelected = false
    let character: ResolvedCharacter
    let weaponSet: WeaponSet?
    let renderer: ModelRenderer?
    let database: GameDatabase?

    var body: some View {
        ZStack {
            // The game lights its own backdrop from in front of the model; drawn flat it is a pale wall
            // that the gear disappears into, so it is taken down to something the model stands out of.
            GameArtwork(path: backdrop, size: size)
                .colorMultiply(Color(white: 0.3))
            model
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .overlay(
            Rectangle()
                .stroke(isSelected ? Theme.accent : .clear, lineWidth: 2)
        )
        .accessibilityHidden(true)
    }

    /// An `SCNView` takes every click that lands on it, and the inventory panel's portrait is a button.
    private var model: some View {
        CharacterModelView(character: character, weaponSet: weaponSet, renderer: renderer, database: database)
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
    }
}
