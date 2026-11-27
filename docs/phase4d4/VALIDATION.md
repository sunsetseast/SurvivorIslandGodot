# Welcome to camp validation

Base: `2fbbf48` (merged PRs 17 and 18). Godot 4.7.2, Compatibility rendering.

| Check | Result |
| --- | --- |
| `ci/test-simulation.sh` | Pass: foundation, legacy/catalog compatibility and permanent-opening tests |
| `opening_application_test.gd` in approved private stage | Pass: button input, arrival teardown, two/three tribes, initial write failure/retry, uncertain read-back, slot conflict, ownership changes, camp-load failure, Continue/Load |
| Isolated PostgreSQL 17, all migrations | Pass; disposable container only |
| Existing `supabase/tests/configurable_rpc.py` synthetic fixtures | 39 checks pass |
| `supabase/tests/opening_rpc.py` synthetic fixtures | 39 checks pass, including all reward/empty cases, ownership, bounds, downgrade and account isolation |
| Integrated Tonsai build and private branding package | Pending |
| Full genuine-input permanent journey | Pending |
| iPhone Safari landscape | Not run; owner device acceptance required |

Synthetic catalogs are confined to isolated simulation/cloud fixtures. Application
checks use the approved catalog recovered from the existing owner-private build.
No restricted assets or personal test data belong in source or public artifacts.
No production database migration has been applied. New account openings retain
local checkpoints and explicitly show pending cloud support.

Owner playtest: New Game → choose contestant → configuration → confirm tribe →
empty slot. Complete marooning, review actual earned supplies, Begin Day 1. Verify
movement/orbit in both steering modes, unlit fire, six/nine actual tribe members,
Tribal Supplies, Save, Main Menu, Continue, Load and browser reload. Test Safari
landscape, two thumbs, background/resume and storage failure separately on device.
