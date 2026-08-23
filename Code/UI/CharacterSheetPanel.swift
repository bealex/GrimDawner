// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import SwiftUI

/// The figures the game's character window prints beside the doll: who this is, the three attributes,
/// the pools, the combat stats and the resistance grid.
///
/// The Stats tab is the full account; this is the glance the equipment screen gives, with the same
/// popups the game opens on Armor Rating.
struct CharacterSheetPanel: View {
    let character: ResolvedCharacter

    private var sheet: CharacterSheet { character.sheet }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            attributesCard
            combatCard
            resistancesCard
        }
    }

    /// The name is the window's own title, so the panel opens on what the game prints under it.
    private var header: some View {
        Text(subtitle)
            .font(.title3.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 4)
    }

    private var subtitle: String {
        [
            "Level \(character.level)",
            character.className,
            character.isHardcore ? "Hardcore" : nil,
            character.difficulty.title,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var attributesCard: some View {
        SectionCard(title: "Attributes") {
            VStack(spacing: 6) {
                attribute("Physique", sheet.physique)
                attribute("Cunning", sheet.cunning)
                attribute("Spirit", sheet.spirit)
                Divider().padding(.vertical, 2)
                StatRow(title: "Health", value: whole(sheet.health), icon: "heart.fill")
                StatRow(title: "Energy", value: whole(sheet.energy), icon: "bolt.fill")
            }
        }
    }

    /// An attribute reads as its total, with what gear and skills add to the level's own points beside it.
    private func attribute(_ title: String, _ value: CharacterSheet.Attribute) -> some View {
        StatRow(
            title: title,
            value: whole(value.total),
            valueColor: value.bonus > 0 ? Theme.valueColor(1) : .primary,
            range: value.bonus > 0 ? "\(whole(value.base)) + \(whole(value.bonus))" : nil
        )
    }

    private var combatCard: some View {
        SectionCard(title: "Combat Stats") {
            VStack(spacing: 6) {
                // The weapon's own damage is not modelled, and everything the game's damage panel prints
                // is built on it.
                StatRow(title: "Damage Per Second", value: "—", icon: "flame.fill")
                    .help("Weapon damage is not modelled yet, so the game's damage panel has no figure here.")
                StatRow(title: "Offensive Ability", value: whole(sheet.offensiveAbility), icon: "target")
                StatRow(title: "Defensive Ability", value: whole(sheet.defensiveAbility), icon: "figure.fencing")
                ArmorRatingRow(sheet: sheet)
            }
        }
    }

    private var resistancesCard: some View {
        SectionCard(title: "Resistances") {
            VStack(spacing: 6) {
                ForEach(ResistanceKind.allCases, id: \.self) { kind in
                    ResistanceRow(
                        kind: kind,
                        value: sheet.resistances[kind] ?? 0,
                        maximum: sheet.maxResistances[kind] ?? CharacterSheet.resistanceCap
                    )
                }
            }
        }
    }

    private func whole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}

/// Armor Rating, opening the same region-by-region account the game's own popup gives.
private struct ArmorRatingRow: View {
    let sheet: CharacterSheet

    @State
    private var isShowingRegions = false

    var body: some View {
        Button(action: { isShowingRegions = true }) {
            StatRow(
                title: "Armor Rating",
                value: sheet.armor.rounded().formatted(.number.precision(.fractionLength(0))),
                icon: "shield.fill",
                range: "\(Int(sheet.armorAbsorption))% absorbed"
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("What each hit region carries")
        .popover(isPresented: $isShowingRegions, arrowEdge: .trailing) {
            ArmorRegionsPopover(sheet: sheet)
        }
    }
}

/// Every hit region: how often it is the one struck, what it wears, and how much of a hit it absorbs.
private struct ArmorRegionsPopover: View {
    let sheet: CharacterSheet

    /// Head down to feet, the order the game's own popup lists them in.
    private static let regions: [EquipmentSlot] = [ .head, .shoulders, .chest, .hands, .legs, .feet ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Armor Rating")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow {
                    Text("Region")
                    Text("Hit")
                        .gridColumnAlignment(.trailing)
                    Text("Armor")
                        .gridColumnAlignment(.trailing)
                    Text("Absorbed")
                        .gridColumnAlignment(.trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                ForEach(Self.regions, id: \.self) { slot in
                    GridRow {
                        Text(slot.title)
                        Text("\(Int((sheet.armorHitChance[slot] ?? 0).rounded()))%")
                        Text((sheet.armorBySlot[slot] ?? 0).rounded().formatted(.number.precision(.fractionLength(0))))
                        Text("\(Int(sheet.armorAbsorption))%")
                    }
                    .monospacedDigit()
                }
            }
            Text(
                "Armor Rating is the average of the regions, each counting as often as it is hit. "
                    + "A region absorbs that share of the physical damage its own armour covers."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 260, alignment: .leading)
        }
        .padding(14)
    }
}

/// One resistance: the game's own mark, the type in its colour, the figure it counts at, and whatever
/// stands over the cap.
private struct ResistanceRow: View {
    let kind: ResistanceKind
    let value: Double
    let maximum: Double

    @Environment(\.damageIcons)
    private var damageIcons

    private var over: Int { Int((value - maximum).rounded()) }

    var body: some View {
        StatRow(
            title: kind.title,
            value: "\(Int(min(value, maximum).rounded()))%",
            valueColor: value < 0 ? .red : .primary,
            accents: [ Theme.Accent(word: kind.title, color: kind.color) ],
            iconPath: damageIcons[Theme.damageToken(forStatKey: kind.resistanceKey) ?? ""],
            range: over > 0 ? Theme.overCap(Double(over)) : nil
        )
        .help("\(kind.title): \(Int(value))%, capped at \(Int(maximum))%")
    }
}
