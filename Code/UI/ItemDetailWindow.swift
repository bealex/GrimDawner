// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import SwiftUI

/// One item's whole account in a window of its own: what it carries, who drops it, and what a roll of
/// it could look like.
///
/// The sidebars show what fits a sidebar. This is the rest — the two questions a sidebar has no room
/// for, and which the game itself answers only the long way round.
struct ItemDetailWindow: View {
    static let id = "item-detail"

    let model: MainScreen.Model

    private enum Tab: String, CaseIterable, Identifiable {
        case info = "Item"
        case loot = "Loot"
        case affixes = "Affixes"

        var id: String { rawValue }
    }

    @State
    private var tab: Tab = .info
    @State
    private var search = ""

    var body: some View {
        Group {
            if let item = model.detailItem {
                content(item)
            } else {
                DetailPlaceholder(
                    title: "No item open",
                    hint: "Double-click an item in the directory or on the doll and it opens here."
                )
            }
        }
        .frame(minWidth: 620, minHeight: 460)
        .environment(\.textures, model.textures)
        .environment(\.damageIcons, model.damageIcons)
        .environment(\.quickSearch, QuickSearch(search))
        .background(TypeToSearch(text: $search).frame(width: 0, height: 0))
        .overlay(alignment: .top) {
            if !search.isEmpty { SearchOverlay(text: $search) }
        }
        .animation(.easeOut(duration: 0.15), value: search.isEmpty)
    }

    private func content(_ item: ResolvedItem) -> some View {
        VStack(spacing: 0) {
            header(item)
            Divider()
            ScrollView {
                switch tab {
                    case .info:
                        ItemDetailView(item: item, showsRolls: false, showsHeader: false, renderer: model.modelRenderer)
                            .padding(16)
                    case .loot: ItemLootView(item: item, model: model)
                    case .affixes: ItemAffixesView(item: item, model: model)
                }
            }
            // A different item is a different reading of everything, pickers and toggles included.
            .id(item.recordPath)
        }
        .navigationTitle(item.displayName)
    }

    /// What the panel used to repeat under the name: the rarity and the two levels.
    private func levels(_ item: ResolvedItem) -> String {
        [
            item.rarity.title,
            item.itemLevel > 0 ? "Item Level \(item.itemLevel)" : nil,
            item.levelRequirement > 0 ? "Requires Level \(item.levelRequirement)" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func header(_ item: ResolvedItem) -> some View {
        HStack(alignment: .center, spacing: 14) {
            GameIcon(path: item.iconPath, size: 28, fallbackSymbol: "shippingbox")
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    ItemQualityMark(path: item.qualityMarkPath, size: 14)
                    Text(item.displayName)
                        .font(.headline)
                        .foregroundStyle(item.rarity.color)
                }
                Text(levels(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
