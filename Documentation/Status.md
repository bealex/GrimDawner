# Where the app stands

## Working

The save parser consumes a current save exactly. Names and icons for items, skills, factions and
constellations resolve from the installed game's data. Six tabs render — Inventory, Items, Affixes, Skills,
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

**Collected but not folded into derived numbers.** Damage conversions are parsed into
`StatBlock.conversions` and shown, but not applied to damage totals, and retaliation totals are listed
rather than summed into a figure.

**The damage panel is not modelled.** The game's *Fire Damage 50*, *Aether Damage 9118–9993* and *Damage
Per Second* combine the weapon's own damage range with conversions, flat bonuses and the percentages; the
app shows the flat damage a character adds and the percentage it is raised by, which are exact, but not
the weapon figures those feed. Attacks per second is computed from a base rate of 1.5 swings a second,
fitted to one reading, since the records name a weapon's speed class without stating its rate.

**Verified** against the game's own character window for a level 100 character: all ten resistance totals
against their own caps, health, energy, offensive and defensive ability, health and energy regeneration,
every damage modifier, cooldown reduction, skill energy cost, constitution, healing, dodge, deflect and
every control resistance match to the point, as does every rolled figure on the items checked against
their tooltips, bands included. Armor Rating matches region by region — 1508, 1550, 1710, 1456,
2035, 1456 — as does the rating those weigh into and armour absorption. Attack speed, run speed and attacks per second read as the game
prints them, and every figure of the Pet Bonuses panel matches, the rolled resistances included.

`StatCatalog` is the whitelist of `.dbr` fields the app understands. A stat absent from it is read from no
record and shown nowhere; adding one means adding its definition.

## Unverified by test

The build machine grants screen recording but not accessibility control, so screenshots work while
synthetic clicks and keystrokes never reach the app. Selection in each tab, the quick-search overlay, the
weapon-set switch, the devotion map's wheel zoom, pinch, two-finger pan and middle-button drag, the
sidebar divider and panel shrinking are checked by eye rather than by test; the search's matching rules
are covered by `QuickSearchTests`.

**Whether Nemesis is the right tier around −12000.** The band runs from the floor at −20000 up to −8000,
which follows from reading `factionValueN` as lower bounds — consistent with 25000 being both the Revered
threshold and the cap. If the game shows *Hated* there instead, the boundaries are upper bounds and
`CharacterBuilder.tier(for:thresholds:)` is inverted.

## Known approximations

**Base regeneration is fitted, not read.** The game states the shape — "percent bonuses only affect
regeneration from gear and skills; not base regeneration, which is based on spirit" — but the rate per
point is in the executable. `StatEngine` carries 0.1656 per spirit and 0.03847 per physique, fitted to one
level-100 character and exact for it. A second character that disagrees means the rate is not flat per
point.

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
modifier changes and nothing else. A line about one of the character's own skills opens that skill on its
mastery panel; a skill of another class has no panel to open, so the line names the mastery instead —
`+2 to Hellfire Mine · Demolitionist`. A change to a skill the character
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

A skill reads in full: its rank, its parameters at that rank, what it grants, what it adds to every pet
(`petBonusName`), and what it summons. A summon carries the pet's own record — its life and resistances,
with the pet's unnamed adjuster skills folded in, as the game folds them — how long it stands
(`spawnObjectsTimeToLive`), how many stand at once (`petLimit`), and its named abilities at the ranks the
pet record gives them. A pet's own abilities are read without summons of their own, so nothing recurses.

A skill's sidebar names every item, set and mastery bonus that lifts its rank, `+N` each, beside the
total the sheet counts. Three reaches feed it: `+N to <skill>`, `+N to <mastery>` and `+N to all skills`.

Artwork that recedes is darkened rather than faded. A skill button turned transparent shows the
connectors the panel draws beneath it, so the search's dimming and the unlearned-skill dimming both
multiply the colour down instead of dropping the opacity.

## The affix catalogue

The Affixes tab lists every named prefix and suffix — 6,191 records under 386 names — swept from
`records/items/lootaffixes/` in the same pass as the item directory and cached in the same file. The
folder an affix sits in is what makes it a prefix or a suffix; its name is the `lootRandomizerName` tag.

A name covers more than a level ladder. The game writes it once per level tier and, at each tier, once per
kind of item it can land on, and those differ in what they grant rather than only in how much: "of
Spellweaving" holds 42 distinct rolls at level 24 alone. Nothing in the data keys those variants — not the
record name, whose trailing letters group records that share a level, and not the stat set — so the
catalogue lists one line per name, the sidebar picks the level, and every roll written at that level is
shown rather than one of them chosen arbitrarily.

An affix has no copy of its own, so there is no seed and no rolled value: each figure shows as the band it
can land in, rolled through the same `ItemRoll` path an item's prefix takes, at the affix's own
`lootRandomizerJitter`.

## Upgrading an epic piece

`ItemArtifactFormula` records name what a blueprint consumes and what it produces. The 97 whose reagents
include `craft_awakeningashes.dbr` are the awakening upgrades: `reagentBaseBaseName` is the epic piece,
`artifactName` the awakened item it becomes. The directory carries that link on the item it upgrades,
with the ashes' own artwork beside its name.

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
