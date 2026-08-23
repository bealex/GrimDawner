# Where the app stands

## Working

The save parser consumes a current save exactly. Names and icons for items, skills, factions and
constellations resolve from the installed game's data. Five tabs render — Inventory, Items, Skills,
Devotions, Parameters — each with a detail sidebar and the shared quick search, which starts on the first
keystroke rather than from a field in the toolbar. The app runs dark whatever the system is set to, since
every panel it draws is the game's own artwork.

Panels are drawn at the game's own pixel coordinates from its UI records — the equipment doll, both
mastery trees, the devotion sky — and are never scaled up, only shrunk to fit a narrow window.
[GameData.md](GameData.md#window-layouts) says which record holds what.

## The stat engine

**Exact.** Attributes, health, energy, offensive and defensive ability, Armor Rating and absorption, every
resistance against its own cap and after the difficulty penalty, per-item and per-affix breakdowns, skill
ranks and their effects at the clamped rank. All from the game's records, with the combat equations
evaluated at runtime.

**Every item stat is the value that copy rolled.** The seed in the save drives the game's own randomiser,
so the sheet adds real numbers rather than the middle of each band, and the sidebar prints the band beside
each figure as the tooltip does. [GameData.md](GameData.md#the-item-randomiser) has the draw order and the
rules published references do not model.

**What feeds the sheet.** Gear, item set bonuses, mastery bars, devotion stars, the difficulty's
resistance penalty, and always-on skills — passives, transmuters, toggled auras, the modifiers hanging off
them, and skills whose numbers live on the buff they drive. Anything the player presses does not, nor does
a celestial power or a low-health trigger: those numbers are the proc's own, and counting them inflates
the sheet.

**Collected but not folded into derived numbers.** Damage conversions (parsed into `StatBlock.conversions`
and shown, but not applied to damage totals), retaliation totals, pet stats.

**Verified** against the game's own character window for a level 100 character: all ten resistance totals,
health, energy, offensive and defensive ability, energy absorption, freeze resistance and life leech
resistance match to the point, as does every rolled figure on the items checked against their tooltips,
bands included.

`StatCatalog` is the whitelist of `.dbr` fields the app understands. A stat absent from it is read from no
record and shown nowhere; adding one means adding its definition.

## Unverified by test

The build machine grants screen recording but not accessibility control, so screenshots work while
synthetic clicks and keystrokes never reach the app. Selection in each tab, the quick-search overlay, the
weapon-set switch, the devotion map's zoom and pan, the sidebar divider and panel shrinking are checked by
eye rather than by test; the search's matching rules are covered by `QuickSearchTests`.

**Whether Nemesis is the right tier around −12000.** The band runs from the floor at −20000 up to −8000,
which follows from reading `factionValueN` as lower bounds — consistent with 25000 being both the Revered
threshold and the cap. If the game shows *Hated* there instead, the boundaries are upper bounds and
`CharacterBuilder.tier(for:thresholds:)` is inverted.

## Known approximations

**Armor Rating is about a percent low** — 1645 against 1660 on the character it was checked with. Every
armour figure and both `defensiveProtectionModifier` bonuses match their tooltips, so the gap is in how
the regions are weighted or how a belt's armour spreads, not in the values.

## Known cosmetic gaps

- `elementalinfusion1` has modifiers but no `skillConnectionOn` list, so its branch is not drawn.
- Two factions point at `faction_user3.tex`, which the game ships as a blank white placeholder.
- Stat lists show flat and percentage variants under the same label, distinguished by the `%` suffix — as
  the game does.
- The doll's centre box is empty. The game renders the character's 3D model there; the record behind it is
  a scene view, not a texture.

## The item directory

The Items tab lists every named item in the game — 8,001 of 26,196 records under `records/items`, the rest
being loot tables, affixes, crafting formulas, lore notes and potions. Gear is every `Armor*` and
`Weapon*` class; the three crafting classes join it under the names the game uses rather than its own —
`ItemRelic` is a **Component**, `ItemArtifact` a **Relic**, `ItemEnchantment` an **Augment** — and each
gets a rarity of that name so both filter menus offer it. None of the three carries an `itemNameTag`:
their name is the `description` tag. The sweep reads each record once straight from the
archives, deliberately bypassing `GameDatabase`'s memo: keeping 26,000 decompressed records would cost far
more memory than re-reading the few that are opened again.

An item is written once per level tier under one name tag, so the directory groups its tiers into a single
line that opens onto them — 8,001 records read as
roughly a third as many entries.

A skill an item grants sits on the item's own record, so the sidebar gives the base record's skills a card
of their own, each reading with the condition that fires it in the game's own words.

Only a skill an item brings into being is described in full. A `+N to <skill>` line and an "Enhances" line
both point at a skill with a panel of its own: `+N` shows the reference alone, "Enhances" shows what the
modifier changes and nothing else. A skill outside the character's masteries appears on no panel, so those
lines name the mastery instead — `+2 to Hellfire Mine · Demolitionist`. A change to a skill the character
has spent no point on changes nothing, so it reads faded. The same changes appear under the skill itself
in the Skills tab, one card per item that changes it. The directory has no character, so every line there
names its mastery and none is faded.

A rolled stat shows as its band alone in the directory: nobody owns these copies, so there is no seed and
no roll to print.

Each entry carries the names of the stats its record holds, so the directory filters by what an item does
as well as by what it is called. Everything searchable about an entry is folded once when the listing
loads: folding 8,001 entries on every keystroke would be felt.

The listing is cached under `Caches/GrimDawner/items-<fingerprint>.json`, where the fingerprint is a
SHA-256 of every loaded archive's name, size and modification date. A patched game hashes differently and
is listed again, and the stale file is deleted. `Hasher` cannot be used for this — its seed changes with
every launch, so nothing cached under it would ever be read back.

## Performance

Listing every item takes about 3 seconds in Release from a cold cache and nothing at all afterwards.
Opening the database takes ~300 ms and building a character ~160 ms in Release, devotion map included —
110 constellations and 559 stars, each resolved to a named skill with its stats. Warming a character's
artwork now covers 427 textures, the devotion sky's five 2048² nebulas among them, and runs off the main
thread. Once warm, a tab paints in 0 ms.

The devotion map is one `Canvas` rather than a view per star, and hit-tests clicks against star rectangles
by hand. A view per star would be 559 of them, and laying that out costs far more than the arithmetic.

Resident memory settles around 300–420 MB: the archives are memory-mapped, but the `.arz` string tables are
real heap — roughly 80k strings per archive across seven archives. Reducing that would mean interning them
lazily.

The Debug build is *much* slower than Release for the decode paths; hand testing should use Release.
