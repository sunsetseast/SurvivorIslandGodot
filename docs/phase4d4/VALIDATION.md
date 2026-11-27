# Welcome to camp validation

Base: `2fbbf48` (merged PRs 17 and 18). Godot 4.7.2, Compatibility rendering.

| Check | Result |
| --- | --- |
| `ci/test-simulation.sh` | Pass: foundation, legacy/catalog compatibility and permanent-opening tests |
| `opening_application_test.gd` in approved private stage | Pass: button input, arrival teardown, two/three tribes, initial write failure/retry, uncertain read-back, slot conflict, ownership changes, camp-load failure, Continue/Load |
| Isolated PostgreSQL 17, all migrations | Pass; disposable container only |
| Existing `supabase/tests/configurable_rpc.py` synthetic fixtures | 39 checks pass |
| `supabase/tests/opening_rpc.py` synthetic fixtures | 39 checks pass, including all reward/empty cases, ownership, bounds, downgrade and account isolation |
| Integrated Tonsai stage / Web export | Pass: 14 selected existing session/race/camp/app/UI checks; single-threaded 4.7.2 Compatibility export |
| Private branding packaging guard | Pass: all 11 resources loaded from exported PCK; exact engine/pack reconstruction |
| Genuine native touch journey | Reached actual arrival and Day 1; both camp steering modes passed. Supplies return was then fixed and checked with the retained genuine handoff |
| Retained genuine handoff → Day 1 → supplies → Continue/Load | All input assertions pass; 209 meaningful events, all 50 dispositions; opening packet 59,056 bytes |
| Fresh application restart / account local-only creation | Pass |
| iPhone Safari landscape | Not run; owner device acceptance required |

Synthetic catalogs are confined to isolated simulation/cloud fixtures. Application
checks use the approved catalog recovered from the existing owner-private build.
No restricted assets or personal test data belong in source or public artifacts.
Failures found during production-input validation were corrected: navigation repath
diagnostics have no witness list and stay transient; historical floating-point
measurements use canonical decimal strings to prevent JSON drift; Back to Camp
stays above the scrolling supplies list. Synthetic fixtures now cover fractional
measurements and navigation diagnostics. The native capture driver still reports
two 21,844-byte texture leaks at shutdown with forced rendering; this is not a
clean graphics-resource acceptance result. No iPhone performance claim is made.

The original integrated build's unchanged deck-stress sweep was stopped after six
completed cases (maximum observed carrier stall 2s), then relevant checks continued
on the same stage: session, stroke impulses, moving boarding, race UI/authority,
Phase 4C configuration/camp, Tonsai, application, permanent application, selection,
title, credential and benchmark. The full legacy stress sweep is not claimed to pass.
Use `TONSAI_STAGE_ONLY=1 bash ci/build-tonsai.sh` to prepare a stage, then run selected
tests with `godot --headless --path build/tonsai-project --fixed-fps 60 --script res://tests/NAME.gd`.
The export uses `--export-release Web`; `package_preview.py --require-private-brand`
checks the actual pack before private publication. Runtime implementation checked
through `58b573b`; later delivery documentation and source markers do not change it.

No production database migration has been applied. New account openings retain
local checkpoints and explicitly show pending cloud support.

Owner playtest: New Game → choose contestant → configuration → confirm tribe →
empty slot. Complete marooning, review actual earned supplies, Begin Day 1. Verify
movement/orbit in both steering modes, unlit fire, six/nine actual tribe members,
Tribal Supplies, Save, Main Menu, Continue, Load and browser reload. Test Safari
landscape, two thumbs, background/resume and storage failure separately on device.
