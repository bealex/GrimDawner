// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import SwiftUI

/// The equipment doll, laid out on the game's own character panel, with both weapon sets.
struct InventoryTab: View {
    let character: ResolvedCharacter
    let search: QuickSearch
    @Binding
    var selection: ResolvedItem?

    @State
    private var weaponSet: Int?

    var body: some View {
        TabLayout {
            // The doll sits in the middle of the space it is given, and only scrolls when it outgrows it.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        if let doll = character.doll {
                            DollView(
                                doll: doll,
                                character: character,
                                weaponSet: shownWeaponSet,
                                search: search,
                                selection: $selection
                            )
                        }
                        weaponSetPicker
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                }
            }
        } detail: {
            if let selection {
                ItemDetailView(item: selection, wearer: character.skillContext)
            } else {
                DetailPlaceholder(title: "No item selected", hint: "Pick a piece of gear to see everything it carries.")
            }
        }
    }

    /// The set the doll shows: whichever the character is holding, until you pick the other.
    private var shownWeaponSet: WeaponSet? {
        guard let index = weaponSet else { return character.weaponSets.first(where: \.isActive) }

        return character.weaponSets.first { $0.index == index }
    }

    private var weaponSetPicker: some View {
        Picker("Weapon set", selection: Binding(get: { shownWeaponSet?.index ?? 0 }, set: { weaponSet = $0 })) {
            ForEach(character.weaponSets) { set in
                Text(set.isActive ? "\(set.title) (in hand)" : set.title).tag(set.index)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 360)
        .accessibilityLabel("Weapon set shown on the doll")
    }
}

/// The doll itself: the game's panel art with an item drawn in each box.
private struct DollView: View {
    let doll: EquipmentDoll
    let character: ResolvedCharacter
    let weaponSet: WeaponSet?
    let search: QuickSearch
    @Binding
    var selection: ResolvedItem?

    var body: some View {
        // The doll's boxes are small next to the skill panel's, so it is given a quarter more room.
        ScaledCanvas(size: doll.canvas, maximumScale: 1.25) {
            ZStack(alignment: .topLeading) {
                GameArtwork(path: doll.background, size: doll.canvas)

                ForEach(doll.slots) { slot in
                    let item = item(in: slot)
                    DollBox(
                        slot: slot,
                        item: item,
                        isSelected: item != nil && selection?.id == item?.id,
                        emphasis: search.emphasis(isMatch: matches(item)),
                        select: { selection = item }
                    )
                    .position(x: slot.frame.midX, y: slot.frame.midY)
                }
            }
        }
    }

    private func item(in slot: DollSlot) -> ResolvedItem? {
        switch slot.kind {
            case let .equipment(kind): character.equipment.first { $0.slot == kind }?.item
            case .mainHand: weaponSet?.items.first ?? nil
            case .offHand: weaponSet?.items.last ?? nil
        }
    }

    private func matches(_ item: ResolvedItem?) -> Bool {
        guard let item else { return false }

        return search.matches(
            [ item.displayName, item.rarity.title ] + item.stats.titles
                + item.parts.map(\.name) + item.grantedSkills.map(\.name)
        )
    }
}

/// One box on the doll: the item in it, or the outline the game shows when it is empty.
private struct DollBox: View {
    let slot: DollSlot
    let item: ResolvedItem?
    let isSelected: Bool
    let emphasis: QuickSearch.Emphasis
    let select: () -> Void

    @State
    private var isHovered = false

    var body: some View {
        Button(action: select) {
            ZStack {
                if let item {
                    GameIcon(
                        path: item.iconPath,
                        width: slot.frame.width - 2,
                        height: slot.frame.height - 2,
                        fallbackSymbol: slot.symbolName
                    )
                } else {
                    GameIcon(
                        path: slot.silhouette,
                        width: slot.frame.width,
                        height: slot.frame.height,
                        fallbackSymbol: slot.symbolName
                    )
                    .opacity(0.35)
                }
            }
            .frame(width: slot.frame.width, height: slot.frame.height)
            .background(background)
            .overlay(border)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(item == nil)
        .scaleEffect(isHovered && item != nil ? 1.04 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .help(helpText)
        .quickSearch(emphasis, cornerRadius: 4)
        .accessibilityLabel("\(slot.title): \(item?.displayName ?? "empty")")
        .accessibilityHint(item == nil ? "" : "Shows this item's full stats")
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill((item?.rarity.color ?? .clear).opacity(isSelected ? 0.28 : 0.1))
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 3)
            .stroke(
                isSelected ? Theme.accent : (item?.rarity.color ?? .clear).opacity(0.7),
                lineWidth: isSelected ? 2 : 1
            )
    }

    private var helpText: String {
        guard let item else { return "\(slot.title) — empty" }

        return "\(item.displayName)\n\(slot.title) · \(item.rarity.title)"
    }
}
