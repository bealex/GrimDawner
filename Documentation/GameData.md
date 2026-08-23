# Reading the game's own data

Everything the app knows about Grim Dawn it reads at runtime. This is where each fact lives.

## Archives

| File | Holds |
| --- | --- |
| `database/database.arz`, `gdx1..3/database/*.arz`, `survivalmode*/database/*.arz` | every `.dbr` record |
| `resources/Text_EN.arc` and each expansion's | `tag* = display string` |
| `resources/UI.arc` and each expansion's | skill, devotion and faction art |
| `resources/Items.arc` and each expansion's | item art |

Load order is base then gdx1, gdx2, gdx3; **later wins**. `GameDatabase` searches its databases in reverse
so the first hit is the winning override, and `TextureStore` searches the newest expansion's archive first.

Record paths are lowercase and are matched that way.

### `.arz`

24-byte header: `u16 magic` (2), `u16 version` (3), `u32 recordTableStart`, `u32 recordTableSize`,
`u32 recordCount`, `u32 stringTableStart`, `u32 stringTableSize`.

String table: `u32 count`, then `u32 length` + bytes each.

Record table row: `u32 nameId`, `u32 classLength` + bytes, `u32 offset`, `u32 compressedSize`,
`u32 decompressedSize`, `u64 filetime`. The offset is relative to the end of the 24-byte header.

A record's payload is an LZ4 block. Decompressed it is a stream of `u16 valueType`, `u16 valueCount`,
`u32 keyId`, then `valueCount` raw `u32`s. Types: 0 int32, 1 float32 (bit-reinterpret), 2 string (index
into the string table), 3 bool.

**Many fields are arrays indexed by skill rank.** `SkillResolver.stats(of:atLevel:)` exists for that; a
rank-12 aura and a rank-1 aura read different elements of the same field.

### `.arc`

28-byte header: `u32 "ARC\0"`, `u32 version` (3), `u32 fileCount`, `u32 partCount`, `u32 partsTableSize`,
`u32 stringTableSize`, `u32 footerOffset`.

Footer, in order from `footerOffset`: parts table (12 bytes each: offset, compressed, decompressed), string
table, then the TOC (44 bytes each).

TOC entry, at these offsets: 28 `partCount`, 32 `firstPartIndex`, 36 `nameLength`, 40 `nameOffset`. The
64-bit file time at 20 is **not** aligned to 24 — getting that wrong shifts every field by four bytes.

A part is stored raw when `compressedSize == decompressedSize`, otherwise it is an LZ4 block.

Text files inside are `key=value`, CRLF. Split on `\.isNewline`, never on `"\n"` — Swift treats CRLF as one
grapheme, so `"\n"` never matches and the whole file reads as a single line.

### `.tex`

Twelve-byte wrapper — `"TEX"`, version byte, `u32`, `u32 payloadSize` — around a DDS whose magic reads
`DDSR`, not `DDS `. Nearly every icon is uncompressed 32-bit in **B, G, R, A** byte order; some are 24-bit
BGR; a handful are BC1 or BC3.

Texture paths in records name their archive in the first path component: `ui/skills/...` lives in `UI.arc`
as `skills/...`, `items/...` in `Items.arc` as `...`.

Sizes to expect: skill icons 32×32, item art 32×32 to 32×96, faction icons 24×24, constellation art around
430×171, class illustrations 640×605.

## Where each fact comes from

| Fact | Record |
| --- | --- |
| Attribute → health/energy conversion, points per level | `creatures/pc/playerlevels.dbr` |
| Base pools, base OA/DA, base attributes | `creatures/pc/malepc01.dbr` / `femalepc01.dbr` |
| OA/DA equations, damage scaling, hit-region chances | `game/combatformulas.dbr` |
| Armour absorption base (70), mastery tier levels | `game/gameengine.dbr` |
| Faction order, tier boundaries, vendor discounts | `game/gamefactions.dbr` |
| Resistance penalty per difficulty | `game/balancingadjustment_mp+difficulty_players01.dbr` |
| Item rarity colours | `ui/styles/text/style_items*.dbr` |
| Skill panel geometry | `ui/skills/classNN/classtable.dbr` → each button's `bitmapPositionX/Y` |
| Constellation membership, affinity, art | `ui/skills/devotion/constellations/constellationNN.dbr` |
| Equipment doll boxes | `ui/character/character_mastertable.dbr` → `equip*` |
| Devotion sky | `ui/skills/devotion/devotion_mastertable.dbr` |

### Names

- Items: `itemNameTag`, else `description`, else `FileDescription`. The game prefixes that with the item's
  quality and style — `itemQualityTag`, then `itemStyleTag` — which is where *Mythical*, *Empowered* and
  *Elite* come from (`tagStyleUniqueTier3` reads "Mythical"). Without them the endgame version of a unique
  is indistinguishable from the one that drops at level 20.
- Affixes: `lootRandomizerName`. Ascendant affixes have no name of their own — use the skill named by
  `modifiedSkillName1`.
- Skills: `skillDisplayName`; if absent, follow `buffSkillName` or `petSkillName` and read it there.
- Localised strings carry inline colour codes: a caret followed by one letter, as in `^kPrismatic Diamond`.
  `GameDatabase.localised` strips them.

### Item parts

`bitmap`, or `artifactBitmap` for relics, or `relicBitmap` / `shardBitmap` for components. Prefixes,
suffixes and ascendant affixes have **no artwork in the game either** — they are text-only.

`+N to skills` comes from `augmentSkillName1..8` / `augmentSkillLevel1..8`, `augmentMasteryName1..4` /
`augmentMasteryLevel1..4`, and `augmentAllLevel`. A granted ability is `itemSkillName`, whose rank is
`itemSkillLevel` or the formula in `itemSkillLevelEq` (evaluate with `Equation`).

### Window layouts

Every panel the app draws is the game's own, at the game's own pixel coordinates.

**The equipment doll.** `character_mastertable.dbr` names one item box per slot (`equipHead`, `equipNeck`,
… `equipHandLeft` for the off hand, `equipHandRight` for the main hand). Each box record gives `itemX`,
`itemY`, `itemXSize`, `itemYSize` and a `silhouette` texture for when it is empty. The same table names
the weapon-swap button (`equipSwap1LeftButton`, positioned and drawn like any other button, with its two
rollover lines under `equipSwapButtonRollover`) and `characterView`, the scene the game renders the
character's model in — a rectangle at 111, 95 sized 177 × 273, with a backdrop texture.

The boxes are laid out inside the top-left corner of `characterDisplayInspectBitmap` rather than
`characterDisplayBitmap`: both textures hold the whole character window in one image, and the two draw
the same panel, but the inspect window closes it off at the bottom where the character window puts its
gold display. Neither draws the frame down the panel's right edge, since the bag grid abuts it there, so
the app mirrors the left strip onto it.

**A mastery panel.** `classtable.dbr` gives the panel background, the class artwork, the mastery bar and
its position, and `tabSkillButtons`. A button record carries `bitmapPositionX/Y` (its top-left),
`bitmapNameUp` (square for a skill, round for a modifier) and `skillOffsetX/Y` (where the icon sits inside
that border). `skills_classpanelconfiguration.dbr` holds the rank-text box and the colours a rank is
printed in; `gameengine.dbr`'s `skillMasteryTierLevel` holds the nine milestone levels printed under the
bar.

**The devotion sky.** `devotion_mastertable.dbr` gives its size (7168 × 6144, centred on the origin), the
star-field tile, the five nebula sections, the connector textures and width, the affinity icons, and
`devotionConstellation1..110`. A constellation record gives its artwork and position, `devotionButton1..12`
(a star each, positioned the same way as a skill button), `devotionLinksN` (the star that star hangs off,
counting from one), the affinity it grants and requires, and the three tints — active, available,
unavailable — the window paints it in. A star's skill record tells the rest: `Skill_Passive` is a plain
star, anything else is the constellation's celestial power.

### Skill tree connectors

A skill record's `skillConnectionOn` / `skillConnectionOff` is a list of 78×80 tile textures, one per
80-unit step to the *right* of the skill. The tile's file name says what that step is: `center` a plain
run, `branchup` / `branchdown` where a branch leaves the row, `transmuterstub` the tail of that branch.

So the horizontal run reaches `(number of non-stub tiles) × 80`, and each branch tile marks a vertical at
`(step + 1) × 80` going to the row 32 units above or below. Modifiers sit on the **same row** as their
parent; transmuters sit 32 units off it.

Not every parent has the field — `elementalinfusion1` has modifiers but no connector list, so its branch
simply is not drawn.

## The item randomiser

An item's numbers are rolled from its 32-bit save seed, not read from the record. `ItemRoll` primes
MINSTD (Park-Miller, `16807 * s mod 2^31 - 1`, by Schrage's method) with the seed and walks a fixed order
of stores — character, flat damage, damage modifiers, leech, offensive, retaliation, defence, conversion,
skill — drawing as it goes. Because the stream is shared, a stat's value depends on every stat drawn
before it, so a field the app does not draw for throws off every later one. The order and the per-store
mechanics come from [marius00/GrimDawnItemStats](https://github.com/marius00/GrimDawnItemStats); nothing
in the shipped data describes them. Five rules it does not model, each confirmed against a tooltip:

- **The blacksmith's bonus draws in the item's own stream**, at its field's natural place — the medal's
  `defensiveBlockAmountModifier` draws at the head of the defence store, so every resistance after it
  shifts. Prefix, suffix and crafting bonus are one stream with the base.
- **A relic ignores the crafting bonus its save entry names.** Agrivix's Malice stores `ac01_health`
  and the game shows no Health line; rolling it moves every other figure off.
- **`retaliationFearMin` draws** where the other retaliation damages do.
- **A racial bonus never draws.** Two items carrying identical `racialBonusRace` and
  `racialBonusPercentDamage` fields prove it: the relic's figures only match when it takes no draw.
- **A chance is a value, not a field.** A damage line whose source gives it a chance is a proc of its own
  rather than part of the total — but records declare `…Chance` whether or not they use it, so the figure
  decides. Reading the field's presence instead drops a weapon's own damage from every item that carries
  an affix.

**A pet bonus rolls in a stream of its own.** `petBonusName` on an item, its prefix or its suffix names a
record of what every pet is given; each rolls from the item's seed in its own stream, so the block neither
takes draws from the item's own figures nor gives them any. `characterTotalSpeedModifier` there raises a
pet's attack, cast and run speed together.

`characterManaRegen` is read straight from the record and takes no draw, as `ItemRoll.fixedFields` says.
A component and an augment do not roll at all — the game prints their figures without a band — and a
weapon's own damage is written rather than rolled.

Verified against the game's own tooltips: for the test character all ten resistance totals, energy, and
every rolled figure on the hat, ring, medal, relic and wand match exactly. Health, Offensive and Defensive
Ability match once truncated, which is what the game prints.

## Rules the engine encodes

**Health and energy.** `playerlevels.dbr` gives health per point of Physique (20), Cunning (8) and Spirit
(12), energy per point of Spirit (16), and 8 attribute points per allocation. Per *unit* of attribute that
is 2.5 / 1.0 / 1.5 health and 2.0 energy. The save's `biography.health` and `.energy` already hold the pool
the character's own allocations produce — this was checked against a real save and reproduces the stored
value exactly — so gear and mastery attributes add on top of it, never instead of it.

**Armor Rating is an average, not a sum.** Each of the six armour slots is a hit region with its own
chance of being struck (torso 26, legs 20, head 15, shoulders 15, arms 12, feet 12, summing to 100). The
rating is the weighted mean. Armour from belts, jewellery and skills is added to *every* region, so it
survives the weighting intact. The game states this itself in `tagCharStatsArmorTotalDescription`. Summing
overstates it several times over. The figure the game prints against a region is that region's own armour
and the shared armour together, with `defensiveProtectionModifier` over both: a head carrying 1149 with 108
shared and +20% reads as 1508.

**A component's bonus armour belongs to its own piece.** `defensiveBonusProtection` — the 35 armour a
Scaled Hide adds — lands on the hit region of the item it is socketed in, not on every region the way
armour from a belt or a skill does. The game's per-region breakdown is what says so: two Scaled Hides on
the shoulders and legs raise exactly those two regions.

**Absorption multiplies.** "Increases Armor Absorption by X%" scales the base 70%, capped at 100 — the same
wording, and the same behaviour, as "Increases Armor by X%".

**Blanket bonuses fold into every figure they reach**, and the figure never names them. A resistance takes
`defensiveAllResistance`, and fire, cold and lightning also take `defensiveElementalResistance`; a maximum
resistance takes `defensiveAllMaxResist`; a damage percentage takes `offensiveTotalDamageModifier`, the
elemental three taking `offensiveElementalModifier` as well; a damage-over-time percentage takes the
total-damage bonus too — the game's own panel reads +100% Bleed for +65% bleeding and +35% total damage.
`StatComposition` holds these rules, and both the sheet and its breakdowns read them, so a figure and the
sources behind it can never disagree. Flat elemental damage counting as that much of each of the three, and
the elemental bonus not reaching an elemental damage over time, are inferences rather than readings.

**Displayed damage percentages exclude attribute scaling.** `tagCharStatsPhysicalPercentDmgInfo` says so
outright. Cunning and Spirit still scale damage in combat; they are simply not in this number.

**Difficulty costs resistance.** `balancingadjustment_mp+difficulty_players01.dbr` holds the penalty as an
array of four party sizes per difficulty, so Ultimate single-player reads the ninth entry: −50% fire, cold,
lightning, pierce and poison, −25% aether, chaos, vitality, bleeding and life leech resistance. The game's
own character window shows the penalised number, and without it a character on Ultimate reads far too well.

**A skill counts on the sheet only while it is in effect** — record classes `Skill_Passive`,
`SkillBuff_Passive`, `Skill_BuffSelfToggled`, `Skill_BuffRadiusToggled`, `Skill_BuffAttackRadiusToggled`
and `Skill_Transmuter`. Attacks, timed buffs and celestial powers do not, and neither does
`Skill_PassiveOnLifeBuffSelf`, which waits for low health. A `Skill_Modifier` counts when the skill it
hangs off does — the panel states which that is, by putting the modifier along its parent's row. A skill
that keeps its numbers on the buff it drives is read there as well as on itself.

**Resistances** are summed, with `defensiveElementalResistance` applying to fire, cold and lightning, and
`defensiveAllResistance` to everything except physical. Cap is 80 plus `defensive*MaxResist`. Bleeding is a
resistance with no matching damage type, which is why `ResistanceKind` exists separately from `DamageType`.

**`+skills` cap at a skill's ultimate level.** A one-point transmuter stays at one however much `+skill`
the character wears. Read effect values at the clamped rank.

**An item's own skill says what sets it off.** `itemSkillAutoController` names a controller record
holding `triggerType`, `chanceToRun` and, for the two thresholds, `triggerParam`. The game's wording for
the pair is `tagAutoSkillConditionNN` — "(25% Chance on Attack)", "(100% Chance at 50% Health)". Which tag
goes with which trigger is the one thing the data does not state: the template lists the triggers in the
engine's order (`OnEquip;OnKill;LowHealth;…`) and the tags run in another, so `SkillTrigger` pairs them by
what each says. A component's always-on skill names no controller and reads without a condition.

**An item that changes a skill names both halves.** `modifiedSkillNameN` is the skill it changes and
`modifierSkillNameN` a `Skill_Modifier` record holding what it changes — flat damage, a conversion, a
cooldown. Those paths are the same ones the mastery panel's buttons use, so a change matches its skill by
record path. A change to a summon or a mine is a `SkillSecondary_PetModifier`, which keeps its numbers one
step further on, at `petSkillName`.

**An item wears a badge for what it is.** `ui/character/item_monsterinfrequent.tex`,
`item_doublerare.tex`, `item_doubleraremonsterinfrequent.tex`, `item_awakened.tex` and the
`item_ascended_*` family are 32×32 marks the game stamps on an item's slot. A monster infrequent is a
gear record whose own `itemClassification` is `Rare`; a double rare is an item whose prefix and suffix
are both rare-classified; an awakened item sits under `records/items/awakened/`. Which mark goes with
which item is decided in the engine and stated nowhere in the data, so `ItemQualityMark` follows the
texture names. `itembackground.tex` and `itembackgroundlegendary.tex` are 64×64 slot backgrounds rather
than marks.

**A skill that only drives a buff states no ranks of its own.** Its `skillMaxLevel` is zero and the buff
it names carries both the ceiling and the per-rank arrays. Reading the ceiling from the skill alone pins
such a skill at rank 1 however many points and `+skill` bonuses it has — Iskandra's Elemental Exchange at
rank 8 grants 66% elemental damage against 10% at rank 1.

**Speeds are printed as results, not bonuses.** `gameengine.dbr` states what a player may reach —
`playerRunSpeedCapMax` is 135, `playerAttackSpeedCapMax` 200 — and the weapon's `characterBaseAttackSpeed`
scales the total: a hundred plus every bonus plus `characterTotalSpeedModifier`, times the weapon's own
rate, clamped. A wand at −0.1 with +25% attack speed and +11% total speed reads 122%.

**Regeneration.** `tagCharStatsEnergyRegenInfo` states the shape: percent bonuses apply to what gear and
skills give, not to the base, which comes from an attribute — spirit for energy, physique for health. The
rate per point is not in the records.

**Factions.** Only records with `questEnabled` are reputations the player earns; the rest are the engine's
hostility groups and the game's faction window never lists them. Eight tiers, from
`factionValueN` / `factionTagN`, with `factionMarketDiscountN` confirming the alignment:

| From | Tier | Vendor |
| --- | --- | --- |
| 25000 | Revered | −20% |
| 10000 | Honored | −12% |
| 5000 | Respected | −8% |
| 1500 | Friendly | −5% |
| 0 | Tolerated | 0 |
| −1500 | Despised | +20% |
| −8000 | Hated | +50% |
| −20000 | Nemesis | won't trade |

25000 is both the Revered threshold and the reputation cap, and −20000 is the floor, which is why a
finished character reads as Revered with nearly everything.

**No devotion star grants skill ranks** in this game version — checked across the whole database. The
devotion column of the rank breakdown is computed properly and will simply read zero.
