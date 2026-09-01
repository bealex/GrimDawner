# The engine's attack, decompiled

How one blow travels from the attacker's records to the defender's health bar, read out of the game's
own binary. Everything here was verified against `x64/Game.dll` from the installed game (v1.3, Fangs
of Asterkarn era) with Ghidra 12.1.3 — the DLL exports its C++ symbols, so functions carry their real
names — and cross-checked against three outside sources:

- the official combat guide, <https://www.grimdawn.com/guide/gameplay/combat/>, whose worked PTH
  examples and nine-step "Order of Defense" match the decompiled code exactly;
- controlled community measurements — NavLord's modded-monster test
  (<https://forums.crateentertainment.com/t/a-big-concern-monster-phy-dam-in-world-map-may-need-nerf-for-new-player-experiences-sake/137044/34>)
  reproduces a measured hit to 0.2% with the formula below;
- the Dawn Index (<https://grimdawn.info/mechanics>) for the mitigation formulas.

Addresses are image offsets in that DLL (base `0x180000000`). A patch will move them; the names will
survive, and the string anchors (`"pthThreshold1"`, `"physicalDamageEquation"`,
`"    PTH %f, Rand Value %f\n"`) will find them again.

## The cast

| thing | where |
| --- | --- |
| `GAME::Character` | one per creature; players and monsters run the same code |
| `GAME::CombatManager` | at `Character+0x530`; holds the combatformulas equations and per-fight state |
| `GAME::SkillManager` | at `Character+0x850`; the creature's skills, passives included |
| `GAME::CharacterBio` | at `Character+0xee0`; the record's base attributes and their equations |
| attribute accumulators | at `Character+0xf78`; `GetValue(1)`=physique, `(2)`=cunning, `(3)`=spirit, `(4)`=max life |
| `GAME::ParametersCombat` | the attack packet: accumulators of damage and modifier objects, attacker OA at `+0x14`, fumble at `+0x94`, crit-damage bonus at `+0xa0`, the rolled band multiplier at `+0x9c` |
| `GAME::CombatAttributeAccumulator` | a list of typed damage objects plus a list of modifier objects |

Damage is typed objects (`CombatAttributeDamage_BasePhysical`, `CombatAttributeAbsDamage`,
`CombatAttributeAbsDamageElemental`, `CombatAttributeDurDamage` for the over-time families…), each
carrying min/max and per-object modifier pools. Modifiers are objects too:
`CombatAttributeAbsDamageMod` carries one `offensive<Type>Modifier` figure,
`CombatAttribute_DamageMultiplier` carries one `offensiveTotalDamageModifier` figure, and
`CombatAttribute_DamageCritBonus` one `offensiveCritDamageModifier`. The class decides the
arithmetic, which is why "+% Physical" and "Total Damage Modified" behave differently.

## Attacker side — `GAME::Skill::CollectCombatParameters` @ `0x180485380`

Every attack skill funnels through this one function (`Skill_AttackWeapon`'s vtable slot 159). It
fills the `ParametersCombat` packet the defender will consume.

```
CollectCombatParameters(attacker, target, style, mainHandId, offHandId, packet, scale, offhand):
    # a pet attacking with player scaling swaps `attacker` for its owner here
    racial = attacker.ContributeRacialBonusDamage(target.races)      # "+% damage to Beasts"
    packet.racialAbsolute = racial.absolute
    scaleInfo[0] = scale + racial.percent                            # a percent; 0 means "unused"
    packet.style, packet.attackerId, packet.skillId = ...

    skill.CollectLocalOffensiveDamageAttributes(acc, skillLevel)     # the skill's own flat damage
    skill.CollectLocalOffensiveModifierAttributes(acc, skillLevel)   # the skill's own +% lines
    packet.critBonus += acc.GetTotalDamageModifierType(critDamage)   # offensiveCritDamageModifier

    wd = skill.CollectLocalWeaponDamage(...)                         # weaponDamagePct
    if wd > 0:                                                       # logs "^bWeapon Damage Percentage %f"
        SkillManager.CollectAvailableOffensiveDamageAttributes(mainHandId, offHandId, acc, wd/100):
            Character.GetEquipArmorDamageAttributes(...)             # flat damage on worn gear
            Character.ContributeMiscOffensiveDamageAttributes(...)   # item-set flat damage
            Character.ContributeGameBalance…(...)                    # for a monster: the difficulty
                                                                     #   adjustment record's flat damage
            Character.ContributeMutator…(...)                        # SR / Crucible mutators
            SkillManager.GetOffensiveDamageAttributes(...)           # EVERY passive's flat damage —
                                                                     #   damagebase_physical06's 1014 lives here
            weapon.ContributeDamage(acc, wd/100)                     # the equipped weapon record's own
                                                                     #   damage; monsters swing theirs too
            or CombatManager.GetHandHitDamage(acc, wd/100)           # unarmed: 1–1, set in Load @0x108ff0
        # each flat object remembers wd/100 (its +0x54) and multiplies by it in Process
    skill conversions collected and applied (ConvertDamage)

    SkillManager.CollectAvailableOffensiveModifierAttributes(acc, skillId):
        Character.GetEquipOffensiveModifierAttributes(...)           # gear +%
        Character.ContributeMiscOffensiveModifierAttributes(...)     # item sets +%
        Character.ContributeGameBalance…/ContributeMutator…(...)     # difficulty and mutator +%,
                                                                     #   per type and total both
        SkillManager.GetOffensiveModifierAttributes(skillId)         # EVERY passive's +% lines —
                                                                     #   armorbase06's −135% physical among
                                                                     #   them — skipping the skill being
                                                                     #   used, so it is not counted twice
    equipment conversions applied

    acc.ModifyDamage():                                              # @0x1801061c0, two passes
        pass 1: every modifier that is not a DamageMultiplier adds its figure into the pool of every
                damage object of ITS OWN TYPE (ModifyAbsoluteDamage @0x1801007e0) — plain addition
        pass 2: every DamageMultiplier (offensiveTotalDamageModifier) calls ScaleDamage on every
                damage object: min,max ×= (100 + value)/100          # multiplicative, once per source

    reduction = attacker's own received "reduced damage dealt" debuffs (duration-manager ids 0x1c–0x1f)
    CollectComboMultiplier(...) → scaleInfo[1]                       # charged-finale weapon pools

    for each damage object: object.Process(attacker, reduction, scaleInfo, chanceValue)

    packet.OA = SkillManager-computed offensive ability
    packet.fumble = attacker's fumble chance
```

### What `Process` does to one damage object

`CombatAttributeDamage_BasePhysical::Process` @ `0x180103930`; the typed
`CombatAttributeAbsDamage::Process` @ `0x180100390` is the same shape minus the pierce split.

```
Process(attacker, reduction, scaleInfo, flatDebuff):
    pierced = value × pierceRatio × (1 + ratioPool/100)     # the weapon's % Armor Piercing; the pierced
    value  −= pierced                                       #   share becomes pierce damage
    value  += |value| × pool/100;  clamp at 0               # THE PER-TYPE ADDITIVE POOL: every
                                                            #   offensive<Type>Modifier source, the
                                                            #   difficulty's, and the attribute bonus —
                                                            #   a net −107% zeroes, it never goes negative
    pierced += |pierced| × piercePool/100;  clamp at 0
    value ×= scaleInfo[0]/100  if set                       # racial bonus and skill-passed scale
    value ×= weaponDamageShare                              # the wd/100 stored at collection
    value ×= scaleInfo[1]/100  if set                       # combo multiplier
    value −= flatDebuff                                     # flat "reduced damage" on the attacker
    value −= |value| × max(totalReduction%, typeReduction%)/100 + flatReduction;  clamp at 0
```

A `% of max life` figure is converted to flat through the character's own equations mid-Process
(the equation objects at `Character+0x720`/`+0x740`).

## Defender side — `GAME::CombatManager::TakeAttack` @ `0x18010a650`

`Character::TakeAttack` @ `0x1800678c0` is the thin wrapper. The order below is the code's own and
matches the guide's published "Order of Defense" — Zantai: "The order of defense in the game guide
is correct."

```
TakeAttack(packet, skillManager, bio):
    region = PickRegion(rand)                       # @0x18010da90 — weighted by combatRegion<Part>Chance;
                                                    #   chosen BEFORE anything else, one region per blow
    melee:  fumble roll (rand100 < packet.fumble → miss, "^yFumble Chance (%f) caused a miss")
            dodge roll (CanIDodgeAttack @0x18010a450 → miss)
    ranged: deflect roll (CanIDeflectProjectile), projectile fumble
    direct: neither — a ground effect is not dodged

    DA  = DesignerCalculateDefensiveAbility(0)      # defender's, via the record equation
    PTH = DesignerCalculateProbabilityToHit(packet.OA, DA)     # @0x18010e490 — evaluates
                                                    #   probabilityToHitEquation, then floors at
                                                    #   pthMinimum (55)
    rand = MINSTD() / 2^31                          # 16807-multiplier LCG, the game's one PRNG
    modifier = CalculateDamageModifier(PTH, rand):  # @0x18010d810 — THE hit-and-band roll
        roll = max(PTH, 100) × rand                 # 100.0 is set in the constructor @0x1801087c0
        if PTH < 100 and roll > PTH:  MISS (modifier 0)
        if PTH ≤ pthThreshold1 (70):  modifier = normalPTHEquation(PTH)     # = PTH/70: a weak pairing
                                                    #   hits softer as well as less often
        else: modifier = pthDamageModifier of the highest pthThreshold2..6 the roll clears
                                                    #   90/105/120/130/135 → ×1.1/1.2/1.3/1.4/1.5
    packet.bandModifier = modifier

    defender defenses collected into the same accumulator (GetAllDefenseAttributes)

    sunder = durationManager(damageTakenMult) + defenderOwnDamageTaken      # Sundered: strongest
    if 100 < 100 + sunder:  every damage object ×= (100 + sunder)/100      #   instance only, and it
                                                                            #   multiplies BEFORE armor
    if modifier > 1:  modifier += packet.critBonus  # crit damage ADDS to the band figure
    ProcessBluntDamageModifier(modifier)            # band × crit lands on the direct damage values

    reductions = defender's received resistance-reduction debuffs (duration-manager ids 0x20–0x25)
    ProcessDefense(defender, reductions, flatReducedDamage)     # resistances made ready, RR applied

    shield block: chance = blockChance + modifiers (melee and projectile only, not while recovering);
        on success damage −= blockAmount × (1 + amountModifier), ×absorption; recovery timer starts
        ("^yDefender Blocked Attack")

    racial percent defense; ExecuteDefense          # the defense objects walk the damage objects:
                                                    #   resistance %, then armor for physical —
                                                    #   DesignerCalculatePhysicalDamageDefense
                                                    #   @0x18010e130 runs the DGP/DLEP equations against
                                                    #   the struck region — then % absorption, then flat
    ExecuteDamage(defender)                         # each object: CombatManager::ApplyDamage @0x18010a040
                                                    #   subtracts health; DoT objects land on the
                                                    #   DurationDamageManager instead
    retaliation, reflected damage, life leech return
```

## The three verdicts this settled

**Which band a swing lands in.** One roll decides hit and band together: uniform over
`0 … max(PTH, 100)`, miss above PTH, band by threshold. Conditioned on landing, the roll is uniform
over the hit figure, so a band is worth the span it covers of `0 … PTH` — the reading the app had
assumed — and chance to hit is `clamp(PTH, 55, 100)`, which it also had. The guide's own examples
say the same ("PTH = 124: 1-89 hits, 90-104 ×1.1, 105-119 ×1.2, 120-124 ×1.3"). Crit damage bonuses
*add* to the band figure rather than multiplying it.

**What a monster's per-type modifier is scoped to.** Nothing special: `offensive<Type>Modifier` from
every source — the level-scaled adjuster passives with their −135%, the difficulty adjustment, gear —
sums into one additive pool per type, and the pool is clamped at zero, not allowed to turn damage
negative. What keeps a boss hitting despite a −107% physical pool is the attribute bonus sitting in
the same pool (below). `offensiveTotalDamageModifier` is a different mechanism entirely: a
`DamageMultiplier` object that scales all damage multiplicatively, once per source, after the pool.
NavLord's controlled test pins the whole shape:
`978 × (1 + 3.14 + 1016/215) × (1 − 0.17) × (1 − 0.67) = 2374.9` against a measured 2370.

**Whether attributes scale a monster's damage.** They scale everyone's. The game's own attribute
tooltip (v1.3 text, read from the installed archives) still says so — "A cunning intellect improves
your combat technique, increasing physical, pierce, bleed and internal trauma damage" — and the
sheet's per-type info tags exclude it from the displayed percentage ("not including the bonus from
Cunning"). The rates are the `combatformulas.dbr` equations read as a percent into the pool:
cunning/2.45 for physical and pierce, cunning/2.15 for their over-time twins, spirit/2.15 for the
magical types, spirit/2.00 for theirs. A level-100 boss with 1188 cunning carries +485% physical
from attribute alone, which is what its −107% adjuster pool is balanced against — and why reading
the adjusters without the attribute bonus leaves a boss hitting for nothing. One honest gap: the
instruction in `Game.dll` that folds the attribute percent into the pool was not located — the
per-attack path never evaluates the damage equations (`DesignerCalculatePhysicalDamage` and kin are
export-only designer previews), so it is baked in during stat collection somewhere this dig did not
reach. The semantics rest on the equations, the tooltips, and the measured fits, which agree.

## What an attack spawns

The visuals travel beside the damage, not inside it, and the same dig read their machinery out:

- **A cast's own effects are the skill record's, each with its stated place.**
  `SkillProfile::LoadProfile` @ `0x1805307d0` pairs `particleEffectName1…3` with
  `particleEffectAttachPoint1…3` by number, and reads `warmUpEffectAttachPoint` beside the warm-up
  effect and `radiusEffectName` as a per-rank array. `Skill::ApplyCastVisualEffects` @ `0x180488db0`
  hangs the profile's casting effect on the character; `Skill::ApplyActiveWorldVisualEffects`
  @ `0x180488c20` adds a toggled skill's world effect as an entity of its own at the caster's feet.
- **Firing rides the animation.** The attack action's `AnimationCallback` fires the skill when the
  animation's hit callback comes round, so what a skill launches leaves on that frame — the same
  frame the blow lands on.
- **A projectile is an actor of its own.** `ProjectileBase::Load` @ `0x1803f1830` reads the record:
  `projectileVelocity`, `projectileDistance`, `launchAngle`, `actorRadius`, `projectileFlightFX`
  riding the flight, `projectileImpactFX` and `projectileExplodingImpactFX` for the landing, its own
  launch and flight animations, and `projectileWeaponTrail`. A `ProjectileSpark` crawler adds
  `inflightGroundFxPakName` dropped every `inflightGroundFxDropTime` seconds — the look of a fault
  line — while its mesh wears `system/textures/invisible.tex`, the game's stand-in for "the effect is
  the whole look".
- **The skill states the launch.** `Skill_AttackProjectileBurst::CreateProjectile` @ `0x1804a9de0`
  spawns the record `skillProjectileName` names, once per projectile, at the attacker's own
  coordinates; `launchAttachPointName` (read by the Burst, Ring, LineFan and Wave loaders) is the
  point of the model it leaves from; `projectileLaunchNumber` (per rank) is how many leave at once and
  `projectileLaunchRotation` the spread they fan across.

## Smaller facts worth keeping

- The engine's combat log is compiled in and gated on a flag (`gLogCombat`): "`    PTH %f, Rand
  Value %f`", "`^bWeapon Damage Percentage %f`", per-blow damage totals. A live fixture exists if it
  is ever needed.
- `pthMinimum` floors the PTH *figure*, not the roll: at PTH 55 the miss chance is a true 45%.
- The fumble roll is a separate d100 before anything else; dodge is melee-only, deflect
  projectile-only, and a "direct" attack (ground effects) skips both but still rolls PTH.
- Bare hands are 1–1 damage. A creature's real blow is the flat damage on its passives plus the
  weapon record it actually spawned holding — monsters swing their rolled equipment like players do.
- The displayed crit chance is `(PTH − 90) / max(PTH, 100)` (`DesignerCalculateCriticalChance`
  @ `0x18010d7e0`).
- Percent damage absorption applies per buff, multiplicatively across sources; flat absorption
  comes last of all.
- The `Designer*` family (`DesignerCalculatePhysicalDamage`, `…OffensiveAbility`, …) are exported
  previews for tooling; only `…ProbabilityToHit`, `…DefensiveAbility`, `…PhysicalDamageDefense` and
  the block pair are also called by the live pipeline.
