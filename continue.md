# Where to pick this up

Everything up to here is committed. Tests: `_scripts/test.sh` with `GRIM_DAWN_FOLDER` and an **absolute**
`GRIM_DAWN_SAVE` (a relative one resolves against each package's own folder). `_scripts/check.sh` is
clean. Run the app with `_scripts/build.sh --release`; Debug is too slow to use.

## What the last sessions did

The effects work is written up in [Documentation/History.md](Documentation/History.md), with the engine
facts in [GameData.md](Documentation/GameData.md#effects) and the open items at the end of History. In
short: the `.pfx` emitters are read the right way round, particles draw at the size and blend the file
states, projectiles fly at their own speed from the limb the animation calls out, a dying creature sinks
into the ground, weapons leave their `WeaponTrail` ribbon, and there is a checked floor one square to the
unit. The Dread's claw swipe is still far dimmer than the game's and the reason is unread; that thread
stops at `shaders/particle/particleadditive.ssh`.

A Ghidra project for `Engine.dll` and `Game.dll` lives in the session scratchpad and is disposable;
`~/.claude/projects/…/memory/grim-dawn-install-and-decompiling.md` has the recipe to rebuild it.

## The next task: find the best items for a build

Two things, in this order.

**One slot at a time, from the current build.** For each slot, try every item that could go there
against the character as it stands, keep the best, and show what it changed. Start with belt, medal,
rings and amulet.

**Then several slots together, with some held fixed.** The player pins what stays (a set, say
Clairvoyant), and the search fills the rest. Brute force over every candidate in every open slot is the
answer wanted, and it is too big to run naively, so it needs pruning: an item that is worse than another
on every axis the score reads can never be part of a best answer and drops before the search starts;
slots that share nothing can be searched apart; and the one-at-a-time pass gives a bound to cut with.

### What already exists

- `Engine/Sources/GrimDawnerEngine/Optimizer/` is a working search over **sockets** (components and
  augments), not items: `LoadoutProblem` (the choices per socket and their stats), `LoadoutEvaluator`
  (folds a choice into the sheet), `LoadoutOptimizer.run(goal:seed:progress:)` with a single, pair and
  optional trio pass, `LoadoutSearch` for the passes, `LoadoutTarget` and `LoadoutGoal` for what is
  being maximised, and `figures(of:)` / `score(_:goal:)` for reading a result. `Code/UI/OptimizerTab.swift`
  and `OptimizerPlanView.swift` drive it. The natural move is a second problem kind whose "sockets" are
  equipment slots and whose choices are items.
- `ItemCatalogue.build(from:)` (`Domain/ItemCatalogue.swift`) is every item in the game as
  `CataloguedItem`, with `kind(ofClass:)` for which slot an item goes in. That is the candidate pool.
- `ItemRoll` rolls an item's affixes from a seed the way the game does; a catalogued item has no roll, so
  a candidate's stats are a band, and the search has to pick a policy (midpoint, floor, or the band both
  ways).
- `CharacterBuilder` / `ResolvedCharacter` turn a save plus gear into the sheet; `StatEngine` is the sheet.
  `Encounter` scores a character against a monster, which is one candidate for the goal.

### Things to settle before the search

- **The score.** The socket optimizer maximises a `LoadoutGoal`; items need the same or a richer one.
  Resistance caps, armour ceiling and ability floor already exist as constraints there.
- **Set bonuses.** A set piece's value depends on which other pieces are worn. The evaluator has to fold
  set bonuses per combination, not per item.
- **Affixed candidates.** A blue or green item is a base plus affixes. Enumerating every affix pair is the
  brute force that is too big; the catalogue's affix tables (`CataloguedAffix`, `AffixEntry`) say what can
  roll where, so a first version can search legendaries and set pieces (fixed stats) and treat affixed
  items separately.
- **Skill bonuses.** `+N to Skill` on an item changes the sheet only if the character has the skill; the
  evaluator must read the character's masteries.
