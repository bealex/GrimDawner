// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import AppKit
import Foundation
import GrimDawnerEngine
import GrimDawnerRender
import SwiftUI

enum MainScreen {}

extension MainScreen {
    @Observable @MainActor
    final class Model {
        enum LoadState {
            case idle
            case loading
            case ready
            case failed(String)
        }

        enum Panel: String, CaseIterable, Identifiable {
            // The character's own views come first and the game's own reference after them, since a
            // reader opens the app for a character. `allCases` is what the picker draws, so this is the
            // order the tabs appear in.
            case inventory = "Inventory"
            case skills = "Skills"
            case devotions = "Devotions"
            case parameters = "Stats"
            case optimizer = "Optimizer"
            case items = "Items"
            case affixes = "Affixes"
            case monsters = "Monsters"

            var id: String { rawValue }

            /// The number key that selects this view, in the order the picker shows them.
            var shortcut: KeyEquivalent {
                switch self {
                    case .inventory: "1"
                    case .skills: "2"
                    case .devotions: "3"
                    case .parameters: "4"
                    case .optimizer: "5"
                    case .items: "6"
                    case .affixes: "7"
                    case .monsters: "8"
                }
            }

            var symbolName: String {
                switch self {
                    case .inventory: "shield.lefthalf.filled"
                    case .skills: "sparkles.rectangle.stack"
                    case .devotions: "sparkles"
                    case .parameters: "person.text.rectangle"
                    case .optimizer: "slider.horizontal.3"
                    case .items: "list.bullet.rectangle"
                    case .affixes: "textformat.abc"
                    case .monsters: "pawprint"
                }
            }
        }

        private(set) var characters: [CharacterFile] = []
        /// Every named item in the game, listed the first time the directory is opened.
        private(set) var catalogue: [DirectoryEntry] = []
        private(set) var affixes: [AffixEntry] = []
        private(set) var catalogueState: LoadState = .idle
        /// Every monster in the game, listed the first time the Monsters tab is opened.
        private(set) var monsters: [MonsterEntry] = []
        private(set) var monsterState: LoadState = .idle
        private(set) var character: ResolvedCharacter?
        private(set) var saveState: LoadState = .idle
        private(set) var databaseState: LoadState = .idle

        var selection: CharacterFile.ID?
        var panel: Panel = .inventory
        /// What the quick-search field holds; every tab reads the same query.
        var search = ""

        var selectedItem: ResolvedItem?
        var selectedCatalogueItem: ResolvedItem?
        var selectedCataloguePath: String?
        /// Which affix name is open, which of its level tiers is being read, and the records that
        /// tier holds — one name at one level can cover several different rolls.
        var selectedAffixKey: String?
        var selectedAffixLevel: Int?
        private(set) var selectedAffixes: [ResolvedAffix] = []
        var selectedSkill: ResolvedSkill?
        var selectedStar: DevotionStar.ID?
        var selectedConstellation: ResolvedConstellation.ID?
        var selectedParameter: ParameterSelection?
        /// The item the details window is reading. Kept apart from the sidebars' own selections, since
        /// either of them can open it and neither should move it afterwards.
        private(set) var detailItem: ResolvedItem?
        /// Every monster that drops each item, which nothing in the game states and which takes a walk
        /// of the whole roster to work out.
        private(set) var drops: ItemDropIndex?
        private(set) var dropState: LoadState = .idle
        private(set) var dropProgress: Double = 0
        private(set) var selectedMonsterPath: String?
        private(set) var selectedMonster: ResolvedMonster?
        /// The level a monster is read at; monsters scale, so nothing about one is known without it.
        private(set) var monsterLevel = 100
        /// Monsters are worth several times more on Ultimate than on Normal, so the difficulty is read
        /// alongside the level.
        private(set) var monsterDifficulty: Difficulty = .ultimate

        /// What the loadout search is doing, which outlives any one view of it.
        let optimizer = OptimizerState()

        var saveFolderName: String? { saveAccess?.url.lastPathComponent }
        var gameFolderName: String? { gameAccess?.url.lastPathComponent }
        var isReady: Bool { character != nil }

        var isListingItems: Bool {
            if case .ready = catalogueState { return false }

            return true
        }

        var isListingMonsters: Bool {
            if case .ready = monsterState { return false }

            return true
        }
        var textures: TextureStore? { database?.textures }
        /// The game's own mark for each damage type, by the token a stat key names it with.
        var damageIcons: [String: String] {
            guard let database else { return [:] }

            var icons = [String: String]()
            for (kind, path) in LayoutResolver(database: database).resistanceIcons() {
                guard let token = Theme.damageToken(forStatKey: kind.resistanceKey) else { continue }

                icons[token] = path
            }
            return icons
        }

        private let saveFolder = FolderAccess(defaultsKey: "saveFolderBookmark")
        private let gameFolder = FolderAccess(defaultsKey: "gameFolderBookmark")

        private var saveAccess: FolderAccess.Access?
        private var gameAccess: FolderAccess.Access?
        private var database: GameDatabase?
        /// The records, for the views that read them directly — the model of a human is assembled from
        /// the gear its record equips.
        var records: GameDatabase? { database }
        /// Draws the game's own models, once the game folder is known.
        private(set) var modelRenderer: ModelRenderer?

        init() {
            restore()
        }

        // MARK: - The item directory

        /// Lists every item in the game, from the cache when the installed version has been listed before.
        func openCatalogue() {
            guard case .idle = catalogueState, let database else { return }

            catalogueState = .loading
            Task {
                let listing = await Task.detached(priority: .userInitiated) {
                    let listed =
                        ItemCatalogueStore.load(fingerprint: database.fingerprint)
                        ?? {
                            let built = ItemCatalogue.build(from: database)
                            ItemCatalogueStore.save(built)
                            return built
                        }()

                    return (listed.items.map(DirectoryEntry.init), listed.affixes.map(AffixEntry.init))
                }.value

                catalogue = listing.0
                affixes = listing.1
                catalogueState = .ready
            }
        }

        // MARK: - The monster listing

        /// Lists every monster in the game, from the cache when the installed version has been listed
        /// before.
        func openMonsters() {
            guard case .idle = monsterState, let database else { return }

            monsterState = .loading
            Task {
                let listed = await Task.detached(priority: .userInitiated) {
                    let catalogue =
                        MonsterCatalogueStore.load(fingerprint: database.fingerprint)
                        ?? {
                            let built = MonsterCatalogue.build(from: database)
                            MonsterCatalogueStore.save(built)
                            return built
                        }()

                    return catalogue.monsters.map(MonsterEntry.init)
                }.value

                monsters = listed
                monsterLevel = character?.level ?? monsterLevel
                monsterDifficulty = character?.difficulty ?? monsterDifficulty
                monsterState = .ready
            }
        }

        /// Opens one item in the details window, whichever list asked for it.
        func openItem(at path: String) {
            guard let database else { return }

            let resolver = ItemResolver(database: database, skills: SkillResolver(database: database))
            detailItem = resolver.resolve(Gdc.Item(baseName: path))
        }

        /// The same item with a prefix and a suffix on it, for reading what an affix would do to it.
        func item(at path: String, prefix: String?, suffix: String?) -> ResolvedItem? {
            guard let database else { return nil }

            var entry = Gdc.Item(baseName: path)
            entry.prefixName = prefix ?? ""
            entry.suffixName = suffix ?? ""
            // A seed of nothing rolls every figure at the bottom of its band, which is the honest thing
            // to show for an item nobody owns: what it is guaranteed to carry.
            return ItemResolver(database: database, skills: SkillResolver(database: database)).resolve(entry)
        }

        /// Which affixes an item can roll. The first call walks the loot tables; the database keeps
        /// the answer, so every item asked about after that is quick.
        func affixPool(forItemAt path: String) async -> ItemAffixPool {
            guard let database else { return ItemAffixPool(prefixes: [], suffixes: []) }

            return await Task.detached(priority: .userInitiated) {
                ItemAffixPool.of(itemAt: path, in: database)
            }.value
        }

        /// Works out which monsters drop what, from the cache where this version has been walked before.
        ///
        /// Nothing in the game runs this way round, so answering it means reading every monster's tables
        /// — ten seconds or so the first time, and nothing on every launch after it.
        func loadDrops() {
            guard case .idle = dropState, let database else { return }

            dropState = .loading
            Task {
                let index = await Task.detached(priority: .userInitiated) {
                    ItemDropIndexStore.load(fingerprint: database.fingerprint)
                        ?? {
                            let built = ItemDropIndex.build(from: database)
                            ItemDropIndexStore.save(built)
                            return built
                        }()
                }.value

                drops = index
                dropState = .ready
            }
        }

        /// Reads one monster at a level and a difficulty, which is what every figure it has depends on.
        func selectMonster(path: String, level: Int, difficulty: Difficulty? = nil) {
            guard let database else { return }

            let skills = SkillResolver(database: database)
            let resolver = MonsterResolver(
                database: database,
                skills: skills,
                items: ItemResolver(database: database, skills: skills)
            )
            selectedMonsterPath = path
            monsterLevel = level
            monsterDifficulty = difficulty ?? monsterDifficulty
            selectedMonster = resolver.monster(at: path, level: level, difficulty: monsterDifficulty)
        }

        /// The skills the attack plan can be measured on: the character's own, that it has spent a
        /// point on and that carry damage of their own.
        var optimizerSkills: [ResolvedSkill] {
            (character?.masteries.flatMap(\.skills) ?? [])
                .filter { $0.baseLevel > 0 && !EncounterEngine.damage(of: $0).isEmpty }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        /// Looks for the components and augments that hold the resistances and make the most of the rest.
        func optimize(target: LoadoutTarget, skill: ResolvedSkill?) {
            guard let character, let database else { return }

            optimizer.search(
                character: character,
                database: database,
                catalogue: catalogue.map(\.item),
                skill: skill,
                target: target
            )
        }

        /// Shows a piece of the character's gear where it is worn.
        func reveal(_ item: ResolvedItem) {
            selectedItem = item
            panel = .inventory
        }

        /// Shows a skill of the character's own where its mastery panel draws it.
        func reveal(skillAt path: String) {
            guard
                let skill = character?.masteries
                    .flatMap(\.skills)
                    .first(where: { $0.recordPath.caseInsensitiveCompare(path) == .orderedSame })
            else { return }

            selectedSkill = skill
            panel = .skills
        }

        /// Reads every record one affix holds at one of its level tiers, with the band each figure
        /// rolls in.
        func selectAffixes(key: String, level: Int, paths: [String]) {
            guard let database else { return }

            let resolver = ItemResolver(database: database, skills: SkillResolver(database: database))
            selectedAffixKey = key
            selectedAffixLevel = level
            selectedAffixes = paths.compactMap(resolver.affix(at:))
        }

        /// Reads one catalogued item in full, as it comes out of the box with no affixes on it.
        func selectCatalogued(_ path: String) {
            guard let database else { return }

            let resolver = ItemResolver(database: database, skills: SkillResolver(database: database))
            selectedCataloguePath = path
            selectedCatalogueItem = resolver.resolve(Gdc.Item(baseName: path))
        }

        // MARK: - Folder selection

        func chooseSaveFolder() {
            guard let url = pickFolder(title: "Choose the Grim Dawn save folder") else { return }

            try? saveFolder.store(url)
            saveAccess = FolderAccess.Access(url: url, needsRelease: url.startAccessingSecurityScopedResource())
            reloadCharacters()
        }

        func chooseGameFolder() {
            guard let url = pickFolder(title: "Choose the Grim Dawn installation folder") else { return }

            try? gameFolder.store(url)
            gameAccess = FolderAccess.Access(url: url, needsRelease: url.startAccessingSecurityScopedResource())
            loadDatabase()
        }

        private func pickFolder(title: String) -> URL? {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.message = title
            panel.prompt = "Choose"

            guard panel.runModal() == .OK else { return nil }

            return panel.url
        }

        private func restore() {
            saveAccess = try? saveFolder.resolve()
            gameAccess = try? gameFolder.resolve()

            if gameAccess != nil { loadDatabase() }
            if saveAccess != nil { reloadCharacters() }
        }

        // MARK: - Loading

        private func loadDatabase() {
            guard let folder = gameAccess?.url else { return }

            modelRenderer = ModelRenderer(gameFolder: folder)
            databaseState = .loading
            Task {
                let result = await Task.detached(priority: .userInitiated) {
                    Result { try GameDatabase(gameFolder: folder) }
                }.value

                switch result {
                    case let .success(loaded):
                        database = loaded
                        databaseState = .ready
                        warmSweeps(of: loaded)
                        reloadSelected()
                    case let .failure(error):
                        database = nil
                        databaseState = .failed(error.localizedDescription)
                }
            }
        }

        /// Works out the facts that cost a sweep of every record, so the first monster picked does not
        /// wait on one. The database keeps the answer, and every reader after this pays nothing.
        private func warmSweeps(of database: GameDatabase) {
            Task.detached(priority: .utility) { _ = MonsterPhases.map(in: database) }
        }

        /// Decodes the character's artwork off the main thread so switching tabs does not stall on it.
        private func warmIcons(for character: ResolvedCharacter) {
            guard let textures = database?.textures else { return }

            let paths = character.iconPaths
            Task.detached(priority: .utility) { textures.prewarm(paths) }
        }

        func reloadCharacters() {
            guard let folder = saveAccess?.url else { return }

            characters = SaveFolder.characters(in: folder)
            if selection == nil || !characters.contains(where: { $0.id == selection }) {
                selection = characters.first?.id
            }
            reloadSelected()
        }

        private func clearSelections() {
            selectedItem = nil
            selectedCatalogueItem = nil
            selectedCataloguePath = nil
            selectedAffixes = []
            selectedAffixKey = nil
            selectedAffixLevel = nil
            selectedSkill = nil
            selectedStar = nil
            selectedConstellation = nil
            selectedParameter = nil
            selectedMonsterPath = nil
            selectedMonster = nil
        }

        func reloadSelected() {
            guard
                let file = characters.first(where: { $0.id == selection })
            else {
                character = nil
                saveState = .idle
                return
            }
            guard
                let database
            else {
                character = nil
                saveState = .idle
                return
            }

            saveState = .loading
            clearSelections()

            Task {
                let result = await Task.detached(priority: .userInitiated) {
                    Result {
                        let data = try Data(contentsOf: file.playerFile)
                        let save = try Gdc.Parser.parse(data)
                        return CharacterBuilder(database: database).build(save, file: file)
                    }
                }.value

                switch result {
                    case let .success(resolved):
                        character = resolved
                        saveState = .ready
                        warmIcons(for: resolved)
                    case let .failure(error):
                        character = nil
                        saveState = .failed(error.localizedDescription)
                }
            }
        }
    }
}
