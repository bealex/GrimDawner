# What the app reads, and what it does not

Every field the game writes on an item, a monster, a skill or a devotion record, checked against what
the engine actually reads. A field counts as read when `StatCatalog` defines it or the source names it,
including the ones built by interpolation — `offensive\(rawValue)Min`, `loot\(slot.field)Item\(index)`.

The counts below are how many records write the field at all, not how much it matters. The matcher has
false positives in both directions, so everything called out by name was checked against the source by
hand; the totals are a guide.

| Domain | Records | Fields | In the catalogue | Read elsewhere | Unread |
| --- | ---: | ---: | ---: | ---: | ---: |
| Items | 9,772 | 521 | 173 | 188 | 160 |
| Monsters | 3,096 | 1,224 | 37 | 178 | 1,009 |
| Skills | 10,796 | 903 | 188 | 290 | 425 |
| Devotion | 846 | 310 | 0 | 165 | 145 |

A monster's thousand unread fields are almost all the engine driving it about — anger, distress calls,
walk speed, footstep surfaces, gib thresholds, light rigs. Devotion is nearly complete: what is left is
the panel's own paint, `isCircular` and the constellation state colours.

## Worth reading and not read

**The race a racial bonus names.** `racialBonusPercentDamage` is in the catalogue and shows as "Damage
to Race"; `racialBonusRace` beside it says which race, and is read nowhere. The game's own wording is
`{%+.0f0}% Damage to {%s1}`, so the line is printed with its subject missing. 235 records.

**What an item costs.** `itemCost` and `itemCostName` — the price and the equation that scales it.
2,622 records.

**How heavy a piece of armour is.** `armorClassification` — light, medium or heavy, which is what
decides a piece's attribute requirement band. 2,590 records.

**Whether an item is soulbound.** `soulbound`, 1,206 records.

**A component's completion bonus table.** `bonusTableName`, 170 records. The optimizer already says it
cannot promise one; the table it draws from is still nowhere to be seen.

**What a lore note is worth.** `experienceBonus`, `subHeading` and `codexTitle` — the XP a note grants
and where the codex files it. 315 records each.

**Which expansion an item needs.** `dlcRequirement`, 196 records.

**How many relics a formula makes.** `artifactCreateQuantity`, 927 records.

## Skills the game words and the app does not

These carry a text tag named after the field, so the game states the wording as well as the value, and
the parameter list does not read them:

- `projectileLaunchNumber` — "{%d0} Projectile(s)", 718 records
- `projectilePiercingChance` — "{%.1f0}% Chance to pass through Enemies", 318 records
- `cooldownCharges` — "{%d0} Charges", 70 records
- `skillChargeLevel` and `skillChargeDuration` — charge level and how long it holds, 109 records each

Read by nothing and worded by nothing: `projectileDamageRange1..3` (damage by distance, 442 records),
`instantCast`, `notDispelable`, `refreshCooldownTrigger`, `refreshDurationTrigger`, `skillTargetAngle`,
`debufSkill`, `autoCastSkill`, `skillWeaponRestriction`.

## Monsters

Nearly all of it is behaviour the app has no use for. The exceptions:

- `specialAttackChance`, `specialAttack2Chance`, `specialAttack3Chance` — how often a monster reaches
  for each of its specials, which is what a damage-per-second figure for one attack cannot say.
- `giveXP` — whether it grants experience at all, the twin of `dropItems`.
- `hitThreshold` and `gibThreshold` — what it takes to stagger or dismember it.
