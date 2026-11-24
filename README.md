# Survivor Island — Godot Phase 0

The Phase 3A game starts at a development menu and runs an 18-contestant technical season with Tonsai as its playable camp. The [technical design](docs/TECHNICAL_DESIGN.md) covers the session, simulation, saves and build boundaries. Run `bash ci/build-tonsai.sh` with the pinned Godot toolchain to assemble the current game.

## Phase 0 laboratory

Phase 0 tests the iPhone-only build and preview workflow on Godot 4.7.2 stable. The scene uses Godot primitives for a short movement and camera test.

## Test on iPhone 17 Pro Max

1. Find **Publish GitHub Pages preview** in the latest successful main-branch [Actions run](https://github.com/sunsetseast/SurvivorIslandGodot/actions/workflows/ios-safari-web-export.yml). Open its deployment URL in Safari.
2. Turn off Portrait Orientation Lock and rotate the phone sideways. Wait for the beach, character and FPS display to appear.
3. Drag your left thumb from inside the left half of the screen to walk. Drag your right thumb from inside the right half to orbit the camera. Try both together, then lift each thumb separately to check that its input stops.
4. Rotate back to portrait and then back to landscape. Switch tabs and return. Check that the game resizes, the HUD stays legible, and controls respond again.
5. Note the initial load time and FPS while moving. After two to three minutes of short walks and camera turns, check for hitching, heat, reloads, and crashes. Stay on the sand. The scene has a finite collision plane.

On desktop use **WASD** or the arrow keys to walk, and right-drag to orbit the camera.

## Builds and preview

GitHub Actions imports the project, runs the headless smoke test and builds a single-threaded WebGL 2 export from the official Godot 4.7.2 editor and matching template. Each build uploads an artifact, and successful builds on `main` publish the same files to Pages.

For initial Pages setup, a repository administrator selects **Settings → Pages → Build and deployment → Source → GitHub Actions**. Then run the workflow on `main` from the **Actions** tab. The Pages deployment is a hosted preview. Keep private art and contestant references out of any public build.

To reproduce the build on Linux x86-64, run:

```sh
bash ci/install-godot-web.sh
bash ci/build-web.sh
python3 -m http.server 8000 --directory build/web
```

Open `http://localhost:8000/` in a browser. The smoke test covers scene initialization, player collision with the beach, the active camera, simultaneous movement and orbit, and touch cancellation. The build checks that the HTML, JavaScript, WebAssembly and resource pack were produced. Browser and device checks are recorded separately.

## Reference projects

- `sunsetseast/SurvivorIsland2025`
- `sunsetseast/SurvivorIsland3Dprototype`
