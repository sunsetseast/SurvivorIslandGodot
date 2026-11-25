# Phase 0 verification record

Record the commit SHA, GitHub Actions run URL, Pages deployment URL and device results together so each test can be traced to a build.

| Check | Evidence |
| --- | --- |
| Godot 4.7.2 headless import and smoke test | Successful build job |
| Single-threaded Web export | Build artifact containing `index.html`, `index.js`, `index.wasm` and `index.pck` |
| Hosted browser launch | Verified deployment URL and a browser that renders the beach, capsule and FPS overlay |
| iPhone 17 Pro Max in Safari landscape | Record first-load time, legibility, independent two-thumb input, orientation changes, tab recovery, FPS and temperature |

This milestone ends at verifying the build and preview workflow. Character production, full island layout and additional gameplay are outside Phase 0.

### Phase 4A review

Main base was independently verified at the PR #10 merge. The draft introduces a
presentation-only title environment and shared `IslandTheme`; see the existing
technical design for ownership and the selective asset audit. Public exports use the
text title; private review staging may receive the original approved optimized logo
via `SURVIVOR_PRIVATE_LOGO`. Keep that variable out of public Actions. Review the
actual landscape UI before merge. Phase 4B should replace `_new_game` with the approved
18-person selection flow after reconciling the two reference cast catalogs; no Phase 4A
stats or custom rules should be inferred from the technical season.

Phase 4A visual revision replaces the rejected application styling with original private
wood/Survivant assets and a brighter live tropical title. `SURVIVOR_PRIVATE_UI` stages
only the four approved files through `tools/tonsai/stage_private_ui.py`. Public Actions
must leave it unset. Future artwork uses and deferred shoreline/wind/weather targets
are recorded in TECHNICAL_DESIGN.md. The Web regression now follows the deliberate
NEW_GAME → Choose Save Slot boundary; it retains the complete gameplay assertions.
