# Validation record

## Verified baseline

Remote main and merged PR #16 independently verified at
`75090ff8baeea0ae51a6519d67dc74b754d906fa`; remote main rechecked during this task
and unchanged. An isolated baseline stage reproduced the original two/three-tribe
physical scramble acceptance with zero failures, all 17 NPCs collecting and all
tribes loading. Current relevant regression gates also pass, including original
marooning traversal, both full supply scrambles, foundation, season compatibility,
selection, title, credential mocks, 16 benchmarks, application lifecycle and Tonsai
movement/swimming/touch. Tonsai measured 668.98m walked and 59 NPC arrivals.

The approved private catalog was reconciled using the existing staging script and
pinned references `cf894e578d77fce1e588d793dfc8d14f61ec7628` and
`708a21c43b4b2969aa28bf2142005e4f5df0bcdf`: 18 identities, 27 ratings per identity,
no changed permanent rating or new likeness. Restricted catalog, portraits, exports
and captures stay under ignored build directories, outside commits and Actions.

## Automated checks

`tests/scramble_test.gd`: normal pickup/drop/loading; Throw rejected; expiry;
50-instance conservation; exact theft transfer and failed ownership preservation;
remote/blocked theft; completion range revalidation; secured cargo rejection;
cooldowns/revenge protection; semantic identities; simultaneous theft completion
ordering and deterministic outcomes.

`tests/race_test.gd`: six/nine capacity through two/three configurations; unique
anchors and capsule clearance during boarding; remote/blocked boarding; completion
revalidation; mass and draft; cargo acceleration tradeoff under equal force;
no-paddler coasting; fatigue; stroke spam; exclusive reward; suspension; strategic
NPC swimming; moving-raft reboarding; exact local-anchor stability; seeded races.

`tests/race_physical_test.gd`: actual 120-second collection followed by real deck
navigation, bow access, swimming, validated boarding, paddling, reward competition,
water stop, physical disembarkation and shoreline arrival. A technical motor pilot
controls the selected actor without relocations. This is scene/motor testing, not
browser interaction. Focus suspension, transient result, restart, original
configuration, all 18 participants and physics-policy restoration are checked.
Both final two/three-tribe physical runs pass, including platform-local drift assertions and restart. Observed departure-to-arrival results:

| Tribes | Elapsed s | Boardings | Recovery incidents | Reward | Secured cargo kg by tribe (including reward) | Peak raft speeds m/s |
|---|---:|---:|---:|---|---|---|
| 2 | 114.10 | 16 | 1 | tribe-1 | 72.3 / 56.8 | 4.14 / 3.79 |
| 3 | 109.95 | 15 | 3 | tribe-2 | 41.8 / 36.6 / 81.5 | 3.08 / 3.85 / 3.43 |

The remaining contestants swam independently. Both selected tribes reached shore physically before their summaries. These are gameplay seconds after the separate 120-second scramble, not wall-clock device measurements.

Recorded deck recovery incidents remain visible; they are not counted as normal
boarding or used to manufacture supply deliveries.

`tests/race_balance.gd`: authority harness only, not rendered/device playtesting.
The machine-readable results in BALANCE.json compare 14 scenarios across two and
three tribes: 0/160kg cargo, strong/weak paddlers, perfect/missed player strokes,
and early/late independent swimming. Observed winners include both t0 and t1.
Heavier cargo slows the equivalent crew; perfect input can change the winner;
early swimming can lose a race that later swimming preserves. These observations
are specific to those fixtures, not proof that every strategy is balanced.

## Browser and delivery

Godot 4.7.2 / Compatibility single-threaded Web export succeeds; the generated HTML
sets GODOT_THREADS_ENABLED=false. A private loopback Chromium 956×440 run exercised
actual simultaneous movement/camera touches, full collection, departure, NPC reward
claim, continued camp approach and Exit Preview. Browser errors: none; season ID
empty, slot/revision zero. It did not drive that inactive human to the beach.
Camera-only review hooks produced actual in-game ship, raft side and overhead,
supply gameplay and reward-claim captures under build/race-captures.

That observed run's last 300 frame intervals had median 633.3ms and maximum 3489.5ms
on Cloud software rendering. These are NOT iPhone performance measurements.
A later concurrent screenshot attempt timed out after 30 seconds; the harness now
allows a longer capture timeout. No physical iPhone or Safari test is claimed.

An additional browser pilot physically walked off the bow, swam around the ship and raft, boarded by touch and used Paddle. Actual timing UI captures were taken at 956×440 and 812×375, plus loaded nine-crew raft side/overhead and competing-raft views. That older export reproduced the shore congestion defect before the later native fix; it is not a final browser-arrival pass. Screenshot inspection also caught clipped bottom controls. The final panel grows upward, uses larger touch targets, and contextual scramble actions occupy the lower right. `tests/race_ui_test.gd` checks all these action rectangles at both landscape sizes with zero failures. The complete requested screenshot matrix remains outstanding.

Cloud status advertises HTTP port 3000 but returns no HTTPS URL. Automatic approval
review rejected binding the restricted build to 0.0.0.0 because owner-only access
was unverified. A safer loopback-only server is running for automated browser
acceptance. No public host, deployment, paid service, or restricted Actions artifact
was created. A localhost address is not a physical-phone preview. Owner-only HTTPS
link readiness and access verification remain required for phone delivery.

## Remaining acceptance work

Physical iPhone 17 Pro Max Safari landscape acceptance remains outstanding: test
pickup/drop/load/steal with independent camera input; board, rhythm, rest, deliberate
jump and moving-raft reboard; reward via raft and swimming; shore arrival; focus
loss/resume and restart in each mode. Check 956×440 and a smaller landscape viewport,
button reach, timing readability and actual frame pacing. Restricted captures must
remain private. Cloud/browser tests do not certify real-device performance.

The current initial AI may need a bounded, journaled recovery after deck navigation
fails in a congested loaded scene. An inactive player can keep their own arrival
unresolved while NPCs continue. Rival arrival state may remain unresolved when the
selected tribe completes; it is preserved explicitly in the transient handoff.

## Reproduce

Use the existing private staging pipeline, then `ci/build-tonsai.sh` with
GODOT_BIN pointing to the pinned binary, SURVIVOR_PRIVATE_CAST set to the approved
private stage, and TONSAI_REFERENCE pointing to the pinned prototype. This runs the
new authority, balance and physical gates as well as the existing regressions.
`python3 tools/marooning/review_race.py URL build/private-race-review` performs the
browser touch/competition/exit check. That harness does not itself pilot the human
through boarding/arrival and must not be reported as doing so.
