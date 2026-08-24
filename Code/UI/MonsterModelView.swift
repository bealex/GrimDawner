// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import GrimDawnerMesh
import GrimDawnerRender
import SceneKit
import SwiftUI

/// The monster itself, drawn from the game's own model.
///
/// The scene is built once per model and handed to SceneKit, which draws it live: dragging turns the
/// creature, scrolling moves in. Given an animation it is skinned to its own skeleton and plays it in a
/// loop. A model that cannot be read leaves the box empty rather than failing.
struct MonsterModelView: NSViewRepresentable {
    let monster: ResolvedMonster
    let renderer: ModelRenderer?
    /// The records, for the gear a human is drawn from: its own record names only its head.
    var database: GameDatabase?
    /// What it is doing. Nothing is the bind pose, which is how the game's own models are stored.
    var animation: MonsterAnimation?
    /// A share of the rate the game plays it at, so a half is half as fast.
    var speed: Double = 1
    /// A skill whose own effects are shown on the creature, on top of what the animation spawns.
    var skill: String?

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .clear
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        let shown = "\(monster.path)|\(animation?.path ?? "")|\(speed)|\(skill ?? "")"
        guard context.coordinator.shown != shown else { return }

        context.coordinator.shown = shown
        view.scene = scene()
        view.pointOfView = view.scene?.rootNode.childNodes.first { $0.camera != nil }
        // A still scene is drawn when something asks for it; a moving one, every frame, and only a view
        // that is playing advances what is on it — an effect emits nothing while the view is idle.
        let moving = animation != nil || skill != nil
        view.rendersContinuously = moving
        view.isPlaying = moving
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
        // The view keeps drawing while an animation plays, which is what lets an effect emit.
        configuration.emitsEffects = true
        let played = animation.flatMap { try? renderer.animation(at: $0.path) }
        var effects = played.map { renderer.effects(of: $0, in: database) } ?? []
        if let skill, let database { effects += renderer.effects(ofSkillAt: skill, in: database) }

        return ModelScene(configuration: configuration).scene(
            for: models,
            playing: played,
            speed: speed,
            showing: effects
        )
    }
}

/// The model, what it is doing, and how fast — with what the animation calls out while it plays.
///
/// A creature's animation table names every move it has, and the ones its attacks ask for by name are
/// named after those attacks. It opens on the first, which is the creature standing about.
struct MonsterModelPane: View {
    let monster: ResolvedMonster
    let renderer: ModelRenderer?
    var database: GameDatabase?

    /// The rates worth watching something at, as shares of the game's own.
    private static let rates: [(title: String, rate: Double)] = [ ("1×", 1), ("½×", 0.5), ("¼×", 0.25) ]

    @State
    private var chosen: MonsterAnimation?
    @State
    private var speed: Double = 1
    @State
    private var skill: String?
    @State
    private var moments = [Moment]()

    /// A frame of the animation the game calls something out on.
    private struct Moment: Identifiable {
        let id = UUID()
        let at: TimeInterval
        let title: String
        let where_: String
        let isEffect: Bool
    }

    var body: some View {
        MonsterModelView(
            monster: monster,
            renderer: renderer,
            database: database,
            animation: chosen,
            speed: speed,
            skill: skill
        )
        .overlay(alignment: .topLeading) {
            if !moments.isEmpty { happenings }
        }
        .overlay(alignment: .bottom) {
            if !monster.animations.isEmpty { controls }
        }
        // Opens on the creature's first animation, and on the new one's when the monster changes.
        .task(id: monster.path) {
            chosen = monster.animations.first
            skill = nil
        }
        .task(id: chosen?.path) { moments = read(chosen) }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Still") {
                    chosen = nil
                    skill = nil
                }
                // An attack is the animation it plays and the effects the skill throws, together.
                if !attacks.isEmpty {
                    Section("Attacks") {
                        ForEach(attacks, id: \.path) { attack in
                            Button(attack.title) {
                                chosen = attack.animation
                                skill = attack.path
                            }
                        }
                    }
                }
                Section("Animations") {
                    ForEach(monster.animations) { animation in
                        Button(animation.title) { chosen = animation }
                    }
                }
            } label: {
                Text(chosen?.title ?? "Still")
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: 220)

            Picker("Effects", selection: $skill) {
                Text("No effect").tag(String?.none)
                Divider()
                ForEach(showable, id: \.path) { ability in
                    Text(ability.title).tag(String?.some(ability.path))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 200)
            .help("What a skill of this creature's puts on it: the aura a passive carries, or what a cast throws")

            Picker("Speed", selection: $speed) {
                ForEach(Self.rates, id: \.rate) { rate in
                    Text(rate.title).tag(rate.rate)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 130)
            .disabled(chosen == nil)
        }
        .padding(8)
    }

    /// The creature's attacks that have an animation of their own, so one pick both plays what it does
    /// and shows what it throws.
    private var attacks: [(path: String, title: String, animation: MonsterAnimation)] {
        var seen = Set<String>()
        return monster.attacks.compactMap { ability in
            guard let animation = ability.animation, seen.insert(animation.path).inserted else { return nil }

            return (ability.skill.recordPath, ability.title ?? animation.title, animation)
        }
    }

    /// The creature's own skills that put something visible on it.
    private var showable: [(path: String, title: String)] {
        guard let renderer, let database else { return [] }

        var seen = Set<String>()
        return monster.abilities.compactMap { ability in
            let path = ability.skill.recordPath
            guard
                seen.insert(path).inserted,
                !renderer.effects(ofSkillAt: path, in: database).isEmpty
            else { return nil }

            let title = ability.title ?? ability.kind
            return (path, ability.role == .passive ? "\(title) · passive" : title)
        }
    }

    /// What the animation spawns and where, in the order it happens.
    private var happenings: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(moments) { moment in
                HStack(spacing: 6) {
                    Text(String(format: "%.2fs", moment.at / speed))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: moment.isEffect ? "sparkles" : "burst")
                        .font(.caption2)
                        .foregroundStyle(moment.isEffect ? Color.orange : Color.secondary)
                    Text(moment.title)
                        .font(.caption)
                    if !moment.where_.isEmpty {
                        Text(moment.where_)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(8)
        .background(.black.opacity(0.35), in: .rect(cornerRadius: 8))
        .padding(10)
    }

    /// Everything the animation calls out: the effects it spawns, and the frames a blow lands on.
    private func read(_ animation: MonsterAnimation?) -> [Moment] {
        guard
            let animation,
            let renderer,
            let played = try? renderer.animation(at: animation.path)
        else {
            return []
        }

        let rate = Double(max(played.framesPerSecond, 1))
        var moments = renderer.effects(of: played, in: database).map { effect in
            Moment(
                at: Double(effect.frame ?? 0) / rate,
                title: effect.name,
                where_: effect.attachment.isEmpty ? "" : "at \(effect.attachment.lowercased())",
                isEffect: true
            )
        }
        moments += played.events
            .filter { $0.kind == .callback && $0.name.lowercased().contains("hit") }
            .map {
                Moment(at: Double($0.frame) / rate, title: spaced($0.name), where_: "", isEffect: false)
            }
        return moments.sorted { $0.at < $1.at }
    }

    /// `RightHandHit` reads as *Right hand hit*.
    private func spaced(_ name: String) -> String {
        var words = ""
        for (index, character) in name.enumerated() {
            if index > 0, character.isUppercase {
                words += " "
                words += character.lowercased()
            } else {
                words.append(character)
            }
        }
        return words
    }
}
