# Phase 4D.3.1 — playable scramble refinement

Verified base/main: `75090ff8baeea0ae51a6519d67dc74b754d906fa`.
Verified prior draft PR #17 head: `47b907d84546d3d774a904fa4321bffb22309723`.
Validation results and remaining device checks are recorded in [VALIDATION.md](VALIDATION.md).
No Phase 4D.4, save/account/database changes, paid services or new ship.

## Authority and interaction

The existing 50 IDs, 15 definitions, quantities, weights, masses and result fields
remain authoritative. Physical scenes install own-tribe unloading zones. Entering
one starts the ordinary load command with its visible catalog handling delay.
Current pending actions take precedence; a later drop cannot replace a locked
deposit. At completion, ownership, tribe, range, vertical separation, collision
access and challenge time are checked again. Legacy scene-independent callers
without zones retain explicit load behavior. SECURED semantics remain unchanged.

Pickup initiates at 1.75m and completes within 1.9m. Theft initiates within 1.95m
and completes within 2.15m with unobstructed access, exact victim/instance identity,
existing seeded chance, cooldown and victim protection. Base theft handling is .8s
before the existing dexterity multiplier. The highlight and primary action use one
stable selection scored by camera bearing, distance and previous target preference.
In-progress interactions retain their original item. Normal gameplay has one
pickup/theft action and secondary Drop; own-basket deposit needs no button.

## Deck and traffic

Editable layout anchors preserve the ship and existing collisions. Resource islands
leave the mast/central connections and bow corridor free. Collection bins use actual
tribe names/colors, physical bodies, three separate approaches and visible cargo.
Secured instance presentation slots are stable. The same visible objects transition
onto their correct raft over .85s; no additional inventory is created.

Deck traffic owns planar path advancement; NavigationAgent3D supplies local RVO
safe velocity applied to actual motors. Objectives reset paths only on a change or
bounded progress failure. Slot reservations do not grant cargo ownership. Carriers
participate in progress sampling and release/rotate approaches after stalls.
Completed carriers clear the station; idle actors receive separate reachable
parking positions. The human is a moving avoidance obstacle without input override.
NPCs retain physical body collisions. Deck-only motors exclude people from step
probes and moving-floor attachment; ordinary Tonsai motors are unchanged.

Departure uses the same planar navigation to centre fully in the bow corridor,
then proceeds down the plank. There is no ordinary navigation teleport. All tribes
share a 12s minimum assembly and 60s maximum; early launch requires NPCs aboard and the human either aboard or deliberately
in an eligible exterior-water start area. Testing the initial 45s limit left only
8/18 boarding events; the final physical routes produce 14/16 boarding events in two/three tribes. Physical stern and side
boarding, optional swimming, reward authority, rhythm and raft mass/speeds remain.
Disembarkation uses distinct outboard positions to avoid coincident physical bodies.

## Validation and delivery

See [VALIDATION.md](VALIDATION.md) for reproduced causes, baseline comparisons,
physical and GUI results, browser acceptance status and iPhone limits. See
[ASSETS.md](ASSETS.md) for original prop provenance and the evaluated asset leads.
The existing owner-only HTTPS Site and personal private evidence Page are reused;
no restricted evidence is committed to GitHub.
