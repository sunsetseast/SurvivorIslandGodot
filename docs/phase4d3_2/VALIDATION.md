# Validation record — prepublication checkpoint, 2026-11-27

Base main: `75090ff8baeea0ae51a6519d67dc74b754d906fa`.
Starting draft PR #17: `1016476c0049363c082cdcce3f812a83c4b7f16e`.
Pinned engine: Godot 4.7.2 `ed1daf0bf`, Compatibility, single-thread Web export.

This file distinguishes authority fixtures, physical motor pilots and genuine input acceptance. Earlier success does not certify a later export. Hosted final-head browser acceptance and final private evidence delivery are still pending for this candidate.

## Observed checks so far

| Check | Observed result | Limit |
| --- | --- | --- |
| Supply authority and automatic deposits | Pass | Pure command fixtures |
| Shared-clock/per-tribe launch/cutoff ordering | Pass | Pure authority; exact 60s completion wins, later completion cancels |
| Stroke impulse, early/late equality, rest/spam, blocked displacement and cargo mass | Pass | Controlled equal-crew/equal-mass trials |
| Moving anchor reservation, capacity, cancellation and reboard | Pass | Authority fixtures; physical input separately below |
| Visible side ramp out/return and closed bow | Pass in both layouts | Capsule motor geometry fixture |
| HUD landscape/portrait/safe areas/held-touch activation | Pass | Bounds and actual GUI event regression |
| Eight approved-roster carrier stress cases | All60 initial cargo instances delivered across eight cases; maximum stalls2,2,1,2,1,3,2,2 seconds | Unchanged limit ≤8s; earlier Manual candidate failed at19s and is retained as a failure in private investigation logs |
| Eight public-fixture carrier stress cases | All60 initial instances delivered; stalls1,2,2,2,1,2,6,1 seconds | Same unchanged≤8s gate; no restricted catalog in this stage |
| Physical continuous two/three-tribe pilots | Completed in115.55s/110.2s in an earlier integrated candidate | Direct motor pilot, not genuine touch acceptance; final changes require retest |
| Native ordinary UI/touch two-tribe route | Completed123.73s; moored board, paddle, moving jump/reboard, shore, summary/restart/exit | Earlier candidate; final-head rerun pending |
| Native ordinary UI/touch three-tribe route | Completed131.95s; full-minute collection route, late swim, summary/restart/exit | Earlier candidate; final-head rerun pending |
| Exceptional stalled-NPC fixture | One validated2.4m sideways assist after45s/11 retries; no objective/cargo/reward award; human unchanged | Deliberately immobilized technical fixture, not normal journey evidence |
| Phase4C/setup/camp, selection, title, application lifecycle, credential mocks | Pass | Existing regressions |
| Benchmark fixtures | 16 scenarios pass | No physical iPhone FPS claim |
| Isolated foundation/save compatibility | Pass | Run outside approved private catalog stage |

The first fresh frozen1016476 replay did not reproduce the historical11-second Random3/seed1/selected14 episode: that baseline pass had1–3-second maxima. A subsequent run with the common measurement observer reproduced a19-second two-tribe Random/seed99 episode. Baseline failures and successful runs are both retained. The historical failure remains valid evidence; RVO/physics scheduling is not bitwise deterministic. The new investigation reproduced19/21-second Manual and20/24-second Battle of the Sexes stalls in intermediate candidates, identified target-change resets of the immobility clock, and verified independent immobility tracking plus capsule-clear physical retreat. Other concrete recoveries addressed omitted basket colliders in the navigation bake, depositing agents incorrectly advertising willingness to yield, out-of-bounds queue goals, a basket blocking its side gate, a ramp tip touching its raft and premature turns near neighboring hulls.

No acceptance threshold was lowered. The two current full stress passes above are observations of the final traffic implementation, with approved and synthetic catalogs kept separate. A final repeated pass and matched baseline/final reversal, congestion and stall distributions are recorded privately. The common observer samples once per second; reversals/congestion compare the first60s, while carrier gates retain their full90s stress window. Percentiles use nearest rank, recomputed from the actual episode durations. The old collection contract lasts120s and the new one closes at60s, so full90s stall distributions must be read with that difference. Full public CI/export, dedicated-server staging, final native input/pose/scenery captures and hosted traces still require the publication-specific record.

## Reproduce

The private cast stage is intentionally outside Git. Do not run fixture-writing season compatibility scripts against it. Use `ci/test-simulation.sh` for isolated foundation/save checks. `ci/build-tonsai.sh` creates its own export stage; preserve an approved private stage before invoking it. Private environment variables are forbidden in GitHub Actions.

The focused tests include `session_test.gd`, `stroke_impulse_test.gd`, `moving_board_test.gd`, `ship_access_test.gd`, `deck_traffic_test.gd`, `navigation_recovery_test.gd`, `marooning_pose_test.gd`, `race_ui_test.gd`, `race_test.gd`, `race_balance.gd`, `concurrent_physical_test.gd` and `native_marooning_touch_test.gd`. Physical/animation tests use `--fixed-fps60`. `MAROONING_TOUCH_FORMAT` optionally selects a native input route; the default runs both. Native diagnostic captures are opt-in via `MAROONING_CAPTURE_DIR` and must remain private.

The existing owner-private Site is `https://survivor-island-phase-3b.peachybeetle18.chatgpt.site`. Its revision1 policy was independently verified: sole owner, no editors, groups or external visitors. Anonymous page, source marker, engine and pack requests returned403 with normal TLS. Candidate 04b9a04a94c808e5bffa9862ee0a4b97aa061208 was published privately. A fresh normal-TLS delivery check on 2026-11-27 verified the authenticated HTML/source/JavaScript and every engine/pack part byte-for-byte against local output, plus reconstructed raw engine/pack hashes; every anonymous counterpart returned403. Full hosted candidate acceptance is still in progress. Final acceptance must verify the exact served source SHA, authenticated assets and anonymous denial again after publication.

The owner must play and approve before merge. Physical iPhone acceptance remains pending owner review if no real device is available. No Phase4D.4 work is authorized here.

## Accessible private record

The personal owner-private [Phase4D.3.2 evidence Page](https://chatgpt.com/space/page_496b9b22b710819188832b2a4753a537) holds actual captures and the publication-specific results. Its sharing roster was independently verified with no shares or inherited sources. The final delivery record must bind the served source marker, engine setting, pack hash, source-repository commit and Site version; earlier candidate evidence is labelled separately. This source document records observations available before publication, and the Page records subsequent hosted acceptance without changing export provenance.

Matched scene views (956×440, native Compatibility/llvmpipe, explicit rendering with the ordinary loop disabled) measured previous1016476 deck/shore at395/87 draw calls,290681/95376 primitives and64224208 texture bytes. The working candidate measured476/143 calls,338540/120310 primitives and81045457 texture bytes. This includes repaired shore LOD placement and the actual private carved UI/font. These are costs, not an iPhone FPS or memory certification. Final same-source captures are required after the candidate is committed.

## Hosted harness and authenticated worklets

Candidate04b9a04 hosted genuine touch reached early side jumping, moored boarding, three accepted paddle strokes and a moving jump/reboard at52.60 gameplay seconds. All four CSS viewports were captured. It stopped at a focus assertion because Playwright forces `document.hasFocus()` true unless `Emulation.setFocusEmulationEnabled(false)` is sent. A separate two-page probe demonstrated blur with that override removed, in both headed and headless Chromium; the final harness uses actual tab focus rather than directly calling game suspension. This candidate run is not a full arrival pass.

Two audio-worklet module loads returned401 because module-loader requests omitted the normal authenticated document request headers. Static packaging now fetches those unchanged, same-origin modules through the existing authenticated session and instantiates the authorized bytes as local blobs. The Site ACL and anonymous denial remain unchanged. A normal-TLS probe fetched both modules with200, registered both processors and reported zero page errors. This verifies module loading, not listening or audio presentation.

## Loaded vessel contact investigation

The626691c native two-tribe replay (Balanced seed1372773787, selected18 in Salani) failed genuine acceptance: an early Jump tap was vetoed, then the selected loaded raft stopped near(-4.8666,110.7564) against the actual fishing dock despite179 accepted human strokes. Team summary was still unavailable at319.47s. All50 supplies remained accounted for and no exceptional NPC recovery ran. The three-tribe replay reached actual summary at132.83s with zero exceptional recoveries, but the combined native suite correctly failed. Failed images and traces are retained privately and are not labelled successful summary evidence.

The hull contact made tiny successful steps between blocked frames, resetting the consecutive blocked timer. The correction measures3s displacement together with actual collision evidence, uses collision-checked3.5m backwater powered by accepted strokes, and plans outboard dock clearance after reward resolution. Reverse paddle sweeps match the maneuver. It does not relocate a raft, add force, grant cargo or weaken collision. Three loaded-hull technical fixtures (observed contact, mirrored contact and head-on contact) reached physical grounding in27.68/27.68/29.77s with one explicit backwater each and no fade assist. Multi-raft authority, balance and normal native/hosted journeys remain required after this change.

Two consecutive Camp CI attempts reproduced pinned Godot4.7.2 font-import crashes/worker-thread SceneTree notifications before gameplay tests. The disposable Tonsai stage now uses the engine-supported `editor/import/use_multiple_threads=false`; runtime gameplay threading is unchanged. Final successful CI must still be observed.

The corrected full six-seed/capacity authority suite, all14 balance scenarios, three weighted physical dock fixtures, post-mixer pose checks, mobile HUD and controlled impulse trials now pass. The controlled impulses remain152.625/111.925/66.1375N·s for Perfect/Good/Mistimed, with early/late Mistimed both0.748407m in the same controlled trial. These are not final rendered journey results. Two complete approved-catalog traffic passes and one public fixture pass remain within the unchanged8s gate (max3/3/6s), with actual durations and matched measures in the private record.
