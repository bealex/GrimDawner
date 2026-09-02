// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import GrimDawnerRender
import SwiftUI

/// What to socket into the gear the character already wears.
///
/// The left side is the ask — which difficulty the caps are held on, how far past them to push, the
/// Defensive Ability and absorption to reach, the Armor Rating past which more is wasted, and which
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
    let renderer: ModelRenderer?
    let database: GameDatabase?
    /// Opens a component or an augment in the window that reads an item in full.
    var openItem: ((String) -> Void)?

    @State
    private var target = LoadoutTarget(minimumDefensiveAbility: 2800)
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
                    hint: "Say what to hold and press Find loadouts. "
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
                    "Every resistance the game caps has to reach its maximum, read on the difficulty being "
                        + "planned for — the deeper the game goes the more of them it takes away. Nothing "
                        + "else is allowed to trade that away."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 16) {
                    difficultyPicker
                    overcap
                    leastAbility
                }
                HStack(spacing: 16) {
                    leastAbsorption
                    armorCeiling
                    skillPicker
                    Spacer()
                }
                passes

                HStack(spacing: 10) {
                    Button(state.isSearching ? "Searching…" : "Find loadouts") {
                        start(target, skill)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isSearching || isListing)

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

    /// What the plan is for. Ascendant is Ultimate: the game's ascendant adjustment is laid over the
    /// monsters, and takes nothing more off the character.
    private var difficultyPicker: some View {
        HStack(spacing: 6) {
            Text("Plan for")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Plan for", selection: $target.difficulty) {
                ForEach(Difficulty.allCases, id: \.self) { difficulty in
                    Text(PlanDetail.title(of: difficulty)).tag(difficulty)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
        .help(
            "The difficulty the plan holds the caps on. Ultimate takes 50% off fire, cold, lightning, "
                + "pierce and poison and 25% off the rest, so a plan that caps on \(character.difficulty.title) "
                + "is under the cap the moment Ultimate starts. Ascendant takes nothing further: its "
                + "adjustment is the monsters' alone."
        )
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

    private var armorCeiling: some View {
        HStack(spacing: 6) {
            Text("Armor up to")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(
                "0",
                value: Binding(get: { target.armorCeiling }, set: { target.armorCeiling = max($0, 0) }),
                format: .number
            )
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(width: 66)
        }
        .help(
            "Armor Rating past this is worth nothing to a plan, so the search spends the socket elsewhere. "
                + "It is not a limit: armour that rides along with something else worth having is kept. "
                + "Leave it at 0 for no ceiling. The character stands at "
                + "\(Int(character.sheet.armor.rounded())) now."
        )
    }

    private var leastAbsorption: some View {
        HStack(spacing: 6) {
            Text("Least absorption")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(
                "0",
                value: Binding(
                    get: { target.minimumArmorAbsorption },
                    set: { target.minimumArmorAbsorption = min(max($0, 0), 100) }
                ),
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
        .help(
            "The share of a physical blow the armour swallows that the defence and balanced plans aim "
                + "for. The attack plan is not held to it. The character stands at "
                + "\(Int(character.sheet.armorAbsorption.rounded()))% now."
        )
    }

    private var passes: some View {
        HStack(spacing: 16) {
            Toggle("Check every pair of sockets", isOn: $target.refinesPairs)
                .toggleStyle(.checkbox)
                .help(
                    "On, each run finishes by trying every pair of sockets against every pair of their "
                        + "fittings, so nothing is left that two sockets could improve together — which "
                        + "one at a time cannot see. It is exact over pairs and takes several times as "
                        + "long as the sweeps. Off, the search stops where no single change helps."
                )
            Toggle("…and every trio", isOn: $target.refinesTriples)
                .toggleStyle(.checkbox)
                .help(
                    "One level further: every trio of sockets against every trio of their fittings, "
                        + "nothing shortlisted out of it. Two hundred million combinations a run, so a "
                        + "search takes minutes rather than seconds. It is worth a fraction of a percent "
                        + "where it finds anything at all — the eight starting points already cover most "
                        + "of what it reaches."
                )
            Spacer()
        }
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
                        renderer: renderer,
                        database: database,
                        openItem: openItem
                    )
                }
            }
        }
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
                // Held at two lines either way, so three cards side by side line their figures up.
                Text(plan.goal.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

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
