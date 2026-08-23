# GrimDawner

A macOS app that reads Grim Dawn saves and shows a character the way GrimTools does: attributes,
resistances and derived stats, both mastery panels, the devotion sky, and every worn item with the values
that copy actually rolled.

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

Both are kept as security-scoped bookmarks, so they survive relaunches. ⌘1 … ⌘5 switch tabs, ⌘R re-reads
the save folder.

Every tab works the same way: click something to see it in full in the sidebar, and start typing to light
up whatever matches — there is no field to click into first. What you typed floats at the top of the
window; escape or the × clears it. Matching ignores case, spaces and punctuation, so `twinfangs` finds
Twin Fangs.

## What it shows

**Inventory** — the equipment doll on the game's own character panel, either weapon set. Selecting an item
breaks it down part by part — base, prefix, suffix, crafting bonus, component, augment, ascendant affix —
with what each contributes and the skills it grants.

**Items** — every named item in the game, around eight thousand, with components, relics and augments,
folded so one item's level tiers read as a single line. Typing filters this list rather than dimming it,
and matches stats as well as names: `fireres` finds everything carrying fire resistance. Filters above the
list cover the lowest level, rarity and kind. Rolled figures show as the band a copy can land in.

**Skills** — both mastery trees on the game's own panels, with class artwork, mastery bar, tier milestones
and the connectors between a skill and its modifiers. A skill's sidebar gives its rank over its cap, its
parameters at that rank, everything it grants, and what each worn item changes about it.

**Devotions** — the whole sky: 110 constellations over the game's nebulas, taken stars lit and linked, the
rest tinted by whether affinity reaches them. Clicking a star shows what it grants and what its
constellation asks for.

**Parameters** — every number the sheet knows, grouped: attributes, offence, defence, armour per hit
region, resistances against their caps, control resistances, damage by type, damage over time,
retaliation, utility, the kill record and faction standings. Clicking a number lists every item, skill and
constellation behind it.

## How it works

| Layer | What it does |
| --- | --- |
| `Code/Save` | Decrypts and parses `player.gdc`. The file must parse with nothing left over, so a format change surfaces as an error rather than as wrong numbers. |
| `Code/Database` | Readers for the `.arz` record database and `.arc` archives, a pure-Swift LZ4 block decompressor and a `.tex` decoder. Archives are memory-mapped; records and icons decode lazily and are memoised. |
| `Code/Domain` | Resolves save records into named items, mastery panels and constellations. |
| `Code/Stats` | The stat catalogue, the accumulator, an evaluator for the game's stored formulas, and the engine that produces the sheet. |
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

Checked against the game's own character window: all ten resistance totals, health, energy, offensive and
defensive ability match to the point, as do the rolled figures on individual items, bands included.
[Documentation/Status.md](Documentation/Status.md) records what is still approximate.

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
- **The game's own tooltips and character window**, used as the ground truth every number was checked
  against.

## Licence

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Alex Babaev.

Grim Dawn is a trademark of Crate Entertainment. This project is unaffiliated, ships none of the game's
data, and reads only the copy already installed on the machine.
