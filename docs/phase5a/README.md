# Living Camp, configurable ruleset 3

SeasonSimulation owns calendar seconds, conditions, canonical `tribal_inventory`
and the monotonic transaction sequence. CampSimulation owns activity slots and
execution; LocalGameSession supplies trusted observations and active-time steps.
Presentation never applies recovery or advances its own clock.

Each 250 ms tick advances 30 simulated seconds. Day 1 starts at 08:00 and lasts
22 hours; subsequent days turn at 06:00 and last 24 hours (12 active minutes).
Elapsed ticks remain distinct from calendar seconds and the camp phase. Periods:
dawn 05–07, daylight 07–17, dusk 17–19, night 19–05. Menus and dialogue pause;
suspension resets the partial tick and resumed wall time is discarded. No offline
advancement, fast-forward, challenge, council or elimination is invented.

Condition uses 7,200 integer units per positive point, with exact per-step rates
in LivingCampRules. Health stays stable while the survival loop is incomplete.
Efficiency stays between 0.5 and 1 and modifies relevant activity duration.
Attributes and catalog defaults remain immutable. Cached profiles use actual
catalog ratings with neutral 5 only for unavailable fields. Utility considers
needs, work/social drives, relevant ability, repetition, current site, capacity,
food availability and seeded variation. Work/fire remain decorative: no pretend
resource production or construction. Rival camps execute abstract travel and
activity durations against their own stock.

Activity stages retain existing `waiting`, `travel`, `occupied` wire values:
selection/reservation is atomic, travel requires trusted arrival in physical
camps, completion/interruption/failure releases only that actor's slot. Physical
travel expires after 60 active seconds; restored occupied NPCs must reach the site
again before resuming remaining work. Multi-person sites use bounded capacity.
All activities are interruptible. Rest at the shelter site recovers energy;
well visits restore 12 hydration, consuming 250 ml if available, otherwise drinking
directly. Coconuts/fruit restore 10 nutrition for one discrete unit. Humans use
the same recovery function and may eat coconuts at the shelter. Raw rice is never
edible. Movement away interrupts human rest/drinking. No gathering is introduced.

Inventory remains keyed by stable tribe and instance IDs. Rice is grams, water
millilitres, equipment whole units. `acquired_quantity` and immutable opening
history retain provenance while `quantity` may reach zero. Internal atomic
transactions validate ownership, bounds, resource definitions and stock before
mutation. A persisted sequence rejects all stale/duplicate transactions without
an unbounded journal. Acquisitions and same-tribe split transfers get deterministic
season/sequence IDs; adjustment removes authorized quantities. Player commands
cannot acquire/adjust/transfer resources. Player consumption additionally requires
trusted proximity, ownership and an expected revision, preventing replay after
reload even when transient receipts are absent.

Version 2 migrates on restore: old day `d` and tick remainder `r` map to
`r*79200/2400` seconds on Day 1; otherwise
`79200+(d-2)*86400+r*86400/2400`, rounded down by integer division.
No historical depletion is fabricated. Recorded fatigue initializes energy once.
Original supply IDs, remaining quantities, opening history, RNG, pose, account and
save-slot ownership survive. Version 1 and technical seasons retain their rules.
Local two-generation/checksum/revision protections and downgrade fences remain.

The SQL candidate is deliberately outside migrations at
`supabase/compatibility/living_camp_v3.sql`. It reuses the v2 immutable-opening
validator and canonical v1 checks, but is disconnected from the live RPC, storage
constraints and sync support. Account v3 saves stay local; enabling cloud support
requires separate authorization and verification. No production SQL was applied.
