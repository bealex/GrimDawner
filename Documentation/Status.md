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

**A creature with no attack skill swings its own body.** 293 of the game's 3,081 named monsters name
nothing in any attack slot — the Oversized Maggot among them — and what they fight with is the flat
damage their passives carry, at their own attack rate. The app read them as having no attack at all, so
the Attacks card was empty and the Interaction tab said a monster that one-shots a level 100 character
throws nothing. The bare swing is now what the encounter uses where no skill is named, and the Attacks
card says so in place of a skill it does not have.

**Checked against the game's own character window** (a level 100 Spellbinder, Ultimate, from 2026-09-01
footage). Twelve figures are exact: Offensive Ability 2797, Energy 7166, Armor Rating 3200, Physique
1375, Cunning 404, Spirit 840, and all ten resistances at their own caps — 83/83/86/80/80 and
80/87/80/80/24, Health 16,339 and Defensive Ability 2,859. Every figure that window shows matches, to
the digit the game truncates at.

The last two did not, until the gear's **"Enhances" lines were put on the sheet**. An item that enhances
a skill carries its figures on a modifier record of its own — `modifiedSkillName1` names the skill,
`modifierSkillName1` the record holding the numbers — and the app read those lines for the sidebar but
never fed them in. Where the skill enhanced is one the character keeps up they belong on the sheet
exactly as a mastery's own modifier does; where it rides an attack that has to be pressed they belong to
that attack. A ring's ascendant affix granting +100 Health to Spectral Binding was 113 health the game
showed and the app did not, and the same omission was the whole of the Defensive Ability gap.

**A character heals while it fights, and now that is counted.** The Interaction tab reads what its
regeneration gives and what its attack leeches — `offensiveLifeLeechMin`, the game's "% of Attack Damage
converted to Health" — against what the monster throws, and says *never — you heal faster* where the
healing wins. Without it a boss looked lethal that the character's own sustain outruns, which is what a
channelled build actually does. **The figure is only as good as the attacking side**, and that is the
open gap below: the app reads 4,284 damage a second for Albrecht's Aether Ray where the game's own
character window says 261,553, so the leech it derives is far too small.

**A monster's damage against a live reference.** The interaction arithmetic is pinned to the game's
own binary and to one controlled community measurement — the roll model, the additive pools, the
attribute bonus and the multiplicative total-damage layer, all in
[AttackPipeline.md](AttackPipeline.md), with `EncounterTests` holding the composition. Checked
against GrimTools' monster database — The Dread matches to the unit — and against three live
Ascendant fights: Beronath, the Keeper of the Seal, and Grand Magus Morgoneth on video. Both
domain-laid health bars reproduce to a rounding error (10,983,503 computed against 10,983,499
shown; 13,256,500 against 13,256,496 under the Forbidden layer), the game's printed ×2.32 crit
reproduces exactly, misses appear at the computed hit chance, and the beam's per-tick damage lands
once the reader dials in resistance reduction and timed buffs — the two things a save cannot state.
A domain's random mutators are unknowable from outside the run, but none touches monster health, so
a mutated fight's bar is still exact; what they shift is its damage. The engine's combat log,
compiled in behind a flag, remains the fixture for anything finer.

**Finding that took two corrections.** The Shattered Realm's own databases were overriding world
records, reading every reused boss as its retuned Shattered Realm self — a third of The Dread's real
health; they now load weakest. And an attack was read from its record alone: the modifier skills
hanging off it and what items change about it now ride the attack — Disintegration is most of an
Aether Ray, and the skill-aimed crit damage is what makes the game print ×2.32.

**A monster's equipped weapon adds nothing to its blow here.** The engine collects the weapon a
creature spawned holding into every swing — a Dreadguard's axe is 318–491 physical, and Crate's
modding guide states the monster is "actively benefiting from" its Initial Equipment — but the app
does not roll one for the fight, so an armed humanoid reads low. The Dread carries nothing and is
unaffected.

**Night-only buffs count around the clock.** 57 monsters carry a `nightBuffSkill`, every one a
toggled buff the resolver reads as permanent; the modding guide says it is active only at night.
Whether GrimTools counts them the same always-on way is unchecked, so which reading to show is
undecided — matching GrimTools and matching the game at noon diverge for those 57.

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

**Every skill the creature has is picked as one thing.** The model tab's skill menu lists all of them —
its attacks, then its passives, then the ones the game gives nothing to draw — each under the name the
Attacks tab and the Interaction tab call it by, and picking one plays the animation that skill asks for
*and* shows what it throws. A buff's aura is on the buff record the skill points at rather than on the
skill (370 monster skills name one, 193 of those buffs carry the look), so that pointer is followed and
an aura now shows. A second menu plays any raw animation on its own, and playback runs at full, half or
quarter speed — which is what makes a two-frame difference between two casts readable. Along the top is
the skill being watched and what the animation calls out: each effect it spawns, the frames a blow lands
on, and what the skill fires when it does.

**What an attack fires flies the way the game flies it.** The projectile leaves the point its record
names, on the animation's hit callback, as many at a time and across the spread the record states, and is
aimed at a target standing in front of the creature at the skill's own `distanceProfile` range —
`records/game/gameengine.dbr` says how far that is. A straight one goes at it with gravity off; one the
engine throws — a grenade, or an exploding projectile that says `useTrajectory` — leaves at the record's
`launchAngle` above the ground, at exactly the speed that arc needs to land on the target, and falls under
the world's own gravity of 14 from there. It is pointed the way it is going the whole way down, and swells
over its first second where the record's `projectileScaleFactor` says it should. What each looks like is
the game's own: the projectile's model where it has a visible one, its flight effect or the trail it lays
where the model is the game's invisible stand-in. All of it was read out of the engine —
[AttackPipeline.md](AttackPipeline.md#how-a-projectile-flies) — and cast flashes hang on the attach
points the skill record pairs them with rather than on the creature's middle.

**The particle systems are read, and every curve in them is mapped.** `PfxFile` takes the `.pfx` apart the
way the engine's own reader does, and all 4,452 of the game's come back whole. What a slot *means* is not
in the file — the emitter fetches every one by index — so each of the 26 curves was traced to where
`Engine.dll` uses it. [GameData.md](GameData.md#effects) has the table. Twenty-four have a use; the two
left are read by nothing in the emitter and keep a clock of their own.

What the app draws now comes from the file: the emission rate, how long a particle lives, how big it is,
how fast and into what cone it is thrown, the box the emitter throws from, what pulls it down, how fast it
spins, and the colour the game paints it. Before, every one of those was a number the app made up from
the skill's reach.

**Nine of the curves run both ways, and their nothing is half their own range.** Read straight, a claw
swipe was born across eight units of ground, fell at five and spun at 425 degrees a second; read off
their centre it is born within a unit, does not fall, and the left and right claws spin *against* each
other at −70 and +65, as a mirrored pair must. That is the proof.
[GameData.md](GameData.md#effects) has which nine and how it was counted. Everything an emitter does is
now the game's own figure.

**The shapes go in whole, not as one figure each.** A curve is a shape over time, and SceneKit takes a
shape: the size, alpha, spin and colour curves are handed over as they are written, so a particle swells
and fades the way the file says rather than holding one value. The three colour curves are read together,
since a colour moves as one thing.

**What an animation spawns is a burst, not a flash.** Every effect an attack throws carries the frame it
starts on, and those went down a path that drew one picture for a moment and never read the emitter at
all. Auras improved and attacks did not. They now throw the game's own particles, opening
on their frame and following the rate curve while they do. That curve is where a burst is: a rate
curve's domain is the emitter's clock, not how long it throws for, and the yeti's swipe stands at
nothing for a third of its three tenths of a second, opens to 149 a second for a fiftieth, and shuts —
three or four billboards nine units across. That is a claw swipe.

**An effect rides the bone it hangs on.** The attach point is a node of the posed rig, so the emitter is
carried where the claw or the mouth goes and leaves its particles along the way, at the game's own rate.
Nothing about the emitter is invented any more: no cap on how many are alive, no stood-off sweep, no
made-up spawn volume.

**A particle is drawn the size the file states, and the size is easy to state twice.** SceneKit measures
a particle from its middle — a `particleSize` of one draws two units across — and a size *controller*
multiplies that rather than replacing it. Both were being handed the stated figure, which squared it:
the Dread's eleven-unit claw swipe drew at 242 and crossed the whole frame. The size goes in halved, and
the curve goes in as a share of its own peak.

**Two systems in three add their light; the rest are laid over the scene.** The shader the system names
says which, and drawing all of them additively lost anything painted dark — the Dread's stomp threw up
no rubble at all. [GameData.md](GameData.md#effects) has the counts.

**An emitter that opens near the end of an animation wraps round to the start.** The stomp opens its
rubble on frame 129 of 131, so all but a fifteenth of that burst belongs to the next time round; cut off
at the end of the loop it threw nothing.

**A thing in flight is its own emitter, not a sticker.** A projectile's `projectileFlightFX` was read
for its texture alone and drawn as one still billboard sized by `actorRadius`, which is the thing's
collision radius rather than its picture — so every projectile came out the same grey puff. The emitter
is carried down the flight now: the Bloatworm's aether orb is 1.10 across where its radius says 0.50,
and green-cyan where nothing said any colour at all.

**The frame takes in what a projectile is aimed at.** The flight was built and parented to the scene but
never counted in the bounds, so a creature spitting fourteen units threw at nothing off the edge of the
picture. The whole path now opens the frame — and past the cap an effect that merely wraps the creature
is held to, since where a thing lands is half of what there is to see.

**A flight can outlast the animation that throws it.** The Bloatworm's spit crosses fourteen units in
1.17s and the spitting takes 0.60s, and the copy was squeezed into what was left of one turn — four
times too fast. It gets as many whole turns of the animation as it needs instead, which keeps the two in
step and lets it fly at the speed the record states.

**A carried emitter throws per unit, not per second.** `EmitParticles` has a second mode that accumulates
`rate × distance`, and a thing in flight is what it exists for. Which mode a system is in is still not
read, so this much is the app's: an emitter being carried has its rate multiplied by how fast it is
carried. It is the difference between six sparks strung out behind the orb and a trail.

**A projectile leaves the limb the animation calls out.** Only 9 of the game's 1,325 projectile skills
name a launch point, so nearly every one fell back to `FXCentered` — on a mesh that does not parent that
point to a bone, the model's own middle, which is where the Bloatworm's spit came from. The animation's
hit callback names the limb instead: `RightHandHit` → `R Hand`.

**The model stands on a check.** A faint grey floor, one square to the world unit, so how big a creature
is and how far an effect reaches can be read off it rather than guessed. `SceneConfiguration.showsFloor`.
It writes no depth of its own but is tested against what does, and is drawn after the creature, so
anything below it reads as being under it rather than on top of it.

**A creature dies into the ground.** A key's translation is held at the mesh's own on every bone — that
is what keeps a skeleton rigid, and composing it stretches the worst bone 4.29 times — **except on the
trunk**, the one bone the body hangs off, where it is the creature's own placement and nothing below it
can be stretched by it. It is still through an idle, a walk and an attack, and runs seven units down as
The Dread dies. The root above the trunk stays undrawn: it carries the ground the creature covers
(11.89 over a walk cycle, nothing in a death), which a view that stands it in one place has no use for.

**A swung weapon leaves a ribbon.** `WeaponTrail` is a mechanism apart from the particle systems: the
weapon record names one in `weaponTrail`, the blade carries the `Anchor1` and `Anchor2` it is strung
between — 1,895 of the 1,909 trail-bearing weapon meshes have them — and the animation's own `Swipe…`
and `Swipe…Off` callbacks say when it runs. The blade's two ends are sampled every frame of the stroke
and joined into a strip that thins away behind the edge, in the record's own colour and over its own
fade. 85 of 120 armed monsters swing one. [GameData.md](GameData.md#effects) has the engine's path.

**What is still not drawn.** The light an emitter casts (curves 22–25) is drawn by nothing, and the
three light colours are the one place the centred reading is untested — they share the pattern but a
negative light colour means nothing, and there is no light to check it against. An `EffectEntity`'s
`decal` — the dark stain a stomp leaves on the ground, which outlasts the rubble in it — is not read.
Neither is `particledistort`: 189 systems bend what is behind them, and here they are laid over instead.

An attach point the mesh gives no parent bone — `FXForward`, `HeadFXUP`, `Target` — stands in the model
rather than on the rig, so an effect hung there holds still while the creature moves. That is what the
mesh states, but whether the game carries such a point with the entity is unchecked.

**A held weapon may be turned the wrong way, and it is not yet known against what.** Aetherblaze's
dagger comes out across the chest: its blade sits 89° off the forearm, where that rig's weapon bone has
`+X` running down the arm. Every weapon mesh is modelled the same way — blade along −Z on 56 of 56 — but
the bone is not, so there is no one rotation to apply. Settling it needs the same character held up
against the game.

**An aura is now drawn the size its file states, which is small.** The Dread's `Buffaura Red Selfloop`
is 1.97 units across on a creature spanning 18, so it reads as a tinge at the chest rather than the
cloud the squared size used to give it. Nothing in the records scales it — no `EffectEntity` states a
`scale` — so either the figure is right and the game's aura really is that small, or the birth size is
read from the wrong slot: `EmitParticle` picks between size modes on the emitter's `integer[0]`, and
only one of them is curve 15. That switch is the next thing worth reading out of the engine.

And a swipe is a burst of billboards where the game draws one stretched arc, which is a different way of
drawing rather than a different number.

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

**What is not drawn.** The travel a key carries, so a walk plays on the spot. And nothing blends one frame
into the next, so a loop restarts rather than easing round. The particles are drawn, from the game's own
emitters — what is left of that is further down.

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

The arithmetic behind both cards is the engine's own, decompiled and cross-checked —
[AttackPipeline.md](AttackPipeline.md). A monster's Cunning and Spirit raise its damage exactly as a
character's do, additively into each type's percentage pool, which is what its negative adjuster
passives are balanced against; the summed total-damage modifier multiplies once over the pool; the
band roll is uniform across the hit figure; crit damage adds to the band; dodge and deflection come
off the blows they meet; a charged finale lands once per its charge count with bare swings between.

**Rates are per attack, not per weapon.** A beam, cone, drain, tether or spin ticks at its own
`timeBetweenAttacks` — Albrecht's Aether Ray at 300ms and cast speed — while a charge or a growing radius
ticks that fast within one use and is governed by its cooldown instead. A cooldown shorter than the swing
means the skill is always ready, not that it is thrown faster.

**Buffs and Nerfs** sits beside the attack picker. Passives, auras and transmuters are already in every
figure and are listed in a card so you can see which. What a save cannot know is which timed buffs were
up and which of the monster's debuffs had landed, so those are checkboxes: your own self-buffs on one
side, and on the other everything the monster leaves on you — Sundered, and its reductions to your
abilities and damage. Only the strongest of each kind counts.

**Mode covers Ascendant, and a Domain picker sits beside it.** Ascendant is not a difficulty the save
records but a second adjustment over Ultimate, roughly doubling a boss's health and tripling its
damage; a challenge area — Dangerous, Treacherous or Forbidden Domain — lays one adjustment more, and
picking one reads the monster as the fight inside it.

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

**What the answer is, exactly.** A sweep is exact for one move — every option of that coordinate is tried,
none sampled — so a run settles where no single change to one socket helps. That is blind to two sockets
that only pay off together, which is the half of a resistance neither can cap alone, so each run finishes
with a pass over all 325 pairs of coordinates, every pair of their options against each other. A pass
takes a pair only where no resistance falls further short, so a plan can never lose a cap to one, and it
goes round again while it keeps finding something.

A second checkbox goes one level further, over all 2,600 trios, exact and with nothing shortlisted out of
it. `theTrioPassIsExactWhereTheWholeSpaceFitsInATrio` is what settles that it really is exact: cut the
problem to three sockets whose augments cannot move, count out all 216 combinations, and the pass must
land on the best of them.

**What each is worth, measured on the reference character.** The pair pass takes a run from 0.12s to
0.87s and is worth about 1.4% of the score. The trio pass takes a run to 27–102s — a whole search from 8
seconds to nine minutes — and changed one plan of the three: Defence traded 400 Armor Rating and 42
Defensive Ability for 2,400 health. On the other two it found nothing the eight starting points had not
already covered. So it is off by default and labelled with its cost.

None of it is proof of a global best. Four sockets moving together are outside even the trio pass, and
the objective is the reduced evaluator rather than a built character.

Ranking uses a reduced set of figures rather than a built character, since building one for each of the
hundreds of thousands of combinations would take days. That makes the arithmetic a second telling of the
sheet's, so `LoadoutOptimizerTests` pins the two together: read the character's own fittings back through
the evaluator and every figure must be the sheet's. None of it reaches the screen. The app sockets a
finished plan into a copy of the save, rebuilds it through `CharacterBuilder`, and shows that sheet.

**What it does not count.** The game draws a component's completion bonus at random from its own table,
so no plan can promise one and none is counted: every figure is the least the plan is worth. Skill ranks
stay at what the character has now, so a fitting granting +1 to a mastery gets no credit for what that
rank would unlock. Folding that in would mean re-levelling every mastery per combination.

**What "on max" means.** Every resistance the game caps — all of them but physical — targets the
character's own maximum as it stands, plus whatever overcap is asked for. A fitting that raises a cap
costs nothing for doing so, and the plan reports the final maximum beside what it reached.

**A plan is made for a difficulty, not for the save's own.** The game takes resistance off a character
the deeper it goes — on Ultimate 50% of fire, cold, lightning, pierce and poison and 25% of the rest,
out of `balancingadjustment_mp+difficulty_players01.dbr` — so a set of fittings that caps on Elite is
under the cap the moment Ultimate starts. The ask names the difficulty to hold the caps on and defaults
to Ultimate; the save's own penalty comes back out of the character and the planned one goes in, and the
plan's sheet is rebuilt on that difficulty too, so what is shown is what will be held. **Ascendant is
Ultimate here**: every ascendant record in the game adjusts a monster, and none of them touches the
player, so a character in Ascendant carries Ultimate's penalty and no more.

**Armour can be told to stop counting.** "Armor up to" is a ceiling on what armour is worth to the score,
not a limit on the plan: past it more armour scores nothing, so a socket that would have bought it buys
Defensive Ability, absorption or health instead. Armour that rides along with something else worth having
is kept, and a plan may still land above the figure.

**Two figures are aimed at rather than held.** A least Defensive Ability and a least Armor Absorption
enter as prices that climb while the plan is under them, the same machinery the caps use — but a plan
short of either still comes back and says by how much. Neither is asked of the attack plan; both are
defensive figures, and holding the attack plan to them would only stop it being an attack plan.

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
