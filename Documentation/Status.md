# Where the app stands

## Working

The save parser consumes a current save exactly. Names and icons for items, skills, factions and
constellations resolve from the installed game's data. Six tabs render — Inventory, Items, Affixes,
Skills, Devotions, Stats — each with a detail sidebar and the shared quick search, which starts on the
first keystroke rather than from a field in the toolbar. The app runs dark whatever the system is set to,
since every panel it draws is the game's own artwork.

Panels are drawn at the game's own pixel coordinates from its UI records — the equipment doll, both
mastery trees, the devotion sky — and are never scaled up, only shrunk to fit a narrow window.
[GameData.md](GameData.md#window-layouts) says which record holds what.

## The stat engine

**What feeds the sheet.** Gear, item set bonuses, mastery bars, devotion stars, the difficulty's
resistance penalty, and always-on skills — passives, transmuters, toggled auras, the modifiers hanging off
them, and skills whose numbers live on the buff they drive. Anything the player presses does not, nor does
a celestial power or a low-health trigger: those numbers are the proc's own, and counting them inflates
the sheet.

**Every item stat is the value that copy rolled.** The seed in the save drives the game's own randomiser,
so the sheet adds real numbers rather than the middle of each band, and the sidebar prints the band beside
each figure as the tooltip does. [GameData.md](GameData.md#the-item-randomiser) has the draw order.

**Verified** against the game's own character window for a level 100 character, to the point:

- the ten resistances against their own caps, and every control resistance;
- health, energy, offensive and defensive ability, health and energy regeneration;
- Armor Rating region by region — 1508, 1550, 1710, 1456, 2035, 1456 — the rating they weigh into, and
  armour absorption;
- every damage modifier, cooldown reduction, skill energy cost, constitution, healing, dodge, deflect;
- attack speed, run speed and attacks per second, which read as results rather than bonuses;
- every figure of the Pet Bonuses panel, the rolled resistances included;
- every rolled figure on the items checked against their tooltips, bands included.

`StatCatalog` is the whitelist of `.dbr` fields the app understands. A stat absent from it is read from no
record and shown nowhere; adding one means adding its definition.

## What the game shows and the app does not

**The damage panel.** *Fire Damage 50*, *Aether Damage 9118–9993* and *Damage Per Second* combine the
weapon's own damage range with conversions, flat bonuses and the percentages. The app shows the flat
damage a character adds and the percentage it is raised by — both exact — but not the weapon figures they
feed.

**Conversions and retaliation** are parsed and displayed but never folded into a total.

## Fitted rather than read

Two figures come from the executable, so they are fitted to one level-100 character and exact for it. A
second character that disagrees means the shape is wrong, not just the constant.

- **Base regeneration.** The game states the shape — "percent bonuses only affect regeneration from gear
  and skills; not base regeneration, which is based on spirit" — but not the rate: `StatEngine` carries
  0.1656 per spirit and 0.03847 per physique.
- **The base attack rate**, 1.5 swings a second, from which attacks per second follows. The records name a
  weapon's speed class without stating what it swings at.

## Unverified

The build machine grants screen recording but not accessibility control, so screenshots work while
synthetic clicks and keystrokes never reach the app. Selection in each tab, the quick-search overlay, the
weapon-set switch, the devotion map's wheel zoom, pinch, two-finger pan and middle-button drag, the
sidebar divider and panel shrinking are checked by eye rather than by test; the search's matching rules
are covered by `QuickSearchTests`.

Blocking reads zero on the character it was checked against, which wears no shield, so those three rows
are structurally right and numerically untested. Pet stats have no reference either.

**Whether Nemesis is the right tier around −12000.** The band runs from the floor at −20000 up to −8000,
which follows from reading `factionValueN` as lower bounds — consistent with 25000 being both the Revered
threshold and the cap. If the game shows *Hated* there instead, the boundaries are upper bounds and
`CharacterBuilder.tier(for:thresholds:)` is inverted.

## Cosmetic gaps

- `elementalinfusion1` has modifiers but no `skillConnectionOn` list, so its branch is not drawn.
- Two factions point at `faction_user3.tex`, which the game ships as a blank white placeholder.
- The doll's centre box is empty. The game renders the character's 3D model there; the record behind it is
  a scene view, not a texture.

## The catalogues

Both are swept from `records/items/` in one pass and cached in one file under
`Caches/GrimDawner/items-<fingerprint>.json`, where the fingerprint is a SHA-256 of every loaded archive's
name, size and modification date. A patched game hashes differently and is listed again, and the stale
file is deleted. `Hasher` cannot be used for this — its seed changes with every launch, so nothing cached
under it would ever be read back. The sweep reads each record once straight from the archives, bypassing
`GameDatabase`'s memo: keeping 26,000 decompressed records would cost far more memory than re-reading the
few that are opened again.

Each entry carries the names of the stats its record holds, so both catalogues filter by what something
does as well as by what it is called, and everything searchable is folded once when the listing loads:
folding thousands of entries on every keystroke would be felt.

**Items.** 7,756 lines from 26,196 records, the rest being loot tables, affixes, crafting formulas, lore
notes and potions. Gear is every `Armor*` and `Weapon*` class; the three crafting classes join it under
the names the game uses rather than its own — `ItemRelic` is a **Component**, `ItemArtifact` a **Relic**,
`ItemEnchantment` an **Augment** — and each gets a rarity of that name so both filter menus offer it. None
of the three carries an `itemNameTag`: their name is the `description` tag. Records that duplicate one
another collapse, since the same weapon is written once per monster that carries it. One line covers every
level an item is written at, and the sidebar picks between them.

**Affixes.** 6,191 records under 386 names. The folder an affix sits in is what makes it a prefix or a
suffix; its name is the `lootRandomizerName` tag. A name covers more than a level ladder: the game writes
it once per level tier and, at each tier, once per kind of item it can land on, and those differ in what
they grant rather than only in how much — "of Spellweaving" holds 42 distinct rolls at level 24 alone.
Nothing in the data keys those variants, so the catalogue lists one line per name, the sidebar picks the
level, and every roll written at that level is shown rather than one of them chosen arbitrarily.

Neither an affix nor a directory item is anybody's copy: there is no seed and no roll to print, so each
figure shows as the band it can land in.

## How the sidebars read

Only a skill an item brings into being is described in full. A `+N to <skill>` line and an "Enhances" line
both point at a skill with a panel of its own: `+N` shows the reference alone, "Enhances" shows what the
modifier changes. A line about one of the character's own skills opens that skill on its mastery panel; a
skill of another class has no panel to open, so the line names the mastery instead — `+2 to Hellfire
Mine · Demolitionist`. A change to a skill the character has spent no point on changes nothing, so it
reads faded. The same changes appear under the skill itself in the Skills tab, one card per item that
changes it. The catalogues have no character, so every line there names its mastery and none is faded.

A skill reads in full: its rank, its parameters at that rank, what it grants, what it adds to every pet
(`petBonusName`), and what it summons. A summon carries the pet's own record — its life and resistances,
with the pet's unnamed adjuster skills folded in, as the game folds them — how long it stands
(`spawnObjectsTimeToLive`), how many stand at once (`petLimit`), and its named abilities at the ranks the
pet record gives them. A pet's own abilities are read without summons of their own, so nothing recurses.
A skill's sidebar also names every item, set and mastery bonus that lifts its rank, `+N` each, beside the
total the sheet counts.

Artwork that recedes is darkened rather than faded: a skill button turned transparent shows the connectors
the panel draws beneath it, so the search's dimming and the unlearned-skill dimming both multiply the
colour down instead of dropping the opacity.

## Upgrading an epic piece

`ItemArtifactFormula` records name what a blueprint consumes and what it produces. The 97 whose reagents
include `craft_awakeningashes.dbr` are the awakening upgrades: `reagentBaseBaseName` is the epic piece,
`artifactName` the awakened item it becomes. The directory carries that link on the item it upgrades, with
the ashes' own artwork beside its name.

## Performance

Listing every item takes about 3 seconds in Release from a cold cache and nothing at all afterwards.
Opening the database takes ~300 ms and building a character ~160 ms in Release, devotion map included —
110 constellations and 559 stars, each resolved to a named skill with its stats. Warming a character's
artwork covers 427 textures, the devotion sky's five 2048² nebulas among them, and runs off the main
thread. Once warm, a tab paints in 0 ms.

The devotion map is one `Canvas` rather than a view per star, and hit-tests clicks against star rectangles
by hand. A view per star would be 559 of them, and laying that out costs far more than the arithmetic.

Resident memory settles around 300–420 MB: the archives are memory-mapped, but the `.arz` string tables
are real heap — roughly 80k strings per archive across seven archives. Reducing that would mean interning
them lazily.

The Debug build is much slower than Release for the decode paths; hand testing should use Release. The
engine's tests need neither: `swift test` in `Engine/` runs the suite in about 20 milliseconds.
