// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import SwiftUI

/// One mastery drawn on the panel the game lays it out on, at the game's own coordinates.
struct MasteryPanelView: View {
    let mastery: ResolvedMastery
    let search: QuickSearch
    @Binding
    var selected: ResolvedSkill?

    @Environment(\.textures)
    private var textures

    var body: some View {
        let canvas = textures?.size(at: mastery.panel.background) ?? contentBounds.size
        let buttonSize = textures?.size(at: buttons.first?.frame ?? "") ?? CGSize(width: 40, height: 40)

        ScaledCanvas(size: canvas) {
            ZStack(alignment: .topLeading) {
                GameArtwork(path: mastery.panel.background, size: canvas)
                artwork
                Connectors(skills: buttons, buttonSize: buttonSize, pitch: columnPitch, panel: mastery.panel)
                skillButtons(size: buttonSize)
                masteryBar
                milestones
            }
        }
    }

    private var buttons: [ResolvedSkill] {
        mastery.skills.filter { $0.position != .zero && !$0.frame.isEmpty }
    }

    @ViewBuilder
    private var artwork: some View {
        if let size = textures?.size(at: mastery.panel.artwork) {
            GameArtwork(path: mastery.panel.artwork, size: size)
                .position(x: size.width / 2, y: size.height / 2)
        }
    }

    private func skillButtons(size: CGSize) -> some View {
        ForEach(buttons) { skill in
            SkillButton(
                skill: skill,
                size: size,
                panel: mastery.panel,
                isSelected: selected?.recordPath == skill.recordPath,
                emphasis: search.emphasis(matching: [ skill.name ] + skill.stats.titles),
                select: { selected = skill }
            )
            .position(x: skill.position.x + size.width / 2, y: skill.position.y + size.height / 2)
        }
    }

    @ViewBuilder
    private var masteryBar: some View {
        if let size = textures?.size(at: mastery.panel.bar) {
            let fraction = min(Double(mastery.level) / Double(max(mastery.maxLevel, 1)), 1)
            GameIcon(path: mastery.panel.bar, width: size.width, height: size.height)
                .mask(alignment: .leading) { Rectangle().frame(width: size.width * fraction) }
                .position(
                    x: mastery.panel.barOrigin.x + size.width / 2,
                    y: mastery.panel.barOrigin.y + size.height / 2
                )
                .accessibilityLabel("Mastery level \(mastery.level) of \(mastery.maxLevel)")
        }
    }

    private var milestones: some View {
        ForEach(mastery.panel.milestones) { milestone in
            Text("\(milestone.level)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(mastery.level >= milestone.level ? Color.green : Color.secondary)
                .position(x: milestone.centre.x, y: milestone.centre.y)
        }
        .accessibilityHidden(true)
    }

    /// The grid step the panel places its columns on, taken from the buttons themselves.
    private var columnPitch: CGFloat {
        let columns = Set(buttons.map(\.position.x)).sorted()
        let steps = zip(columns, columns.dropFirst()).map { $1 - $0 }.filter { $0 > 1 }
        return steps.min() ?? 80
    }

    /// Where the panel's content reaches, used only when its background art is missing.
    private var contentBounds: CGRect {
        guard let first = buttons.first else { return CGRect(x: 0, y: 0, width: 1, height: 1) }

        var rect = CGRect(origin: first.position, size: .zero)
        for skill in buttons { rect = rect.union(CGRect(origin: skill.position, size: CGSize(width: 40, height: 40))) }
        for milestone in mastery.panel.milestones { rect = rect.union(CGRect(origin: milestone.centre, size: .zero)) }
        return rect
    }
}

/// The lines the panel draws from a skill to the modifiers along its row.
private struct Connectors: View {
    let skills: [ResolvedSkill]
    let buttonSize: CGSize
    let pitch: CGFloat
    let panel: MasteryPanel

    var body: some View {
        Canvas { context, _ in
            for skill in skills where !skill.connectors.isEmpty {
                draw(skill, in: &context)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ skill: ResolvedSkill, in context: inout GraphicsContext) {
        let centre = self.centre(of: skill)
        let colour = skill.isLearned ? panel.completeColor : panel.unavailableColor
        let opacity = skill.isLearned ? 0.9 : 0.45
        let width: CGFloat = skill.isLearned ? 2 : 1

        // A stub tile is the tail of a branch, not another step along the row.
        let steps = skill.connectors.count { $0.kind != .transmuterStub }
        var spine = Path()
        spine.move(to: centre)
        spine.addLine(to: CGPoint(x: centre.x + CGFloat(steps) * pitch, y: centre.y))
        context.stroke(spine, with: .color(colour.opacity(opacity)), lineWidth: width)

        for connector in skill.connectors where connector.kind != .straight && connector.kind != .transmuterStub {
            let x = centre.x + CGFloat(connector.step + 1) * pitch
            guard let target = branchTarget(from: centre, at: x, up: connector.kind == .branchUp) else { continue }

            var branch = Path()
            branch.move(to: CGPoint(x: x, y: centre.y))
            branch.addLine(to: CGPoint(x: x, y: target))
            context.stroke(branch, with: .color(colour.opacity(opacity)), lineWidth: width)
        }
    }

    /// The modifier a branch drops to: the nearest button in that column, on the side the tile points.
    private func branchTarget(from centre: CGPoint, at column: CGFloat, up: Bool) -> CGFloat? {
        skills
            .map(self.centre(of:))
            .filter { abs($0.x - column) < 1 && (up ? $0.y < centre.y : $0.y > centre.y) }
            .min { abs($0.y - centre.y) < abs($1.y - centre.y) }?
            .y
    }

    private func centre(of skill: ResolvedSkill) -> CGPoint {
        CGPoint(x: skill.position.x + buttonSize.width / 2, y: skill.position.y + buttonSize.height / 2)
    }
}

/// One skill on the panel: its button, its icon, and the rank printed beneath it.
private struct SkillButton: View {
    let skill: ResolvedSkill
    let size: CGSize
    let panel: MasteryPanel
    let isSelected: Bool
    let emphasis: QuickSearch.Emphasis
    let select: () -> Void

    @State
    private var isHovered = false

    var body: some View {
        Button(action: select) {
            ZStack {
                GameIcon(
                    path: skill.iconPath,
                    width: size.width - skill.iconOffset.x * 2,
                    height: size.height - skill.iconOffset.y * 2,
                    fallbackSymbol: "sparkle"
                )
                // Darkened rather than faded: a transparent icon would show the connectors the panel
                // draws underneath it.
                .saturation(skill.isLearned ? 1 : 0)
                .colorMultiply(skill.isLearned ? .white : Color(white: 0.45))

                GameIcon(path: skill.frame, width: size.width, height: size.height, fallbackSymbol: "square")

                if isSelected {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Theme.accent, lineWidth: 2)
                }
            }
            .frame(width: size.width, height: size.height)
            .overlay { rank.position(panel.rankOffset) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.08 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .help(helpText)
        .quickSearch(emphasis, cornerRadius: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(helpText)
        .accessibilityAddTraits(.isButton)
    }

    private var rank: some View {
        Text("\(skill.totalLevel) / \(skill.maxLevel)")
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(rankColor)
            .shadow(color: .black.opacity(0.9), radius: 1)
            .fixedSize()
    }

    private var rankColor: Color {
        if !skill.isLearned { return panel.unavailableColor }
        if skill.bonusLevel > 0 { return panel.augmentColor }

        return skill.totalLevel >= skill.maxLevel ? panel.completeColor : .white
    }

    private var helpText: String {
        guard skill.isLearned else { return "\(skill.name) — not learned (max \(skill.maxLevel))" }

        return "\(skill.name) — \(skill.baseLevel) spent, +\(skill.devotionBonus) devotion, "
            + "+\(skill.itemBonus) items (max \(skill.maxLevel), ultimate \(skill.ultimateLevel))"
    }
}
