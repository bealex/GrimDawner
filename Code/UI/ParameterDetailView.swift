// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import SwiftUI

/// What the parameters sidebar is showing.
enum ParameterSelection: Equatable {
    case stat(title: String, key: String)

    var title: String {
        switch self {
            case let .stat(title, _): title
        }
    }

    var key: String {
        switch self {
            case let .stat(_, key): key
        }
    }
}

/// One stat pulled apart: every piece of gear, skill and constellation that feeds it.
struct ParameterDetailView: View {
    let selection: ParameterSelection
    let character: ResolvedCharacter
    /// Opens a piece of gear where it is worn, since a line naming it invites a look.
    let reveal: (ResolvedItem) -> Void

    var body: some View {
        let sources = StatSources.contributors(to: selection.key, in: character)

        VStack(alignment: .leading, spacing: 14) {
            header(total: sources.reduce(0) { $0 + $1.value })

            if sources.isEmpty {
                Text("Nothing the app reads feeds this — it comes from the character's own level.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
            } else {
                ForEach(StatSources.Kind.allCases, id: \.self) { kind in
                    let group = sources.filter { $0.kind == kind }
                    if !group.isEmpty {
                        SectionCard(title: kind.title) {
                            VStack(spacing: 6) {
                                ForEach(group) { source in
                                    row(source)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// One source of the figure. A line only becomes a button where there is a piece of gear to open:
    /// a disabled button is drawn greyed, and a mastery or a constellation is no less real a source for
    /// having no doll to be shown on.
    @ViewBuilder
    private func row(_ source: StatSources.Entry) -> some View {
        let line = StatRow(
            title: source.name,
            value: format(source.value),
            valueColor: Theme.valueColor(source.value),
            icon: source.item == nil ? nil : "arrow.up.forward.square",
            titleIconPath: source.item?.iconPath,
            isNamed: true
        )

        if let item = source.item {
            Button(action: { reveal(item) }) {
                line.contentShape(.rect)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("Show \(source.name) on the doll")
        } else {
            line
        }
    }

    private func header(total: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selection.title)
                .font(.title3.bold())
            Text(selection.key)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text("Sources add up to \(format(total))")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func format(_ value: Double) -> String {
        StatCatalog.definition(for: selection.key).map { $0.unit.format($0.shown(value)) }
            ?? value.formatted(.number.precision(.fractionLength(0)))
    }
}

/// Where one stat's value comes from, piece by piece.
enum StatSources {
    enum Kind: CaseIterable {
        case gear
        case skills
        case devotion
        case difficulty

        var title: String {
            switch self {
                case .gear: "Gear"
                case .skills: "Masteries and skills"
                case .devotion: "Devotion"
                case .difficulty: "Difficulty"
            }
        }
    }

    struct Entry: Identifiable {
        let id = UUID()
        let kind: Kind
        let name: String
        let value: Double
        /// The gear this line is about, for selecting it in the Inventory tab.
        var item: ResolvedItem?
    }

    /// Everything feeding one figure, the blanket bonuses it folds in included: fire resistance is fed
    /// by "+3% to all resistances" and "+15% elemental resistance" as much as by its own stat.
    static func contributors(to key: String, in character: ResolvedCharacter) -> [Entry] {
        var entries = [Entry]()
        for part in StatComposition.parts(feeding: key) {
            entries += contributors(to: part, in: character)
        }
        return entries.sorted { abs($0.value) > abs($1.value) }
    }

    private static func contributors(to part: StatComposition.Part, in character: ResolvedCharacter) -> [Entry] {
        var entries = [Entry]()
        let key = part.key

        func name(_ source: String) -> String {
            part.note.isEmpty ? source : "\(source) · \(part.note)"
        }

        for item in character.equippedItems {
            let value = item.stats.value(key)
            guard value != 0 else { continue }

            // A component or an augment is worn as part of the item, and the game credits it by name;
            // its share is listed under the piece it sits in rather than folded into it.
            let fitted = item.parts.filter { part in
                part.kind == .component || part.kind == .augment || part.kind == .completionBonus
            }
            for fitting in fitted where fitting.stats.value(key) != 0 {
                entries.append(Entry(
                    kind: .gear,
                    name: name("\(fitting.title) · in \(item.displayName)"),
                    value: fitting.stats.value(key),
                    item: item
                ))
            }

            let fittedTotal = fitted.reduce(0) { $0 + $1.stats.value(key) }
            if abs(value - fittedTotal) >= 0.005 {
                entries.append(Entry(kind: .gear, name: name(item.displayName), value: value - fittedTotal, item: item))
            }
        }

        for mastery in character.masteries {
            let value = mastery.bonuses.value(key)
            if value != 0 {
                entries.append(Entry(kind: .skills, name: name("\(mastery.name) mastery"), value: value))
            }

            for skill in mastery.sheetSkills {
                let value = skill.stats.value(key)
                guard value != 0 else { continue }

                entries.append(Entry(kind: .skills, name: name(skill.name), value: value))
            }
        }

        for set in character.sets {
            let value = set.bonuses.value(key)
            guard value != 0 else { continue }

            entries.append(Entry(kind: .gear, name: name("\(set.name) (\(set.summary))"), value: value))
        }

        for constellation in character.devotion.startedConstellations {
            let value = constellation.bonuses.value(key)
            guard value != 0 else { continue }

            entries.append(Entry(kind: .devotion, name: name(constellation.name), value: value))
        }

        let penalty = character.difficultyPenalty.value(key)
        if penalty != 0 {
            entries.append(Entry(
                kind: .difficulty,
                name: name("\(character.difficulty.title) difficulty"),
                value: penalty
            ))
        }

        return entries
    }
}
