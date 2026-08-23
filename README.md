# GrimDawner

A macOS app that reads Grim Dawn saves and shows a character the way GrimTools does: attributes,
resistances and derived stats, both mastery panels, the devotion sky, and every worn item with the values
that copy actually rolled. It also reads the game's own models, so every monster in the game can be looked
at from any angle.

Nothing about the game is hardcoded. Names, panel coordinates, faction tiers, resistance caps and the
combat formulas are read from the installed game's own records at runtime, so the app follows the game
across patches and expansions.

## Requirements

- macOS 27 or later, Xcode 27 (Swift 6)
- A Grim Dawn installation — the app reads its `database` and `resources` folders

## Building

```sh
_scripts/build.sh            # --release for a release build
_scripts/test.sh
_scripts/check.sh --fix      # format + lint gate
_scripts/release.sh          # checks, builds, zips into build/
```

`_scripts/format.sh` builds its helper tool from source on first run, which takes a few minutes.

## Using it

On first launch, pick two folders:

- **Game folder** — the installation containing `database/database.arz`. A CrossOver or Wine bottle works;
  point at the game folder inside the bottle.
- **Save folder** — the game's `save` folder, or its `main` subfolder.

Both are kept as security-scoped bookmarks, so they survive relaunches. ⌘1 … ⌘7 switch tabs, ⌘R re-reads
the save folder.

Every tab works the same way: click something to see it in full in the sidebar, and start typing to light
up whatever matches — there is no field to click into first. What you typed floats at the top of the
window; escape or the × clears it. Matching ignores case, spaces and punctuation, so `twinfangs` finds
Twin Fangs.

## What it shows

**Inventory** — the equipment doll on the game's own character panel, either weapon set. Each slot wears
the game's own quality badge: a monster infrequent's gem, a double rare's pair of them, the frame an
ascendant affix adds. Selecting an item breaks it down part by part — base, prefix, suffix, crafting
bonus, component, augment, ascendant affix — with what each contributes and the skills it grants.

**Items** — every named item in the game, some seven and a half thousand, components, relics and augments
among them, one line each with a dropdown for the levels it is written at. Typing filters this list rather
than dimming it, and matches stats as well as names: `fireres` finds everything carrying fire resistance.
Filters above the list cover the lowest level, rarity and kind, and it sorts by name or by level. Rolled
figures show as the band a copy can land in. An epic piece the Ashes of Awakening upgrade carries the
ashes' own icon beside its name and a link to the awakened item it becomes.

**Affixes** — every prefix and suffix a random item can roll, one line per name. The sidebar picks which
level tier to read and lists every roll the game writes at it, with the band each figure lands in and the
skills some of them grant. Filters for prefix or suffix and for quality; typing searches names and stats
alike, so `aetherres` lists everything that could put aether resistance on a rare item.

**Skills** — both mastery trees on the game's own panels, with class artwork, mastery bar, tier milestones
and the connectors between a skill and its modifiers. A skill's sidebar gives its rank over its cap, which
items lift that rank and by how much, its parameters at that rank, everything it grants, and what each
worn item changes about it.

**Devotions** — the whole sky: 110 constellations over the game's nebulas, taken stars lit and linked, the
rest tinted by whether affinity reaches them. A star reads in full: its rank, its parameters at that rank,
what it grants, what it adds to every pet, and what it summons — the pet's own life, how long it stands
and each of its abilities. Two fingers pan the sky and a pinch zooms it; a mouse wheel zooms and the
middle button drags.

**Monsters** — every named monster in the game, filtered by rank, by race and by name. A monster is read
at a level and a difficulty, since everything it has is an equation of both: what it is worth in a fight,
its attacks with their ranges and timings, its passives, and what it drops from each equipment slot with
the odds. Double-clicking opens it in a window of its own, with its whole sheet, its attacks, its loot,
and its **model** — the game's own, drawn live: drag to turn it, scroll to move in.

**Stats** — every number the sheet knows, grouped: attributes, offence, defence, armour per hit region,
resistances against their caps, control resistances, damage by type, damage over time, retaliation,
utility, blocking, what the character grants its pets, the kill record and faction standings.
Clicking a number lists every item, skill and constellation behind it — a component or an augment by its
own name, under the piece it sits in.

## How it works

Three Swift packages hold everything that is not a view, so their tests run without an app to host them.
The app is those packages plus `Code/UI` and `Code/App`.

| Layer | What it does |
| --- | --- |
| `Engine/…/Save` | Decrypts and parses `player.gdc`. The file must parse with nothing left over, so a format change surfaces as an error rather than as wrong numbers. |
| `Engine/…/Database` | Readers for the `.arz` record database and `.arc` archives, a pure-Swift LZ4 block decompressor and a `.tex` decoder. Archives are memory-mapped; records and icons decode lazily and are memoised. |
| `Engine/…/Domain` | Resolves save records into named items, mastery panels and constellations. |
| `Engine/…/Stats` | The stat catalogue, the accumulator, an evaluator for the game's stored formulas, and the engine that produces the sheet. |
| `Mesh/` | Reads the game's `.msh` models: Titan Quest's format, undocumented, worked out for this project. |
| `Render/` | Builds a SceneKit scene from a model and draws it, and ships `render-monsters` for doing the whole roster offline. |
| `Code/UI` | SwiftUI views over the resolved character. |

Icons are the game's own art. A record names a texture by a path whose first component is the archive it
lives in, and a `.tex` is a twelve-byte wrapper around a DDS. Those archives run past a gigabyte, so they
are memory-mapped and only the table of contents is read up front.

### Accuracy

Health, energy and the two abilities come from `playerlevels.dbr` and `combatformulas.dbr`, evaluated at
runtime rather than transcribed. Armor Rating is the weighted average over the six hit regions, not the
sum of the pieces. Every item stat is rolled from the seed the save stores, so the sheet adds the values
that copy actually has rather than the middle of each band.

Gear, set bonuses, mastery bars, devotion stars, the difficulty's resistance penalty and always-on skills
feed the sheet. Abilities the player presses do not, so numbers that depend on an active buff read lower
here than in game with that buff up.

Checked against the game's own character window: the ten resistances, health, energy, both abilities, both
regenerations, armour region by region, every damage modifier and every pet bonus match to the point, as
do the rolled figures on individual items, bands included. The damage panel and its damage per second are
not modelled.

Monsters have no such window in the game, so they are checked against GrimTools' monster database, which
reads the same records: Ravager of Minds at level 100 on Ultimate matches to the unit.
[Documentation/Status.md](Documentation/Status.md) has the whole of it.

## Documentation

- [Documentation/SaveFormat.md](Documentation/SaveFormat.md) — the `.gdc` layout.
- [Documentation/GameData.md](Documentation/GameData.md) — the `.arz`, `.arc` and `.tex` formats, which
  record holds which fact, and the rules the engine encodes.
- [Documentation/Status.md](Documentation/Status.md) — how far the stat engine goes.

## Sources

The formats are not published by the game's authors. What this implementation was built from:

- **The installed game's own data** — `database.arz`, `templates.arc` and the text archives are the
  primary source for every name, layout, formula and constant, and for the field lists in
  [GameData.md](Documentation/GameData.md).
- **[lost.org.uk/grimdawn.html](https://www.lost.org.uk/grimdawn.html)** — community documentation of the
  save and database formats, and the tools linked from it. The `.gdc` layout here was re-verified against
  a current save and differs from those references, which were written for 1.1.x.
- **[marius00/GrimDawnItemStats](https://github.com/marius00/GrimDawnItemStats)** — the reverse-engineered
  item randomiser: the MINSTD generator, the store order it draws in, and the per-store mechanics.
  [GameData.md](Documentation/GameData.md#the-item-randomiser) records the four rules this project found
  that reference does not model.
- **[grimtools.com/monsterdb](https://www.grimtools.com/monsterdb/)** — the reference every monster figure
  was checked against, and what showed that the difficulty's own adjustment had to be in there.
- **The game's own tooltips and character window**, used as the ground truth every character number was
  checked against.

The `.msh` model format is documented nowhere; [GameData.md](Documentation/GameData.md#the-model-format)
is this project's own reading of it.

## Licence

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Alex Babaev.

Grim Dawn is a trademark of Crate Entertainment. This project is unaffiliated, ships none of the game's
data, and reads only the copy already installed on the machine.
