# Phase 5A checkpoint

Base c9d4b79 (merged #19); branch phase5a-living-camp.
Implementation commit: 4a94520b30aa15a529f49cb58d9cab9d0051fee4.

Complete: v3 authoritative calendar/condition; exact integer rates; canonical
base-unit resources and atomic sequenced transactions; shared capacity/reservation
and physical-arrival lifecycle; cached utility profiles; abstract rival camps;
HUD/recovery/time periods; v2 migration, local downgrade/cloud fences; isolated
SQL compatibility candidate outside migrations. No production database changes.

Passing: `ci/test-simulation.sh` (foundation, compatibility, opening, 174 Living
Camp checks); 14 selected staged tests (session, stroke, moving board, race,
race UI, Phase 4C, Phase 4C camp, Tonsai, application, permanent application,
selection, title, credentials, benchmark). Isolated PostgreSQL 17: existing 39 +
39 checks and 54 v3 candidate checks pass. Logs retained under /tmp/*5a* and
/tmp/5a-*test.log. Private integrated stage: build/tonsai-project, source 4a94520.

Remaining: finish Web export using ABSOLUTE output path (first export used a
relative path and failed before producing an artifact); inspect four private
captures; finish saved/restored evidence assertion in ignored living_evidence.gd;
package/verify private branding and publish to the established owner-only preview;
verify deployed source/pack and anonymous denial. Owner iPhone Safari untested.

Private approved assets recovered from the existing private preview export into
/workspace/private-assets (outside public repository). Private hosting checkout:
/workspace/private-preview. Owner-only access verified, no external visitors.
No credentials or private URLs belong in this public checkpoint. Disposable QA
containers: survivor-phase5a-db and survivor-phase5a-display. Synthetic cloud
fixtures: /tmp/phase5a-fixtures. Do not rebuild/research completed work.
