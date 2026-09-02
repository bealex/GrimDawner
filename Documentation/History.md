# History

What changed and why. Findings live in [GameData.md](GameData.md) and [Status.md](Status.md); this file
holds the record of corrections so that no code comment has to.

## Particle systems

**Nine emitter curves are centred.** Curves 4, 8, 9 to 11, 16 and 18 to 20 store a slider position between
`-range/2` and `+range/2`, so half the range means zero. Read straight, a claw swipe was born across
eight units of ground, fell at five and spun at 425°/s. Over the game's 4,631 systems, curve 18 sits at
exactly half its range on 99% and at zero on none. The proof is a mirrored pair: the yeti's two claws
spin at +65 and -70 once centred, and at +425 and +290 read straight.

That correction removed three inventions: a stood-off swept emitter, a cap on particles alive at once,
and a spawn volume sized from the skill's reach.

**A particle was drawn at the square of its size.** SceneKit measures a particle from its middle, so a
`particleSize` of one draws two units across, and a `.size` property controller multiplies instead of
replacing. Both got the stated figure, and the Dread's 11-unit swipe drew at 242. Measured against a box
of known size.

**Every property controller multiplies.** With `particleAngularVelocity` at zero, no controller value
turns a particle at all. The spin curve was handed over in degrees on top of a base already set to the
same figure, so the yeti's claws turned at 4,157°/s and read as swirling smoke. Curves now go in as a
share of their own peak. Where a colour or alpha curve exists the particle starts white and the curve
alone decides.

**Only two systems in three add their light.** `strings[1]` names the shader, and 1,618 of 4,631 systems
are combine, lit or distort. Drawing them additively lost anything painted dark, so the Dread's stomp
threw up no rubble.

**A burst near the end of an animation was clipped.** The stomp starts its rubble on frame 129 of 131.
The window ran off the end of the loop and was clamped flat. It wraps now.

**A rate curve's domain is not how long it throws for.** The window is where the curve is non-zero. A
swipe's is a fiftieth of a second inside a domain of three tenths.

**`flag[5]` throws a burst flat.** Read out of `Engine.dll`: `EmitParticle` builds a direction with
elevation starting straight up and the spread curve, in degrees, tilting it; azimuth is random over the
whole circle; with `flag[5]` set the vertical is zeroed, and the burst radiates across the ground.

**The invented per-particle scatter is gone** where the system was read. Nothing in a `.pfx` says how far
a particle may stray from its curves.

## Projectiles

**A thing in flight was a sticker.** `projectileFlightFX` was read for its texture alone and drawn as a
still billboard sized by `actorRadius`, the collision radius. Every projectile came out the same grey
puff. The emitter rides the flight now, at the size and colour its own system states.

**Almost nothing says where a projectile leaves from.** Only 9 of 1,325 projectile skills fill in
`launchAttachPointName`, so nearly every one fell back to `FXCentered`, the model's middle on a mesh that
leaves that point unparented. The animation's hit callback names the limb, and
`Skill::GetCoordsFromCallback` in `Game.dll` confirms the game reads it the same way.

**A flight can outlast the animation that throws it**, and was squeezed into what was left of one turn,
four times too fast for the Bloatworm's spit. It gets whole turns now.

**The frame ignored the flight.** The path was built but never counted in the bounds, so a creature threw
at a target off the edge of the picture.

**A carried emitter throws per unit travelled.** `EmitParticles` spreads each frame's particles along the
segment the emitter moved, and a second mode measures distance instead of time. A thing in flight is
taken as that kind; six sparks became a trail.

## Weapon trails

**A swung weapon left nothing behind it.** The arc a swing draws is `WeaponTrail`, a mechanism apart from
the particle systems. The weapon record names it in `weaponTrail` (1,990 weapons), the blade carries
`Anchor1` and `Anchor2` (1,895 of 1,909 trail-bearing meshes), and the animation's `Swipe...` and
`Swipe...Off` callbacks start and stop it through `SkillActivatedWeapon::SwipeAction`. The two anchors are
sampled every frame of the stroke and joined into a strip that thins away behind the edge. 85 of 120
armed monsters swing one.

## Posing

**A dying creature stayed on top of the ground.** Every key's translation was discarded to keep the
skeleton rigid. Holding the mesh's own translation keeps each bone its exact length, while composing the
key's stretches the worst 4.29 times, so the rule stands, with one exception: the trunk carries the
body's own placement and can stretch nothing below it. The root above it stays undrawn; it holds the
ground the creature covers, 11.89 over one of the Dread's walk cycles and nothing at all in either death.

**The floor hid nothing.** It was drawn before the creature with no depth test, so anything below it drew
on top.

## Still open

- **The Dread's swipe comes out a thin faint streak where the game blazes.** Measured against the floor's
  own unit squares the quad is the size the record states, the attach point sits at world (0, 2.24, 8),
  and the arc with its rays is painted into the one texture, so nothing sweeps. But
  `clawswipe_distortion01b_256.tex` is 8% mean alpha and 4% mean brightness, with 1% of it bright. Drawn
  once, additively, times a colour under 1, that is a faint streak. The game turns the same picture into
  a crescent wider than the creature. Where the amplification comes from is unread; the next place is
  `shaders/particle/particleadditive.ssh`, a format nothing here touches.
- The Dread has no `weaponTrail` and no anchors, so the trail mechanism does not apply to it. The unarmed
  trail path (`SetUnarmedWeaponTrail`) is only called for shapeshifted players.
- A leap does not arc. The yeti's root moves 6.86 units through its leap, but that is forward travel.
- A held weapon may be turned wrong. Aetherblaze's dagger sits 89° off the forearm. Every weapon mesh is
  modelled with its blade along -Z (56 of 56), but the rig's weapon bone follows no one convention: the
  axis running down the forearm is `+Y` on 36 of 60 rigs and `+X` on 18.
- An aura is drawn the size its file states, 1.97 units on the 18-unit Dread. No `EffectEntity` states a
  `scale`, so either that is right or the birth size comes from a slot not yet read; `EmitParticle` picks
  between size modes on `integer[0]`.
- Curve 17 is not a second dimension. `UpdateParticles` writes it to particle `+0x10` unscaled, beside the
  scaled size at `+0x0c`. What it is remains unread.
- The `decal` an `EffectEntity` names, the stain a stomp leaves, is not drawn.
- `particledistort` (189 systems) is laid over the scene instead of bending it.
- Bloom is available (`SceneConfiguration.bloom`) and off; nothing the app draws crosses its threshold.
