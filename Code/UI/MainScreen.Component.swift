// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import SwiftUI

extension MainScreen {
    struct Component: View {
        @Bindable
        var model: Model

        var body: some View {
            NavigationSplitView(sidebar: { sidebar }, detail: { detail })
                .environment(\.textures, model.textures)
                .environment(\.damageIcons, model.damageIcons)
                .environment(\.quickSearch, QuickSearch(model.search))
                .navigationTitle(model.character?.name ?? "GrimDawner")
                .navigationSubtitle(subtitle)
                .toolbar { toolbar }
                .background(panelShortcuts)
                .background(TypeToSearch(text: $model.search).frame(width: 0, height: 0))
                .background(UnifiedTitleBar().frame(width: 0, height: 0))
                .overlay(alignment: .top) {
                    if !model.search.isEmpty { SearchOverlay(text: $model.search) }
                }
                .animation(.easeOut(duration: 0.15), value: model.search.isEmpty)
                .frame(minWidth: 980, minHeight: 640)
        }

        /// ⌘1 … ⌘6 select a view and ⌘R re-reads the save folder, as a tabbed Mac app is expected to.
        ///
        /// These carry only the key equivalents. They are invisible, and an invisible button still takes
        /// clicks, so pointer input and the accessibility tree both skip them — the picker is the control.
        private var panelShortcuts: some View {
            Group {
                ForEach(Model.Panel.allCases) { panel in
                    Button(panel.rawValue) { model.panel = panel }
                        .keyboardShortcut(panel.shortcut, modifiers: .command)
                }
                Button("Reload", action: model.reloadCharacters)
                    .keyboardShortcut("r", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }

        private var subtitle: String {
            guard let character = model.character else { return "" }

            return "Level \(character.level) \(character.className)"
        }

        // MARK: - Sidebar

        @ViewBuilder
        private var sidebar: some View {
            List(selection: $model.selection) {
                Section("Characters") {
                    if model.characters.isEmpty {
                        Text("No characters found")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                    ForEach(model.characters) { file in
                        Label(file.displayName, systemImage: "person.fill")
                            .tag(file.id)
                            .accessibilityLabel("Character \(file.displayName)")
                    }
                }

                Section("Folders") {
                    folderRow(title: "Save folder", value: model.saveFolderName, action: model.chooseSaveFolder)
                    folderRow(title: "Game folder", value: model.gameFolderName, action: model.chooseGameFolder)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 220)
            .onChange(of: model.selection) { model.reloadSelected() }
        }

        private func folderRow(title: String, value: String?, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout)
                    Text(value ?? "Not chosen")
                        .font(.caption)
                        .foregroundStyle(value == nil ? Color.orange : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title): \(value ?? "not chosen"). Click to choose.")
            .accessibilityHint("Opens a folder picker")
        }

        // MARK: - Detail

        @ViewBuilder
        private var detail: some View {
            switch (model.databaseState, model.saveState) {
                case let (.failed(reason), _), let (_, .failed(reason)):
                    notice(title: "Could not load", detail: reason, symbol: "exclamationmark.triangle")
                case (.loading, _), (_, .loading):
                    ProgressView("Reading save data…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                default:
                    if let character = model.character {
                        content(for: character)
                    } else {
                        setupPrompt
                    }
            }
        }

        @ViewBuilder
        private func content(for character: ResolvedCharacter) -> some View {
            let search = QuickSearch(model.search)

            switch model.panel {
                case .inventory:
                    InventoryTab(
                        character: character,
                        search: search,
                        selection: $model.selectedItem,
                        renderer: model.modelRenderer,
                        database: model.records,
                        revealSkill: model.reveal(skillAt:)
                    )
                case .items:
                    ItemsTab(
                        items: model.catalogue,
                        isListing: model.isListingItems,
                        search: search,
                        selectedPath: model.selectedCataloguePath,
                        selected: model.selectedCatalogueItem,
                        select: model.selectCatalogued
                    )
                    .task { model.openCatalogue() }
                case .skills:
                    SkillsTab(
                        character: character,
                        search: search,
                        selected: $model.selectedSkill,
                        revealItem: model.reveal
                    )
                case .devotions:
                    DevotionsTab(
                        character: character,
                        search: search,
                        selectedStar: $model.selectedStar,
                        selectedConstellation: $model.selectedConstellation,
                        database: model.records
                    )
                case .affixes:
                    AffixesTab(
                        affixes: model.affixes,
                        isListing: model.isListingItems,
                        search: search,
                        selectedKey: model.selectedAffixKey,
                        selectedLevel: model.selectedAffixLevel,
                        selected: model.selectedAffixes,
                        select: model.selectAffixes
                    )
                    .task { model.openCatalogue() }
                case .monsters:
                    MonstersTab(
                        monsters: model.monsters,
                        isListing: model.isListingMonsters,
                        search: search,
                        selectedPath: model.selectedMonsterPath,
                        selected: model.selectedMonster,
                        level: model.monsterLevel,
                        difficulty: model.monsterDifficulty,
                        renderer: model.modelRenderer,
                        database: model.records,
                        select: model.selectMonster(path:level:difficulty:)
                    )
                    .task { model.openMonsters() }
                case .parameters:
                    ParametersTab(
                        character: character,
                        search: search,
                        selection: $model.selectedParameter,
                        reveal: model.reveal
                    )
            }
        }

        private var panelPicker: some View {
            // Plain text segments: a `Label` collapses to icon-only in the title bar, which reads as
            // three unexplained glyphs.
            Picker("View", selection: $model.panel) {
                ForEach(Model.Panel.allCases) { panel in
                    Text(panel.rawValue).tag(panel)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(minWidth: 360)
            .accessibilityLabel("Character view")
        }

        @ViewBuilder
        private var setupPrompt: some View {
            let needsGame = model.gameFolderName == nil
            let needsSave = model.saveFolderName == nil

            notice(
                title: needsGame || needsSave ? "Choose your folders" : "Select a character",
                detail: needsGame
                    ? "GrimDawner reads item and skill names straight from the game's database. "
                        + "Pick your Grim Dawn installation folder, then your save folder."
                    : needsSave
                        ? "Pick the save folder that holds your characters."
                        : "Pick a character in the sidebar.",
                symbol: "folder.badge.questionmark"
            )
        }

        private func notice(title: String, detail: String, symbol: String) -> some View {
            ContentUnavailableView(label: { Label(title, systemImage: symbol) }, description: { Text(detail) })
        }

        // MARK: - Toolbar

        @ToolbarContentBuilder
        private var toolbar: some ToolbarContent {
            if model.isReady {
                ToolbarItem(placement: .principal) { panelPicker }
            }
        }
    }
}
