// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import GrimDawnerRender
import SwiftUI

/// The awakened item an epic piece becomes, and where to find it.
struct ItemUpgrade: Sendable {
    let name: String
    let path: String
}

/// Everything one item carries: its parts, the stats each grants, and the skills it confers.
struct ItemDetailView: View {
    let item: ResolvedItem
    /// The directory lists items no character owns, so there is no roll to show — only the band.
    var showsRolls = true
    /// False where something else already names the item — a window whose own title bar does.
    var showsHeader = true
    /// The character wearing this, as far as its skill lines need. Absent in the directory, where
    /// there is no character for a skill to belong to or a point to have been spent on.
    var wearer: SkillContext?
    /// Opens one of the character's own skills on its mastery panel, when there is a panel to open.
    var revealSkill: ((String) -> Void)?
    /// What the Ashes of Awakening turn this item into, for the directory that can go and show it.
    var upgrade: ItemUpgrade?
    var selectItem: ((String) -> Void)?
    /// Every level the game writes this item at, for the directory that lets you read any of them.
    /// Who sells this and at what standing, for the augments a faction stocks.
    var vendor: (faction: String, standing: String)?
    var tiers: [CataloguedItem] = []
    var tierPath: String?
    var selectTier: ((String) -> Void)?
    /// Draws the model of a world object, which is the only picture the game has of one.
    var renderer: ModelRenderer?

    @Environment(\.quickSearch)
    private var search

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsHeader {
                HStack(alignment: .top, spacing: 12) {
                    GameIcon(path: item.iconPath, size: 64, magnifies: false, fallbackSymbol: "shippingbox")
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            ItemQualityMark(path: item.qualityMarkPath, size: 20)
                            Text(item.displayName)
                                .font(.title3.bold())
                                .foregroundStyle(item.rarity.color)
                                .quickSearchText(search.emphasis(matching: item.displayName))
                        }
                        HStack(spacing: 8) {
                            Text(item.rarity.title)
                            if item.itemLevel > 0 { Text("Item Level \(item.itemLevel)") }
                            if item.levelRequirement > 0 { Text("Requires Level \(item.levelRequirement)") }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        // What the game says the item is, under what it is called.
                        if !item.flavourText.isEmpty {
                            Text(item.flavourText)
                                .font(.callout.italic())
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            }

            if showsModel {
                SectionCard(title: "Model") {
                    // The pane's own height: an `SCNView` asks a scroll view for none and would come
                    // out zero pixels tall.
                    ItemModelView(meshPath: item.meshPath, texturePath: item.texturePath, renderer: renderer)
                        .frame(height: 260)
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: 6))
                }
            }

            if !item.contents.isEmpty {
                SectionCard(title: "What it holds", subtitle: contentsSubtitle) {
                    VStack(spacing: 0) {
                        ForEach(item.contents) { entry in
                            contentRow(entry)
                        }
                    }
                }
            }

            if !item.requirements.isEmpty {
                SectionCard(title: "Requirements") {
                    VStack(spacing: 6) {
                        ForEach(item.requirements.sorted(by: { $0.key < $1.key }), id: \.key) { name, value in
                            StatRow(title: name, value: value.formatted(.number.precision(.fractionLength(0))))
                        }
                    }
                }
            }

            if let vendor, !vendor.faction.isEmpty {
                SectionCard(title: "Sold by") {
                    StatRow(title: vendor.faction, value: vendor.standing, valueColor: Theme.accent)
                }
            }

            if tiers.count > 1, let selectTier {
                Picker("Level", selection: Binding(get: { tierPath ?? tiers[0].path }, set: selectTier)) {
                    ForEach(tiers) { tier in
                        Text(tier.levelRequirement > 0 ? "Level \(tier.levelRequirement)" : "Any level")
                            .tag(tier.path)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .help("Which level tier of this item to read")
            }

            if let upgrade {
                SectionCard(title: "Ashes of Awakening") {
                    Button {
                        selectItem?(upgrade.path)
                    } label: {
                        StatRow(
                            title: "Awakens into \(upgrade.name)",
                            value: "",
                            icon: "arrow.up.forward.square",
                            isNamed: true
                        )
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectItem == nil)
                    .help("Show \(upgrade.name)")
                }
            }

            SectionCard(title: "Total Bonuses") {
                StatBlockView(
                    block: item.stats,
                    lowest: item.statsLowest,
                    highest: item.statsHighest,
                    showsRolls: showsRolls
                )
            }

            // A relic, a component or a proc weapon carries its skill on the base record itself.
            if let base = item.parts.first(where: { $0.kind == .base }), !base.grantedSkills.isEmpty {
                SectionCard(title: "Granted Skills") {
                    grantedSkills(base.grantedSkills)
                }
            }

            ForEach(item.parts.filter { $0.kind != .base }) { part in
                SectionCard(title: part.title, subtitle: part.subtitle, iconPath: part.iconPath) {
                    VStack(alignment: .leading, spacing: 8) {
                        // An ascendant affix has no bonuses of its own, only the skill it changes.
                        if !part.stats.hasNothingToShow || part.grantedSkills.isEmpty {
                            StatBlockView(block: part.stats)
                        }
                        // A skill is a block rather than another line, so it stands apart from the
                        // component's own numbers.
                        if !part.grantedSkills.isEmpty {
                            grantedSkills(part.grantedSkills)
                                .padding(.top, 6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// A world object has no inventory icon — it is never carried — so its model stands in for one.
    /// Everything that does have artwork keeps showing that instead.
    private var showsModel: Bool { item.iconPath.isEmpty && !item.meshPath.isEmpty && renderer != nil }

    /// How much comes out, and whether the list is all of it. The engine reads the likeliest sixty,
    /// which for a deep chest is a fraction of what it can roll.
    private var contentsSubtitle: String {
        let drops = item.drops == 1 ? "1 drop" : "\(item.drops) drops"
        return item.contents.count >= 60
            ? "\(drops) — the 60 likeliest, as a share of each" : "\(drops), as a share of each"
    }

    private func contentRow(_ entry: MonsterLootEntry.Item) -> some View {
        Button {
            selectItem?(entry.recordPath)
        } label: {
            HStack(spacing: 8) {
                GameIcon(path: entry.iconPath, size: 20, fallbackSymbol: "shippingbox")
                Text(entry.name)
                    .foregroundStyle(entry.rarity.color)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(entry.share.formatted(.number.precision(.fractionLength(entry.share < 1 ? 2 : 1))) + "%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(selectItem == nil || entry.recordPath.isEmpty)
        .help("Show \(entry.name)")
    }

    @ViewBuilder
    private func grantedSkills(_ skills: [GrantedSkill]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(GrantedSkillGroup.grouping(skills, for: wearer)) { group in
                GrantedSkillView(group: group, wearer: wearer, reveal: revealSkill)
            }
        }
    }
}

/// Everything one item does to one skill, gathered under that skill.
///
/// An item can name the same skill several times over — ranks from the base record, an enhancement from
/// an ascendant affix, another from a component — and listing those apart reads as several skills when
/// it is one. What the character can actually use comes first: a rank or an enhancement aimed at a skill
/// of another class, or at one nobody has spent a point on, gives nothing at all.
struct GrantedSkillGroup: Identifiable {
    let entries: [GrantedSkill]
    /// Whether the character takes anything from it.
    let isReachable: Bool

    var id: String { entries[0].recordPath.isEmpty ? entries[0].id.uuidString : entries[0].recordPath }

    /// The line that names the skill: the one conferring it where the item does, the first otherwise.
    var lead: GrantedSkill { entries.first { $0.kind == .granted } ?? entries[0] }
    /// Ranks the item adds, however many lines add them.
    var addedRanks: Int {
        entries.filter { $0.kind == .added }.reduce(0) { $0 + $1.level }
    }

    var enhancements: [SkillChanges] {
        entries.compactMap { $0.kind == .enhanced ? $0.modifications : nil }.filter { !$0.isEmpty }
    }

    static func grouping(_ skills: [GrantedSkill], for wearer: SkillContext?) -> [GrantedSkillGroup] {
        var order = [String]()
        var byPath = [String: [GrantedSkill]]()
        for skill in skills {
            let key = skill.recordPath.isEmpty ? skill.id.uuidString : skill.recordPath.lowercased()
            if byPath[key] == nil { order.append(key) }
            byPath[key, default: []].append(skill)
        }

        let groups = order.compactMap { key -> GrantedSkillGroup? in
            guard let entries = byPath[key], !entries.isEmpty else { return nil }

            return GrantedSkillGroup(entries: entries, isReachable: reachable(entries, for: wearer))
        }
        // Stable within each half, so the item's own order survives inside what the character can use.
        return groups.filter(\.isReachable) + groups.filter { !$0.isReachable }
    }

    /// A skill the item confers is the item's own and always works. Ranks and enhancements only count
    /// where the character has spent a point on the skill they name.
    private static func reachable(_ entries: [GrantedSkill], for wearer: SkillContext?) -> Bool {
        guard let wearer else { return true }
        guard !entries.contains(where: { $0.kind == .granted }) else { return true }

        return wearer.learned.contains(entries[0].recordPath.lowercased())
    }
}

/// What an item's skill actually does, rather than the name of the record behind it.
///
/// One block per skill: its name, what sets it off, what it does, the ranks the item adds, whatever the
/// item changes about it, and its own numbers. A skill the character takes nothing from — one of another
/// class, or one nobody has spent a point on — reads faded rather than being left out, since it is still
/// what the item carries.
struct GrantedSkillView: View {
    let group: GrantedSkillGroup
    /// The character reading it, when there is one. Absent in the catalogues, where no skill is
    /// anybody's own and nothing has a point spent on it.
    var wearer: SkillContext?
    var reveal: ((String) -> Void)?

    private var granted: GrantedSkill { group.lead }

    /// Whether the skill is one of the character's own, which the skill panels already show in full.
    private var isOwn: Bool { wearer?.own.contains(granted.recordPath.lowercased()) ?? false }

    @Environment(\.quickSearch)
    private var search
    /// Nothing until it is clicked, and then whatever it was set to. A skill the character takes nothing
    /// from opens closed, since it is there to be seen rather than read.
    @State
    private var isOpened: Bool?

    /// Whether the skill belongs to the character at all. An ability the item confers is always theirs;
    /// a class skill is theirs only where they took that mastery.
    private var isAvailable: Bool {
        guard wearer != nil else { return true }

        return granted.kind == .granted || isOwn
    }

    /// A skill of a mastery the character never took opens closed: it is there to say what the item
    /// carries, not to be read.
    private var isExpanded: Bool { isOpened ?? isAvailable }

    /// A line about one of the character's own skills opens that skill's panel; anything else — a skill
    /// of another class, or an ability the item itself grants — has no panel to open.
    private var opensPanel: Bool { isOwn && granted.kind != .granted && reveal != nil }

    /// A skill of a mastery is described on its own panel, and the sidebar links to it. Repeating the
    /// description here says nothing the panel does not, so only an ability the item itself brings
    /// into being explains itself.
    private var description: String? {
        guard granted.mastery == nil, let text = granted.skill?.description, !text.isEmpty else { return nil }

        return text
    }

    /// Whether there is anything under the name worth opening for.
    private var hasDetail: Bool {
        condition != nil || description != nil || group.addedRanks > 0 || !group.enhancements.isEmpty
            || (granted.kind == .granted && granted.skill != nil)
    }

    /// The skill's name, with its own artwork and whose it is.
    private var header: some View {
        HStack(spacing: 6) {
            if let icon = granted.skill?.iconPath, !icon.isEmpty {
                GameIcon(path: icon, size: 20, fallbackSymbol: granted.symbolName)
            } else {
                Image(systemName: granted.symbolName)
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
            Text(granted.title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                // A skill line says what the item does; a search for something else must not fade it
                // out of the card.
                .quickSearchText(search.highlight(matching: granted.title))
            // A skill outside the character's masteries appears on no panel, so the line says whose it
            // is instead of pointing at one.
            if !isOwn, let mastery = granted.mastery {
                Text(mastery)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if opensPanel {
                Image(systemName: "arrow.up.forward.square")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            if hasDetail {
                Button(action: { isOpened = !isExpanded }) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 10)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(isExpanded ? "Hide what this does" : "Show what this does")
            }
        }
    }

    /// What has to happen for it to fire, and — where the character takes nothing from the line — why.
    /// A skill of a mastery they never took needs no explanation: the mastery's name is already beside
    /// it.
    ///
    /// The rank an item runs a granted ability at is left out. It is the item's to decide, the reader
    /// cannot move it, and every figure below is already worked out at it, so printing it says nothing
    /// the numbers have not.
    private var condition: String? {
        [
            granted.trigger,
            isAvailable && !group.isReachable ? "no points spent on it" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        .nilWhenEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Only a skill with a panel to open becomes a button: a disabled one is drawn greyed, and a
            // skill of another class is no less part of what the item grants for having nowhere to go.
            if opensPanel {
                Button {
                    reveal?(granted.recordPath)
                } label: {
                    header.contentShape(.rect)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help("Show \(granted.title) on its mastery panel")
            } else {
                header
            }

            if isExpanded {
                detail
            }
        }
        .opacity(group.isReachable ? 1 : 0.4)
        .accessibilityElement(children: .combine)
    }

    /// What the skill does, under its name.
    private var detail: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let condition {
                Text(condition)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // What the skill does reads the same wherever it is described — under an item, under a
            // component, under an augment.
            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if group.addedRanks > 0 {
                StatRow(title: granted.ranksTitle, value: "+\(group.addedRanks)", valueColor: Theme.valueColor(1))
            }
            ForEach(Array(group.enhancements.enumerated()), id: \.offset) { _, changes in
                SkillChangesView(changes: changes)
            }
            if let skill = granted.skill, granted.kind == .granted {
                ForEach(skill.parameters) { parameter in
                    StatRow(title: parameter.name, value: parameter.value)
                }
                if !skill.stats.hasNothingToShow {
                    StatBlockView(block: skill.stats)
                }
                SkillPetView(skill: skill)
            }
        }
        .padding(.leading, 26)
    }
}

/// What an item changes about a skill: its stats, and the parameters no stat covers.
struct SkillChangesView: View {
    let changes: SkillChanges

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !changes.stats.hasNothingToShow {
                StatBlockView(block: changes.stats)
            }
            ForEach(changes.parameters) { parameter in
                StatRow(title: parameter.name, value: parameter.value)
            }
        }
    }
}

/// Renders a stat block grouped the way the character sheet groups it.
struct StatBlockView: View {
    let block: StatBlock
    /// The ends of the band each figure rolled in, when it is an item's and rolls at all.
    var lowest: StatBlock?
    var highest: StatBlock?
    /// False shows a rolled figure as its band alone, for an item nobody owns a copy of.
    var showsRolls = true
    /// How far apart the groups sit. A stat block reads as one list of what a thing does, so the groups
    /// run together at the spacing the lines themselves use: a gap between damage and defence separates
    /// nothing a reader was looking for. What does earn a gap is a skill's own block, and that is spaced
    /// where it is built rather than here.
    var groupSpacing: CGFloat = 4

    @Environment(\.damageIcons)
    private var damageIcons

    var body: some View {
        let groups = block.catalogued()

        if block.hasNothingToShow {
            Text("No bonuses")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            // The group's name is left out: what a stat is about reads from its own line, and a column
            // of headings over one or two lines each is noise.
            VStack(alignment: .leading, spacing: groupSpacing) {
                ForEach(groups, id: \.group) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(StatBlock.merged(group.lines), id: \.title) { line in
                            let bands = bandText(of: line.parts)
                            let figures = Theme.figures(line.parts)
                            StatRow(
                                title: line.title,
                                value: showsRolls ? figures : (bands ?? figures),
                                valueColor: Theme.valueColor(line.parts.first?.value ?? 0),
                                accents: [
                                    Theme.damageAccent(
                                        forStatKey: line.parts.first?.definition.key ?? "",
                                        in: line.title
                                    )
                                ]
                                .compactMap { $0 },
                                iconPath: damageIcons[
                                    Theme.damageToken(forStatKey: line.parts.first?.definition.key ?? "") ?? ""
                                ],
                                range: showsRolls ? bands.map { "[\($0)]" } : nil
                            )
                        }
                    }
                }

                ForEach(block.conversions, id: \.self) { conversion in
                    StatRow(
                        title: "\(conversion.source) \(Theme.convertsTo) \(conversion.target)",
                        value: "\(Int(conversion.percent))%",
                        valueColor: Theme.valueColor(conversion.percent),
                        // Both sides of a conversion name a type, and each reads in its own colour.
                        accents: [
                            Theme.damageAccent(forStatKey: "offensive\(conversion.source)", in: conversion.source),
                            Theme.damageAccent(forStatKey: "offensive\(conversion.target)", in: conversion.target),
                        ]
                        .compactMap { $0 }
                    )
                }

                if block.allSkillBonus != 0 {
                    StatRow(title: "To all skills", value: "+\(block.allSkillBonus)", valueColor: .green)
                }
            }
        }
    }
}

extension StatBlockView {
    /// The band a rolled figure can land in, as `24–36`.
    /// The bands a whole line's figures roll in, paired the way the figures themselves are.
    ///
    /// A minimum and a maximum are the two ends of one number, so they read as one band. Where a record
    /// writes only the minimum the app fills the maximum in to match it, and printing both would say
    /// the same thing twice: 12 flat elemental damage is "13–18", never "13–18 & 13–18". Nothing at all
    /// where any figure on the line does not roll, since a line half in bands reads as neither.
    fileprivate func bandText(of parts: [(definition: StatDefinition, value: Double)]) -> String? {
        guard !parts.isEmpty else { return nil }

        let minimum = parts.first { $0.definition.key.hasSuffix("Min") }
        let maximum = parts.first { $0.definition.key.hasSuffix("Max") }
        var used = Set<String>()
        var pieces = [String]()

        if let minimum, let maximum, let low = band(of: minimum), let high = band(of: maximum) {
            used.insert(minimum.definition.key)
            used.insert(maximum.definition.key)
            // Two ends that roll apart are one span from the lowest a minimum can be to the highest a
            // maximum can reach; two ends that roll alike are one figure.
            pieces.append(low == high ? low : span(from: minimum, to: maximum) ?? low)
        }
        for part in parts where !used.contains(part.definition.key) {
            guard let band = band(of: part) else { return nil }

            pieces.append(band)
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: " & ")
    }

    /// The whole reach of a rolled damage range: the least its minimum can be, the most its maximum can.
    private func span(
        from minimum: (definition: StatDefinition, value: Double),
        to maximum: (definition: StatDefinition, value: Double)
    ) -> String? {
        guard
            let low = lowest?.value(minimum.definition.key),
            let high = highest?.value(maximum.definition.key)
        else { return nil }

        return Self.band(of: minimum.definition, from: low, to: high)
    }

    fileprivate func band(of line: (definition: StatDefinition, value: Double)) -> String? {
        guard
            let low = lowest?.value(line.definition.key),
            let high = highest?.value(line.definition.key),
            low.rounded() != high.rounded()
        else { return nil }

        return Self.band(of: line.definition, from: low, to: high)
    }

    /// A rolled figure's two ends. A reduction carries its sign on the first of them only — the game
    /// writes "−7/9% Skill Energy Cost" rather than repeating the minus.
    static func band(of definition: StatDefinition, from low: Double, to high: Double) -> String {
        let unit = definition.unit
        let first = unit.format(definition.shown(low), signed: false)
        let second = unit.format(abs(definition.shown(high)), signed: false)
        return "\(first)–\(second)"
    }
}

private extension String {
    /// A joined line that came out empty is nothing to show rather than a blank one.
    var nilWhenEmpty: String? { isEmpty ? nil : self }
}
