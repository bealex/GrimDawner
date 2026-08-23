# Where the app stands

## Working

The save parser consumes a current save exactly. Names and icons for items, skills, factions and
constellations resolve from the installed game's data. Seven tabs render — Inventory, Items, Affixes,
Skills, Devotions, Stats, Monsters — each with a detail sidebar and the shared quick search, which starts
on the first keystroke rather than from a field in the toolbar. The app runs dark whatever the system is set to,
since every panel it draws is the game's own artwork.

Panels are drawn at the game's own pixel coordinates from its UI records — the equipment doll, both
mastery trees, the devotion sky — and are never scaled up, only shrunk to fit a narrow window. The
equipment panel carries the game's own weapon-swap button where the game puts it, and a character in the
box the game renders its model in. Clicking that character — which is also what the tab opens on — reads
the sheet into the sidebar: the attributes, the pools, the combat stats and the resistance grid, with
Armor Rating opening the same region-by-region account the game's popup gives.
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
- the game's Physical panel line for line: physical and pierce modifiers, bleeding and internal trauma
  with the total-damage bonus folded in, and life steal;
- attack speed, run speed and attacks per second, which read as results rather than bonuses;
- every figure of the Pet Bonuses panel, the rolled resistances included;
- every rolled figure on the items checked against their tooltips, bands included.

`StatCatalog` is the whitelist of `.dbr` fields the app understands. A stat absent from it is read from no
record and shown nowhere; adding one means adding its definition.

Clicking a figure opens what feeds it — every item, component, skill, set, constellation and the
difficulty's own penalty. The blanket bonuses are in that list under the stat they lift, which is the only
way a fire resistance of 126 reads as −50 from Ultimate and +176 elemental rather than as a bare −50.

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

**Two blanket-bonus rules are inferred**, both in `StatComposition`: flat elemental damage counts as that
much of each of fire, cold and lightning, and the elemental percentage does not reach an elemental damage
over time. The game's Fire panel settles the second — Burn should read +446% rather than +599% for the
character checked here.

**Whether Nemesis is the right tier around −12000.** The band runs from the floor at −20000 up to −8000,
which follows from reading `factionValueN` as lower bounds — consistent with 25000 being both the Revered
threshold and the cap. If the game shows *Hated* there instead, the boundaries are upper bounds and
`CharacterBuilder.tier(for:thresholds:)` is inverted.

## Cosmetic gaps

- `elementalinfusion1` has modifiers but no `skillConnectionOn` list, so its branch is not drawn.
- Two factions point at `faction_user3.tex`, which the game ships as a blank white placeholder.
- The doll's centre box shows the character's class artwork. The game renders its 3D model there, which
  the app has no way to pose, so the mastery the most points went into stands in for it.

## The monster listing

Every named monster in the game, filtered by rank, by faction and by whatever is typed. A monster is read
at a level, since everything it has is an equation of one, and the sidebar opens on the level the
character is: what it is worth in a fight, its attacks with their ranges and timings, its passives, and
what it carries in each equipment slot with the odds of each. Its whole stat sheet is far more than a
sidebar holds, so **All Stats…** opens it in a window of its own.

A monster's stats are what its record states, what its equations produce at that level, what its permanent
skills add, and the adjustment the difficulty lays over every enemy. **Checked against GrimTools' monster
database**, which reads the same records: Ravager of Minds at level 100 on Ultimate agrees to the unit on
its attributes, health, energy, both abilities, armour and all ten resistances. `MonsterStatsTests` pins
those figures; it needs the installed game, so it reads `GRIM_DAWN_FOLDER` from the environment and skips
without it.

The listing shows a monster's race rather than its faction: a record's faction is a pack it counts as for
hostility and reputation, and most creatures carry the Aetherials' whatever they are made of. A nemesis
names its own faction — Kubacabra reads as the Beasts' nemesis — because the faction pack is what says so. Records that share a name and
differ in what they hold stay as separate lines — three Ravagers of Minds
are three different fights — with the record's own file name to tell them apart. Copies that a region
merely repeats collapse into one.

## The models

`Mesh` reads the game's `.msh` models and `Render` draws them, both packages of their own.
[GameData.md](GameData.md#the-model-format) has the format. Every one of the 782 models the monsters name
reads and renders; `render-monsters` writes the lot as PNGs with a transparent background in about twelve
seconds:

```sh
cd Render && swift run -c release render-monsters "<game folder>" <output> --size 512
```

`SceneConfiguration` is the whole look — where the camera stands, how bright the rig is, whether there is
a background and a floor at all. The app draws the same scene live rather than from a picture: the
monster sidebar and the model tab of its window hold a SceneKit view, which is a drag to turn and a
scroll to move in.

**A human NPC renders as a head.** Their record names the head alone, and the game dresses the rest from
the equipment it wears; nothing here assembles that. Animations are not read at all — the `.anm` files
beside the models are a format of their own.

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
total the sheet counts. A line naming a worn piece opens it on the doll; a set bonus is no single item's,
so it stays a line.

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
