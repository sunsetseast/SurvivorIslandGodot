# Survivor Island technical design

Phase 3A establishes the game application and local technical season on Godot 4.7.2, typed GDScript and the Compatibility renderer. Phase 0 and the character laboratory remain separately staged development builds. The game starts at `application/game_app.tscn`. Controller B is the game default. Controller A remains available from the camp HUD for comparison.

## Application and ownership

| Owner | Responsibility |
| --- | --- |
| `SurvivorGameApp` | Menu, slot selection, settings, active session, suspension, shutdown and save policy |
| `PlayerProfile` | Installation-scoped guest principal and device preferences, independent of the controlled contestant and season |
| `LocationManager` | Mapping from semantic location IDs to available scene presentations, instantiation and teardown |
| `SeasonSimulation` | Canonical roster, controller ownership, ruleset, season phase, clock, RNG and command resolution |
| `CampSimulation` | Activity reservations, occupied objects, travel intent, object state and participant journals within a location |
| `GameSession` | Command submission, resolved receipts and authorized projections |
| `PersistenceProvider` | Slot inspection, revision-checked checkpoints and deletion |

The main menu offers New Game, Continue, Load Game and Settings. New Game uses an empty slot. The slot picker shows the season ID prefix, day, save revision and recovery status. Replacing a slot is an explicit two-step delete followed by New Game. Continue scans the three slots for the latest compatible save for the current guest. Manual Save and Main Menu are available in camp. If a save fails on exit, the game offers a choice between retaining the active session and explicitly leaving without saving.

The app cancels gestures and pauses the scene and season clock on suspension. Web uses visibility and page lifecycle events. Native uses application pause and resume notifications and intercepts window close to checkpoint. OS termination can occur before a lifecycle callback. Autosaves also run at season creation, on accepted conversation replies and every 30 simulation seconds. Camera steering, sensitivity, quality and preferred walking/running pace are device settings. A/B selection is temporary developer state.

## Simulation and presentation

The technical ruleset registers 18 contestants across three tribes of six. Five named NPC identities and one Explorer share the existing technical rig at Tonsai. The other two camps contain numbered catalog slots. Registry rows hold catalog reference, tribe, location, active status and human/AI assignment. Tribe membership and current location are separate fields. Swaps, merge, jury status and alternate roster construction belong in later rulesets. This ruleset validates its fixed membership when reading saves.

The fixed semantic step is 250 ms. The local host accumulates physics-clock deltas and consumes up to four steps per callback, dropping excess catch-up. Gameplay day rolls over every 2,400 steps in the technical season. The phase stays at camp. Wall-clock timestamps order saves. Rendering, camera interpolation and animation are presentation. Each of 17 NPCs has one bounded activity/deadline check per step. A physical camp reports actual arrivals or stalled routes. The other camps use a six-second abstract travel leg, then reserve and occupy an activity object on their respective schedules. Object IDs are scoped to their location. An occupied activity has an exclusive reservation and a deadline. Travel, pose and animation presentation can be reconstructed from the schedule.

Only Tonsai has a scene. Unloading it removes the physical adapter and lets the same session run abstractly. Occupied NPCs reappear at the activity site, while travelers restart their physical leg from the formation. Player position and heading are checkpointed independently. RNG seed and state reproduce the same trajectory for the same starting state, simulation steps and ordered trusted observations. Collision and navigation observations can differ between physical and abstract execution.

A local talk operation binds the guest principal, checks actor ownership and co-presence from trusted local observations, resolves one semantic action and emits a receipt. The scene subscribes and reacts to the result to open, animate or close the dialogue. Talk replies produce participant-specific records. The guest projection emits their own journal and the camp presentation fields. It omits other contestants' journals and off-screen state. Simulation state revisions track mutations independently from slot revisions. The protocol uses explicit command IDs, stable actor and target IDs, a result status, reason, revision and optional event. Accepted replies retain their IDs with bounded journal history. The open conversation is transient and closes on reload.

`RemoteGameSession` is the client boundary for a future server-backed implementation. It will receive projections and receipts over replaceable secure WebSockets. The dedicated headless Godot server must bind a verified principal per connection, own trusted movement and proximity observations, validate actions through the same rules, and project state and events per recipient. The local adapter's physics observations and save snapshots are internal host APIs. Server/private state needs an explicit allowlist for every projection and event before multi-user play. Add transport-level reconnect, ordering, receipt retention and revision reconciliation when introducing networking.

## Save format and migration

A save is a JSON envelope with schema, game version, save revision, UTC epoch timestamp and state. SHA-256 detects damaged payloads. Seed and RNG state are signed decimal strings to retain exact 64-bit precision through JSON. State covers guest and contestant IDs, ruleset and version, season ID, roster, tribes, phase, day, ticks, world objects, activity deadlines, participant journals and bounded pose. Active reservations are reconstructed from validated unique assignments. The app validates checkpoint location against the playable polygon and terrain. Nodes, resources, callbacks and UI state stay in memory.

Schema 2 adds the dive flag to the v1 pose. The migration defaults it to surface behavior in memory. Only a succeeding checkpoint writes the current format. Keep migrations stepwise and test old-format fixtures plus resumed deterministic behavior. Unknown schemas and rulesets block writes to their slot. A stale session revision or a different season cannot replace a valid existing slot.

Each slot alternates between two independently checksummed generations. A completed write is read back. A truncated generation leaves the other readable. Native writes to `user://` and flushes the newly written generation. Web replaces one origin-local `localStorage` entry synchronously, which avoids waiting for a deferred filesystem flush. Browser storage is best effort and can disappear with site data clearing, privacy mode, eviction, a different origin or a different device. One client instance per save slot is supported. Revision checks catch sequential stale writes. Simultaneous writers across browser processes do not have a transactional lock. Storage failures surface in the UI.

## Original game integration

The read-only SurvivorIsland2025 audit establishes existing system ownership and fidelity targets. Its save audit documents world snapshots and the difficult in-flight boundaries around camp activities, strategy and Tribal Council. The conversation and delegation architecture resolve semantic actions once, preserve attributed evidence, and give each contestant a separate view of what they heard, saw or inferred. [Save audit](https://github.com/sunsetseast/SurvivorIsland2025/blob/main/docs/save-state-audit.md) · [Conversations](https://github.com/sunsetseast/SurvivorIsland2025/blob/main/docs/conversations/ARCHITECTURE.md) · [Delegation](https://github.com/sunsetseast/SurvivorIsland2025/blob/main/docs/strategic-delegation/ARCHITECTURE.md)

| Future owner boundary | Integration target |
| --- | --- |
| Contestant registry and rulesets | Port stable character references and attributes separately from runtime stats. Season progression owns rounds, tribe swaps, merge, elimination and jury eligibility. |
| Relationship, trust and memory | Keep directed relationship/trust, attributed evidence, private incidents and perceived reliability as distinct durable projections. |
| Conversations, alliances and deals | Resolve shared semantic actions to durable receipts. Preserve conditional commitments, attributed promises, secrecy and consequence history. |
| Strategic objectives and delegated tasks | Plan at semantic boundaries with bounded candidate sets and owned evidence. Save acceptance, travel, execution, reporting and deadline state. A report reaches its recipient through a new interaction. |
| Challenge and Tribal Council | Public outcome and eligibility events feed progression. Sealed ballots, immunity, advantage resolution, revotes and jury state belong to authoritative rules. Define safe mid-event checkpoints before enabling resume there. |
| Camp objects, resources and inventory | Use location-scoped object and activity IDs. Extend reservation rules for sitting, resting, fire, water, shelter work and searches. Inventories and idol evidence have separate owner-private projections. |

Tonsai geometry uses the existing allowlisted inputs from SurvivorIsland3Dprototype. The adapter consumes the site's baked navigation and current character motor. The prototype's other maps, cast assets and artwork are outside game staging. See the [asset register](phase2/ASSETS.md) and the pinned checksums in [the Tonsai input manifest](../tools/tonsai/inputs.json).

## Delivery, performance and native platform

- Run `ci/test-simulation.sh` to verify the rules and persistence in an isolated project without art, scene, input or audio dependencies.
- `ci/build-tonsai.sh` imports an allowlisted project, bakes navigation, runs Tonsai and lifecycle tests, and exports single-threaded Compatibility Web. `tools/tonsai/review_web.py` exercises the real canvas, touch-slot corruption, locomotion, dialogue and a full browser reload. CI separately builds and smoke-tests Phase 0 and the laboratory.
- Publish the allowlisted game export to a separate HTTPS origin with the full source SHA in `source-commit.txt`. Preserve `main` and its Pages deployment. Keep generated export binaries, credentials, reference imagery and private likeness files out of the source branch. Include license notices and honor the individual source licenses before distributing an asset.
- Performance targets on landscape iPhone Safari are Full at 60 FPS where feasible (16.7 ms/frame) and Economy at 30 FPS or better (33.3 ms/frame), with six active rigs and 18 simulated contestants. Treat up to 18 visible rigs as a future stress case. Record browser/GPU, DPR, warm/cold cache, render frame duration, draw calls, startup, location transitions, save latency, scheduler cost and memory. Browser JavaScript heap and engine static allocation figures are partial metrics. Use device profiling for actual process/GPU memory. Reserve roughly 1 ms of a frame for a four-step simulation catch-up during this technical phase. Later work can vary render LOD, animation culling, tick cadence and off-screen simulation independently.
- Native iOS uses the same Godot project, Compatibility presentation and `user://` persistence. A future macOS/Xcode build host, tuned native export preset, App ID, signing and provisioning, device testing and App Store review are required. Validate safe areas, background termination, Keychain-backed account tokens and native performance when that build exists.

## Phase 3B prerequisites

Agree on account sign-in and guest linking semantics, including explicit import/ownership when an account already has a save. Define PostgreSQL rows and indexes, per-account row-level security, per-slot optimistic revisions, migration behavior and conflict UI before provisioning Supabase Auth and PostgreSQL over HTTPS. Define token storage, account deletion, retry/offline behavior and an authenticated test matrix across two devices. Cloud synchronization will consume the existing persistence and identity boundaries. Multiplayer hosting and native signing remain separate milestones.
