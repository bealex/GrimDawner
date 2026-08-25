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
                    case .info: ItemDetailView(item: item, showsRolls: false).padding(16)
                    case .loot: ItemLootView(item: item, model: model)
                    case .affixes: ItemAffixesView(item: item, model: model)
                }
            }
        }
        .navigationTitle(item.displayName)
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
                Text(item.rarity.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
