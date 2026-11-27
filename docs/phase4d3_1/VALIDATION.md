# Phase 4D.3.1 validation

This amendment starts from draft PR #17 head `47b907d84546d3d774a904fa4321bffb22309723` and main `75090ff8baeea0ae51a6519d67dc74b754d906fa`, independently checked before editing. PR #17 remains draft and unmerged. No Phase 4D.4 work is included.

## Reproduced causes and measured change

The previous recovery investigation in `../phase4d3/DELIVERY_VALIDATION.md` identified raised waypoint heights and premature bow handoff, rather than a general collision failure. The former 40s accumulated deck timeout could relocate a progressing actor. This amendment advances deck paths horizontally, requires actual bow centring, and replaces that fallback with measured-progress replanning, unloading-slot rotation, short physical yielding and objective rejection. Ordinary NPC travel never teleports.

Additional actual-scene diagnosis found idle actors discarded their avoidance velocity, capsules treated nearby people as steps, and agents repeatedly converged on the same collection point. Agents now apply safe velocity to their real motors, retain body collisions, reserve three independently reachable approaches, and physically clear the collection area. Distinct priorities and bounded sideways/backward movement break local minima. A moving human avoidance obstacle follows actual player velocity; player input is not overridden.

| Actual 120s scene replay | Two tribes before | Two tribes after | Three tribes before | Three tribes after |
| --- | ---: | ---: | ---: | ---: |
| Secured supplies of 50 | 25 | 50 | 33 | 50 |
| Worst stationary heading reversals per actor | 52 | 5 | 54 | 5 |

These are native rendered scene replays with all 18 physical bodies and timestamped actor samples, not device performance measurements. Reversal counting uses the same harness on both versions. Total stalled seconds also include empty-handed actors after all 50 supplies are secured: one three-tribe idle parking case accumulated 90.42s and 66 path resets. That residual idle case is disclosed; it did not strand cargo or block departure. The narrower simultaneous-carrier test below measures active delivery instead.

## Acceptance results

- All 50 resource anchors have at least two collision-clear, navigable pickup approaches in both tribe formats, using the actual capsule, ground elevation and action range. No supplies are merely labelled reachable.
- Eight physical deck stress scenarios cover two/three tribes, Balanced, Brains/Brawn/Beauty, Battle of the Sexes, Random and Manual; seeds 1, 7, 42 and 99; varied selected contestants. Six or nine initial carriers approach the same tribe station while all 18 bodies remain active. Every initial carried instance is delivered; longest active reserved-carrier jam is at most 3s. These are deliberately seeded stress fixtures, distinct from ordinary player selection.
- Latest full physical scramble-to-shore regressions: two tribes 140.77s, 14 boarding events, zero recovery events; three tribes 145.20s, 16 boarding events, zero recovery events. Both finish arrival, preserve identities/configuration, verify exact moving-platform seats and restart. Contestants who miss assembly swim independently; the test does not award them a boarding event.
- Continuous native touch GUI journeys in both formats exercise ordinary selection-independent scene input, simultaneous move/look, repeated pickups and automatic deposits, Drop, boarding, three paddle strokes, jumping, moving reboarding, arrival summary and GUI restart. Paired moving-carrier fixtures exercise actual primary-button theft failure (seed 2) and success (seed 3); chance is not overridden.
- Deposit authority covers wrong station, walls at start and completion, movement interruption, pending action precedence, cooldowns, timer expiry and duplicate awards. Pickup/theft preserve exact instance/victim and seeded chance. Race authority, mass/drag/propulsion and 14-scenario balance regressions pass.
- HUD checks pass at 956×440 and 812×375 with at least 44 CSS-pixel actions; simulated safe-area side/bottom insets remain inside bounds. Native capture is full resolution; software browser capture at DPR .25 is not an iPhone quality/performance benchmark.
- Foundation, season compatibility, Phase 4C/camp, application, selection, title, credentials, benchmark and Tonsai regressions pass. The fixture-writing season test runs only in the isolated public simulation stage. Approved private catalog SHA-256 remains `7bd827434176ff969fa6545a061503d3ceacf6f8217c7736ad2e3714b6370f43`.

The earlier two-tribe browser journey reached arrival phase 3 at 157.9 simulation seconds, with one pickup/deposit, paddling and independent swimming, no browser errors and no saved season. A later three-tribe browser run boarded, paddled and reboarded but exhausted its wall-clock polling budget before an arrival was observed; that run is not a pass. The browser helper now records final state and allows time based on simulation progress. Final hosted browser outcomes are recorded on the private evidence Page and in PR #17's validation notes rather than inferred from native results.

The managed local Sites preview CLI returned `listen EPERM` at startup. It was not replaced with public forwarding or new infrastructure. Existing private HTTPS delivery remains the destination for hosted verification. Physical iPhone Safari rendering, touch feel, audio and sustained frame rate require owner review and are not claimed from desktop automation.

## Reproduction and evidence

Use Godot 4.7.2 (`ed1daf0bf`), Compatibility, single-threaded Web. `ci/test-simulation.sh` isolates synthetic fixtures; `ci/build-tonsai.sh` stages the allowlisted project and runs the marooning/layout/prop/deposit/traffic/race/UI/balance/physical/application regressions. Never run fixture-writing season compatibility against an approved private cast stage.

For private native GUI evidence, set `MAROONING_EVIDENCE_DIR` outside the export stage and run `res://tools/marooning/review_refinement.gd` or `review_theft_refinement.gd` from that prepared stage. The browser helper uses touch input and read-only review metadata; it does not award cargo, move scene actors or change game state through JavaScript. Exported read-only review metadata includes the implementation commit.

Actual before/after screenshots, prop comparisons, GUI evidence, timestamped traces and recording are delivered only to the personal private evidence Page:
https://chatgpt.com/space/page_9dcac3875a288191a4d24fbbbd92399c

Restricted images, approved catalogs and game packs are excluded from GitHub and public Actions artifacts. The existing owner-only Site is reused without changing its audience. Deployment provenance, anonymous denial and authenticated file checks are reported with the final private delivery.
