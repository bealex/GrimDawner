// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import GrimDawnerRender
import SwiftUI

/// Every monster in the game, with what it does and what it drops.
///
/// Like the item directory, a search narrows the list rather than dimming it: there are three thousand
/// of these and only a handful ever match.
struct MonstersTab: View {
    let monsters: [MonsterEntry]
    let isListing: Bool
    let search: QuickSearch
    let selectedPath: String?
    let selected: ResolvedMonster?
    let level: Int
    let difficulty: Difficulty
    /// Draws the game's own models, when the game folder is open.
    let renderer: ModelRenderer?
    let database: GameDatabase?
    let select: (_ path: String, _ level: Int, _ difficulty: Difficulty?) -> Void

    @State
    private var filter = MonsterFilter()
    @Environment(\.openWindow)
    private var openWindow

    var body: some View {
        let rows = matches

        TabLayout {
            VStack(spacing: 0) {
                header(rows)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Divider()

                if isListing {
                    ProgressView("Reading every monster in the game…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list(rows)
                        .background(ArrowKeys(move: { move($0, within: rows) }))
                }
            }
        } detail: {
            if let selected {
                MonsterDetailView(
                    monster: selected,
                    level: level,
                    difficulty: difficulty,
                    setLevel: { select(selected.path, $0, nil) },
                    setDifficulty: { select(selected.path, level, $0) },
                    renderer: renderer,
                    database: database,
                    openMonster: { select($0, level, nil) }
                )
            } else {
                DetailPlaceholder(
                    title: "No monster selected",
                    hint: "Pick a monster to see what it does and what it drops."
                )
            }
        }
        .onChange(of: rows.first?.id, initial: true) { _, _ in
            guard selectedPath == nil, search.isActive || filter.isActive, let first = rows.first else { return }

            select(first.monster.path, level, nil)
        }
    }

    private var matches: [MonsterEntry] {
        monsters.lazy
            .filter { !search.isActive || search.matchesFolded($0.folded) }
            .filter { filter.admits($0.monster) }
            .prefix(2000)
            .map { $0 }
    }

    private func header(_ rows: [MonsterEntry]) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Monsters")
                    .font(.headline)
                Text(summary(rows))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(width: 190, alignment: .leading)

            if !isListing {
                MonsterFilterBar(filter: $filter, races: races)
            }

            Spacer(minLength: 8)
        }
    }

    private func summary(_ rows: [MonsterEntry]) -> String {
        guard !isListing else { return "reading the game's records" }
        guard search.isActive || filter.isActive else { return "\(monsters.count.formatted(.number)) monsters" }

        return "\(rows.count.formatted(.number)) of \(monsters.count.formatted(.number)) monsters shown"
    }

    private var races: [String] {
        Set(monsters.map { $0.monster.race }).filter { !$0.isEmpty }.sorted()
    }

    private func list(_ rows: [MonsterEntry]) -> some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { entry in
                        MonsterRow(
                            monster: entry.monster,
                            isSelected: entry.monster.path == selectedPath,
                            select: { select(entry.monster.path, level, nil) },
                            open: {
                                select(entry.monster.path, level, nil)
                                openWindow(id: MonsterStatsWindow.id)
                            }
                        )
                        .id(entry.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .onChange(of: selectedPath) { _, path in
                guard let path else { return }

                scroll.scrollTo(path)
            }
        }
    }

    private func move(_ step: Int, within rows: [MonsterEntry]) {
        guard !rows.isEmpty else { return }

        let current = selectedPath.flatMap { path in rows.firstIndex { $0.monster.path == path } }
        let next = current.map { min(max($0 + step, 0), rows.count - 1) } ?? 0
        select(rows[next].monster.path, level, nil)
    }
}

/// One line of the listing: what it is called, what it is, and what it fights for.
private struct MonsterRow: View {
    let monster: CataloguedMonster
    let isSelected: Bool
    let select: () -> Void
    /// Opens the monster's own window, which is what a double click is for.
    let open: () -> Void

    @Environment(\.quickSearch)
    private var search

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Text(monster.name)
                    .foregroundStyle(monster.rank.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !monster.variant.isEmpty {
                    Text(monster.variant)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .help("Several records carry this name and differ in what they hold; this is which one")
                }

                Spacer(minLength: 8)

                Text(monster.race)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 140, alignment: .trailing)
                    .lineLimit(1)
                Text(monster.rank.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 82, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? Theme.accent.opacity(0.22) : .clear, in: .rect(cornerRadius: 5))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // The button keeps the single click; the double click runs alongside it rather than replacing
        // it, so one selects and two open the window.
        .simultaneousGesture(TapGesture(count: 2).onEnded(open))
        .quickSearch(search.emphasis(matching: monster.name), cornerRadius: 5)
        .help("Double-click to open \(monster.name) in a window of its own")
        .accessibilityLabel("\(monster.name), \(monster.rank.title), \(monster.race)")
        .accessibilityAction(named: "Open in a window", open)
    }
}

/// What the listing is being narrowed to, beyond whatever is typed in the search field.
struct MonsterFilter: Equatable {
    var name = ""
    var ranks: Set<MonsterRank> = []
    /// The race, not the faction: a monster's faction is who it fights beside, and the nemeses all
    /// carry the same one whatever they are. What a player means by "a beast" is the race.
    var race: String?

    var isActive: Bool { !name.isEmpty || !ranks.isEmpty || race != nil }

    func admits(_ monster: CataloguedMonster) -> Bool {
        guard ranks.isEmpty || ranks.contains(monster.rank) else { return false }
        guard race == nil || race == monster.race else { return false }

        return name.isEmpty || monster.name.localizedCaseInsensitiveContains(name)
    }
}

private struct MonsterFilterBar: View {
    @Binding
    var filter: MonsterFilter
    let races: [String]

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Name", text: $filter.name)
                    .textFieldStyle(.plain)
                    .frame(width: 130)
                if !filter.name.isEmpty {
                    Button(action: { filter.name = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Theme.panel, in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.subtleBorder))

            ForEach(MonsterRank.allCases, id: \.self) { rank in
                RankToggle(rank: rank, isOn: binding(for: rank))
            }

            Picker("Race", selection: $filter.race) {
                Text("Every race").tag(String?.none)
                ForEach(races, id: \.self) { race in
                    Text(race).tag(String?.some(race))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 175)
            .help("What the game's own \"damage to\" bonuses call it")

            if filter.isActive {
                Button("Clear") { filter = MonsterFilter() }
                    .buttonStyle(.link)
            }
        }
    }

    private func binding(for rank: MonsterRank) -> Binding<Bool> {
        Binding(
            get: { filter.ranks.contains(rank) },
            set: { isOn in
                if isOn {
                    filter.ranks.insert(rank)
                } else {
                    filter.ranks.remove(rank)
                }
            }
        )
    }
}

/// A rank of the filter bar, which has to read as on or off at a glance: a filled chip in the rank's
/// own colour against an outlined one.
private struct RankToggle: View {
    let rank: MonsterRank
    @Binding
    var isOn: Bool

    var body: some View {
        Button(action: { isOn.toggle() }) {
            Text(rank.title)
                .font(.caption.weight(isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Color.black : rank.color)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(isOn ? rank.color : .clear, in: .capsule)
                .overlay(Capsule().stroke(rank.color.opacity(isOn ? 0 : 0.55), lineWidth: 1))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(isOn ? "Showing \(rank.title) monsters — click to stop" : "Click to show \(rank.title) monsters")
        .accessibilityLabel("\(rank.title) monsters")
        .accessibilityValue(isOn ? "shown" : "hidden")
    }
}

extension MonsterRank {
    /// The tint the listing reads a rank in, rising with how dangerous it is.
    var color: Color {
        switch self {
            case .common: .primary
            case .champion: Color(red: 0.55, green: 0.78, blue: 0.98)
            case .hero: Color(red: 0.98, green: 0.82, blue: 0.35)
            case .quest: Color(red: 0.62, green: 0.85, blue: 0.55)
            case .boss: Color(red: 0.98, green: 0.55, blue: 0.30)
            case .superBoss: Color(red: 0.90, green: 0.35, blue: 0.85)
        }
    }
}
