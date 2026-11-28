# Phase 5A checkpoint

Base c9d4b79 (merged #19); branch phase5a-living-camp.
Implementation commit: bd29005da944acc5a6acfb5a27905d882947aa22.
Draft PR: https://github.com/sunsetseast/SurvivorIslandGodot/pull/20.

Complete: v3 authoritative calendar/condition; exact integer rates; canonical
base-unit resources and atomic sequenced transactions; shared capacity/reservation
and physical-arrival lifecycle; cached utility profiles; abstract rival camps;
HUD/recovery/time periods; v2 migration, local downgrade/cloud fences; isolated
SQL compatibility candidate outside migrations. No production database changes.

Passing: `ci/test-simulation.sh` (foundation, compatibility, opening, 178 Living
Camp checks); 14 selected staged tests (session, stroke, moving board, race,
race UI, Phase 4C, Phase 4C camp, Tonsai, application, permanent application,
selection, title, credentials, benchmark). Isolated PostgreSQL 17: existing 39 +
39 checks and 54 v3 candidate checks pass. Logs retained under /tmp/*5a* and
/tmp/5a-*test.log. Private integrated stage: build/tonsai-project, source bd29005.

Complete: Web export and exact compressed reconstruction; all 11 required private
branding resources verified from the actual exported pack. Four private native
captures inspected (daytime, rest, night, restored), with real water consumption
and energy recovery assertions. Authoritative state restores exactly; a JSON
presentation coordinate differs by one ULP but the physical Vector3 is identical.
Application tests explicitly verify supplies pause, background pause, discarded
offline delta and normal resumed advancement.

Delivered: verified bd29005 export/evidence published through the established
owner-only operation. Native deployment and saved-version source provenance pass;
anonymous source/pack access reaches sign-in (pack HTTP 401). Authenticated HTTP
read-back is untested because this browser has no owner session. Owner iPhone
Safari remains untested. See VALIDATION.md for exact results and playtest steps.
Implementation scope is complete; retain draft status and do not begin Phase 5B.

Private approved assets recovered from the existing private preview export into
/workspace/private-assets (outside public repository). Private hosting checkout:
/workspace/private-preview. Owner-only access verified, no external visitors.
No credentials or private URLs belong in this public checkpoint. Disposable QA
containers were survivor-phase5a-db and survivor-phase5a-display; stopped after QA. Synthetic cloud
fixtures: /tmp/phase5a-fixtures. Do not rebuild/research completed work.
