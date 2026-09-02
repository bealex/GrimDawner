// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import GrimDawnerRender
import SwiftUI

/// What a plan is worth, in the sidebar beside the doll that shows what it puts where.
struct PlanDetail: View {
    let plan: LoadoutPlan
    let character: ResolvedCharacter

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            worth
            resistances
            if !plan.vendors.isEmpty {
                merchants
            }
            caveats
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(plan.goal.rawValue, systemImage: plan.goal.symbolName)
                .font(.title3.weight(.semibold))
            Text(plan.goal.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !plan.isFeasible {
                Text(shortfallText)
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if plan.defensiveAbilityShortfall > 0.5 {
                Text("Defensive Ability lands \(Int(plan.defensiveAbilityShortfall.rounded())) under what was asked.")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if plan.armorAbsorptionShortfall > 0.5 {
                Text("Armor Absorption lands \(Int(plan.armorAbsorptionShortfall.rounded()))% under what was asked.")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var shortfallText: String {
        let short = plan.shortfalls
            .sorted { $0.key.title < $1.key.title }
            .map { "\($0.key.title) by \(Int($0.value.rounded(.up)))%" }
        return "Nothing reaches every cap: short on " + short.joined(separator: ", ") + "."
    }

    private var worth: some View {
        SectionCard(title: "What it comes to") {
            VStack(spacing: 0) {
                figure("Offensive Ability", character.sheet.offensiveAbility, plan.sheet.offensiveAbility)
                figure("Defensive Ability", character.sheet.defensiveAbility, plan.sheet.defensiveAbility)
                figure("Armor Rating", character.sheet.armor, plan.sheet.armor)
                figure("Armor Absorption", character.sheet.armorAbsorption, plan.sheet.armorAbsorption, unit: "%")
                figure("Health", character.sheet.health, plan.sheet.health)
                if let damage = plan.skillDamagePerSecond {
                    figure("Skill Damage / second", 0, damage, showsChange: false)
                }
            }
        }
    }

    private func figure(
        _ title: String,
        _ now: Double,
        _ then: Double,
        unit: String = "",
        showsChange: Bool = true
    ) -> some View {
        let change = then - now
        let value = then.formatted(.number.precision(.fractionLength(0))) + unit
        let detail =
            showsChange && abs(change) >= 0.5
            ? (change > 0 ? "+" : "") + change.formatted(.number.precision(.fractionLength(0)))
            : ""

        return StatRow(
            title: title,
            value: value,
            valueColor: !showsChange || abs(change) < 0.5 ? .primary : (change > 0 ? .green : .red),
            range: detail.isEmpty ? nil : detail
        )
    }

    private var resistances: some View {
        SectionCard(title: "Resistances", subtitle: "on \(Self.title(of: plan.difficulty))") {
            VStack(spacing: 0) {
                ForEach(ResistanceKind.allCases, id: \.self) { kind in
                    let held = plan.sheet.resistances[kind] ?? 0
                    let cap = plan.sheet.maxResistances[kind] ?? 80
                    // What actually stops damage is the capped figure; the rest is the buffer a
                    // resistance-stripping enemy eats into before the cap starts falling.
                    StatRow(
                        title: kind.title,
                        value: "\(Int(min(held, cap)))%",
                        valueColor: held >= cap ? .primary : .orange,
                        range: aside(held: held, cap: cap, taken: plan.difficultyPenalty[kind] ?? 0)
                    )
                }
            }
        }
    }

    /// What sits beside a resistance: how much of it stands over the cap as a buffer, and what the
    /// difficulty took off it to begin with — the two figures that say how hard the cap was to hold.
    private func aside(held: Double, cap: Double, taken: Double) -> String? {
        let parts = [
            held > cap ? "↑\(Int(held - cap))%" : nil,
            taken < 0 ? "\(Int(taken))% taken" : nil,
        ]
        .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Ascendant takes nothing further off a character, so the two share a line.
    static func title(of difficulty: Difficulty) -> String {
        difficulty == .ultimate ? "Ultimate / Ascendant" : difficulty.title
    }

    private var merchants: some View {
        SectionCard(title: "Bought from") {
            VStack(spacing: 0) {
                ForEach(plan.vendors, id: \.faction) { vendor in
                    StatRow(title: vendor.faction, value: vendor.standing, valueColor: Theme.accent, isNamed: true)
                }
            }
        }
    }

    private var caveats: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What this does not count")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(
                "A component's completion bonus is drawn at random from its own table, so no plan can "
                    + "promise one and none is counted — every figure here is the least the plan is worth. "
                    + "Skill ranks are held at what the character has now, so a fitting that grants +1 to a "
                    + "mastery is not credited with what that rank would unlock."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Which way a block reads. A block down the left of the panel ends against it — its artwork on the
/// inside edge and its words running back out — so the panel keeps a clean margin on both sides.
enum BlockAlignment {
    case leading
    case centre
    case trailing

    var horizontal: HorizontalAlignment {
        switch self {
            case .leading: .leading
            case .centre: .center
            case .trailing: .trailing
        }
    }

    var frame: Alignment {
        switch self {
            case .leading: .topLeading
            case .centre: .top
            case .trailing: .topTrailing
        }
    }

    var text: TextAlignment {
        switch self {
            case .leading: .leading
            case .centre: .center
            case .trailing: .trailing
        }
    }
}

/// What a plan puts where, drawn on the game's own character panel with each socket's fittings
/// written out beside the piece they go into.
///
/// Everything is laid out in the panel's own coordinates and scaled once, so a block can be put at the
/// height of the slot it belongs to. Most slots take a gutter to their own side of the panel; the two
/// rings and the amulet sit within forty points of one another, so those read as a row above the panel
/// instead, and the belt and medal as a row below it.
struct PlanDoll: View {
    let doll: EquipmentDoll
    let character: ResolvedCharacter
    let plan: LoadoutPlan
    let weaponSet: WeaponSet?
    let renderer: ModelRenderer?
    let database: GameDatabase?
    var openItem: ((String) -> Void)?

    /// One block, once it has been given a place to sit.
    private struct Placement: Identifiable {
        let choice: LoadoutChoice
        let title: String
        let reading: BlockAlignment
        let width: CGFloat
        var origin: CGPoint

        var id: String { choice.id }
    }

    private static let gutter: CGFloat = 250
    private static let blockWidth: CGFloat = 236
    /// A band's blocks are narrower than a gutter's: four of them have to fit the panel's own width
    /// plus both gutters.
    private static let bandBlockWidth: CGFloat = 200
    private static let blockHeight: CGFloat = 68
    private static let blockGap: CGFloat = 8
    /// The clear space between a row of blocks and the panel itself.
    private static let bandGap: CGFloat = 12
    /// How far into its own half a slot has to sit before its block goes to that side.
    private static let leftShare: CGFloat = 0.55

    /// What reads above the panel, left to right. The head joins the jewellery there: its own box is
    /// at the top of the panel, and the row has the width for it.
    private static let above: [EquipmentSlot] = [ .ring1, .head, .neck, .ring2 ]
    private static let below: [EquipmentSlot] = [ .waist, .medal ]

    private static var band: CGFloat { blockHeight + bandGap }

    private var canvas: CGSize {
        CGSize(width: doll.canvas.width + Self.gutter * 2, height: doll.canvas.height + Self.band * 2)
    }

    var body: some View {
        // Sized by its own aspect ratio, then scaled from whatever width that wins. It is deliberately
        // not `ScaledCanvas`: that measures itself into a piece of state, and a canvas whose scale sets
        // its own height feeds its own layout — AppKit throws once the window has taken more constraint
        // passes than it has views. Reading the size inside an overlay writes no state, so it settles.
        Color.clear
            .aspectRatio(canvas.width / canvas.height, contentMode: .fit)
            .frame(maxWidth: canvas.width)
            .overlay {
                GeometryReader { proxy in
                    board.scaleEffect(proxy.size.width / canvas.width, anchor: .topLeading)
                }
            }
    }

    private var board: some View {
        ZStack(alignment: .topLeading) {
            panel
                .offset(x: Self.gutter, y: Self.band)

            ForEach(placements) { placement in
                SocketBlock(
                    title: placement.title,
                    choice: placement.choice,
                    reading: placement.reading,
                    openItem: openItem
                )
                .frame(
                    width: placement.width,
                    height: Self.blockHeight,
                    alignment: placement.reading.frame
                )
                .offset(x: placement.origin.x, y: placement.origin.y)
            }
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
    }

    private var panel: some View {
        ZStack(alignment: .topLeading) {
            background
            PortraitView(
                backdrop: doll.portraitBackground,
                size: doll.portrait.size,
                character: character,
                weaponSet: weaponSet,
                renderer: renderer,
                database: database
            )
            .offset(x: doll.portrait.minX, y: doll.portrait.minY)

            ForEach(doll.slots) { slot in
                PlanDollBox(slot: slot, item: item(in: slot), choice: choice(for: slot), openItem: openItem)
                    .position(x: slot.frame.midX, y: slot.frame.midY)
            }
        }
        .frame(width: doll.canvas.width, height: doll.canvas.height, alignment: .topLeading)
    }

    private var background: some View {
        ZStack(alignment: .topLeading) {
            GameArtwork(path: doll.background, size: doll.panel)
            // The artwork draws the panel's frame down its left edge only; mirroring that strip closes it.
            GameArtwork(path: doll.background, size: CGSize(width: doll.frame, height: doll.panel.height))
                .scaleEffect(x: -1, y: 1)
                .offset(x: doll.panel.width)
        }
    }

    private var placements: [Placement] {
        row(of: Self.above, atY: 0, gap: Self.blockGap * 2)
            + row(of: Self.below, atY: Self.band + doll.canvas.height + Self.bandGap, gap: Self.blockGap * 10)
            + column(onLeft: true)
            + column(onLeft: false)
    }

    /// A band of blocks across the top or the bottom, centred over the panel. The gap is the row's own:
    /// the top row is four blocks and has none to spare, the bottom row is two and would otherwise read
    /// as one wide block.
    private func row(of slots: [EquipmentSlot], atY y: CGFloat, gap: CGFloat) -> [Placement] {
        let found = slots.compactMap { slot in
            block(for: .equipment(slot)).map { (title: $0.title, choice: $0.choice) }
        }
        guard !found.isEmpty else { return [] }

        let span = CGFloat(found.count) * Self.bandBlockWidth + CGFloat(found.count - 1) * gap
        let start = (canvas.width - span) / 2

        return found.enumerated().map { index, entry in
            Placement(
                choice: entry.choice,
                title: entry.title,
                reading: Self.reading(at: index, of: found.count),
                width: Self.bandBlockWidth,
                origin: CGPoint(x: start + CGFloat(index) * (Self.bandBlockWidth + gap), y: y)
            )
        }
    }

    /// Which way a block in a band reads. Those left of the band's middle end against the panel, the
    /// one on the middle is centred under it, and the rest start from it — so a row leans inwards
    /// rather than reading as three separate columns.
    private static func reading(at index: Int, of count: Int) -> BlockAlignment {
        let middle = Double(count - 1) / 2
        if Double(index) < middle { return .trailing }
        if Double(index) > middle { return .leading }

        return .centre
    }

    /// A gutter's blocks, each at its slot's own height, then pushed down far enough not to sit on the
    /// one above it, and the whole column lifted if that ran it off the bottom.
    private func column(onLeft isLeft: Bool) -> [Placement] {
        let x = isLeft ? 0 : Self.gutter + doll.canvas.width + 14
        let wanted = doll.slots
            .filter { !isBanded($0) }
            .compactMap { slot -> Placement? in
                guard
                    let choice = choice(for: slot),
                    (slot.frame.midX < doll.panel.width * Self.leftShare) == isLeft
                else { return nil }

                return Placement(
                    choice: choice,
                    title: slot.title,
                    reading: isLeft ? .trailing : .leading,
                    width: Self.blockWidth,
                    origin: CGPoint(x: x, y: Self.band + slot.frame.midY - Self.blockHeight / 2)
                )
            }

        var placed = [Placement]()
        var lowest = -CGFloat.greatestFiniteMagnitude
        for var placement in wanted.sorted(by: { $0.origin.y < $1.origin.y }) {
            placement.origin.y = max(placement.origin.y, lowest)
            lowest = placement.origin.y + Self.blockHeight + Self.blockGap
            placed.append(placement)
        }

        let overflow = (placed.last.map { $0.origin.y + Self.blockHeight } ?? 0) - canvas.height
        guard overflow > 0 else { return placed }

        let lift = min(overflow, placed.first?.origin.y ?? 0)
        return placed.map {
            Placement(
                choice: $0.choice,
                title: $0.title,
                reading: $0.reading,
                width: $0.width,
                origin: CGPoint(x: $0.origin.x, y: $0.origin.y - lift)
            )
        }
    }

    private func isBanded(_ slot: DollSlot) -> Bool {
        guard case let .equipment(kind) = slot.kind else { return false }

        return Self.above.contains(kind) || Self.below.contains(kind)
    }

    private func block(for place: LoadoutSocket.Place) -> (title: String, choice: LoadoutChoice)? {
        guard
            let slot = doll.slots.first(where: { self.place(of: $0) == place }),
            let choice = choice(for: slot)
        else { return nil }

        return (slot.title, choice)
    }

    private func item(in slot: DollSlot) -> ResolvedItem? {
        switch slot.kind {
            case let .equipment(kind): character.equipment.first { $0.slot == kind }?.item
            case .mainHand: weaponSet?.items.first ?? nil
            case .offHand: weaponSet?.items.last ?? nil
        }
    }

    private func choice(for slot: DollSlot) -> LoadoutChoice? {
        plan.choices.first { $0.socket.place == place(of: slot) }
    }

    private func place(of slot: DollSlot) -> LoadoutSocket.Place {
        switch slot.kind {
            case let .equipment(kind): .equipment(kind)
            case .mainHand: .weapon(0)
            case .offHand: .weapon(1)
        }
    }
}

/// One socket written out: where it is worn, what component goes in it, and what augment.
///
/// The sizes are in the panel's coordinates, which the canvas scales as one, so they are points rather
/// than text styles.
private struct SocketBlock: View {
    let title: String
    let choice: LoadoutChoice
    let reading: BlockAlignment
    var openItem: ((String) -> Void)?

    /// What a row sits on. The component and the augment carry their own, so a block where only one
    /// of the two changes says which one.
    private static let keepBackground = Color.black.opacity(0.28)
    private static let changeBackground = Color.white.opacity(0.12)

    var body: some View {
        VStack(alignment: reading.horizontal, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            VStack(alignment: reading.horizontal, spacing: 3) {
                row(choice.component, worn: choice.socket.wornComponent)
                row(choice.augment, worn: choice.socket.wornAugment)
            }
        }
        .multilineTextAlignment(reading.text)
    }

    @ViewBuilder
    private func row(_ fitting: LoadoutFitting?, worn: String) -> some View {
        let isChanged = (fitting?.recordPath ?? "") != worn

        Group {
            if let fitting {
                Button(action: { openItem?(fitting.recordPath) }) {
                    HStack(alignment: .top, spacing: 4) {
                        // The artwork sits on the side the panel is on, so a column of blocks reads as one
                        // edge rather than as a ragged one.
                        if reading == .trailing {
                            words(fitting, isChanged: isChanged)
                            GameIcon(path: fitting.iconPath, size: 15, fallbackSymbol: "circle.hexagongrid")
                        } else {
                            GameIcon(path: fitting.iconPath, size: 15, fallbackSymbol: "circle.hexagongrid")
                            words(fitting, isChanged: isChanged)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help("Open \(fitting.name) in a window of its own")
                .accessibilityLabel("\(fitting.kind.rawValue): \(fitting.name)")
                .accessibilityHint("Opens it in a window of its own")
            } else {
                Text("empty")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(isChanged ? Self.changeBackground : Self.keepBackground, in: .rect(cornerRadius: 4))
        .overlay {
            if isChanged {
                RoundedRectangle(cornerRadius: 4).stroke(Theme.accent.opacity(0.5), lineWidth: 0.75)
            }
        }
    }

    private func words(_ fitting: LoadoutFitting, isChanged: Bool) -> some View {
        VStack(alignment: reading.horizontal, spacing: 0) {
            Text(fitting.name)
                .font(.system(size: 9.5))
                .foregroundStyle(isChanged ? Color.primary : .secondary)
                .lineLimit(1)
            if let source = source(of: fitting) {
                Text(source)
                    .font(.system(size: 7.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    /// Where to get it. Only an augment names a faction: a component is found rather than bought.
    private func source(of fitting: LoadoutFitting) -> String? {
        guard !fitting.faction.isEmpty else { return nil }

        return fitting.standing.isEmpty ? fitting.faction : "\(fitting.faction) · \(fitting.standing)"
    }
}

/// One box of the doll: the piece worn there, with the component and augment the plan puts in it.
private struct PlanDollBox: View {
    let slot: DollSlot
    let item: ResolvedItem?
    let choice: LoadoutChoice?
    var openItem: ((String) -> Void)?

    /// Which edge of the box the fittings sit against.
    ///
    /// Jewellery reads along the top and the bottom row along its own bottom, so a badge never covers
    /// the part of an icon that says what the piece is. They stay inside the box: the amulet is against
    /// the panel's top edge with nothing above it, and a ring sits seven points under the amulet, so
    /// there is nowhere outside either of them to put anything.
    private enum Placement {
        case bottomLeading
        case top
        case bottom
    }

    private var isChanged: Bool { choice?.isChanged ?? false }

    private var placement: Placement {
        switch slot.kind {
            case .equipment(.neck), .equipment(.ring1), .equipment(.ring2): .top
            case .equipment(.waist), .equipment(.medal), .equipment(.relic): .bottom
            default: .bottomLeading
        }
    }

    /// Both badges and the gap between them have to sit inside the width of the box they belong to,
    /// which a ring's is nowhere near wide enough for at the size an armour box uses.
    private var badgeSize: CGFloat {
        min(Self.fullBadge, (slot.frame.width - Self.badgeGap - 4) / 2)
    }

    private static let fullBadge: CGFloat = 18
    private static let badgeGap: CGFloat = 2

    var body: some View {
        piece
            .frame(width: slot.frame.width, height: slot.frame.height)
            .overlay(alignment: alignment) {
                if choice != nil { fittings }
            }
            .help(hint)
            .accessibilityLabel(hint)
    }

    private var alignment: Alignment {
        switch placement {
            case .bottomLeading: .bottomLeading
            case .top: .top
            case .bottom: .bottom
        }
    }

    private var piece: some View {
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
            }
        }
        // The piece is the backdrop here rather than the subject: what the plan puts into it has to be
        // the thing the eye lands on.
        .opacity(0.3)
        .frame(width: slot.frame.width, height: slot.frame.height)
        .overlay {
            // A changed socket has to be findable at a glance on a panel of fourteen boxes.
            if isChanged {
                RoundedRectangle(cornerRadius: 3).stroke(Theme.accent, lineWidth: 2)
            }
        }
    }

    private var fittings: some View {
        HStack(spacing: Self.badgeGap) {
            badge(choice?.component)
            badge(choice?.augment)
        }
        .padding(2)
    }

    @ViewBuilder
    private func badge(_ fitting: LoadoutFitting?) -> some View {
        if let fitting {
            Button(action: { openItem?(fitting.recordPath) }) {
                GameIcon(path: fitting.iconPath, size: badgeSize, fallbackSymbol: "circle.hexagongrid")
                    .background(Color.black.opacity(0.55), in: .rect(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.25)))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("\(fitting.kind.rawValue): \(fitting.name) — click to open it")
        }
    }

    private var hint: String {
        var lines = [ "\(slot.title) — \(item?.displayName ?? "empty")" ]
        if let component = choice?.component { lines.append("Component: \(component.name)") }
        if let augment = choice?.augment { lines.append("Augment: \(augment.name)") }
        if choice != nil, isChanged { lines.append("Changed from what is socketed now") }
        return lines.joined(separator: "\n")
    }
}
