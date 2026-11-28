# Phase 5A validation

Implementation: `bd29005da944acc5a6acfb5a27905d882947aa22`.
Draft PR: https://github.com/sunsetseast/SurvivorIslandGodot/pull/20.
Godot `4.7.2.stable.official.ed1daf0bf`, Compatibility, single-threaded Web export.
Later commits contain application assertions and delivery documentation only.

| Verification | Result |
| --- | --- |
| `GODOT_BIN=godot bash ci/test-simulation.sh` | Pass: foundation, legacy/catalog compatibility, permanent opening, 178 Living Camp assertions |
| Small seeded matrix | Pass: balanced, provider, low-work, exhausted; two/three tribes; deterministic autonomous continuation and checkpoints |
| Integrated Tonsai stage | Pass: import, both navigation bakes; 14 selected tests listed below |
| Production application pause/resume | Pass: supplies pauses time, backgrounding pauses, offline delta discarded, ordinary camp resumes; permanent lifecycle test rerun after final code |
| Web export | Pass: final staged export, absolute output path |
| Isolated PostgreSQL 17 | Pass: existing configurable 39 + opening 39 + disconnected v3 candidate 54 checks; rolled back test data |
| Private pack guard | Pass: all 11 required branding resources loaded from actual PCK, source marker checked |
| Compression/reconstruction | Pass: exact WASM and PCK reconstruction |
| Native rendered evidence | Pass: daytime HUD; rest increased energy 60→63; drinking consumed 250 ml and restored 12 hydration; night; saved/restored season |
| Existing owner-only preview | Deployment succeeded; native version provenance matches pushed hosting source; source and pack remain behind sign-in |
| Authenticated HTTP source/pack read-back | Not run: this browser has no authenticated owner session |
| Physical iPhone Safari landscape | Not run; owner acceptance remains required |

The selected integrated tests were `session_test`, `stroke_impulse_test`,
`moving_board_test`, `race_test`, `race_ui_test`, `phase4c_test`,
`phase4c_camp_test`, `tonsai_test`, `application_test`,
`opening_application_test`, `selection_test`, `title_test`, `credential_test`,
and `benchmark_test`. Tonsai continuously walked 668.98 m with 55 NPC arrivals
and no failures. The unchanged full deck stress sweep was not repeated.

Preparation used the existing `TONSAI_STAGE_ONLY=1 ci/build-tonsai.sh` path with
approved private staging. Focused simulation fixtures stayed in disposable
public-safe test stages. No private data or captures belong in public artifacts.
The first export attempt used a relative output path and failed before artifact
creation; the absolute-path export passed. The final native run uses software
OpenGL; its unsupported V-Sync warning is not an iPhone performance result.

Native evidence uses a seeded production handoff with the approved catalog and
fixed semantic tick advancement. It verifies actual commands, condition and
resource changes, local persistence, and rendered presentation; it is not an
owner-completed marooning or device acceptance claim. Authoritative state restores
exactly. JSON parsing changes one presentation-coordinate double by one ULP;
the restored physical Vector3 is identical. Four captures and their machine-readable
assertion summary are retained only in private staging and the owner-only preview.

Final PCK SHA-256:
`0326a6e5e75f6afb012895e503e186dba769a12094bc87d04fa23bc85816879b`.
The required branding guard verifies source `bd29005`; the native Sites deployment
and saved-version provenance identify the matching private hosting commit. An
anonymous pack request returns HTTP 401 and the sign-in gate. Authenticated served
bytes could not be inspected without an owner browser session; this limit is retained.
No production SQL, synchronization enablement, merge or access-policy expansion occurred.

Owner playtest:
1. Continue an existing version 2 season or complete a new marooning. Check that
   day/progress, identities, supplies and preferences survive. Expand Condition
   to see health; ordinary HUD shows only personal nutrition, hydration and energy.
2. At the shelter site, rest for 15 active seconds (about +3 energy), eat a coconut
   or drink camp water. Check real condition and Tribal Supplies changes. At the
   freshwater well, drinking must work with an empty starting water inventory.
3. Open supplies/settings/dialogue and background/resume Safari: no time jump.
   Save, leave, Continue and reload; verify calendar, condition and remaining stock.
   From 08:00, night arrives after about 5.5 active minutes; Day 2 after 11 minutes.
   Check both steering modes, two-thumb controls and landscape readability on device.

Known limits remain within Phase 5A: health is stable, gathering/cooking/strategic
play is absent, well drinking has no container logistics, and work sites do not
fabricate resources or construction. Account v3 checkpoints remain local pending
separately authorized cloud compatibility. Stop here; Phase 5B is not implemented.
