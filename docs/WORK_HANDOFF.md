# Phase 0 verification record

Record the commit SHA, GitHub Actions run URL, Pages deployment URL and device results together so each test can be traced to a build.

| Check | Evidence |
| --- | --- |
| Godot 4.7.2 headless import and smoke test | Successful build job |
| Single-threaded Web export | Build artifact containing `index.html`, `index.js`, `index.wasm` and `index.pck` |
| Hosted browser launch | Verified deployment URL and a browser that renders the beach, capsule and FPS overlay |
| iPhone 17 Pro Max in Safari landscape | Record first-load time, legibility, independent two-thumb input, orientation changes, tab recovery, FPS and temperature |

This milestone ends at verifying the build and preview workflow. Character production, full island layout and additional gameplay are outside Phase 0.
