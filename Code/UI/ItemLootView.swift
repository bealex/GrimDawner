// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import SwiftUI

/// Who drops one item, and how often.
///
/// The game's tables run the other way — from a monster to what it leaves behind — so answering this
/// means reading every monster's tables once. That is a ten-second walk, done once per installed
/// version and kept on disk after it.
struct ItemLootView: View {
    let item: ResolvedItem
    let model: MainScreen.Model

    /// Off, the list is the monsters actually worth hunting for it. On, it is everything that could
    /// produce it at all, which for a generated item is most of the roster at a hundredth of a percent.
    @State
    private var showsEverything = false

    @Environment(\.openWindow)
    private var openWindow

    private var sources: [ItemDropSource] {
        let all = model.drops?.sources(forItemNamed: item.baseName) ?? []
        return showsEverything ? all : all.filter { $0.chance >= ItemDropSource.significant }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch model.dropState {
                case .loading:
                    ProgressView("Reading what every monster in the game can drop…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                case let .failed(reason):
                    Text(reason).foregroundStyle(.secondary)
                default:
                    controls
                    list
            }
        }
        .padding(16)
        .task { model.loadDrops() }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Toggle("Every source", isOn: $showsEverything)
                .toggleStyle(.checkbox)
                .help(
                    "Off, this lists the monsters worth hunting — a one-in-a-hundred chance or better. "
                        + "On, it lists everything whose tables can reach this item at all."
                )
            Spacer(minLength: 8)
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var summary: String {
        let all = model.drops?.sources(forItemNamed: item.baseName).count ?? 0
        guard all > 0 else { return "nothing drops it" }

        let shown = sources.count
        return shown == all ? "\(all) sources" : "\(shown) of \(all) sources"
    }

    @ViewBuilder
    private var list: some View {
        let sources = sources

        if sources.isEmpty {
            Text(emptyText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 4) {
                ForEach(sources) { source in
                    Button {
                        model.selectMonster(path: source.monsterPath, level: model.monsterLevel)
                        openWindow(id: MonsterStatsWindow.id)
                    } label: {
                        StatRow(
                            title: source.name,
                            value: chance(source.chance),
                            valueColor: source.chance >= ItemDropSource.significant ? Theme.accent : .secondary,
                            range: source.rank.title,
                            isNamed: true
                        )
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help("Open \(source.name)")
                }
            }
        }
    }

    private var emptyText: String {
        let all = model.drops?.sources(forItemNamed: item.baseName).count ?? 0
        if all > 0 {
            return "Nothing drops it at a one-in-a-hundred chance or better. Turn on every source to "
                + "see the \(all) whose tables can reach it at all."
        }
        return "No monster's tables reach this item. It is crafted, sold, or given — or it drops only "
            + "in the Shattered Realm, whose own copies of the roster are not read here."
    }

    private func chance(_ value: Double) -> String {
        value >= 0.01
            ? value.formatted(.number.precision(.significantDigits(1 ... 3))) + "%" : "<0.01%"
    }
}
