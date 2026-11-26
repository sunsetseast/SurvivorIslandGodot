# Phase 4D.3 — race to shore

Base: independently fetched main `75090ff8baeea0ae51a6519d67dc74b754d906fa`,
merged PR #16. No subsequent main commits at task start. Godot 4.7.2 stable
`ed1daf0bf`, Compatibility, single-threaded Web. This feature never constructs a
production GameSession or writes a season save. Restricted data remains in build/.

## Architecture and state

`MarooningScramble` remains the supply authority. Introduction → Ready → Active
(120 gameplay seconds) → Complete is unchanged, followed continuously by
`MarooningRace`: Boarding (18 seconds) → Raft Race → Camp Approach → Arrival
Complete. `race_adapter.gd` bridges real motors, collision access, boarding,
platform presentation, cargo, HUD and the existing bay. No new map or scene load.

`race.gd` is scene-independent. It advances at 60 fixed steps/second, caps an input
delta at 250ms and freezes on focus loss. Rendering cannot decide strokes or
winners. The existing preview's 120 physics-step allowance is retained, never
increased, and restored on restart/exit. Suspended motors have a separate opt-in
flag; camp defaults remain unchanged. Stalls slow gameplay rather than accumulating
background misses. Decision work runs every four gameplay seconds per raft.

`raft.tscn` / `raft.gd` use AnimatableBody3D with a box collider and replaceable
visuals: 13 bamboo logs, four crossbeams, lashings, member-sized seating, individual
original paddles and tribal identification. Geometry/materials are shared. Overall
platform dimensions: 3.9 × 8m. Nine distinct seats at alternate x=±1.4m and five
longitudinal stations; six-person crews use six anchors. Central cargo rows avoid
paddlers. Rocking applies only to the visual child.

Boarding takes .7s and validates own membership, space, actual stern proximity
(2.7m), empty attachment and collision access at request and completion. Pending
climbs resolve by sorted stable contestant ID. Anchored motors stop platform
velocity accumulation while retaining camera control. A jump immediately detaches,
subtracts mass and propulsion, resets velocity and resumes the existing water
motor. Unattached swimmers are never continuously anchored to the raft.

The bow has a narrow, collision-clipped gangplank access corridor. The rest of the
imported vessel/collision is preserved. NPCs navigate the deck to its access point,
walk off the plank, swim to their stern and use the same boarding command. One
recorded deck-navigation recovery is permitted after 40 seconds of failed progress.

## Supply authority and theft

Throw is rejected at the authority and absent from UI/AI; legacy FLOATING enum and
result field remain readable. Pickup, one carried instance, Drop and own-raft Load
remain. Only SECURED instances count. Physical mass is a separate `mass_kg` per
instance, never ordinal weight interpreted as kg:

| Type | kg | Type | kg | Type | kg |
|---|---:|---|---:|---|---:|
| rice | 20.5 | machete | .7 | pot | 2.5 |
| water | 10.7 | fishing | 1.2 | tarp | 3 |
| rope | 1 | bamboo | 18 | coconut | 4.5 |
| fruit | 6 | wood | 12 | blanket | 1.2 |
| basket | .6 | cup | .9 | tools | 3.5 |

These are tunable gameplay estimates, including packaging and the catalog quantity
per instance. Rice's equipment summary still reports 20kg of contents per sack.

An empty-handed thief must be within 1.35m of an actual carrier and have an
unobstructed ray. A 1.25s interaction is adjusted by existing dexterity handling;
completion revalidates exact victim, instance, range, cooldown and collision access.
Chance = clamp(.5 + .035 × (thief dexterity + deception − victim awareness −
victim dexterity), .15, .85), using seeded RNG. Attempts and failures consume time;
the thief has a five-second cooldown and a successful victim four seconds of
protection. Simultaneous completions use due time then actor ID. Own-tribe theft is
valid. Secured cargo is ineligible. NPC theft is limited to high risk/aggression
actors and nearby valuable food/tools; ordinary collection remains primary.

Events preserve thief, victim, both tribes, instance/type, tribemate flag and
proximity witness candidates. No permanent social judgment is applied. Per-actor
aggregate action/outcome counts survive the bounded 512-event journal.

## Propulsion, attributes and strategy

Neutral occupant placeholder: 75kg; no invented catalog body weights. Base raft:
180kg. Mass M = 180 + secured cargo + occupants × 75 + claimed reward (8kg).
Draft = clamp((M − 180)/4000, 0, .32)m. Presentation eases draft changes at .15m/s.
Force is the sum of actual contributor strokes; no paddlers means drag-only motion.
Drag coefficient D = 38 × (1 + (M − 180)/1600).
Acceleration = (force × coordination − D × speed²)/M, integrated at fixed dt,
with bounded 0–4.4m/s speed and heading turning at .6rad/s. Added mass reduces both
acceleration and terminal speed at equal force. Crew separation uses bounded
heading avoidance and rejects overlapping candidate centres.

Stroke cycle: 1.6s. Perfect is the middle ±.065 of a cycle (150%), Good ±.17 (110%),
Early/Late 65%, missed 0%. One accepted stroke per cycle; resting cannot spam it.
The meter has actual marked timing regions and textual feedback. Optional
`paddle_timing_scale` preference is bounded .7–1.8 for accessibility. NPC stroke
times use seeded bounded error scaled by dexterity. Timing agreement around the
common stroke phase supplies a bounded bonus, influenced by `leader`. A miss
never subtracts another person's power.

Force per stroke = quality × (65 + 9 × strength) × (1 − .35 × fatigue) ×
clamp(1.1 − .035 × laziness, .75, 1.1). Endurance reduces exertion accumulation;
rest recovers .008 fatigue/second. Fatigue stays in [0,1]. The approved catalog has
no swimming or cooperation attribute: swimming uses endurance/speed/balance;
team effort uses the inverse of laziness. Swim speed starts at
clamp(1.5 + .07 × endurance + .045 × speed + .015 × balance, 1.8, 2.8)m/s, with a
bounded fatigue reduction. This is a marooning-only motor multiplier.

Every four seconds, a raft may release at most one NPC when a nearby objective's
swim ETA beats raft ETA after risk/awareness willingness. Three crew remain aboard;
a twelve-second reconsideration delay prevents immediate jump/reboard loops. The
human may always leave; NPC paddling continues independently. No character winner
or arrival time is prescribed.

## Reward, destinations and handoff

The existing `fishing-equipment-preview` identity is a single atomic package.
Physical claim requires ≤4.5m and collision access; NPC and player use the same
command. Claim records actor, tribe, time, approach method and witnesses. The 8kg package is secured directly aboard a claiming raft. A swimmer carries the exact package visibly, with a bounded 6% swim-speed cost, until reboarding or reaching their own destination; only then is it secured. It is never teleported as mass onto a distant raft. All rafts redirect immediately to their existing destination IDs. The
reward dock moves to (0,.5,115) to remove its former large starboard advantage.
Raft mounts are (-12,.55,-8), (12,.55,-8), (22,.55,-6.6): direct horizontal reward distances are approximately 123.58m in all three slots. They remain outside the hull, and NPC swimmers clear the bow before returning along its exterior. Player beach and rival exit destinations retain the existing layout contracts.

Rafts stop in shallow water (the player route approaches z=152, before the rising beach). Each crew member releases near their actual raft and then swims, wades or walks physically to their destination. NPCs approach member-specific positions spaced 1.15m apart and finish within .2m in the horizontal plane. The human uses a 4m landing tolerance. Independent swimmers use the same destination check, and late swimmers redirect to shore when their raft has stopped. Arrival
Complete requires the selected raft AND every selected tribemate resolved, not
merely the player touching shore. No Day 1 or permanent camp inventory is created.

`preview.get_meta("marooning_result")` is a deep-copied transient dictionary:

- version (1), original configuration, selected ID, seed, race RNG state;
- scramble: configuration, seed/RNG state, exact secured instances by tribe,
  unsecured/carried/dropped/abandoned instances, action aggregates and events/routes;
- reward: stable ID, owner tribe, claimant ID, claim time, approach, mass;
- contestants keyed by stable ID: tribe, attachment/mode, position, attributes,
  transient fatigue, strokes/Perfect/Good/misses/force, swim distance,
  boarding/departure totals and transient decision state;
- rafts keyed by tribe: stable route/destination IDs, position, speed/heading,
  crew/capacity, cargo and total mass/draft, peak mass, distance/max speed,
  integrated crew/paddler seconds, arrival state/time;
- bounded recent race events, elapsed gameplay time and phase.

Phase 4D.4 must validate the original configuration/catalog fingerprint before
consuming this in memory. Vector3 values are native Godot data; this is NOT a
production JSON save schema. Do not infer permanent trust or relationships.
