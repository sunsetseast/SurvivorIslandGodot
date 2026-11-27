# Phase 4D.3.2 — continuous marooning

Work in progress. This is not an acceptance report.

Verified starting main: `75090ff8baeea0ae51a6519d67dc74b754d906fa`.
Verified draft PR #17 head: `1016476c0049363c082cdcce3f812a83c4b7f16e`.
PR #17 is open/draft, unmerged, with no auto-merge. Existing owner-private Site
policy revision 1 has one owner, no editors, groups or external visitors. No
restricted assets are served outside that policy. Approved catalog has 18 stable
identities and 486 unchanged ratings; baseline SHA-256:
`7bd827434176ff969fa6545a061503d3ceacf6f8217c7736ad2e3714b6370f43`.

Implementation order follows the owner brief: concurrent authority; physical side
access/mooring/traffic; stroke impulses and boarding; reward/shore progression;
scoped character/environment/HUD presentation; native/hosted acceptance and private
delivery. No Phase 4D.4 or permanent save changes.

The old 120s collection and global assembly/race gate are replaced by a 60s maximum
collection window concurrent with independently launched tribal rafts and swimmers.
One fixed-step gameplay clock, actor table, item ledger and semantic journal own the
session. Renderers cannot advance authority or recreate actors at departure.

Atomic order for each 1/60s step: synchronize validated physical positions; complete
supply commands by due time then ID through the cutoff; close global collection at
60s/all-secured; evaluate/commit each eligible launch and lock that tribe's station;
resolve reserved moving climbs; strokes, vessel motion, claims and landing checks.
A valid deposit completed exactly at a cutoff counts before closure. Pending later
commands are cancelled; launch never awards held cargo. Own station closure is
permanent and independent of other tribes' collection window.

Transient version 2 will retain original configuration/catalog fingerprint, seed,
RNG states, all 50 dispositions and quantities, contribution aggregates, routes,
launch reasons, impulse totals, swimming/fatigue, reward location and explicit
physical/recovered arrivals. Old pure-command fixtures retain meaningful coverage;
no production season, slot, profile, cloud revision or multiplayer behavior changes.

Design: [DESIGN.md](DESIGN.md). Presentation: [PRESENTATION.md](PRESENTATION.md). Observed tests and open final acceptance: [VALIDATION.md](VALIDATION.md).
