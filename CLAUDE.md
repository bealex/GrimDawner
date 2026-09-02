# GrimDawner

macOS app that reads Grim Dawn saves and shows each character GrimTools-style. [README.md](README.md) is
what it does; the references below are what you need before changing it.

- [Documentation/SaveFormat.md](Documentation/SaveFormat.md) — the `.gdc` layout, verified byte-for-byte
  and different from every public reference.
- [Documentation/GameData.md](Documentation/GameData.md) — the `.arz` / `.arc` / `.tex` formats, which
  record holds which fact, and the game rules the engine encodes.
- [Documentation/AttackPipeline.md](Documentation/AttackPipeline.md) — the engine's attack, decompiled
  from `Game.dll`: how a blow is assembled, rolled and mitigated.
- [Documentation/Coverage.md](Documentation/Coverage.md) — every field on an item, monster, skill or
  devotion record, and whether the engine reads it.
- [Documentation/Status.md](Documentation/Status.md) — what is done, what the stat engine does not yet
  cover, and what is unverified.
- [Documentation/History.md](Documentation/History.md) — corrections and what they were. **Anything a
  comment would say about how the code used to be wrong goes here instead.**

## Environment

The game is installed locally and is **read only, never written**. Its folder is machine-specific: the app
takes it as a security-scoped bookmark, and a test that needs it should read the path from the environment
rather than hardcode one.

`Resources/` holds local fixtures — a save to test against, screenshots — and is untracked. Nothing there
may be committed: it is a player's own data and the game's own art.

Screenshots of the running app work. **Synthetic input does not** — this machine grants screen recording
but not accessibility control, so `click at` and `keystroke` reach nothing and `AXPress` reports a success
that never happened. Anything interactive has to be verified by the user.

## Build and check

```sh
_scripts/build.sh        # --release; runs xcodegen first
_scripts/test.sh
_scripts/check.sh --fix  # format + lint gate
_scripts/release.sh      # checks, builds, zips into build/
```

Run `xcodegen generate` after adding or removing a file — otherwise "cannot find type in scope". Hand
testing should use the Release build: Debug is unoptimised and the decode paths are visibly slower.

## Ground rules

**Nothing about the game is hardcoded that the game itself states.** Names, panel coordinates, faction
order, rarity colours, resistance caps and the combat equations all come from the database at runtime.
When you need a new fact, find the record that holds it before writing a constant. `Equation` exists so
the game's stored formulas can be evaluated rather than transcribed.

**The save parser consumes the file exactly.** `Gdc.Parser` fails if one byte is left over. Never "fix" a
parse failure by skipping to the end of a block — that turns a format change into silent wrong numbers.
Blocks the app does not model still read their trailing bytes.

**Aggregation is not always a sum.** Armor Rating averages hit regions; absorption multiplies; the
displayed damage percentages exclude attribute scaling. Before adding a stat, check how the game
aggregates it — `GameData.md` lists the ones that surprised.

**Textures are memory-mapped, never copied.** `Items.arc` alone is 441 MB; `ByteView` exists for this. Do
not reintroduce `[UInt8](data)` over a whole archive.

**The decode paths are hot.** LZ4 and the texture pixel conversion run over unsafe buffers and move whole
runs; the checked byte-at-a-time versions cost over a second across one skill panel.
`TextureStore.prewarm` runs off the main thread when a character loads, ordered so a tab's own artwork
decodes before the stash's.

**Verify against the real install.** Write a temporary test that prints what you need, run it, delete it.
Real save content must never land in a committed test, and a committed test must skip when the local
fixtures are absent.

**A monster has no window in the game to check against.** [grimtools.com/monsterdb](https://www.grimtools.com/monsterdb/)
reads the same records and is the reference `MonsterStatsTests` pins. Anything drawn — a model, a texture —
is checked by eye, and a wrong guess about orientation or mip order looks plausible until something with a
face proves otherwise.

## Traps that have already cost time

**Editing by string replacement silently does nothing.** `_scripts/format.sh` reflows files, so a pattern
captured before a format run will not match after one, and a `str.replace` no-ops without complaining. Two
finished features were lost that way and only found in a screenshot. Use the `Edit` tool, which fails
loudly, and re-read a file after formatting it.

**An invisible SwiftUI view still takes clicks.** The zero-opacity buttons carrying ⌘1–⌘7 need
`allowsHitTesting(false)`, or they swallow pointer input.

**A scroll view starves a SceneKit view.** It offers unbounded height, an `SCNView` asks for none, and the
model comes out zero pixels tall. Give the model the pane and let only the reading tabs scroll.

**A SceneKit particle is measured from its middle, and every property controller multiplies.**
`particleSize` of one draws *two* units across, and a controller scales the property rather than
replacing it — proved by a zero base staying still whatever the controller says. Feeding a stated figure
to both squares it: an 11-unit swipe drew at 242, and a 65°/s spin turned at 4,157. A curve goes in as a
share of its own peak. Measure a new particle property against a known base before trusting it.

## Layout

```
Engine/Sources/GrimDawnerEngine/
    Save        player.gdc reader and parser
    Database    .arz / .arc / .tex readers, LZ4, memory-mapped byte access, folder bookmarks
    Domain      save records -> named items, masteries, constellations, factions, monsters
    Stats       stat catalogue, accumulator, formula evaluator, engine
Mesh/           the .msh model and .anm animation readers, which depend on nothing
Render/         SceneKit scene and renderer, plus the render-monsters command
Code/UI         SwiftUI views
Code/App        the app itself
```

Three packages, all depended on by the app; `Render` depends on the other two. Their tests run with
`swift test` — no app is built and none is launched — so **a probe belongs in the package whose data it
reads**, where it opens the game folder directly rather than through the app's sandbox. `_scripts/test.sh`
runs all three. Everything the views touch is `public`; a new type the UI reads needs that too.

`StatCatalog` is the whitelist of `.dbr` fields the app understands; a stat that does not appear there is
read from no record and shown nowhere. Adding a stat means adding its definition.
