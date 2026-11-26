# Phase 4D.2 supply scramble

Based on verified remote main `2cbc9d8a53458ac854bf6437a8016b74abc38019`.
Godot 4.7.2 stable / Compatibility / single-threaded Web. No production save,
cloud transport, database, raft movement or camp transition is created here.

`MarooningSupplyCatalog` defines 15 types and exactly 50 unique instances, matching
the proposed quantities. `MarooningScramble` is a scene-independent command
processor. `MarooningScrambleAdapter` supplies physical positions, collision access,
navigation, visible cargo and UI. No target reservation grants ownership.

Introduction → Ready → explicit Start → Active (120 gameplay seconds) → Complete.
Physics elapsed time drives the timer. Focus loss/suspension pauses the simulation
and clears touch input. Preview catch-up permits 120 physics steps per render frame;
the prior engine setting is restored on teardown/restart. This prevents the normal
8-step budget discarding most simulation time on a slow software renderer. Extended
stalls still slow gameplay rather than silently skipping collection.

Pickup is within 1.35m and requires a clear collision ray, checked at request and
completion. Loading requires one's own station within 1.45m; the rail stations align
with the existing stationary rafts. The completed item is displayed in that raft.
Throwing requires a designated bow rail access point within 1.3m. Floating cargo
remains unsecured; recovery is deferred. A contestant carries one item. Handling
uses the catalog dexterity rating; carrying uses bounded strength adjustments to
0.95/0.80/0.60/0.50 baselines. Normal camp motor defaults remain 1.0.

Commands complete by due time, then actor ID for ties. Availability is checked again
at completion, atomically. At expiry, completed actions through exactly 120s count;
all unfinished actions cancel with an expired event. Carried cargo is not awarded.
Drops preserve item identity. Secured/floating items cannot be picked up again.

NPCs use the existing humanoid physical motor, navigation agents, shared action
rules, per-tribe need discounts, attribute utility, distance, competition and seeded
variation. Two decisions per 50ms bound planning work. Failed paths and stalled
approaches are temporarily rejected; invalidated targets never retain ownership.
NPCs currently prioritize loading over throwing. No teleported collection is used.

The transient `scramble_result` metadata contains configuration/seed, secured cargo
by tribe, floating/carried/dropped/abandoned arrays, all unsecured items, 512 bounded
semantic events and route/raft/destination references. Nearby witnesses are proximity
candidates, not permanent social judgments. Available uncollected cargo is included
in abandoned handoff cargo without mutating its authoritative instance record.

Imported ship geometry and transforms are retained. Body and fittings supply static
triangle collision, including cabin walls, hull and masts. Smooth analytic stair
ramps replace treads only in collision; triangle clipping opens their exact corridors
through broad imported railing faces. The continuous safety deck and rails remain.
Navigation baking excludes seabed/distant platforms with a deck AABB. Cargo occupies
52 symmetric, seeded slots (50 used), leaving the central mast/circulation channel.

Start: New Game → choose contestant → Standard → Two/Three Tribes → marooning
preview → skip/watch introduction → Start Supply Scramble. Left thumb moves; right
thumb looks. Context buttons pick up/load/throw; Drop releases the current object.
Results permit restart or exit. Inspection relocations are hidden from ordinary play.
Private review camera hooks require `?review` and never ship private screenshots.
