# GrimDawner

macOS app that reads Grim Dawn saves and shows each character GrimTools-style. [README.md](README.md) is
what it does; the references below are what you need before changing it.

- [Documentation/SaveFormat.md](Documentation/SaveFormat.md) — the `.gdc` layout, verified byte-for-byte
  and different from every public reference.
- [Documentation/GameData.md](Documentation/GameData.md) — the `.arz` / `.arc` / `.tex` formats, which
  record holds which fact, and the game rules the engine encodes.
- [Documentation/Status.md](Documentation/Status.md) — what is done, what the stat engine does not yet
  cover, and what is unverified.

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

## Two traps that have already cost time

**Editing by string replacement silently does nothing.** `_scripts/format.sh` reflows files, so a pattern
captured before a format run will not match after one, and a `str.replace` no-ops without complaining. Two
finished features were lost that way and only found in a screenshot. Use the `Edit` tool, which fails
loudly, and re-read a file after formatting it.

**An invisible SwiftUI view still takes clicks.** The zero-opacity buttons carrying ⌘1–⌘5 need
`allowsHitTesting(false)`, or they swallow pointer input.

## Layout

```
Engine/Sources/GrimDawnerEngine/
    Save        player.gdc reader and parser
    Database    .arz / .arc / .tex readers, LZ4, memory-mapped byte access, folder bookmarks
    Domain      save records -> named items, masteries, constellations, factions
    Stats       stat catalogue, accumulator, formula evaluator, engine
Engine/Tests    the suite, and any temporary probe
Code/UI         SwiftUI views
Code/App        the app itself
```

The engine is a Swift package the app depends on. Its tests run with `swift test` — no app is built and
none is launched — so a probe belongs in `Engine/Tests`, where it reads the game folder directly rather
than through the app's sandbox. Everything the views touch is `public`; a new type the UI reads needs
that too.

`StatCatalog` is the whitelist of `.dbr` fields the app understands; a stat that does not appear there is
read from no record and shown nowhere. Adding a stat means adding its definition.
