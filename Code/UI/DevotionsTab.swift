// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import SwiftUI

/// The devotion window: the whole sky, the affinity it has earned, and whatever star you click.
struct DevotionsTab: View {
    let character: ResolvedCharacter
    let search: QuickSearch
    @Binding
    var selectedStar: DevotionStar.ID?
    @Binding
    var selectedConstellation: ResolvedConstellation.ID?

    @State
    private var camera = MapCamera()

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
                ConstellationDetailView(constellation: constellation, star: star)
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
    private var constellationMenu: some View {
        Menu {
            ForEach(character.devotion.startedConstellations) { constellation in
                Button("\(constellation.name)  \(constellation.takenStars)/\(constellation.totalStars)") {
                    selectedConstellation = constellation.id
                    selectedStar = constellation.stars.first(where: \.isTaken)?.id
                }
            }
        } label: {
            Label("Constellations", systemImage: "list.star")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(character.devotion.startedConstellations.isEmpty)
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

            if let star {
                SectionCard(title: star.skill.name, subtitle: star.isTaken ? "taken" : "not taken") {
                    VStack(alignment: .leading, spacing: 10) {
                        if !star.skill.description.isEmpty {
                            Text(star.skill.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        StatBlockView(block: star.skill.stats)
                    }
                }
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
