# Phase 4D.1 validation

Base: `131d352c1c622c20d2a2bdaccf82aecf2cef23aa`, independently verified against
remote main before branching. Main Actions run 45790911066 succeeded. The earlier
editor double-free report did not reproduce in the local baseline import/test run.
The first local Web export was blocked by absent pinned templates; installing the
existing project's checksummed template resolved that setup issue.

Godot 4.7.2 stable `ed1daf0bf`, Compatibility, single-thread Web. No infrastructure,
Supabase schema, account or server changes. No engine or controller changes.

Validated locally:

- Simulation foundation and season save-compatibility gates.
- Existing Phase 0 Web smoke/export gate.
- Existing Tonsai movement, swimming, orbit, touch regression and application
  lifecycle, selection, title, credential and benchmark tests; Web export.
- `tests/marooning_test.gd`: both tribe counts, 18 IDs, controlled actor, distinct
  spawns, raft counts, route/marker contracts, skip and natural intro completion,
  actual simultaneous touch events (including deliberately corrupted reported
  deltas), cancellation, deck support, physical host ramp traversal, real beach
  and dock support, transient configuration preservation and scene teardown.
- Private catalog reconstructed by the existing staging helper from the documented
  pinned reference checkouts: all 18 entries, 27 attributes each, existing portraits,
  zero new models. Staged files and browser captures stay outside public source.

Reproduce browser review on a **private** staged build:

```
python3 tools/marooning/review_web.py http://127.0.0.1:3000 build/private-review
```

This uses a 956 x 440 landscape touch viewport in Chromium with software rendering.
It records actual in-game frames, browser errors, resource requests and wall-clock
render intervals; it is not an iPhone Safari performance measurement. It exercises
selection → tribe review → preview, real dual-touch movement/orbit and release,
zero season/slot/revision creation, exit and reentry. Never upload its private
captures or private export to public GitHub artifacts.

Known limits: simple procedural supply/reward props; identical existing temporary
rigs with name labels and tribe accents; no contestant likeness production. Cannons
integrated into the ship body mesh remain outside the circulation rails (separate
gunport/furled-sail nodes are hidden). The near beach is a small environment endpoint,
not Tonsai camp. Platforms do not move. Physical iPhone frame rate and Safari touch
behavior still require owner device testing. All supply scramble gameplay is deferred.

Owner-only hosting: serve `build/private-preview` on the environment's configured
HTTP port 3000. The current Cloud status lists the port but provides no hosted URL;
HTTPS delivery is blocked until the environment supplies that owner-only preview URL.
No public deployment was substituted.
