// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import AppKit
import SwiftUI

/// Every item in the game, listed and searchable, with whichever one is picked shown in full.
///
/// The one tab a search filters rather than dims: eight thousand dimmed rows would leave the handful
/// that matched to be scrolled for.
struct ItemsTab: View {
    let items: [DirectoryEntry]
    let isListing: Bool
    let search: QuickSearch
    let selectedPath: String?
    let selected: ResolvedItem?
    let select: (String) -> Void

    /// Which groups are showing their level tiers, kept here so the arrow keys know what is on screen.
    @State
    private var expanded: Set<String> = []
    @State
    private var filter = DirectoryFilter()
    /// The row the arrow keys last walked to, which is the only thing that scrolls the list.
    @State
    private var walkedTo: String?

    var body: some View {
        // Grouping every match is the tab's one expensive step, so the list and the auto-selection
        // below read the same pass over it.
        let rows = groups

        TabLayout {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Divider()

                if isListing {
                    ProgressView("Reading every item in the game…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list(rows)
                        .background(ArrowKeys(move: move))
                }
            }
        } detail: {
            if let selected {
                ItemDetailView(item: selected, showsRolls: false)
                    // The query found this item by name, so the whole item is the match and none of
                    // its stats should dim.
                    .environment(\.quickSearch, search.matches(selected.displayName) ? QuickSearch() : search)
            } else {
                DetailPlaceholder(
                    title: "No item selected",
                    hint: "Pick an item to see everything it carries. Type to search the directory."
                )
            }
        }
        // A list narrowed to matches shows the first of them rather than an empty sidebar.
        .onChange(of: rows.first?.item.path, initial: true) { _, first in
            guard selectedPath == nil, search.isActive || filter.isActive, let first else { return }

            select(first)
        }
    }

    private var matches: [CataloguedItem] {
        items.lazy
            .filter { !search.isActive || search.matchesFolded($0.folded) }
            .map(\.item)
            .filter(filter.admits)
    }

    /// The game writes one record per level tier of the same item, so the tiers read as one entry.
    private var groups: [CatalogueGroup] {
        var order = [String]()
        var variants = [String: [CataloguedItem]]()

        for item in matches {
            let key = "\(item.name)|\(item.recordClass)"
            if variants[key] == nil { order.append(key) }
            variants[key, default: []].append(item)
        }
        return order.map { CatalogueGroup(id: $0, variants: variants[$0] ?? []) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Item Directory")
                    .font(.headline)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(width: 190, alignment: .leading)

            if !isListing {
                DirectoryFilterBar(
                    filter: $filter,
                    rarities: availableRarities,
                    kinds: availableKinds,
                    highestLevel: highestLevel
                )
            }

            Spacer(minLength: 8)
        }
    }

    private var summary: String {
        guard !isListing else { return "listing the game's records" }
        guard search.isActive || filter.isActive else { return "\(items.count.formatted(.number)) items" }

        return "\(matches.count.formatted(.number)) of \(items.count.formatted(.number)) items shown"
    }

    /// The rarities and kinds the catalogue actually holds, so the menus offer nothing empty.
    private var availableRarities: [ItemRarity] {
        Set(items.map { $0.item.quality }).sorted()
    }

    private var availableKinds: [String] {
        Set(items.map { $0.item.kind }).sorted()
    }

    /// The deepest level any item asks for, which is as far as the level control needs to run.
    private var highestLevel: Int {
        items.map { $0.item.levelRequirement }.max() ?? 0
    }

    private func list(_ rows: [CatalogueGroup]) -> some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { group in
                        GroupRow(
                            group: group,
                            selectedPath: selectedPath,
                            isExpanded: expanded.contains(group.id),
                            expand: { toggle(group) },
                            select: select
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            // Only the arrow keys scroll the list; a click leaves it where it is.
            .onChange(of: walkedTo) { _, path in
                guard let path else { return }

                scroll.scrollTo(path)
            }
        }
    }

    private func toggle(_ group: CatalogueGroup) {
        if expanded.contains(group.id) {
            expanded.remove(group.id)
        } else {
            expanded.insert(group.id)
        }
    }

    /// The visible rows, top to bottom, which is what the arrow keys walk.
    private var visibleRows: [String] {
        groups.flatMap { group in
            expanded.contains(group.id)
                ? [ group.item.path ] + group.variants.map(\.path)
                : [ group.item.path ]
        }
    }

    private func move(_ step: Int) {
        let rows = visibleRows
        guard !rows.isEmpty else { return }

        let current = selectedPath.flatMap { rows.firstIndex(of: $0) }
        let next = current.map { min(max($0 + step, 0), rows.count - 1) } ?? 0
        select(rows[next])
        walkedTo = rows[next]
    }
}

/// One item of the directory, with however many level tiers the game writes it at.
struct CatalogueGroup: Identifiable {
    let id: String
    let variants: [CataloguedItem]

    var item: CataloguedItem { variants[variants.count - 1] }
    var hasTiers: Bool { variants.count > 1 }

    /// Reads as "lv 94" for a single tier, or "lv 20–94 · 6 tiers" for an item written at several.
    var levels: String {
        let lowest = variants.map(\.levelRequirement).min() ?? 0
        let highest = variants.map(\.levelRequirement).max() ?? 0
        guard hasTiers, lowest != highest else { return highest > 0 ? "lv \(highest)" : "—" }

        return "lv \(lowest)–\(highest)"
    }
}

/// A directory line: the item at its highest tier, opening onto the rest of them.
private struct GroupRow: View {
    let group: CatalogueGroup
    let selectedPath: String?
    let isExpanded: Bool
    let expand: () -> Void
    let select: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ItemRow(
                item: group.item,
                detail: group.levels,
                isSelected: group.variants.contains { $0.path == selectedPath },
                tierCount: group.hasTiers ? group.variants.count : 0,
                isExpanded: isExpanded,
                expand: expand,
                select: { select(group.item.path) }
            )
            .id(group.item.path)

            if isExpanded {
                ForEach(group.variants) { variant in
                    ItemRow(
                        item: variant,
                        detail: variant.levelRequirement > 0 ? "lv \(variant.levelRequirement)" : "—",
                        isSelected: variant.path == selectedPath,
                        tierCount: 0,
                        isExpanded: false,
                        expand: nil,
                        select: { select(variant.path) }
                    )
                    .id(variant.path)
                    .padding(.leading, 26)
                }
            }
        }
    }
}

/// One line of the directory: what the item is, and how far into the game it belongs.
private struct ItemRow: View {
    let item: CataloguedItem
    let detail: String
    let isSelected: Bool
    /// How many level tiers sit under this line, or zero when it is a tier of its own.
    let tierCount: Int
    let isExpanded: Bool
    let expand: (() -> Void)?
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                tierToggle

                GameIcon(path: item.iconPath, size: 28, fallbackSymbol: "shippingbox")

                Text(item.name)
                    .foregroundStyle(item.quality.color)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Text(item.kind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(detail)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(.rect)
            .background(isSelected ? Theme.accent.opacity(0.18) : .clear, in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name), \(item.kind), \(detail)")
    }

    @ViewBuilder
    private var tierToggle: some View {
        if let expand, tierCount > 1 {
            Button(action: expand) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 16)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Hide the other tiers" : "Show all \(tierCount) tiers")
        } else {
            Color.clear.frame(width: 16, height: 1)
        }
    }
}

/// The up and down arrows, which walk a list wherever the pointer happens to be.
///
/// A local monitor, for the same reason the map's wheel is one: nothing here takes focus.
struct ArrowKeys: NSViewRepresentable {
    /// One row down for `1`, one up for `-1`.
    var move: (Int) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ArrowView()
        view.move = move
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? ArrowView)?.move = move
    }

    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        (view as? ArrowView)?.stopWatching()
    }

    private final class ArrowView: NSView {
        var move: ((Int) -> Void)?

        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window == nil ? stopWatching() : startWatching()
        }

        func startWatching() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) == true ? nil : event
            }
        }

        func stopWatching() {
            guard let monitor else { return }

            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        private func handle(_ event: NSEvent) -> Bool {
            guard event.window === window, !(window?.firstResponder is NSText) else { return false }

            switch event.keyCode {
                case Self.downArrow: move?(1)
                case Self.upArrow: move?(-1)
                default: return false
            }
            return true
        }

        private static let upArrow: UInt16 = 126
        private static let downArrow: UInt16 = 125
    }
}

/// What the directory is being narrowed to, beyond whatever is typed in the search field.
struct DirectoryFilter: Equatable {
    var minimumLevel = 0
    /// Empty means every rarity, which is how both menus read when nothing is ticked.
    var rarities: Set<ItemRarity> = []
    var kinds: Set<String> = []

    var isActive: Bool { minimumLevel > 0 || !rarities.isEmpty || !kinds.isEmpty }

    func admits(_ item: CataloguedItem) -> Bool {
        guard item.levelRequirement >= minimumLevel else { return false }
        guard rarities.isEmpty || rarities.contains(item.quality) else { return false }

        return kinds.isEmpty || kinds.contains(item.kind)
    }
}

/// The directory's own controls: how far into the game, of what quality, and of what kind.
private struct DirectoryFilterBar: View {
    @Binding
    var filter: DirectoryFilter
    let rarities: [ItemRarity]
    let kinds: [String]
    let highestLevel: Int

    var body: some View {
        HStack(spacing: 14) {
            level

            menu(
                title: rarities.isEmpty ? "Rarity" : label("Rarity", chosen: filter.rarities.count),
                systemImage: "circle.lefthalf.filled",
                clear: { filter.rarities.removeAll() }
            ) {
                ForEach(rarities, id: \.self) { rarity in
                    Toggle(rarity.title, isOn: binding(for: rarity))
                }
            }

            menu(
                title: label("Type", chosen: filter.kinds.count),
                systemImage: "square.grid.2x2",
                clear: { filter.kinds.removeAll() }
            ) {
                ForEach(kinds, id: \.self) { kind in
                    Toggle(kind, isOn: binding(for: kind))
                }
            }

            if filter.isActive {
                Button("Clear filters", systemImage: "xmark.circle") { filter = DirectoryFilter() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
        }
        .font(.callout)
    }

    private var level: some View {
        HStack(spacing: 6) {
            Text("Level")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(
                "0",
                value: Binding(
                    get: { filter.minimumLevel },
                    set: { filter.minimumLevel = min(max($0, 0), highestLevel) }
                ),
                format: .number
            )
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(width: 52)
            .accessibilityLabel("Lowest level to show")

            Text("+")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func menu(
        title: String,
        systemImage: String,
        clear: @escaping () -> Void,
        @ViewBuilder content: () -> some View
    ) -> some View {
        Menu {
            Button("Any", action: clear)
            Divider()
            content()
        } label: {
            Label(title, systemImage: systemImage)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func label(_ name: String, chosen: Int) -> String {
        chosen == 0 ? name : "\(name) (\(chosen))"
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

    private func binding(for kind: String) -> Binding<Bool> {
        Binding(
            get: { filter.kinds.contains(kind) },
            set: { isOn in
                if isOn {
                    filter.kinds.insert(kind)
                } else {
                    filter.kinds.remove(kind)
                }
            }
        )
    }
}
