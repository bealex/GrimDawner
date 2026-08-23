// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import SwiftUI

/// Every prefix and suffix a random item can roll, listed and searchable.
///
/// Like the item directory, a search filters this list rather than dimming it: there are thousands of
/// affixes and only a handful ever match.
struct AffixesTab: View {
    let affixes: [AffixEntry]
    let isListing: Bool
    let search: QuickSearch
    let selectedKey: String?
    let selectedLevel: Int?
    /// Every record the open affix holds at the level being read.
    let selected: [ResolvedAffix]
    let select: (_ key: String, _ level: Int, _ paths: [String]) -> Void

    @State
    private var filter = AffixFilter()

    var body: some View {
        let rows = groups

        TabLayout {
            VStack(spacing: 0) {
                header(rows)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Divider()

                if isListing {
                    ProgressView("Reading every affix in the game…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list(rows)
                        .background(ArrowKeys(move: { move($0, within: rows) }))
                }
            }
        } detail: {
            if let group = rows.first(where: { $0.id == selectedKey }) ?? openGroup, !selected.isEmpty {
                AffixDetailView(
                    group: group,
                    variants: selected,
                    level: selectedLevel ?? group.levels.last ?? 0,
                    select: { level in open(group, at: level) }
                )
            } else {
                DetailPlaceholder(
                    title: "No affix selected",
                    hint: "Pick an affix to see what it grants. Type to search by name or by stat."
                )
            }
        }
        .onChange(of: rows.first?.id, initial: true) { _, _ in
            guard selectedKey == nil, search.isActive || filter.isActive, let first = rows.first else { return }

            open(first)
        }
    }

    private var matches: [CataloguedAffix] {
        affixes.lazy
            .filter { !search.isActive || search.matchesFolded($0.folded) }
            .map(\.affix)
            .filter(filter.admits)
    }

    /// One line per affix name: the game writes the same name at several levels and, at each level,
    /// once per kind of item it can land on. The sidebar reads whichever level is picked.
    private var groups: [AffixGroup] { Self.grouped(matches) }

    private var allGroups: [AffixGroup] { Self.grouped(affixes.map(\.affix)) }

    private static func grouped(_ affixes: [CataloguedAffix]) -> [AffixGroup] {
        var order = [String]()
        var variants = [String: [CataloguedAffix]]()

        for affix in affixes {
            let key = "\(affix.name)|\(affix.kind.rawValue)"
            if variants[key] == nil { order.append(key) }
            variants[key, default: []].append(affix)
        }
        return order.map { key in
            AffixGroup(id: key, variants: (variants[key] ?? []).sorted { $0.levelRequirement < $1.levelRequirement })
        }
    }

    /// The open affix, even when a filter has since narrowed it out of the list.
    private var openGroup: AffixGroup? {
        guard let selectedKey else { return nil }

        return allGroups.first { $0.id == selectedKey }
    }

    /// Opens an affix at one of its levels, defaulting to the deepest.
    private func open(_ group: AffixGroup, at level: Int? = nil) {
        let wanted = level ?? group.levels.last ?? 0
        select(group.id, wanted, group.variants.filter { $0.levelRequirement == wanted }.map(\.path))
    }

    private func header(_ rows: [AffixGroup]) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Affixes")
                    .font(.headline)
                Text(summary(rows))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(width: 190, alignment: .leading)

            if !isListing {
                AffixFilterBar(filter: $filter, rarities: availableRarities)
            }

            Spacer(minLength: 8)
        }
    }

    private func summary(_ rows: [AffixGroup]) -> String {
        guard !isListing else { return "reading the game's records" }
        guard search.isActive || filter.isActive else { return "\(affixes.count.formatted(.number)) affixes" }

        return "\(rows.count.formatted(.number)) of \(affixes.count.formatted(.number)) affixes shown"
    }

    private var availableRarities: [ItemRarity] {
        Set(affixes.map { $0.affix.quality }).sorted()
    }

    private func list(_ rows: [AffixGroup]) -> some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { group in
                        AffixRow(group: group, isSelected: group.id == selectedKey, select: { open(group) })
                            .id(group.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .onChange(of: selectedKey) { _, key in
                guard let key else { return }

                scroll.scrollTo(key)
            }
        }
    }

    private func move(_ step: Int, within rows: [AffixGroup]) {
        guard !rows.isEmpty else { return }

        let current = selectedKey.flatMap { key in rows.firstIndex { $0.id == key } }
        let next = current.map { min(max($0 + step, 0), rows.count - 1) } ?? 0
        open(rows[next])
    }
}

/// One affix of the catalogue, with however many level tiers the game writes it at.
struct AffixGroup: Identifiable {
    let id: String
    let variants: [CataloguedAffix]

    /// The deepest tier, which is the one a level-100 character sees.
    var deepest: CataloguedAffix { variants[variants.count - 1] }
    var hasTiers: Bool { levels.count > 1 }

    /// The levels this affix is written at, in order.
    var levels: [Int] { Array(Set(variants.map(\.levelRequirement))).sorted() }

    /// Reads as "lv 94", or "lv 5–94" for an affix written at several levels.
    var levelSpan: String {
        guard let lowest = levels.first, let highest = levels.last else { return "—" }
        guard hasTiers else { return highest > 0 ? "lv \(highest)" : "—" }

        return "lv \(lowest)–\(highest)"
    }
}

/// One line of the affix catalogue: what it is called, what kind it is, and how deep into the game it sits.
private struct AffixRow: View {
    let group: AffixGroup
    let isSelected: Bool
    let select: () -> Void

    @Environment(\.quickSearch)
    private var search

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Text(group.deepest.name)
                    .foregroundStyle(group.deepest.quality.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if group.hasTiers {
                    Text("\(group.levels.count) levels")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(group.deepest.kind.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(group.levelSpan)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 84, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? Theme.accent.opacity(0.22) : .clear, in: .rect(cornerRadius: 5))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .quickSearch(search.emphasis(matching: group.deepest.name), cornerRadius: 5)
        .accessibilityLabel("\(group.deepest.name), \(group.deepest.kind.rawValue), \(group.levelSpan)")
    }
}

/// What one affix grants at one of its levels, as the band each figure rolls in.
///
/// A name at a level is not one record: the game writes it once per kind of item it can land on, and
/// those differ, so every one of them is listed.
private struct AffixDetailView: View {
    let group: AffixGroup
    let variants: [ResolvedAffix]
    let level: Int
    let select: (Int) -> Void

    @Environment(\.quickSearch)
    private var search

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.deepest.name)
                    .font(.title3.bold())
                    .foregroundStyle(group.deepest.quality.color)
                    .quickSearchText(search.emphasis(matching: group.deepest.name))
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if group.levels.count > 1 {
                Picker("Level", selection: Binding(get: { level }, set: select)) {
                    ForEach(group.levels, id: \.self) { level in
                        Text(level > 0 ? "\(level)" : "—").tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Which level tier of this affix to read")
            }

            ForEach(variants) { variant in
                SectionCard(
                    title: variants.count > 1 ? "One of \(variants.count) rolls" : "Bonuses",
                    subtitle: variant.jitter > 0 ? "rolling ±\(Int(variant.jitter))%" : nil
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        StatBlockView(
                            block: variant.statsLowest,
                            lowest: variant.statsLowest,
                            highest: variant.statsHighest,
                            showsRolls: false
                        )
                        ForEach(variant.grantedSkills) { granted in
                            Text(granted.summary)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
        }
    }

    private var summary: String {
        [
            group.deepest.kind.rawValue,
            group.deepest.quality.title,
            level > 0 ? "Requires level \(level)" : nil,
            variants.count > 1 ? "\(variants.count) rolls at this level" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

/// What the affix catalogue is being narrowed to, beyond whatever is typed in the search field.
struct AffixFilter: Equatable {
    var kind: CataloguedAffix.Kind?
    var rarities: Set<ItemRarity> = []

    var isActive: Bool { kind != nil || !rarities.isEmpty }

    func admits(_ affix: CataloguedAffix) -> Bool {
        guard kind == nil || kind == affix.kind else { return false }

        return rarities.isEmpty || rarities.contains(affix.quality)
    }
}

/// The catalogue's own controls: prefix or suffix, and of what quality.
private struct AffixFilterBar: View {
    @Binding
    var filter: AffixFilter
    let rarities: [ItemRarity]

    var body: some View {
        HStack(spacing: 10) {
            Picker("Kind", selection: $filter.kind) {
                Text("Both").tag(CataloguedAffix.Kind?.none)
                Text("Prefixes").tag(CataloguedAffix.Kind?.some(.prefix))
                Text("Suffixes").tag(CataloguedAffix.Kind?.some(.suffix))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)

            ForEach(rarities, id: \.self) { rarity in
                Toggle(rarity.title, isOn: binding(for: rarity))
                    .toggleStyle(.button)
                    .tint(rarity.color)
            }

            if filter.isActive {
                Button("Clear") { filter = AffixFilter() }
                    .buttonStyle(.link)
            }
        }
    }

    private func binding(for rarity: ItemRarity) -> Binding<Bool> {
        Binding(
            get: { filter.rarities.contains(rarity) },
            set: { isOn in
                if isOn {
                    filter.rarities.insert(rarity)
                } else {
                    filter.rarities.remove(rarity)
                }
            }
        )
    }
}
