// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import SwiftUI

/// What an item can roll, and what it becomes when it does.
///
/// An item's own record says nothing about its affixes: the loot table that produces it names the
/// prefix and suffix tables anything rolled off it draws from. Picking one of each builds the item the
/// way the game builds a dropped one and reads it back, so the panel below is the real thing rather
/// than a sum of two lists.
struct ItemAffixesView: View {
    let item: ResolvedItem
    let model: MainScreen.Model

    @State
    private var prefix: String?
    @State
    private var suffix: String?
    @State
    private var pool: ItemAffixPool?

    private var rolled: ResolvedItem? {
        guard prefix != nil || suffix != nil else { return nil }

        return model.item(at: item.baseName, prefix: prefix, suffix: suffix)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let pool {
                if pool.isEmpty {
                    Text(
                        "Nothing rolls on this one. A legendary, a quest item or a crafted piece carries "
                            + "what its own record says and takes no prefix or suffix."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    choosers(pool)
                    if let rolled {
                        Divider()
                        ItemDetailView(item: rolled, showsRolls: false)
                    } else {
                        Text("Pick a prefix or a suffix to see what the item becomes.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ProgressView("Reading which affixes reach this item…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            }
        }
        .padding(16)
        .task(id: item.baseName) {
            prefix = nil
            suffix = nil
            pool = nil
            pool = await model.affixPool(forItemAt: item.baseName)
        }
    }

    private func choosers(_ pool: ItemAffixPool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            chooser("Prefix", pool.prefixes, selection: $prefix)
            chooser("Suffix", pool.suffixes, selection: $suffix)
            HStack(spacing: 10) {
                Button("Clear both") {
                    prefix = nil
                    suffix = nil
                }
                .buttonStyle(.link)
                .disabled(prefix == nil && suffix == nil)
                Spacer(minLength: 8)
                Text("Every figure reads at the bottom of its band, which is what the item is sure to carry.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// One side's choices. The same name appears at several level tiers, so each says what it asks for.
    private func chooser(_ title: String, _ choices: [ItemAffixPool.Choice], selection: Binding<String?>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            Picker(title, selection: selection) {
                Text("None").tag(String?.none)
                Divider()
                ForEach(choices) { choice in
                    Text(label(of: choice)).tag(String?.some(choice.path))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 420, alignment: .leading)
            Text("\(choices.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    private func label(of choice: ItemAffixPool.Choice) -> String {
        [
            choice.name,
            choice.levelRequirement > 0 ? "· level \(choice.levelRequirement)" : nil,
            choice.isRare ? "· rare" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}
