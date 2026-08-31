// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import SwiftUI

/// What to socket into the gear the character already wears.
///
/// The left side is the ask — which resistances have to be at their cap, how far past it, and which
/// skill the attack plan is measured on — and each answer the search found. The right side is one plan
/// in full: what it is worth, and every socket it changes.
struct OptimizerTab: View {
    let character: ResolvedCharacter
    let skills: [ResolvedSkill]
    /// The search needs every component and augment in the game, which the directory lists once.
    let isListing: Bool
    let state: OptimizerState
    let start: (LoadoutTarget, ResolvedSkill?) -> Void
    let cancel: () -> Void
    let selectPlan: (LoadoutPlan.ID?) -> Void
    /// Opens a component or an augment in the window that reads an item in full.
    var openItem: ((String) -> Void)?

    @State
    private var target = LoadoutTarget(
        required: Set(ResistanceKind.allCases.filter { $0 != .physical }),
        minimumDefensiveAbility: 2800
    )
    @State
    private var skillPath: String?

    private var skill: ResolvedSkill? {
        skills.first { $0.recordPath == skillPath }
    }

    private var selected: LoadoutPlan? {
        state.plans.first { $0.id == state.selectedPlan } ?? state.plans.first
    }

    var body: some View {
        TabLayout {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ask
                    if state.isSearching {
                        searching
                    }
                    if !state.plans.isEmpty {
                        answers
                        sockets
                    } else if state.hasSearched, !state.isSearching {
                        Text("Nothing fits: none of the worn pieces takes a component or an augment.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        } detail: {
            if let selected {
                PlanDetail(plan: selected, character: character)
            } else {
                DetailPlaceholder(
                    title: "No plan yet",
                    hint: "Pick what has to be capped and press Find loadouts. "
                        + "The search reads every component and augment the game says fits each piece."
                )
            }
        }
    }

    // MARK: - The ask

    private var ask: some View {
        SectionCard(title: "What to hold") {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "Every resistance ticked here has to reach its maximum. Nothing else is allowed to trade that away."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                resistanceChips

                HStack(spacing: 16) {
                    overcap
                    leastAbility
                    skillPicker
                }

                HStack(spacing: 10) {
                    Button(state.isSearching ? "Searching…" : "Find loadouts") {
                        start(target, skill)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isSearching || target.required.isEmpty || isListing)

                    if state.isSearching {
                        Button("Stop", action: cancel)
                    }
                    if isListing {
                        Text("Reading every item in the game…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }

    private var resistanceChips: some View {
        FlowRow(spacing: 6) {
            ForEach(ResistanceKind.allCases, id: \.self) { kind in
                ResistanceChip(
                    kind: kind,
                    isOn: target.required.contains(kind),
                    held: character.sheet.resistances[kind] ?? 0,
                    cap: character.sheet.maxResistances[kind] ?? 80,
                    toggle: {
                        if target.required.contains(kind) {
                            target.required.remove(kind)
                        } else {
                            target.required.insert(kind)
                        }
                    }
                )
            }
        }
    }

    private var overcap: some View {
        HStack(spacing: 6) {
            Text("Overcap")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(
                "0",
                value: Binding(get: { target.overcap }, set: { target.overcap = min(max($0, 0), 200) }),
                format: .number
            )
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(width: 56)
            Text("%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help("Points past the cap to aim for, which is what survives an enemy that strips resistance")
    }

    private var leastAbility: some View {
        HStack(spacing: 6) {
            Text("Least DA")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(
                "0",
                value: Binding(
                    get: { target.minimumDefensiveAbility },
                    set: { target.minimumDefensiveAbility = max($0, 0) }
                ),
                format: .number
            )
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(width: 66)
        }
        .help("The Defensive Ability the defence and balanced plans aim for. The attack plan is not held to it.")
    }

    private var skillPicker: some View {
        Picker("Skill", selection: $skillPath) {
            Text("Offensive Ability alone").tag(String?.none)
            ForEach(skills, id: \.recordPath) { skill in
                Text(skill.name).tag(String?.some(skill.recordPath))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: 260)
        .help(
            "What the attack plan is measured on. A skill's damage here is its own, before the weapon it is swung with."
        )
    }

    // MARK: - Progress

    private var searching: some View {
        SectionCard(title: "Searching") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(LoadoutGoal.allCases) { goal in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Label(goal.rawValue, systemImage: goal.symbolName)
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text(state.stage[goal] ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: state.progress[goal] ?? 0)
                    }
                }
            }
        }
    }

    // MARK: - The answers

    private var answers: some View {
        SectionCard(title: "Plans", subtitle: "\(state.plans.count) found") {
            HStack(alignment: .top, spacing: 10) {
                ForEach(state.plans) { plan in
                    PlanRow(
                        plan: plan,
                        character: character,
                        isSelected: plan.id == (selected?.id),
                        select: { selectPlan(plan.id) }
                    )
                }
            }
        }
    }

    /// What the chosen plan puts where, on the character panel the pieces themselves are worn on.
    @ViewBuilder
    private var sockets: some View {
        if let selected {
            SectionCard(
                title: "What to socket",
                subtitle: "\(selected.changedCount) of \(selected.choices.count) change"
            ) {
                if let doll = character.doll {
                    PlanDoll(
                        doll: doll,
                        character: character,
                        plan: selected,
                        weaponSet: character.weaponSets.first { $0.isActive } ?? character.weaponSets.first,
                        openItem: openItem
                    )
                }
            }
        }
    }
}

/// One resistance of the ask: on or off, and where the character stands on it now.
private struct ResistanceChip: View {
    let kind: ResistanceKind
    let isOn: Bool
    let held: Double
    let cap: Double
    let toggle: () -> Void

    private var isAtCap: Bool { held >= cap }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 5) {
                Image(systemName: isAtCap ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(isAtCap ? Color.green : Color.orange)
                Text(kind.shortTitle)
                Text("\(Int(held))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isOn ? kind.color : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isOn ? kind.color.opacity(0.16) : .clear, in: .capsule)
            .overlay(Capsule().stroke(kind.color.opacity(isOn ? 0.6 : 0.25), lineWidth: 1))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(isOn ? "\(kind.title) must reach its cap of \(Int(cap))%" : "\(kind.title) is left to the search")
    }
}

/// One plan in the list: what it is for, and the two or three figures that say whether it is worth reading.
private struct PlanRow: View {
    let plan: LoadoutPlan
    let character: ResolvedCharacter
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Label(plan.goal.rawValue, systemImage: plan.goal.symbolName)
                        .font(.headline)
                    if !plan.isFeasible {
                        Text("under cap")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.orange)
                    }
                    Spacer()
                    Text("\(plan.changedCount) changed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(plan.goal.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    Delta(title: "OA", now: character.sheet.offensiveAbility, then: plan.sheet.offensiveAbility)
                    Delta(title: "DA", now: character.sheet.defensiveAbility, then: plan.sheet.defensiveAbility)
                    Delta(title: "Armor", now: character.sheet.armor, then: plan.sheet.armor)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.accent.opacity(0.16) : Color.clear, in: .rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Theme.accent.opacity(0.5) : Theme.subtleBorder)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// One figure with what the plan does to it.
private struct Delta: View {
    let title: String
    let now: Double
    let then: Double

    private var change: Double { then - now }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(then.formatted(.number.precision(.fractionLength(0))))
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                if abs(change) >= 0.5 {
                    Text((change > 0 ? "+" : "") + change.formatted(.number.precision(.fractionLength(0))))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(change > 0 ? Color.green : Color.red)
                }
            }
        }
    }
}

/// A row of chips that wraps rather than running off the edge.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = self.rows(subviews, within: width)
        let height = rows.reduce(0) { $0 + $1.height + spacing } - spacing
        return CGSize(width: width == .infinity ? rows.map(\.width).max() ?? 0 : width, height: max(height, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, within: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(_ subviews: Subviews, within width: CGFloat) -> [Row] {
        var rows = [ Row() ]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += rows[rows.count - 1].indices.count == 1 ? size.width : size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
