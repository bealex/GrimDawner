# The `player.gdc` format

Verified byte-for-byte against a Fangs of Asterkarn save. The parser in `Code/Save` requires the whole file
to be consumed with nothing left over, so anything below that stops being true will surface as an error.

The community references — [lost.org.uk](https://www.lost.org.uk/grimdawn.html),
[AaronHutchinson/Grim-Dawn-Save-Decryption](https://github.com/AaronHutchinson/Grim-Dawn-Save-Decryption),
[odie/gd-edit](https://github.com/odie/gd-edit) — describe 1.1.x. **They do not parse a current save.** The
differences are listed under "Deltas from the 1.1.x references".

## Obfuscation

The file is scrambled with a rolling XOR whose key advances over the *encrypted* bytes as they are read.

```
seed  = first four bytes, little-endian, XOR 0x55555555
key   = seed
table[i] for i in 0..<256:
    seed = (seed >>> 1) | (seed << 31)     // rotate right, 32-bit
    seed = seed * 39916801                 // wrapping
    table[i] = seed
```

Reading a value: take the raw bytes, XOR with the current key, then fold each raw byte into the key with
`key ^= table[byte]`.

Three consequences, all load-bearing:

- **Order is everything.** Values must be read in exactly the order the game wrote them.
- **A four-byte string does not decode like an `Int32`.** An int XORs all four bytes against one key; a
  string XORs each byte against the low byte of a key that advances between them.
- **`peekInt` consumes four bytes without advancing the key.** Block lengths and block terminators are
  stored that way. A block that contains nested blocks therefore cannot be skipped by advancing the key
  over its body — the nested lengths and terminators would be counted twice.

## File shape

```
u32  key seed (see above)
u32  magic          0x58434447  "GDCX" little-endian
u32  preamble version, always 2
     header
u32  peek, always 0
u32  file version, 8
16b  character uid
     blocks, in the order below
```

Header: `wstring name`, `bool male`, `string playerClassName`, `u32 level`, `bool hardcore`, `byte
expansionFlags`. The byte after `hardcore` was documented as a constant 3; a current save carries 7. It is
read and ignored.

A block is `u32 id`, `peek u32 length`, body, `peek u32 0`.

| id | contents | block version seen |
| --- | --- | --- |
| 1 | character info: difficulty, iron, tributes, skin texture, loot filters | 5 |
| 2 | biography: level, experience, unspent points, attributes, pools | 8 |
| 3 | inventory: sacks (nested blocks), equipment, weapon sets | 11 |
| 4 | personal stash: tabs (nested blocks) | 11 |
| 5, 6, 7, 17 | respawns, riftgates, markers, shrines — skipped whole | 1, 1, 1, 2 |
| 8 | skills and item skills | 8 |
| 12 | lore notes | 1 |
| 13 | factions | 5 |
| 14, 15 | UI settings, seen tutorials — skipped whole | 5, 1 |
| 16 | play statistics | 12 |
| 10 | trigger tokens — skipped whole | 2 |

Blocks are not in ascending id order: 17 sits between 7 and 8, and 10 comes last.

## Item

```
string  baseName, prefixName, suffixName, modifierName, transmuteName
u32     seed
string  relicName        (the component socketed into it)
string  relicBonus       (a relic's completion bonus)
u32     relicSeed
string  augmentName
u32     unknown
u32     augmentSeed
string  ascendedName     ← Fangs of Asterkarn; empty on older items
u32     ascendedSeed     ←
u32     unknown
u32     stackCount
u32     unknown
u32     unknown
```

Then, depending on where it sits: inventory adds `u32 x, u32 y`; stash adds `float x, float y`; an
equipment slot adds `bool attached`.

Equipment is twelve slots in this order: head, neck, chest, legs, feet, hands, ring, ring, waist,
shoulders, medal, relic. A `bool` separates the twelve from weapon set one, and again from weapon set two;
each set is two items.

**The seed decides the magnitudes, and the app reproduces them.** Each record holds the middle of a band
and the game rolls the item's numbers from its seed: a tooltip reading `32% Vitality Resistance [32-48]`
comes from a record holding 40, and `[237-356]` from one holding 296.5 before an Ascended item's
`attributeScalePercent` is applied. The band is ±20% for an item's own stats and `lootRandomizerJitter` for
an affix's. The generator is MINSTD (Park-Miller) primed once with the seed, and the values a particular
item got follow from the order the engine draws them in — see the draw order in
[GameData.md](GameData.md#the-item-randomiser).

## Skill entry

```
string  name
u32     level
bool    enabled
bool    unknown          ← extra byte, not in the 1.1.x references
u32     isDevotion       (1 for every constellation star, 0 otherwise — a marker, not a rank)
u32     experience
u32     active
byte    unknown
byte    unknown
string  autoCastSkill
string  autoCastController
```

## Factions

`Faction` is `bool modified, bool unlocked, float value, float positiveBoost, float negativeBoost`.

The array is **positional** and mostly internal. Slot order is: `factionPlayer`, `factionSurvivors`,
`factionAetherials`, `factionBeasts`, `factionCthonians`, `factionOutlaws`, then every `factionUserN` from
`gamefactions.dbr` in numeric order — `factionDrifters` and `factionNeutralNPC` are User0 and User1, so
numeric order places them correctly at slots 6 and 7.

Cross-checked against a finished character: hostile monster groups sit at the floor, the mutually
exclusive faction pair reads positive/negative the right way round, and Devil's Crossing lands at the cap.

## Deltas from the 1.1.x references

- Items gained `ascendedName` and `ascendedSeed`, plus three further trailing integers.
- Skill entries gained a flag byte before the devotion marker.
- Character info's loot filters are a length-prefixed byte array; the old `unknown` int before them *is*
  that length. The `always-show-loot` int only exists in block versions 2–4.
- Character info's `texture` is the skin picked at creation — `creatures/pc/hero02.tex` — which is what
  the character's model is drawn in, rather than the player record's own `playerTextures` default.
- Every stash tab carries twenty trailing bytes after its items.
- The skills block and the play-stats block each carry extra trailing values.

Unknown trailing bytes inside a block are read rather than skipped, which is what lets the parser insist on
consuming the file exactly.
