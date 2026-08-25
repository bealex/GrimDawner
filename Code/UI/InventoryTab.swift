// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import GrimDawnerRender
import SwiftUI

/// The equipment doll, laid out on the game's own character panel, with the sheet beside it.
struct InventoryTab: View {
    let character: ResolvedCharacter
    let search: QuickSearch
    @Binding
    var selection: ResolvedItem?
    /// Draws the character's own model in the middle of the doll.
    var renderer: ModelRenderer?
    /// The records, for the gear the model is dressed in.
    var database: GameDatabase?
    /// Opens one of the character's own skills on its mastery panel.
    var revealSkill: ((String) -> Void)?

    @State
    private var weaponSet: Int?

    var body: some View {
        TabLayout {
            // The doll sits in the middle of the space it is given, and only scrolls when it outgrows it.
            GeometryReader { proxy in
                ScrollView {
                    VStack {
                        if let doll = character.doll {
                            DollView(
                                doll: doll,
                                character: character,
                                weaponSet: shownWeaponSet,
                                search: search,
                                selection: $selection,
                                renderer: renderer,
                                database: database,
                                swapWeaponSet: swapWeaponSet
                            )
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                }
            }
        } detail: {
            // The sheet is what the sidebar reads until a piece of gear is picked, and what the
            // character in the middle of the doll goes back to.
            if let selection {
                ItemDetailView(item: selection, wearer: character.skillContext, revealSkill: revealSkill)
            } else {
                CharacterSheetPanel(character: character)
            }
        }
    }

    /// The set the doll shows: whichever the character is holding, until you pick the other.
    private var shownWeaponSet: WeaponSet? {
        guard let index = weaponSet else { return character.weaponSets.first(where: \.isActive) }

        return character.weaponSets.first { $0.index == index }
    }

    private func swapWeaponSet() {
        let sets = character.weaponSets
        guard
            let shown = shownWeaponSet,
            let position = sets.firstIndex(where: { $0.index == shown.index })
        else { return }

        weaponSet = sets[(position + 1) % sets.count].index
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
    let renderer: ModelRenderer?
    let database: GameDatabase?
    let swapWeaponSet: () -> Void

    var body: some View {
        // The doll's boxes are small next to the skill panel's, so it is given a quarter more room.
        ScaledCanvas(size: doll.canvas, maximumScale: 1.25) {
            ZStack(alignment: .topLeading) {
                background
                portrait

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

                if let button = doll.weaponSwap, character.weaponSets.count > 1, let weaponSet {
                    WeaponSwapButton(button: button, set: weaponSet, swap: swapWeaponSet)
                        .offset(x: button.origin.x, y: button.origin.y)
                }
            }
        }
    }

    private var background: some View {
        ZStack(alignment: .topLeading) {
            GameArtwork(path: doll.background, size: doll.panel)
            // The artwork draws the panel's frame down its left edge only, since the inventory bag sits
            // against its right one. Mirroring that strip closes the panel.
            GameArtwork(path: doll.background, size: CGSize(width: doll.frame, height: doll.panel.height))
                .scaleEffect(x: -1, y: 1)
                .offset(x: doll.panel.width)
        }
    }

    private var portrait: some View {
        Button(action: { selection = nil }) {
            PortraitView(
                backdrop: doll.portraitBackground,
                size: doll.portrait.size,
                isSelected: selection == nil,
                character: character,
                weaponSet: weaponSet,
                renderer: renderer,
                database: database
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help("\(character.name) — show the character's own stats")
        .accessibilityLabel("\(character.name): shows the character's stats")
        .offset(x: doll.portrait.minX, y: doll.portrait.minY)
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

/// The character's own model where the game renders it, over the backdrop the game renders it against.
private struct PortraitView: View {
    let backdrop: String
    let size: CGSize
    /// Ringed while the sidebar is reading the character rather than a piece of gear.
    let isSelected: Bool
    let character: ResolvedCharacter
    let weaponSet: WeaponSet?
    let renderer: ModelRenderer?
    let database: GameDatabase?

    var body: some View {
        ZStack {
            // The game lights its own backdrop from in front of the model; drawn flat it is a pale wall
            // that the gear disappears into, so it is taken down to something the model stands out of.
            GameArtwork(path: backdrop, size: size)
                .colorMultiply(Color(white: 0.3))
            model
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .overlay(
            Rectangle()
                .stroke(isSelected ? Theme.accent : .clear, lineWidth: 2)
        )
        .accessibilityHidden(true)
    }

    /// The model sits inside the button that shows the character's own stats, and an `SCNView` takes
    /// every click that lands on it.
    private var model: some View {
        CharacterModelView(character: character, weaponSet: weaponSet, renderer: renderer, database: database)
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
    }
}

/// The game's own weapon-swap button, in the black space the window keeps it in.
private struct WeaponSwapButton: View {
    let button: EquipmentDoll.Button
    let set: WeaponSet
    let swap: () -> Void

    @State
    private var isHovered = false

    var body: some View {
        Button(action: swap) {
            GameBitmap(path: isHovered ? button.over : button.up)
                .overlay(alignment: .bottomTrailing) {
                    Text(set.index == 0 ? "I" : "II")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 2)
                        .background(.black.opacity(0.75), in: .rect(cornerRadius: 3))
                        .padding(2)
                }
        }
        .buttonStyle(PressedArtworkStyle(pressed: button.down))
        .onHover { isHovered = $0 }
        .help("\(button.title) — \(set.title)\(set.isActive ? " (in hand)" : "")\n\(button.hint)")
        .accessibilityLabel("\(button.title), showing \(set.title)")
    }
}

/// A button drawn as artwork, which swaps in the game's pressed image while it is held down.
private struct PressedArtworkStyle: ButtonStyle {
    let pressed: String

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            configuration.label.opacity(configuration.isPressed ? 0 : 1)
            if configuration.isPressed {
                GameBitmap(path: pressed)
            }
        }
        .contentShape(.rect)
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
