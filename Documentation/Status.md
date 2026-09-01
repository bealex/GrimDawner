# Where the app stands

## Working

The save parser consumes a current save exactly. Names and icons for items, skills, factions and
constellations resolve from the installed game's data. Eight tabs render — Inventory, Items, Affixes,
Skills, Devotions, Stats, Optimizer, Monsters — each with a detail sidebar and the shared quick search, which starts
on the first keystroke rather than from a field in the toolbar. The app runs dark whatever the system is set to,
since every panel it draws is the game's own artwork.

Panels are drawn at the game's own pixel coordinates from its UI records — the equipment doll, both
mastery trees, the devotion sky — and are never scaled up, only shrunk to fit a narrow window. The
equipment panel carries the game's own weapon-swap button where the game puts it, and the character's own
model in the box the game renders it in. Clicking that character — which is also what the tab opens on — reads
the sheet into the sidebar: the attributes, the pools, the combat stats and the resistance grid, with
Armor Rating opening the same region-by-region account the game's popup gives.
[GameData.md](GameData.md#window-layouts) says which record holds what.

## The stat engine

**A figure and its band read as one number.** An item nobody owns has no roll to show, only the band
each figure rolls in. A minimum and a maximum are two ends of one number: ends that roll alike make one
band, ends that roll apart make one span. [GameData.md](GameData.md#the-item-randomiser) says why so
much of the game's damage has a minimum and nothing else.

**A stat line leads with its figure**, the way the game's own tooltips word a bonus: `+86% Aether Damage`,
not `Aether Damage +86%`. The name takes the slack after it, and whatever qualifies the figure — the band
an item's roll came from, how much of a resistance stands over the cap — sits at the end, with the damage type's mark and whatever
symbol stands for the line. Every line finds that mark and that colour from its own name, so a type reads the same
wherever it appears; a conversion wears the mark of what it turns into, since that is what you end up
dealing.

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

[Coverage.md](Coverage.md) is the field-by-field audit: every property on an item, monster, skill or
devotion record, and whether anything reads it.


**The damage panel.** *Fire Damage 50*, *Aether Damage 9118–9993* and *Damage Per Second* combine the
weapon's own damage range with conversions, flat bonuses and the percentages. The app shows the flat
damage a character adds and the percentage it is raised by — both exact — but not the weapon figures they
feed. The Interaction tab does carry `weaponDamagePct` through to a skill's damage; the sheet's own panel
does not.

**Flat damage reads as its floor.** The game writes a flat bonus as a minimum with no maximum and a range
as both, and the two keys are summed apart, so a build whose flat bonuses outweigh its ranged ones ends
with a maximum below its minimum — 208 against 99 for aether on the character checked here. Recovering
the real spread means pairing them per source in `ItemRoll`; until then the top is clamped never to read
under the floor.

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

**Which damage band a swing lands in.** The record states the six thresholds and their multipliers but
not how the roll picks between them, and the published sources disagree. The app reads the roll as even
across the pairing's hit figure. Settling it needs the binary.

**What the game scopes a monster's per-type damage modifier to.** The Dread's `offensivePhysicalModifier`
comes to −107% at level 100 and would leave a boss hitting for nothing, so the app uses only the
creature-wide `offensiveTotalDamageModifier`. Leaving it out is incomplete; applying it is wrong.

**A monster's damage against a reference.** `MonsterStatsTests` pins Ravager of Minds' health, attributes,
abilities, armour and resistances to GrimTools, which is the only reference there is. GrimTools' monster
database returns 403 to fetching, so nothing pins a monster's *damage* — the one figure that would settle
whether the interaction numbers are right.

**Whether Nemesis is the right tier around −12000.** The band runs from the floor at −20000 up to −8000,
which follows from reading `factionValueN` as lower bounds — consistent with 25000 being both the Revered
threshold and the cap. If the game shows *Hated* there instead, the boundaries are upper bounds and
`CharacterBuilder.tier(for:thresholds:)` is inverted.

## Cosmetic gaps

- `elementalinfusion1` has modifiers but no `skillConnectionOn` list, so its branch is not drawn.
- Two factions point at `faction_user3.tex`, which the game ships as a blank white placeholder.

## The monster listing

Every named monster in the game — 2,108 lines, filtered by rank, by race and by name. A monster is read at
a level and a difficulty because everything it has is an equation of both, and it opens on the
character's own; the sidebar gives what it is worth in a fight, its attacks with their ranges and timings,
its passives, and what it carries in each equipment slot with the odds of each. Double-clicking a line, or
**All Stats…**, opens it in a window with tabs for the sheet, the attacks, the loot and its model, and its
own type-to-search over all of them.

**The figures agree with GrimTools' monster database**, which reads the same records: Ravager of Minds at
level 100 on Ultimate matches to the unit on its attributes, health, energy, both abilities, armour and
all ten resistances. `MonsterStatsTests` pins those; it needs the installed game, so it reads
`GRIM_DAWN_FOLDER` from the environment and skips without it.

Getting there took three facts no record states outright: the difficulty lays one adjustment over every
enemy, both abilities run through the game's combat equations rather than being read, and the celestial
bosses carry a skill that cancels the game's ascendant-mode bonus.
[GameData.md](GameData.md#monsters) has them.

A line shows a monster's **race**, not its faction: a faction is a pack a creature counts as for hostility
and reputation, and most carry the Aetherials' whatever they are made of — 266 of the 405 beast-race
records do. A nemesis names its own faction, because the faction pack is the record that says so, and
Kubacabra reads as the Beasts' nemesis. Records that share a name and differ in what they hold stay as
separate lines — three Ravagers of Minds are three different fights — with the record's own file name to
tell them apart; copies that a region merely repeats collapse into one.

Most of what a monster fights with has no name: 442 skills carry one and some 3,500 do not, so a line
reads by what its record class is — *Auto attack · Weapon attack · close up · every 2s*. A named skill
shows its own description, and what a skill summons is named inside it and opens as a monster of its own.

## The models

`Mesh` reads the game's `.msh` models and `.anm` animations, `Render` draws them, each a package of its
own. [GameData.md](GameData.md#the-model-format) has both formats, which are undocumented and were worked
out here. Every model and every animation the game ships reads; `render-monsters` draws the whole roster —
each monster dressed in the gear its record puts on it — as PNGs with a transparent background in about
half a minute:

```sh
cd Render && swift run -c release render-monsters "<game folder>" <output> --size 512
cd Render && swift run -c release render-monsters "<game folder>" <output> --animations
```

`--animations` writes an animated PNG per attack instead, in a folder per monster: a GIF cannot say
*transparent* about part of a pixel, and these are drawn against nothing. One picture is drawn per monster
that is drawn differently — 1,990 of the 2,115 records, since a region's own copy of a monster is the same
picture. `SceneConfiguration` is the whole look: where the camera stands, how bright the rig is, whether
there is a background and a floor at all.

The app draws that same scene live rather than from a picture — the monster sidebar, the model tab of its
window, and a window of its own, each a drag to turn and a scroll to move in.

**An attack is picked as one thing.** The model menu lists the creature's attacks above its raw animations,
and picking one plays the animation that attack asks for *and* shows what its skill throws. A second menu
shows any one skill's effects on their own, which is how a passive's aura is looked at, and playback runs
at full, half or quarter speed — which is what makes a two-frame difference between two casts readable.
Along the top is what the animation calls out and when: each effect it spawns, and the frames a blow lands
on.

**A creature is assembled and then posed.** Every part is skinned to a rig merged from all of them — a
head, a body and a breastplate each carry their own copy of the same bones — so a shoulder moves the
pauldron on it. Each part is skinned against **its own** bind pose, though: the copies do not always agree,
and 148 of the 432 assembled monsters hold a part whose bones stand somewhere else. What plays is the
unarmed set of the creature's table, since the animations that hold a weapon pose a hand around one.

**A monster holds what it is meant to be holding.** No record says which weapon that is — only which
tables it draws one from — so one is rolled the way the game weighs those tables, from a stream primed with
the creature's own record path: the same monster keeps the same axe between launches, and two monsters
drawing from one table rarely hold the same thing. A two-handed weapon fills both hands. Of the first 300
records meant to carry something, 298 are drawn carrying it.

**Much of the roster is not a creature.** *Blizzard* and *Cave-In* are weather with a health bar, *Floor
Spikes* are a floor, *Warding Totem* is a totem. The listing badges each one and filters by kind;
[GameData.md](GameData.md#what-a-monster-actually-is) says how the game states it.

**A phased boss is several monsters.** The stages of one fight are chained through `poolToSpawnOnDeath`,
and each is its own line — *Ixall, Phantom of the Korvan Wastes (Phase 1)* and *(Phase 2)* are a different
model, different skills, and loot on the second alone.

**An effect is drawn the size the game says it is.** `skillTargetRadius` for an area skill, `waveDistance`
for a wave. The reach spreads the drift instead of inflating one spark, so a nova covering seven units is
many sparks over that ground while a hand's flash stays a hand's flash. A wave sweeps forward from the
point it hangs on. Where nothing states a size, the creature's own is used.

**The character is a creature like any other.** The doll's centre box holds the player's own model,
assembled the same way a monster is, and dressed in what the character is actually wearing: a default
piece fills a slot only where nothing is worn. The weapons are the set the doll is showing, so the swap
button changes hands, and what plays is the idle the game's own character window plays for the way those
hands are full. [GameData.md](GameData.md#the-players-own-creature) has the records behind all of it.

**The camera turns with the head.** An animation faces wherever the game had the creature facing, which is
rarely the bind pose, so a camera that holds still watches it from behind. How far the head has turned is
added to the camera's own angle — the head rather than the body, because a fighting stance twists the hips
22° and the shoulders 45° while keeping the head on the enemy, and following the shoulders points the face
away. A creature with no head bone is measured by the turn that best carries its whole bind skeleton onto
the posed one.

**An effect drifts rather than hangs.** Only the picture is the game's: particles rise and fade from the
point the effect hangs on, and the drift is this app's. Particles need a view that keeps drawing, so an
offline render holds the picture still instead — `SceneConfiguration.emitsEffects` says which.

**Three readings of a key were measured rather than eyeballed**, each hidden behind the one before it and
each plausible in a still. [GameData.md](GameData.md#animations) has them; what pins them here are tests
that state what a body cannot do — a knee does not bend forwards, a bone does not lengthen, a spine does
not turn 90° in a thirtieth of a second.

**What is not drawn.** The particles themselves, which are a format of their own, and an effect that names
a model rather than a particle system. The travel a key carries, so a walk plays on the spot. And nothing
blends one frame into the next, so a loop restarts rather than easing round.

**A sweep is paid for once.** Anything worked out from the whole record tree — which records are phases
of one fight, which creature the player is — costs the better part of a second, and the answer holds for
as long as the game is installed. The database keeps it, and it is warmed off the main thread when the
database loads, so picking a monster costs 3 ms rather than 740.

**What an item does to a skill reads as one block.** An item can name the same skill several times over
— ranks from its base record, an enhancement from an ascendant affix, another from a component — and the
sidebar gathers those under the skill rather than listing them apart. The block is the skill's name and
artwork, what sets it off, what it does, the ranks added, what the item changes about it, and its own
numbers; a component describes its skill the same way an item does. What the character can actually use
comes first, and a rank or an enhancement aimed at a skill nobody has spent a point on reads faded, since
that is exactly what it is worth.

## One item in full

Double-clicking an item — on the doll or in the directory — opens it in a window with three tabs.
**Item** is what the sidebar shows. **Loot** is every monster that can drop it, with a switch that tells
the ones worth hunting from the ones whose tables merely reach the thing. *Aether Cluster* comes off an
Aetherial Sentinel a quarter of the time; a legendary has sixty-five sources and not one of them above a
hundredth. [GameData.md](GameData.md#who-drops-an-item) says why answering this costs a walk of the
whole roster and how the answer is kept.

**Affixes** lists what the item can roll and shows what it becomes. Picking a prefix and a suffix builds
the item the way the game builds a dropped one and reads it back, so the panel is the real thing rather
than two lists added together. Every figure reads at the bottom of its band, which is what the item is
sure to carry. [GameData.md](GameData.md#which-affixes-an-item-can-roll) has where the pool comes from.

## Character against monster

The monster window's **Interaction** tab reads one of your characters against the monster in front of it.
The two sides sit side by side — what your swing lands on it, what its swing lands on you — with what
each takes off the other underneath. Every figure is the game's own arithmetic out of
`combatformulas.dbr` at the monster's own level and mode;
[GameData.md](GameData.md#the-fight-itself) has the equations.

Both sides show the chance to hit and to crit, what a blow lands at its hardest, what it averages over
misses and bands, and what that comes to over a second. A blow bigger than the whole of your health is
called out as a one shot. Each card carries a picker: yours chooses which of your attacks to read,
starting on the weapon attack, and the monster's chooses which of its attacks it swings back with, since
a boss carries six and they are not close in what they throw.

**Rates are per attack, not per weapon.** A beam, cone, drain, tether or spin ticks at its own
`timeBetweenAttacks` — Albrecht's Aether Ray at 300ms and cast speed — while a charge or a growing radius
ticks that fast within one use and is governed by its cooldown instead. A cooldown shorter than the swing
means the skill is always ready, not that it is thrown faster.

**Buffs and Nerfs** sits beside the attack picker. Passives, auras and transmuters are already in every
figure and are listed in a card so you can see which. What a save cannot know is which timed buffs were
up and which of the monster's debuffs had landed, so those are checkboxes: your own self-buffs on one
side, and on the other everything the monster leaves on you — Sundered, and its reductions to your
abilities and damage. Only the strongest of each kind counts.

**Mode covers Ascendant.** It is not a difficulty the save records but a second adjustment over Ultimate,
and it roughly doubles a boss's health and triples its damage.

**What is still one attack at a time.** The monster's combined figure reads its own attack at full rate
plus each special at its stated chance once per its timeout. That is an estimate: the record says how
often, not in what order. Your side is not combined at all. No pets, no devotion procs, no damage over
time — Reap Spirit's pets fight for eighteen seconds and count for nothing.
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

**Items.** 9,424 lines from 26,196 records, the rest being loot tables, affixes and the proxies and pools
that carry no name. Gear is every `Armor*` and `Weapon*` class; every other class that names something
joins it under a word a player would use rather than the record's own — `ItemRelic` is a **Component**,
`ItemArtifact` a **Relic**, `ItemEnchantment` an **Augment**, `ItemArtifactFormula` a **Blueprint** — and
the three crafting ones get a rarity of that name so both filter menus offer it. None of those three
carries an `itemNameTag`: their name is the `description` tag. Troves and destructibles are listed too and
named as what they are: world objects rather than things carried, and the only entries without artwork,
since they hold model textures rather than an inventory icon. Records that duplicate one
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

## The optimizer

Thirteen sockets, each taking one of a few dozen components and one of a few dozen augments, come to
roughly 10^39 combinations, so the search does not enumerate. It is coordinate ascent under a rising price
on falling short: every socket's component and every socket's augment is one coordinate, a sweep takes each
one's best option with the rest held still, and the price on a missing point of resistance climbs each
round until nothing is short. Eight runs per goal from different starting points, every goal concurrent.
Doubling the budget returns the same plans, which is the only evidence there is that it has settled.

Ranking uses a reduced set of figures rather than a built character, since building one for each of the
hundreds of thousands of combinations would take days. That makes the arithmetic a second telling of the
sheet's, so `LoadoutOptimizerTests` pins the two together: read the character's own fittings back through
the evaluator and every figure must be the sheet's. None of it reaches the screen. The app sockets a
finished plan into a copy of the save, rebuilds it through `CharacterBuilder`, and shows that sheet.

**What it does not count.** The game draws a component's completion bonus at random from its own table,
so no plan can promise one and none is counted: every figure is the least the plan is worth. Skill ranks
stay at what the character has now, so a fitting granting +1 to a mastery gets no credit for what that
rank would unlock. Folding that in would mean re-levelling every mastery per combination.

**What "on max" means.** Each resistance targets the character's own maximum as it stands, plus whatever
overcap is asked for. A fitting that raises a cap costs nothing for doing so, and the plan reports the
final maximum beside what it reached.

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

Drawing a model costs about 15 ms, which is why the app renders one live rather than caching a picture of
it.

The Debug build is much slower than Release for the decode paths; hand testing should use Release. The
tests need neither: `_scripts/test.sh` runs all three packages' suites, and the engine's own finish in
about 20 milliseconds.
