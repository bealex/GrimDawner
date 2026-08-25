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
`DDSR`, not `DDS `. **Mipmaps are written smallest first**, so the full-size level is the last one in the
file, not the first: read from the front and you get a montage of the small levels with the top of the
real image below them. It only shows on what carries mipmaps: 3,004 of the 3,010 icons hold a single level
and read the same either way, while 1,700 of the creature and item skins hold nine.

What a texture is differs by what it is for. **An icon is uncompressed**: 2,620 are 32-bit in **B, G, R, A**
byte order, 374 are 24-bit BGR, and 16 are block-compressed. **A model's skin usually is not**: of the
6,187 under `Creatures.arc` and `Items.arc`, 2,010 are DXT1, 1,316 DXT5, 544 DXT3 and 2,311 uncompressed
32-bit. The block size follows the format — eight bytes per 4×4 block without alpha, sixteen with — and
that is what says where one mip level ends and the next begins.

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

### Monsters

`records/creatures/enemies/**` with `Class = Monster` — 2,970 named ones. The record gives the name
(`description`), the rank (`monsterClassification`: Common, Champion, Hero, Quest, Boss, SuperBoss), the
faction record it fights for, the race the "damage to <race>" bonuses name (`characterRacialProfile` →
`tagRaceNNN`), the levels it is met between, and the experience it is worth. The same monster is written
once per region it appears in, so the listing keeps one line per name, rank and faction.

**Nothing about a monster is a number until a level is chosen.** Its pools and abilities live in the
record `characterAttributeEquations` names, as equations of `charLevel` — the Ravager's life reads
`((charLevel*195)^1.53)+50000` — and its skills are levelled the same way: `skillLevel4 = charLevel/4+1`
against `skillName4`. `Equation` evaluates both.

Its attacks are `attackSkillName` and `specialAttack…SkillName`, each with a range, a first delay and a
timeout; `dyingSkillName` is what it does as it falls. **Nearly all of them are nameless** — 442 monster
skills carry a `skillDisplayName` and some 3,500 do not — so the record's class is what says what one is:
`Skill_AttackWeapon` is a weapon attack, `Skill_AttackProjectileFan` a fan of projectiles,
`Skill_BuffRadiusToggled` an aura. `SkillKind` holds that vocabulary. Everything else in the skill list is a passive —
the game's own level adjusters among them, which is where a monster's armour, resistances and damage
scaling come from.

**Loot is per equipment slot.** `loot<Slot>Item<N>` names a table or an item and
`chanceToEquip<Slot>Item<N>` weighs it against the slot's other entries, with `chanceToEquip<Slot>` the
chance the slot holds anything at all. A `LootItemTable_DynWeight` holds `lootName1..N` and
`lootWeight1..N`, and those entries are often tables of their own, so following them three deep reaches
the items without walking the whole tree.

**A monster's `factions` is a faction pack, not what it is.** The pack — `faction_beast.dbr` and its
kin — says who that creature counts as: its standing toward every other faction, what killing it does to
a reputation, and which nemesis the faction spawns. Most creatures carry the Aetherials' pack whatever
they are made of: 266 of the 405 beast-race records do, Kubacabra among them. What a player means by "a
beast", and what the game's own "+% Damage to Beasts" reads, is `characterRacialProfile`, so that is what
the listing shows and filters by.

**A nemesis belongs to the faction whose pack names it.** `nemesisSpawn` on the pack is the only record
that says so — `faction_beast.dbr` names Kubacabra, `faction_cronley.dbr` names Fabius — and a nemesis is
written as several records, one per phase, that share a name. Reading it from the monster's own faction
field would make Kubacabra an Aetherial.

**A monster is worth far more on the deeper difficulties.**
`balancingadjustment_mp+difficulty_enemies01.dbr` lays one adjustment over every enemy, written as twelve
numbers per stat — three difficulties of four party sizes, single-player first. On Ultimate that is +580%
life, +200% energy, +10% to cunning and spirit, +50 offensive and +75 defensive ability, and resistances
besides. Nothing about a monster reads right without it.

**Twelve celestial bosses cancel the game's ascendant-mode bonus.** `balancingadjustment_ultramode_enemies01.dbr`
is what ascendant mode grants — +850% life, +165% damage — and Ravager, Callagadra, Mogdrogen, Lokarr and
the rest each hold `superboss_ascendantmodeadjustment_01`, which is that adjustment negated stat for stat.
Neither is in effect in an ordinary fight, so the app counts neither, recognising the skill by the fact
that it cancels the record rather than by its name.

**Offensive and defensive ability are equations, not fields.** A monster's `characterAttributeEquations`
gives the base of each; the game's `combatformulas.dbr` turns that, the attribute (cunning for offensive,
physique for defensive) and the level into the figure a fight uses — the same equations a character's
sheet runs. Reading the base alone understates a level 100 boss by a factor of three.

### The model format

A monster record names a `mesh` and the skin it wears, and all 3,096 of them do — 809 distinct models,
775 of them under `creatures/` and the rest borrowed from the level art, the effects and the items. The
archives hold 5,588 models between them: 510 in `Creatures.arc`, 1,534 in `Items.arc`, 3,360 in
`Level Art.arc`, 184 in `FX.arc`. Nothing in the game ships a picture of a monster — the skins are UV
atlases and the UI has no portraits — so a picture has to be rendered.

**`.msh` is Titan Quest's format, and this is what it is.** Four magic bytes, `MSH` and a version, then a
flat list of chunks — a `uint32` id, a `uint32` byte count, and that many bytes:

| id | what it holds |
|---|---|
| 10 | the bounding box, six floats |
| 4 | the vertices |
| 5 | the triangles |
| 7 | the materials |
| 6 | the skeleton |
| 3 | the attach points, as text — see [Effects](#effects) |
| 0, 8 | the source `.mif` it was built from, and the named hit boxes; neither is read |
| 2, 9, 11, 12, 13 | blocks nothing here reads: 13 is two words on every model, 2 a few kilobytes on 516 of them |

Every model carries chunks 4, 5, 6, 7, 8, 10 and 13; the rest are optional.

The vertex chunk is a format, the bytes one vertex takes, how many there are, then one word per element of
the vertex — and those words say what the vertex holds and in what order: 0 position (12 bytes), 1 normal
(12), 2 tangent (12), 3 bitangent (12), 4 texture (8), 5 bone weights (16, four floats), 6 bone indices
(4, a byte each), 7 a second texture (8), 14 vertex colour (4). Exactly six layouts appear across the
game's 5,588 models, and two of them cover nearly all: 56 bytes unskinned and 76 skinned.

The triangle chunk is a count, a group count, three `uint16` indices per triangle, and then one block per
group: **a material index, the triangle it starts at, how many triangles it covers**, a spare word, a
bounding box, and the bones it hangs off — that bone list is what makes the blocks different lengths. A
creature is two or three groups, its body and the vines growing through it, and each wears its own
material; painting them all with the first puts a plant's skin on a monster's chest.

**A vertex's four bone slots index the group's own bone list, not the skeleton** — a list of at most 27,
which is why the same vertex in two groups has to be written twice to be skinned. A slot whose weight is
zero holds 255, which is no bone at all.

The skeleton chunk is a count and then 88 bytes per bone: a 32-byte name, the run of children it claims
(the first child's index and how many follow it), and where it sits in its parent — three rows of a
rotation and then the translation, which are the transform's columns. Chaining those down the hierarchy
gives the bind pose the vertices are written in. **The order is the mesh's own**: a head, a body and a
breastplate carry the same rig in different orders, and often only part of it, so bones are matched by
name and nothing else.

The material chunk is a count, then for each material a shader path and its slots, every string written as
its length and then its bytes. **A slot's value is a path for a texture and a number for anything else** —
a specular colour, a glow strength — and nothing says which, so the pairing is: a name ending in `Texture`
takes the path that follows it. An unfilled slot is followed by the next material's shader, and pairing
that one folds two materials into one.

**Texture coordinates need no flipping.** The first row of a decoded texture is its top and the
coordinates are written to match; a model drawn upside down wears its face inside out, which is how a
wrong guess announces itself.

**Vertices are stored in the bind pose**, so a still needs no skeleton at all. Every model shares that
pose, which is why a helmet and a pair of shoulders drawn in one scene land where they belong. A weapon
does not: it carries no bones of its own and is modelled at the origin, so it is drawn as a child of the
hand bone and hangs where that hand is.

**The parts of one monster do not always agree about the rig.** A head, a helmet and a breastplate each
carry their own copy of it, and 148 of the game's 432 assembled monsters hold a part whose bones stand
somewhere else — a helmet's `Bip01 Head` a whole head's length off, a harpy's wing finger nearly two units.
The bind poses still line up as models, since each is drawn where its own rig puts it; it is only skinning
that has to know, and a part skinned against another part's bind pose comes out facing backwards.

**Every rig names its weapon bone differently**: `Bip01 R Weapon` and `Bip01 L Weapon` on anything on the
player's skeleton, `BN_RWeapon`, `Weapon_R`, `WeaponAttatch_R_0_jnt`, `Weapon_Joint_R0_0_jnt`, or a lone
`Bone_Weapon` on a creature that only ever holds one thing. The side is a token of the name rather than a
place in it, so it is read as one, and a bone with no side is the main hand's. `Weapon_R_Parent` and
`…_Parent_Fix` are rigging helpers and hold nothing. 209 of the 218 models that are meant to hold
something carry such a bone.

**A model with no vertices is a blocker**, one of the game's invisible walls — eight of them across the
archives, `loghorrean01a_blocker.msh` the only one among the creatures.

**A model wears the texture its record names**, or the one its own material names, or — when neither does
— the one beside it under the same name: `humanmale05b.msh` wears `humanmale05b_dif.tex`, and
`aetherialabomination01a_phase1.msh` falls back to `aetherialabomination01a_dif.tex`.

**What a monster wears is not what it drops.** `dropItems = 0` says a creature leaves nothing to loot,
and 294 of the first 400 armed records say it — but they still walk around holding an axe.
`chanceToEquip<Slot>` is what says a slot is filled, and the `loot<Slot>Item<N>` tables are what it is
filled from, whether or not anything of it survives the corpse. 1,056 records are meant to hold something
in the right hand.

**A weapon is a roll, not a record.** Nothing says which axe a monster carries, only which tables it draws
from, so drawing one means rolling it: entries weighed by `chanceToEquip<Slot>Item<N>`, items weighed by
their own share. A class ending in `2h` fills both hands. `WeaponArmor_Shield` and `WeaponArmor_Offhand`
are the left hand's.

**A human is assembled from what it wears.** Its record names a head and nothing else; the body is the
gear it is dressed in, which `default<Slot>Piece` names for each of Head, Shoulders, Chest, Legs, Feet and
Hands — 2,771 monster records carry them, and every human names all six. Each piece names an
`armorMaleMesh` and an `armorFemaleMesh`, and the creature's `characterGenderProfile` says which to draw;
`armorNativeMesh` stands in where a piece has one shape for both. Reading the loot tables instead is what
leaves a human as a bare head: what a monster drops is not what it is wearing.

The player is dressed the same way. `records/creatures/pc/malepc01.dbr` and its female counterpart name a
head mesh and the `defaultChestPiece`, `defaultLegsPiece`, `defaultFeetPiece` and `defaultHandsPiece` that
are the bare body — `torso_default_000-01_m.msh` and its kin, skinned with `creatures/pc/hero02_legs_dif.tex`
— which is where the game finds a character wearing nothing.

### Animations

**`.anm` is flat rather than chunked.** `ANM`, a version byte, then how many bones move, over how many
frames, at how many frames a second — 30 for every one of the 2,021 files the game ships, 1,770 of them
under `Creatures.arc`. Then one track
per bone: its name, length-prefixed, and 14 floats per frame — a translation, a quaternion, a scale, and a
second quaternion. Bones are named rather than numbered and their order is not the mesh's, so an animation
binds to a skeleton by name.

**Reading a key took three corrections, and each hid behind the one before it.** All three look plausible
in a still and give themselves away the moment something moves.

- **Its turn is both quaternions**, the second laid over the first. A quarter of the animations write a
  second that is not an identity, which is why it reads as spare until something uses it: a wight's spine
  jumps 90° between one frame and the next when only the first is read — calm legs under a torso having a
  fit — and 27° when both are. Combining is smoother in 159 animations and rougher in none.
- **The turn is stored the other way round**, stating how the bone's own frame moves under the pose rather
  than how the pose moves the bone, so it is read conjugated. Taken as written every joint bends backwards:
  a limb's swing out of line with the limb above it is signed, and a knee's is never forwards.
- **The translation is not where the bone is.** A skeleton is rigid — a bone stays the distance from its
  parent the mesh gives it — and taking it as an offset pulls a rhino's pelvis a metre out of its spine and
  stretches a human's limbs. It carries the creature's travel through the world, which the game moves the
  creature by. The scale beside it is real: a lashing tongue is written as one.

A key is laid over the bind pose rather than replacing it, so a bone's pose is its bind transform times its
turn, and an animation whose bones barely move is written as identities.

**An animation faces wherever the game had the creature facing**, which is rarely where the bind pose
faces: a combat idle stands side-on, a walk sets off at an angle. Nothing states that turn — it is simply
in the keys — so a camera that holds still watches the creature from behind.

**What follows the tracks is plain text**, the only part of the format that is not fixed-width:

```
CallbackPoint { name = "RightHandHit" frame = 11 }
CreateEntity  { frame = 1 entity = "records/fx/Creatures/AetherCreatureSpawn_FX01.dbr" attach = "Target" }
```

A callback is the moment the game hangs a sound, a blow or a particle start on; a `CreateEntity` spawns an
effect at a point of the rig. A handful of files end in a blank line instead.

### Effects

**An effect ends at a picture, three steps down.** The record is an `EffectEntity` whose `effectFile` names
a particle system under `fx/particlesystems/…`, and the `.pfx` is binary with its texture written into it
as a length and then a path — the same way a mesh writes a material's. The particles themselves are a
format of their own and unread, so that texture is what an effect can be drawn as.

**A skill names its effects in four places**, and only three of them are the creature's. A passive carries
its aura in `charFxPakSelfNames`, a pack naming both the points of the model to hang effects on
(`particleEffectAttachPoints`) and the effects themselves (`particleEffectNames`); a cast's own flash is
`particleEffectName1…N` and what it spreads around itself is `radiusEffectName`. The fourth,
`skillProjectileName`, names a projectile, and the flight and impact effects inside that record belong to
the thing in flight — hung on the caster they read as a swarm of meteors circling a beast that is merely
standing there.

**A particle texture carries no transparency.** It is painted on black and added to what is behind it, so
its own brightness is what says where it is see-through — drawn as it is, an effect is a black square with
a spark inside. A particle system also names the map it warps the picture behind it by (`…_distort…`),
which is not a picture at all and is taken last.

**An effect record names its own bone in `boneList`** — but 3,886 of the 4,077 that fill it in name the
same pair of weapon bones, which most creatures do not have. That is a stamp rather than a placement; what
is left over (`Bip01 Spine1`, `Bip01 R Hand`) is real.

**A model names the points an effect hangs from.** Chunk 3 is text, one block per point: a name, the bone
it hangs from, and where it sits in that bone.

```
AttachPoint { name = "Mouth" parent = "Bip01 Head" origin = (…) xAxis = (…) yAxis = (…) zAxis = (…) }
```

A human names 19 of them, a yeti 14, the questing beast 24 — `Mouth`, `HeadEffect`, `FXForward`,
`SpecialHit01` — and an animation asks for them by name: the yeti's fire breath is spawned at its `Mouth`.
**`FXCentered` is where a creature's own middle is**, which is not the middle of its bounding box: a tail
drags that six units behind the questing beast, and an effect centred there hangs in the air beside it.

### Which animation a creature plays

**A creature names a table rather than files.** `charAnimationTableName` points at a
`charanimationtable.tpl` record whose fields are the whole vocabulary — `unarmedWalkAnim`,
`unarmedAttackAnim2`, `unarmedDieAnim1`, `unarmedSpecialAnim7`. A table written for the player holds one
set per weapon class it can hold (`sword2h…`, `ranged1h…`, `dHanded…`), so an app that draws no weapon
reads the unarmed set.

**An attack finds its own animation by name.** A skill record's `skillSpecialAnimationName` — `GroundSlam`,
`Roar`, `Nova` — matches the table's `unarmedSpecialAnimRef7`, and `unarmedSpecialAnim7` beside it is the
file. 2,063 skill records name one, which is what lets a monster be drawn doing a particular attack.

**A weapon's record class names its animation set.** The part after the underscore is the set's own name
where the table has one: `WeaponMelee_Sword2h` is `sword2h`, `WeaponHunting_Ranged1h` is `ranged1h`. The
one-handed melee classes — `Sword`, `Axe`, `Mace`, `Dagger`, `Scepter` — have no set each and share
`sHanded`, `dHanded` when a second one is held; two `Ranged1h` are `dualRanged`. What fills the other hand
suffixes the set: `WeaponArmor_Shield` gives `sHandedShield`, `WeaponArmor_Offhand` gives
`sHandedOffhand`.

**`…MenuIdleAnim` is the pose the character window holds.** Every set names one, and it is the animation
the game plays behind the equipment doll rather than the `LongIdle` it plays in the world.

### What a "monster" actually is

Much of the roster is not a creature. The game spawns hazards, traps and scenery as monsters so they can
be hit and can hit back, and where it keeps the model says which: `creatures/anomalies` is weather and gas
with no body at all (*Blizzard*, *Cave-In*, *Whirlwind*, *Ugdenbog Gas Cloud* — six of the eight wear
`system/textures/invisible.tex`), `fx/meshfx` is a trap (*Floor Spikes*, *Flare Mine*, *Obsidian Anomaly*),
and `level art/…` or `items/chests/…` is scenery (*Warding Totem*, *Dermapteran Cluster*, *Training
Dummy*). 47 of the roster's records are one of those.

A record that names a `default<Slot>Piece` is a creature whatever its own model is, since only a creature
is dressed. That clause carries one record: the Avatar of Mogdrogen's `mesh` is a headdress under
`items/dlc`, and without it the game's own god would be filed as furniture.

### Several stages of one fight

A boss that changes shape is written as one record per stage, chained through death:
`poolToSpawnOnDeath` names a `spawnondeathpool.tpl` record whose `name1..N` are what can take the dying
creature's place, weighted by `weight1..N`. Where the record it spawns carries the same name, that is the
next phase; a different name is an add. *Ixall, Phantom of the Korvan Wastes* is `nemesis_eldritch_02a` (armour,
holding a sword) dying into `nemesis_eldritch_02b` (a wraith, a different mesh and different skills).

The stages differ in what they drop, and the base game's copy of Ixall's second stage names no loot table
at all: the necklaces the monster database prints for it are on the Shattered Realm copy of the same
record, under `records/endlessdungeon/creatures/…`, through `lootMisc1Item1`.

### How a weapon is held

A weapon mesh carries no bones: its vertices are authored in the frame of the bone the rig hangs it off,
so drawing it is a matter of parenting it there and nothing else. The `Anchor1` / `Anchor2` attachments
several of them carry are unrotated points along the item: the two ends, for what the game strings
between them. They say nothing about placement.

Which way a weapon points is the mesh's own business, and the families differ. Measured from the origin
it hangs by, all 141 caster meshes and all 118 one-handed swords reach along **−Z**, which on a rig whose
weapon bone maps local −Z to world down is the blade hanging from the fist. Focus meshes follow no such
convention at all — 48 reach along −X, 29 along −Z, 22 along +Y, 11 along +X and 10 along +Z — since a
focus is an ornament and each is modelled the way it is meant to sit. Nothing in the item record rotates
one, so a focus that reads oddly in the hand reads that way in the game too.

### How far a skill's effect reaches

`skillTargetRadius` is the ground an area skill covers — 0.1 to 50, on 1,371 skills — and the models are
in the same units, a creature standing two or three of them tall. A wave states its sweep instead:
`waveDistance` out, `waveStartWidth` and `waveEndWidth` across, `waveTime` to cross it. Nothing else in
a skill record says how big what it throws is; the `.pfx` particle systems carry the rest and are not read.

### The fight itself

`records/game/combatformulas.dbr` holds the arithmetic for one side hitting the other. The app evaluates
the record; nothing here is transcribed.

**Whether it lands.** `probabilityToHitEquation` takes the attacker's offensive ability and the
defender's defensive ability and produces one figure. `pthMinimum` (55) is the floor the app reads it
against, and the figure is capped at 100 to read as a chance.

**How hard.** `pthThreshold1..6` (70, 90, 105, 120, 130, 135) and `pthDamageModifier1..6` (1.0 to 1.5)
are six bands: a blow landing past a threshold is multiplied by that band's modifier. The app shows the
highest band a pairing reaches; how often each is rolled is the game's own business and is not guessed at.

**What stops it.** Two armour equations, picked by whether the blow is bigger than the armour:
`physicalDamageDefenseEquationDGP` is `(protection × (1 − absorption)) + (damage − protection)` for a
blow that gets through, `physcialDamageDefenseEquationDLEP` — the game's own spelling — is
`damage × (1 − absorption)` for one the armour swallows. The absorption share itself is
`armorDefensiveAbsorption` on `gameengine.dbr`, raised by whatever `defensiveAbsorptionModifier` a record
adds.

### What one side takes off the other

Three families lower what a target brings, and the game treats them differently:

| written as | field | stacks |
| --- | --- | --- |
| Reduced target's Damage | `offensiveTotalDamageReductionPercent…` | no — largest applies |
| Reduced target's Offensive Ability | `offensiveSlowOffensiveReduction…` | no |
| Reduced target's Defensive Ability | `offensiveSlowDefensiveReduction…` | no |
| % Reduced target's Resistances | `offensive<Type>ResistanceReductionPercent…` | no |
| Reduced target's Resistances | `offensive<Type>ResistanceReductionAbsolute…` | no |
| -X% \<type\> Resistance | a negative `defensive<Type>Resistance` on the debuff applied | yes |

`<Type>` is `Total` for the ones aimed at everything, or a damage family — `Elemental`, `Physical`. The
first five are what a build carries against a target, and carrying two of one wastes the smaller: 236
records name the damage reduction, 120 the flat resistance reduction, 50 the defensive-ability one.

The last is the only one that adds up, and it cannot be told apart from the character's own resistance:
Flame Jet's buff carries `defensiveElementalResistance = -40` under the same key a ring uses for +40 of
its own. Reading it off a character would list that character's own gear as though it were aimed at the
enemy, so the app leaves it out.

### Reduction in duration

`defensive<Type>Duration` is how much shorter a damage over time lasts **on** the character — what the
game words as *Reduction in Burn Duration*. It is the defensive twin of `offensiveSlow<Type>Duration…`,
which lengthens what the character inflicts, and the two are easy to mistake for one another. The stems
follow the over-time family: `defensivePhysicalDuration` is internal trauma, `defensiveLifeDuration`
vitality decay, `defensiveBleedingDuration` bleeding.

### The player's own creature

`records/creatures/pc/malepc01.dbr` and `femalepc01.dbr` are the two `Player`-class records, and no record
names either: the save's `male` flag picks one by its `characterGenderProfile`. A third `Player` record
sits under `records/sandbox` as a leftover test pose, so a search for one stays inside `creatures/pc`.

A player record reads like any other creature: `mesh` is the body, `charAnimationTableName` its table, and
`default<Slot>Piece` what the game dresses it in where a slot is empty — which is what puts hair on a bare
female head, since `femalepc01` names `defaultHeadPiece` and `malepc01` names none. `playerTextures` is
the default skin; the one actually picked at creation is in the save's own character-info block, and the
two agree only until the player changes it.

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
