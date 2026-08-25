// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import SwiftUI

/// The devotion window: the whole sky, the affinity it has earned, and whatever star you click.
struct DevotionsTab: View {
    let character: ResolvedCharacter
    let search: QuickSearch
    @Binding
    var selectedStar: DevotionStar.ID?
    @Binding
    var selectedConstellation: ResolvedConstellation.ID?
    /// The records, for reading a star's skill at a rank other than the character's own.
    var database: GameDatabase?

    @State
    private var camera = MapCamera()
    /// The rank every devotion skill is read at, or nothing for the rank the character has spent.
    @State
    private var rank: Int?

    var body: some View {
        TabLayout {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Divider()
                DevotionMapView(
                    map: character.devotion,
                    search: search,
                    camera: $camera,
                    selectedStar: $selectedStar,
                    selectedConstellation: $selectedConstellation
                )
            }
        } detail: {
            if let constellation {
                ConstellationDetailView(constellation: constellation, star: star, rank: rank, database: database)
            } else {
                DetailPlaceholder(
                    title: "No star selected",
                    hint: "Click a star to see what it grants, or search to light up the ones that match."
                )
            }
        }
    }

    private var constellation: ResolvedConstellation? {
        character.devotion.constellations.first { $0.id == selectedConstellation }
    }

    private var star: DevotionStar? {
        constellation?.stars.first { $0.id == selectedStar }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Devotion")
                    .font(.headline)
                Text("\(character.devotion.takenStars) / \(character.save.biography.totalDevotionUnlocked) points")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            affinities

            Spacer(minLength: 8)

            constellationMenu
            zoomControls
        }
    }

    private var affinities: some View {
        HStack(spacing: 10) {
            ForEach(character.devotion.affinities) { affinity in
                HStack(spacing: 4) {
                    GameIcon(path: affinity.icon, size: 18, fallbackSymbol: "circle.fill")
                    Text("\(affinity.earned)")
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(affinity.earned > 0 ? affinity.color : .secondary)
                }
                .help("\(affinity.name): \(affinity.earned)")
                .quickSearch(search.emphasis(matching: affinity.name), cornerRadius: 4)
                .accessibilityLabel("\(affinity.name) affinity \(affinity.earned)")
            }
        }
    }

    /// A way to reach a constellation the character has stars in without hunting for it on the map.
    /// Picking one takes the sky to it rather than only filling the sidebar.
    private var constellationMenu: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(character.devotion.startedConstellations) { constellation in
                    Button("\(constellation.name)  \(constellation.takenStars)/\(constellation.totalStars)") {
                        show(constellation)
                    }
                }
            } label: {
                Label("Constellations", systemImage: "list.star")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(character.devotion.startedConstellations.isEmpty)

            rankControl
        }
    }

    /// What rank to read every devotion skill at. A celestial power is written per rank, and the one the
    /// character has spent says nothing about what the next point buys.
    private var rankControl: some View {
        Picker("Rank", selection: $rank) {
            Text("Own rank").tag(Int?.none)
            Divider()
            ForEach(1 ... Self.highestRank, id: \.self) { rank in
                Text("Rank \(rank)").tag(Int?.some(rank))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help("Reads every star's skill at this rank instead of the one the character has spent points to")
    }

    /// As deep as a devotion skill is written: the celestial powers stop well short of this.
    private static let highestRank = 25

    private func show(_ constellation: ResolvedConstellation) {
        selectedConstellation = constellation.id
        selectedStar = constellation.stars.first(where: \.isTaken)?.id ?? constellation.stars.first?.id
        camera.focus = constellation.bounds
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button("Zoom out", systemImage: "minus.magnifyingglass") { step(1 / 1.25) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Zoom in", systemImage: "plus.magnifyingglass") { step(1.25) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Fit", systemImage: "arrow.up.left.and.arrow.down.right") { camera.isFramed = false }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }

    private func step(_ factor: CGFloat) {
        camera.scale(by: factor, within: character.devotion.bounds)
    }
}

/// One constellation as the sidebar shows it: what it grants, and what the selected star does.
struct ConstellationDetailView: View {
    let constellation: ResolvedConstellation
    let star: DevotionStar?
    /// The rank to read the star's skill at, or nothing for the one the character has spent points to.
    var rank: Int?
    /// The records, for reading that skill at a rank the character has not bought.
    var database: GameDatabase?

    /// The selected star's skill at the rank being read. A star the character has not taken still has a
    /// skill, and reading it a rank ahead is how a reader sees what the next point buys.
    private var shownSkill: ResolvedSkill? {
        guard let star else { return nil }
        guard let rank, let database else { return star.skill }

        return SkillResolver(database: database).skill(at: star.skill.recordPath, level: rank) ?? star.skill
    }

    /// A star reads as taken or not, and says its rank when it has more than the one.
    private func subtitle(of star: DevotionStar) -> String {
        let state = star.isTaken ? "taken" : "not taken"
        guard star.skill.maxLevel > 1 else { return state }
        guard let rank else { return "\(state) · rank \(star.skill.baseLevel) / \(star.skill.maxLevel)" }

        return "\(state) · read at rank \(min(rank, star.skill.maxLevel)) / \(star.skill.maxLevel)"
    }

    @Environment(\.quickSearch)
    private var search

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !constellation.description.isEmpty {
                Text(constellation.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !constellation.affinityGiven.isEmpty || !constellation.affinityRequired.isEmpty {
                SectionCard(title: "Affinity") {
                    VStack(spacing: 6) {
                        ForEach(constellation.affinityGiven, id: \.self) { affinity in
                            StatRow(title: "Grants \(affinity.name)", value: "+\(affinity.amount)")
                        }
                        ForEach(constellation.affinityRequired, id: \.self) { affinity in
                            StatRow(
                                title: "Requires \(affinity.name)",
                                value: "\(affinity.amount)",
                                valueColor: constellation.isAvailable ? .green : .orange
                            )
                        }
                    }
                }
            }

            if let star, let shown = shownSkill {
                SectionCard(title: shown.name, subtitle: subtitle(of: star)) {
                    VStack(alignment: .leading, spacing: 10) {
                        if !shown.description.isEmpty {
                            Text(shown.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !shown.parameters.isEmpty {
                            VStack(spacing: 4) {
                                ForEach(shown.parameters) { parameter in
                                    StatRow(title: parameter.name, value: parameter.value)
                                }
                            }
                        }
                        StatBlockView(block: shown.stats)
                    }
                }

                SkillPetView(skill: shown)
            }

            SectionCard(title: "Stars", subtitle: "\(constellation.takenStars) of \(constellation.totalStars)") {
                VStack(spacing: 4) {
                    ForEach(constellation.stars) { star in
                        HStack(spacing: 8) {
                            Image(systemName: star.isTaken ? "star.fill" : "star")
                                .font(.caption2)
                                .foregroundStyle(star.isTaken ? Theme.accent : .secondary)
                            Text(star.skill.name)
                                .font(.callout)
                                .foregroundStyle(star.isTaken ? .primary : .secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .quickSearchText(search.emphasis(matching: star.skill.name))
                            if star.isPower {
                                Text("power")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            if !constellation.bonuses.hasNothingToShow {
                SectionCard(title: "Granted so far") {
                    StatBlockView(block: constellation.bonuses)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            GameIcon(path: constellation.iconPath, width: 88, height: 44, fallbackSymbol: "star")

            VStack(alignment: .leading, spacing: 4) {
                Text(constellation.name)
                    .font(.title3.bold())
                    .quickSearchText(search.emphasis(matching: constellation.name))
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var status: String {
        if constellation.isComplete { return "Complete — \(constellation.totalStars) stars" }
        if constellation.isStarted { return "\(constellation.takenStars) of \(constellation.totalStars) stars" }

        return constellation.isAvailable ? "Available" : "Affinity locked"
    }
}
