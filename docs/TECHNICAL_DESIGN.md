# Survivor Island technical design

The game application and local technical season use Godot 4.7.2, typed GDScript and the Compatibility renderer. Phase 0 and the character laboratory remain separately staged development builds. The game starts at `application/game_app.tscn`. Controller B is the game default. Controller A remains available from the camp HUD for comparison.

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

The main menu offers New Game, Continue, Load Game, Private Multiplayer, Settings and Account. New Game uses an empty slot. The slot picker shows the season ID prefix, day, save revision and recovery status. Replacing a slot is an explicit two-step delete followed by New Game. Continue scans the three slots in the active guest or account namespace. Manual Save and Main Menu are available in single-player camp. If a save fails on exit, the game offers a choice between retaining the active session and explicitly leaving without saving.

The app cancels gestures and pauses the scene and season clock on suspension. Web uses visibility and page lifecycle events. Native uses application pause and resume notifications and intercepts window close to checkpoint. OS termination can occur before a lifecycle callback. Autosaves also run at season creation, on accepted conversation replies and every 30 simulation seconds. Camera steering, sensitivity, quality and preferred walking or running pace are stored on the device. Account control transfer is explicit. A/B selection is temporary developer state.

## Simulation and presentation

The technical ruleset registers 18 contestants across three tribes of six. Five named NPC identities and one Explorer share the existing technical rig at Tonsai. The other two camps contain numbered catalog slots. Registry rows hold catalog reference, tribe, location, active status and human/AI assignment. Tribe membership and current location are separate fields. Swaps, merge, jury status and alternate roster construction belong in later rulesets. This ruleset validates its fixed membership when reading saves.

The fixed semantic step is 250 ms. The local host accumulates physics-clock deltas and consumes up to four steps per callback, dropping excess catch-up. Gameplay day rolls over every 2,400 steps in the technical season. The phase stays at camp. Wall-clock timestamps order saves. Rendering, camera interpolation and animation are presentation. Each of 17 NPCs has one bounded activity/deadline check per step. A physical camp reports actual arrivals or stalled routes. The other camps use a six-second abstract travel leg, then reserve and occupy an activity object on their respective schedules. Object IDs are scoped to their location. An occupied activity has an exclusive reservation and a deadline. Travel, pose and animation presentation can be reconstructed from the schedule.

Only Tonsai has a scene. Unloading it removes the physical adapter and lets the same session run abstractly. Occupied NPCs reappear at the activity site, while travelers restart their physical leg from the formation. Player position and heading are checkpointed independently. RNG seed and state reproduce the same trajectory for the same starting state, simulation steps and ordered trusted observations. Collision and navigation observations can differ between physical and abstract execution.

A local talk operation binds the guest principal, checks actor ownership and co-presence from trusted local observations, resolves one semantic action and emits a receipt. The scene subscribes and reacts to the result to open, animate or close the dialogue. Talk replies produce participant-specific records. The guest projection emits their own journal and the camp presentation fields. It omits other contestants' journals and off-screen state. Simulation state revisions track mutations independently from slot revisions. The protocol uses explicit command IDs, stable actor and target IDs, a result status, reason, revision and optional event. Accepted replies retain their IDs with bounded journal history. The open conversation is transient and closes on reload.

`RemoteGameSession` is the client boundary for a future server-backed implementation. It will receive projections and receipts over replaceable secure WebSockets. The dedicated headless Godot server must bind a verified principal per connection, own trusted movement and proximity observations, validate actions through the same rules, and project state and events per recipient. The local adapter's physics observations and save snapshots are internal host APIs. Server/private state needs an explicit allowlist for every projection and event before multi-user play. Add transport-level reconnect, ordering, receipt retention and revision reconciliation when introducing networking.

## Save format and migration

A save is a JSON envelope with schema, game version, save revision, UTC epoch timestamp and state. SHA-256 detects damaged payloads. Seed and RNG state are signed decimal strings to retain exact 64-bit precision through JSON. State covers guest and contestant IDs, ruleset and version, season ID, roster, tribes, phase, day, ticks, world objects, activity deadlines, participant journals and bounded pose. Active reservations are reconstructed from validated unique assignments. The app validates checkpoint location against the playable polygon and terrain. Nodes, resources, callbacks and UI state stay in memory.

Schema 2 adds the dive flag to the v1 pose. The migration defaults it to surface behavior in memory. Only a succeeding checkpoint writes the current format. Keep migrations stepwise and test old-format fixtures plus resumed deterministic behavior. Unknown schemas and rulesets block writes to their slot. Ordinary checkpoints reject stale revisions and different seasons. Explicit cloud conflict resolution can install a checked replacement while retaining the prior generation.

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
- Native iOS uses the same Godot project, Compatibility presentation and `user://` persistence. The Phase 3D standard macOS Actions workflow verifies unsigned readiness; permanent App ID, signing and provisioning, device testing and App Store review remain release tasks. Validate safe areas, background termination, Keychain-backed account tokens and native performance when that build exists.

## Connected accounts and private checkpoints

### Integration choice

The connected menu uses Godot 4.7.2's asynchronous, non-threaded `HTTPRequest` and Supabase's Auth, PostgREST and Edge Function endpoints. Requests carry an `sb_publishable_` key in `apikey`. Authenticated requests send the user JWT in a separate bearer header. The adapter bounds bodies and lifetimes, rejects redirects, cancels obsolete requests and maps transport and service errors without retaining raw auth responses. The game makes zero connected requests for guests.

| Candidate inspected | Result |
| --- | --- |
| Supabase Community Godot 4.x at `77c21f5fb2bf93c71440ae57e5469aa6684bd0dc` (2024-11-13) | MIT, about 152 KiB of addon source. Uses callbacks and HTTP requests, has email OTP and recovery requests, and exposes credentials in the addon user object. Refresh is chained by timer. The project would still need session fencing and rotation coordination, recovery UI and permission-specific RPC wiring. Modern key compatibility, Safari and iOS behavior were unverified. |
| Overvault Supabase Godot API at `2265eaeffd746c7fa3cf2ab9b60d5244a6fac17d` (2025-04-13) | MIT, about 108 KiB. Provides asynchronous tasks and email/password registration. The inspected implementation verifies phone OTP and sends its refresh token to the invite endpoint. The addon lacks the complete email-code recovery workflow. Godot 4.7.2 Web and iOS were unverified. |
| Native Godot HTTPRequest with focused adapter | Zero vendored dependencies. One request node per active exchange with completion and cancellation. Single-threaded Compatibility Web and headless Godot use the same source. Native iOS uses the compatible HTTPRequest API and remains a device validation item. |

No addon source was copied or linked. [Community source](https://github.com/supabase-community/godot-engine.supabase/tree/77c21f5fb2bf93c71440ae57e5469aa6684bd0dc) · [Overvault source](https://github.com/Overvault-64/Supabase-Godot-API/tree/2265eaeffd746c7fa3cf2ab9b60d5244a6fac17d) · [Godot HTTPRequest](https://docs.godotengine.org/en/stable/classes/class_httprequest.html)

### Identity and credentials

| Identity | Persistence and binding |
| --- | --- |
| Supabase account UUID | Verified session subject. Selects the private local namespace `survivor-3b-account-<uuid>` and server-owned rows. |
| Installation | Random 32-character ID in the original guest namespace. Represents this installation independent of sign-in. |
| Guest | Existing 32-character principal and the original three slots under `survivor-3a`. |
| Season principal and contestant | The original checkpoint `player_id` binds the catalog contestant within the season, including when an account takes ownership. New account seasons use an independent local 32-character principal. A future authoritative season binds the account UUID to a server-selected contestant per season. |
| Season and save | Season ID stays stable. A local ordinal 1–3 selects a checkpoint. A generated cloud save UUID selects a private history, which can fork into another UUID while retaining the same season ID. |

Sign-in, explicit email-code verification, recovery and password update use Supabase Auth. Verification and recovery templates issue short-lived email codes using `{{ .Token }}`. Confirmation is required. Supabase generates, validates and rotates tokens. Recovery sessions may update the password through the recovery menu. The client signs out afterward. Forms mask passwords, clear the password field on submission and omit credentials from diagnostics, errors and save data. Web and Android remain memory-only. iOS persists refresh credentials through the Phase 3D Keychain boundary when its plugin is available. Device access and same-origin code still govern local save confidentiality. Access tokens remain in process memory.

The auth epoch invalidates requests when the account session changes. A single refresh handles concurrent authenticated requests. The refresh replaces both tokens together. Transport and rate-limit failures keep the current account cache available in the running process. Explicit revocation clears credentials and switches the app back to the guest namespace. Logout immediately clears the local session and attempts Supabase session revocation. [Passwords](https://supabase.com/docs/guides/auth/passwords) · [Sessions](https://supabase.com/docs/guides/auth/sessions) · [Templates](https://supabase.com/docs/guides/auth/auth-email-templates) · [API keys](https://supabase.com/docs/guides/getting-started/api-keys)

### Local and cloud data

Each account has three independently cached slots on an installation and a maximum of three active cloud saves. Guests can explicitly copy a season into an empty account slot. A duplicate season is detected locally or rejected by the cloud importer. An imported guest snapshot keeps its original local copy. Browser storage is origin-specific. Same-origin legacy Phase 3A data remains readable, including data written through the older IDBFS fallback. The preview is on its own origin and begins with separate guest storage.

Local generation, local checkpoint revision, simulation revision and cloud revision are independent. The game always confirms its local checkpoint before queueing it. The account-scoped sync journal uses two checksummed generations. An upload keeps its original operation UUID, expected revision and immutable payload until acknowledged. A later local checkpoint is coalesced into the next upload. Active sessions checkpoint locally on the existing 30-second schedule. Cloud attempts are spaced at about 90 seconds for automatic checkpoints and scheduled immediately for manual saves or returning to the menu. Transient failures use backoff and jitter, with retry hints when available. Loading a cloud list returns metadata only. Download validates the selected retained checkpoint with SaveCodec and installs a local recoverable generation before it may be resumed.

Cloud Saves is reachable from Account Profile and Load Game. Refresh fetches current metadata for the signed-in account. The menu displays an empty library only after validating an empty PostgREST array. If refresh fails or returns malformed data, the menu displays an error and keeps the last loaded rows visible. A successful refresh is required to select a row. Ending the account session clears the visible listing. Load Game reports sync state from the account's journal and the local checkpoint acknowledgement. Local and cloud revision numbers can differ even when the checkpoint is synced. Account and slot menus use a touch-scrollable panel that scales to the Web visual viewport. A menu swipe cancels the pending tap and lets Godot clear its touch focus on release. Backgrounding cancels an active menu gesture. Gameplay keeps its existing touch input handling.

Cloud revision checks are atomic and serialize account mutations. Conflicts show local and cloud day, tick and revision. Keep Cloud explicitly installs the selected current remote checkpoint. Keep Local sends the snapshot with the confirmed cloud revision. Preserve Both queues the local snapshot under a new save UUID and leaves the remote history present. Cancel keeps both records. An explicitly restored historical revision stays local until selected for its own cloud copy. The game never merges divergent histories based on wall-clock timestamps.

Player controls are retained on the device until the player explicitly saves or applies account controls. The cloud holds steering, sensitivity and default pace with a server revision. A conflicting write requires reloading the current revision. Rendering quality, the accepted multitouch correction and local control selection remain device behavior.

### Database, permissions and deletion

`survivor_private` holds profiles, settings, save metadata and revisions. All tables enable RLS with default-deny behavior and have zero client grants. The public invoker RPC authorizes the authenticated role to call one tightly scoped private definer with an empty search path. The private function derives identity from `auth.uid()`, checks the confirmed Auth user and live session row, and filters reads and writes by owner. Clients cannot assign owners or bypass checks through PostgREST tables. Passwords, secrets and refresh tokens never enter game data. [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) · [API security](https://supabase.com/docs/guides/api/securing-your-api) · [Functions](https://supabase.com/docs/guides/database/functions)

Postgres checks the SaveCodec envelope, checksum, supported ruleset, roster, pose, camp and journal bounds. Integer fields accept equivalent whole JSON numbers such as `100` and `100.0`. The validator preserves the original snapshot bytes and rejects fractions in those fields. It retains three revisions per active save and accepts snapshots up to 256,000 UTF-8 bytes. Three full histories consume at most 2,304,000 payload bytes per account before database overhead. The tested technical-season fixture is under 6 KiB. Long, journal-heavy local checkpoints may exceed the cloud budget and stay available locally. A matching retained operation replays its acknowledgement. A pruned old operation still carries a stale expected revision and cannot create a new revision. Deleting a save removes its payload and leaves bounded tombstone metadata to fence delayed creates.

The account deletion function verifies the gateway bearer and checks the live session and user. It verifies the password through GoTrue, checks that the reauthenticated user matches, then uses the server-only Auth admin API. The request has no target ID field. Hard deletion cascades from `auth.users` to profiles, settings, slots and revisions. An already-deleted user and a revoked session cannot access protected game data even while a prior access token is within its signed lifetime. The client clears that account's credential and local save namespace on confirmed success. An interrupted response can require signing in again to determine if the account still exists. Independent installations retain local caches until the owner clears site data or confirms deletion there. [Edge authorization](https://supabase.com/docs/guides/functions/auth)

### Reproduce and deploy

- Use the isolated Supabase CLI project in `supabase/` with PostgreSQL 17. Authenticate tooling against the specific development project only. This task used v2.84.2 for the local CLI attempt. The November 2026 v3 CLI targets local by default, prompts for hosted mutations and removes deprecated commands. Discover flags with local `--help` and confirm the destination before any hosted write. [CLI v3 breaking change](https://supabase.com/changelog/supabase-cli-v3)
- Start and reset the local Supabase stack, including Auth, PostgREST, Mailpit and the Edge runtime. Serve local functions with the configured gateway JWT verification. Run `supabase/tests/permissions.sql` through local `psql -v ON_ERROR_STOP=1`. Generate the payload fixture with the Godot script `supabase/tests/make_snapshot.gd`, passing an absolute output file after `--`. Set `SURVIVOR_TEST_PUBLIC_KEY` to the local publishable key and run `python3 supabase/tests/integration.py /path/to/fixture.json`. This test is loopback-only and creates and deletes its own disposable users.
- Test independent browser storage with `python3 supabase/tests/browser_sync.py build/tonsai` after building Tonsai and installing Playwright. Pass `--guest-fixture /path/to/fixture.json` to start with a previous game checkpoint. This routes the exported build's target requests to the local test services. Desktop browser timing does not substitute for landscape iPhone 17 Pro Max Safari acceptance.
- Run `python3 supabase/tests/browser_listing.py build/tonsai /path/to/fixture.json` for the portrait and landscape cloud listing regression. The loopback test returns real PostgREST arrays through a gzip-compressing HTTP proxy with an exposed Content-Encoding header. It exercises malformed and unavailable refresh responses, recovery on retry, and a swipe followed immediately by a tap and restore from Load Game. It creates its own disposable Auth account through local Mailpit.
- Apply the reviewed SQL migration to project `hjmhgibfbxgzqvfdomoj` and read back the migration ledger, constraints, grants, RLS and advisors. Deploy `delete-player` with gateway JWT verification enabled. Configure the Confirmation and Reset Password templates in that project's Auth dashboard from `supabase/templates/`, keep email confirmation enabled and use an authorized team recipient for hosted private testing.
- Hosted default SMTP sends only to project team recipients and documents a two-message hourly limit. Keep public release gated on a production email delivery plan. This phase uses the free development tier with no Realtime connection, no paid services and no automatic hosted deployment from the PR. [SMTP restrictions](https://supabase.com/docs/guides/auth/auth-smtp) · [Auth testing](https://supabase.com/docs/guides/auth/testing-auth-flows)

### Deployment and verification record

The development database contains `20261125010040_connected_foundation`, `20261125010228_restrict_direct_access` and `20261125021747_accept_integral_checkpoints`. The hosted migration ledger hashes match the SQL files. Readback verified four private RLS tables, four restrictive policies, constraints, Auth cascades, and RPC grants. The security advisor returned zero findings after restricting the existing automatic RLS trigger's execute grant. The performance advisor flagged the account index as unused on the empty development project. Retain it for owner-scoped listings and foreign-key cascades. The `delete-player` function is active with gateway verification enabled. Hosted email confirmation is required, and both protected endpoints returned HTTP 401 to the publishable key alone.

Local Auth, PostgREST, PostgreSQL 17, Mailpit and the deletion handler passed email verification, invalid code and password handling, password recovery, refresh rotation, logout, deletion, owner isolation, RPC-only access, oversized and invalid payload rejection, simultaneous revision checks, idempotent retries and bounded retention. The standard CLI image pull hit a workspace Docker storage limit. The local verification ran the underlying services separately and exercised the deletion handler in Deno. A physical iPhone tester reported successful hosted registration, verification, sign-in, play and local persistence. A read-only hosted check confirmed the uploaded cloud checkpoint and its retained revisions. Authenticated hosted listing, refresh and independent-device restoration are physical iPhone acceptance steps that the player runs in Safari with their own account.

In the single-threaded Web build, two Chromium browser contexts with separate storage imported a Phase 3A guest checkpoint, restored matching season state, resumed it, synchronized an offline checkpoint after reconnecting and hid Account A's saves after switching to Account B. The test build routed browser requests to the local Supabase services. In that run the menu loaded in 6.0 and 14.0 seconds, import was observed within 484 ms and reconnect including retry delay took 4.2 seconds. The 5,859-byte round-tripped fixture uploaded in 26 ms in the separate local API run. The existing GitHub Actions browser regression also passed. Software-rendered Chromium timings are not physical mobile performance measurements.

The listing investigation distinguished hosted list requests from upload acknowledgements by request length. The list returned HTTP 200 with JSON metadata headers and no recorded Content-Length. On Web, browser Fetch decompresses the response body. Godot HTTPRequest's additional gzip processing is now disabled on Web so an exposed Content-Encoding header cannot trigger a second decompression. The starting Web build reproduced the missing single row against a real chunked gzip response from the loopback proxy, even though the decoded PostgREST body contained one valid save. The correction lists these responses without changing the hosted RPC or database. Native HTTPRequest still handles compression.

## Phase 3C dedicated multiplayer

The dedicated Godot host runs the same `SeasonSimulation` and `CampSimulation` as single-player. Account UUIDs, live Auth sessions, WebSocket connections and contestant IDs have distinct lifecycles. The host fixes membership when the private room fills and assigns Explorer and Jeremy at Tonsai. AI drives the remaining four active camp bodies and twelve off-screen contestants under the same semantic rules. Other camp locations remain abstract. Independent humans can speak with different NPCs at once. Each NPC can have one conversation partner. The single-player save schema and cloud validator retain the original one-human ruleset.

### Transport and authority

Protocol v1 uses text JSON over Godot `WebSocketPeer` for native and single-threaded Web builds. The host allows eight sockets, 4 KiB request packets, 32 queued packets per socket, 40 packets per second per client and one join-code attempt per account every two seconds. The private room uses a random 48-bit code, which can admit a second verified account only while the room is filling. Clients reconnect by authenticated membership. An admitted replacement connection closes the previous controller. Client retry uses six delays from one to fifteen seconds and offers a manual reconnect. A silent connection expires after twelve seconds. An admitted player has up to 45 seconds to load the camp and acknowledge the initial snapshot. The host streams movement after readiness and begins the season when both players are ready.

A client sends sequenced world-space movement intent about 18 times per second. The server runs the shared capsule motor at 30 Hz using baked Tonsai collision and navigation. It accepts bounded walk, run and water inputs and drops stale movement after 300 ms. All positions, headings, arrivals, line-of-sight and conversation-range checks belong to the host. The camera and both steering modes run locally. The client predicts its own movement with the shared motor, corrects against authoritative physics, and interpolates other bodies from 10 Hz movement snapshots. Semantic simulation runs at 4 Hz. Public camp activity changes travel separately from movement. A private journal is streamed only to its participant using bounded batches. Each contestant receives public camp state for their location and their own journal. The server never publishes the recovery record.

### Sign-in and durability

The host sends only the access token to the pinned project’s Auth `/user` endpoint and the existing `player_data` live-session gate. Both must authorize the token before the host uses its claims to check project issuer, audience, identity, session and expiry. The client renews about every 25 seconds and the host revalidates every 45 seconds with a 12-second deadline. Revocation can therefore take up to 57 seconds during a live connection. Expiry, replacement and observed disconnect remove command authority immediately. Tokens remain in memory and travel only in the WSS auth or renewal message and the server’s HTTPS verification calls. [Supabase sessions](https://supabase.com/docs/guides/auth/sessions)

The private season freezes immediately when both members leave or after a five-second grace period when one leaves. Reconnecting after suspension requires both members to continue the clock. Talking locks are transient and close on disconnect or suspension. The host writes one revision-checked row at room transitions, on accepted conversation replies, at suspension and on graceful exit. It also checkpoints movement and the clock approximately every 15 seconds while active. An irreversible reply is acknowledged only after Postgres commits the updated journal and reply receipt. A durable per-contestant command sequence rejects replays older than the last committed reply. An unexpected process loss can discard uncheckpointed movement and time while preserving acknowledged replies and membership. A storage failure stops the host so restart recovers from the latest committed revision. There are no save slots or user-selectable recovery generations. The deployment is a single replica and one fixed two-account test room. Competitive deadline policies, more room capacity and replacement contestants can build on the same session and decision-source boundaries.

### Build and deploy

- Run `bash ci/build-server.sh` with the pinned Godot 4.7.2 executable in `GODOT_BIN`. An existing client stage built with `TONSAI_PREPARE_SERVER=1` can be reused by setting `TONSAI_SERVER_BAKE=build/tonsai-project`. The dedicated resource package contains GDScript, collision shapes, navigation and heightfield data. The runtime image has no client meshes, textures, animation, audio, camera or menu assets.
- For local verification, start the disposable Supabase stack with the repository migrations and email templates. Use its local publishable key as `SURVIVOR_TEST_PUBLIC_KEY`, set `SURVIVOR_TEST_DB_DSN` to the local Postgres connection, then run `python3 supabase/tests/multiplayer.py` with `websockets` installed. The browser companion uses `python3 supabase/tests/browser_multiplayer.py build/tonsai` with Playwright, Chromium and Caddy. Each suite creates its own confirmed accounts and temporary checkpoint credential on a fresh local database. The protocol suite can additionally verify signed expired credentials with the disposable stack's `SURVIVOR_TEST_JWT_SECRET`.
- In Safari, create a Render **Web Service** for this repository and the draft PR branch. Select **Docker**, **Free**, Dockerfile `./server/Dockerfile`, health check `/health`, and one instance. `render.yaml` records the same configuration. Caddy binds Render’s `PORT` and proxies only the `/ws` upgrade to loopback Godot. Render terminates TLS. The process stores no season data on Render’s filesystem and runs no external keep-alives. [Render Free](https://render.com/docs/free) · [WebSockets](https://render.com/docs/websocket)
- In the named development project's Supabase SQL Editor, run the bootstrap once after the migration. Copy the single result directly into Render’s secret environment setting `SURVIVOR_CHECKPOINT_KEY`. The database retains a SHA-256 digest, and the credential can only read or compare-and-swap this checkpoint. Client roles have zero table grants; only the anonymous RPC route can try the opaque key. No service-role credential is needed.

```sql
with key_value as materialized (
    select encode(extensions.gen_random_bytes(32), 'hex') as secret
), inserted as (
    insert into survivor_multiplayer.recovery (secret_hash)
    select sha256(convert_to(secret, 'UTF8')) from key_value
    on conflict do nothing
    returning revision
)
select secret from key_value cross join inserted;
```

- Render is deployed at https://survivor-island-phase3c.onrender.com; the preview retains its WSS endpoint. Verify its deployed `wss://…/ws` handshake and authenticated room flow. Publish the verified endpoint through the Web build parameter `SURVIVOR_WSS_ENDPOINT`. The separate HTTPS preview can also run single-player before a server is configured. For later physical multiplayer acceptance (explicitly deferred beyond Phase 3D), open it on two phones in Safari landscape and sign in with two confirmed development accounts. Create and join using the room code, start at Tonsai, walk past one another, speak to an NPC, background one phone for about twenty seconds, then resume and check the original assignments.

### Measurements

With two human clients and 18 contestants, the local Godot process started in 120–145 ms, used about 77 MiB RSS and averaged 0.038 CPU cores during the throughput sample. Observed ten-second windows averaged 0.68–0.86 ms per physical callback and 0.09–0.13 ms per semantic step. Each client received about 10.8 messages and 5.0 kB of application payload per second. A roughly 6.1 kB checkpoint reached the local database in 131–134 ms. At injected RTT targets of 50, 100 and 200 ms with jitter, the measured pings were 66, 132 and 221 ms. The observing client registered 0.6 m of displacement after 512, 559 and 673 ms respectively. Those movement measurements include acceleration and the snapshot interval. Live logout removed authority after 35 seconds in that run. Hosted load and physical Safari performance remain separate measurements.


## Phase 3D native stores and mobile foundation

The same typed Godot 4.7.2 project and public-safe Tonsai stage target Web, native iOS and native Android. Compatibility remains selected on desktop and mobile. `iOS Readiness` and `Android Readiness` in export_presets.cfg use provisional `org.survivorisland.prototype`, version 0.3.0/build 1, sensor landscape, no privileged client configuration and normal TLS validation. Native saves use `user://`. No ATS exception, synchronization entitlement, background mode, tracking or new permission is required. Internet access is enabled on Android. iOS 15.0 follows the minimum in the pinned engine's platform/ios/export/export_plugin.h. Android is ARM64 with unsigned AAB output; eventual Play signing and Keystore credentials are separate release work.

`Native store readiness` runs on standard GitHub-hosted macos-15-intel and ubuntu-24.04 only when this repository is public (verified before first execution). Public standard runners qualify for free Actions usage; no larger runner, signing credential or paid service is configured. ci/install-native.sh pins editor identity and matching template archive checksum. The macOS job records the selected Xcode and SDK versions, compiles an iOS plugin XCFramework for device/simulator, exports the allowlisted game, then attempts unsigned Xcode device/simulator builds and one bounded simulator launch. `UNSIGNED00` is an export-only placeholder because Godot requires a nonempty team field even for project generation. It is not a real team or signing identity. An unsigned compilation is not an installable iPhone distribution. Use Actions on the branch; no developer Mac, downloads or manual build is required. Workflow failures remain explicit blockers, not certification.

SurvivorCredentialStore is the sole platform boundary. The Godot static iOS plugin links Apple's Security framework and stores only one account-ID/refresh-token record, with `WhenUnlockedThisDeviceOnly`, no password, no access token, no cross-device synchronization. Replacement uses SecItemUpdate or SecItemAdd. Web and Android have no disk credential backend; a future Android Keystore adapter implements the same three methods. Restore exchanges the refresh token with Supabase before accepting identity; epoch and sign-in attempt fences reject late restoration, and the returned account must match the stored account. Existing refresh single-flight and rotation remain in AuthService. Logout and confirmed account deletion clear the adapter. A nonsecret `user://credential-restore-blocked` marker prevents a failed secure write/delete from restoring an obsolete identity on relaunch. Temporary unavailable reads do not expose credentials or fall back to ordinary saves. Runtime iOS Keychain accessibility and physical-device behavior still require native acceptance.

Developer builds opt in with `SURVIVOR_DIAGNOSTICS=1`; ordinary Web, native and server builds do not enable the benchmark. Open the draft preview with `?benchmark`. Select 1/6/12/18 rigs, Full/Economy and Isolated/Tonsai, then Start. A fixed camera, alternating idle/walk clips and fixed seed give repeatable comparisons. Every case discards three warm-up seconds and samples 20 seconds; optional stress samples 180 seconds. Changing a case cancels sampling. A preallocated bounded frame buffer records frame durations; render counters are polled at 2 Hz. Copy report exports build SHA, coarse OS/browser user-agent, viewport/DPR, renderer, case, average FPS, median/p95 frame times, frequency over 33.34 ms, sampled draws/primitives, static memory, load/unload timings and last semantic step time. No analytics or account data is sent. Rendering memory uses cached RenderingServer texture/buffer/total allocation estimates when nonzero; unavailable backends and per-rig animation cost are labeled explicitly. These estimates are not physical GPU memory measurements. Save timing is unavailable in the benchmark because it never writes a checkpoint; normal application regression retains actual checkpoint timing. Benchmark actors never join the separately simulated 18-person season. Benchmark creates no identity, account, save, HTTP or WebSocket service. Visibility changes invalidate interrupted measurements and pause its simulation.

Meshes/materials continue to share imported resources. Settled smile morph values no longer incur redundant writes every frame. Existing distance-based NPC AnimationTree suppression remains; collision, physical schedules and strategic simulation remain active. No new LOD artwork, appearance change, shader redesign or software-renderer-driven quality downgrade was introduced. Future character presentation belongs behind the existing actor boundary and Full/Economy choice. Provisional budgets: six rigs preferably 60 FPS, Economy and twelve rigs at least 30 FPS, eighteen rigs a 30 FPS stress goal. Four strategic ticks/second and bounded four-step catch-up remain unchanged. These are targets, not achieved physical-device results; production hair/clothing/models need new budgets.

LocationManager owns exactly one physical presentation and retains no PackedScene cache. Entry is explicitly marked loading and timed; synchronous loading is intentional on the single-threaded Web export. Teardown disables processing, detaches and queues the camp, clears the manager reference and disconnects the session signal. Child controllers, timers, navigation and rigs belong to the scene tree. Existing page callbacks are removed on exit. Six repeated entry/exit cycles after warm-up produced node counts [19,19,19,19,19,19], released each retired camp and passed save/continue/journal/suspension checks. Engine resource caching alone is not treated as a leak.

Native controls retain DisplayServer safe-area conversion and absolute multitouch coordinates. Native menus also respect safe vertical bounds and reposition after viewport changes. Existing Web visibility/pagehide/pageshow, keyboard-aware account layout, pause checkpoint and touch cancellation remain. Physical Safari suspension, termination/reload, keyboard, safe areas and offline/cloud interruption must still be checked on iPhone 17 Pro Max. Signed iPhone installation, actual Keychain runtime, mobile GPU baseline, App Store artwork/privacy/review and eventual store memberships/signing remain release acceptance tasks. Physical two-device multiplayer is deferred and does not block single-player development.

### Phase 3D verification and release limits

- Public repository and standard GitHub-hosted runner eligibility were checked before execution. No paid runner, signing account, infrastructure or backend change was used.
- Native CI run [45679518821](https://github.com/sunsetseast/SurvivorIslandGodot/actions/runs/45679518821): Android unsigned ARM64 AAB export and packaged native-library inspection passed. iOS native export, Xcode project generation and Keychain XCFramework compilation (device ARM64 and ARM64/x86_64 simulators) passed. Xcode 16.4 build 16F6 / iOS SDK 18.5 reached unsigned linking, then failed because the pinned engine template needs newer SDK symbols, including MTLTensorDomain and CADynamicRange*. No installable iPhone application was produced. Simulator compilation/startup and runtime Keychain writes were not verified.
- The reusable workflow now inventories installed Xcodes and selects Xcode 26+ before downloading/building, or stops with a clear toolchain blocker. This selection correction was syntax-checked but not rerun after the bounded native attempts. Simulator checks can run independently after a successful export. A standard runner with the required SDK is a later retry, not another gameplay infrastructure phase or a reason to buy a Mac/account.
- The 18-contestant headless foundation suite passed at 41.67 microseconds mean/tick. Camp headless regression walked 668.98 m with 59 NPC arrivals and zero failures. Four semantic ticks/second and bounded catch-up remain unchanged.
- Six location entry/exit cycles released every retired scene and held at 19 nodes / 1,707 objects. Static memory ranged from 70,950,368 to 70,958,452 bytes (about 8 KB of residual engine/test allocation). Save/Continue, journal restoration and suspension checks passed. This is evidence against scene accumulation, not a blanket memory-leak certification.
- Credential mock tests passed replacement, rotation, account switching, unavailable logout, matching-account restoration, wrong-account rejection, revoked vs temporary failures, logout during pending restoration and memory-only recovery sessions. Native runtime accessibility and rotation remain device acceptance items.
- All 16 benchmark combinations passed construction/teardown. The actual Start → 20-second sample → Copy Report flow passed with no browser errors. Build d440ac402d858954051462ecee59407b6a1e1f09, isolated six rigs / Full, Chromium 151.0.7922.34 / SwiftShader at 956×440 CSS pixels, DPR 1: 20.108 s, 12.58 FPS, median 81.57 ms, p95 132.00 ms, 73 sampled mean draw calls and 26,724.5 primitives. The benchmark UI uses CSS-scaled 44-pixel targets and hides reports while measuring. Copy Report uses the existing touch-trace native HTML dialog pattern for a trusted Safari clipboard tap, with selectable text as fallback. Release-template static memory is unavailable. These are software-renderer tool-validation results; no physical iPhone rendering target is certified.
- Consolidated browser regression passed New Game / Continue / reload, journal restoration, both controllers/steering modes, touch cancellation, corrupted touch-slot rejection, walking/wading/swimming/diving/shore return, clipboard and lighting presets. Startup was 2.35 s; scene load 858 ms, unload 25 ms, save checkpoint 6,600 microseconds; sampled semantic step 200 microseconds. Camp samples were Full 70 draws/~46k primitives and Economy 50 draws/~30k primitives, at 3–4 software-rendered FPS. Live Supabase sign-in and cloud upload/restoration were not rerun in this phase; local cloud-list decoding and credential/session tests passed.
- Hosted WSS protocol-v1 TLS connection, ping/pong and unauthenticated room denial passed against the existing Render service. No room, schema, server, credential or deployed configuration was changed. Authenticated two-device multiplayer acceptance remains deferred.
- The private [HTTPS draft preview](https://survivor-island-phase-3d.peachybeetle18.chatgpt.site/?benchmark) is separate from Pages, Phase 0 and the character laboratory. Its source marker and gzip-decoded game/engine signatures were verified over authenticated HTTPS. It retains ChatGPT access control. The standalone automated Chromium trust store rejected the hosted certificate; TLS validation was not bypassed. Browser gameplay and benchmark validation used the local exported fixture.

Remaining iPhone 17 Pro Max acceptance: run the 1/6/12/18-rig Full/Economy isolated/Tonsai samples in Safari landscape; check sustained thermals, safe areas, both steering modes, keyboard dismissal, background/foreground, termination/reload and offline/cloud-interruption recovery. Signed native installation, actual Keychain runtime, final App Store/Google Play identities, artwork, privacy declarations, signing and developer enrollment remain release tasks. Android uses memory-only credentials until a Keystore adapter is implemented. No physical two-device multiplayer test or paid prerequisite blocks Phase 4 single-player development.

## Phase 4A — home presentation ownership

Verified base: main `433a9a96eda26add7d076753605dc4f969bc2b24`, the merge of PR #10.
`SurvivorGameApp` still owns navigation, identity, save selection and location lifetime.
`IslandTitleEnvironment` owns only its camera and selected Tonsai presentation resources:
terrain, ocean, limestone, coast palms and selected forest. It has no actors, navigation, collision bodies,
simulation or networking. It uses the existing water shader, warm low sun and a bounded,
slow camera drift. Economy disables title shadows, using the existing preference. The
app releases the entire title node before loading gameplay and rebuilds it on return.
Settings/account/load pages share it; they never create a season. Authentication restoration
continues through the established account service independently of title presentation.

`IslandTheme` owns the original private Survivant font, white/black outlined wood-button
lettering, brown parchment lettering, gold focus accents, spacing, inputs and attribute
bars. Private staging accepts only logo.png, rect-button.png, rect-button-1.png and
Survivant.ttf from the approved source through `SURVIVOR_PRIVATE_UI`; the staging helper
crops alpha padding and resizes the PNGs while preserving their proportions. Wood and
ornate parchment use nine-slice StyleBoxTexture resources. Do not commit restricted
art/fonts or enable private staging in public Actions. Public builds retain Noto Sans
and procedural wood-colored surfaces pending distribution/license clearance. The global
default theme/fallback and separate HUD and Label3D typography inherit the same font.
Main has no background panel or scrim; its logo and seven individual buttons sit over the
live scene. Metadata sits beneath the logo so the navigation fits 402/440 px landscape.
The existing keyboard-aware menu scroller remains responsible for small screens and inputs.

Continue chooses the most recently timestamped owned local checkpoint and shows only known
day/slot metadata. New Game is an explicit explanation and empty-slot boundary into the
existing technical season. Phase 4B replaces this boundary with contestant selection; it
must reconcile the 18 approved contestants and existing calibrated catalogs before exposing
attributes. No new stats, season rules, schema, marooning or opening-challenge abstraction
is introduced here. Multiplayer stays a secondary testing entry.

### Asset decisions

Inspected the actual 1536×910 RGBA `Assets/logo.png` and representatives of Buttons, Tribe,
Resources, Idols, Journey and Screens from SurvivorIsland2025. The original logo is reusable
after optimization **in the authorized private preview**: 1024×610 PNG after cropping only transparent padding; original artwork and alpha are retained. Public distribution rights are unverified, so neither logo bytes nor
screenshots containing it enter GitHub or public Actions exports. `SURVIVOR_PRIVATE_LOGO`
accepts an external approved PNG only during intentional private staging; without it the
same screen renders the text-title fallback. Keep that variable unset in public CI.

| Collection | Decision |
| --- | --- |
| Tonsai meshes, water, sky, textures | Reusable; existing public allowlist and provenance in phase2/ASSETS.md. Title omits actors, props, full foliage and collisions. |
| Original logo, rect-button.png, rect-button-1.png | Crop alpha padding and optimize for authorized private review; rights/provenance verification required before public distribution. No redesign. |
| Buttons/blank.png | Replace with theme surfaces; old ornamental texture is too visually heavy and large for primary navigation. |
| Tribe/green-banner.png | Visual reference only for woven color accents; no imported cards or banners. |
| Resources/coconut.png, Idols/tribe1.png | Potential future inventory reference; rights/provenance verification required, then mobile optimization. Not imported. |
| Journey/arrival.png, Screens/beach.png | Visual reference only; live Tonsai replaces illustrated home backgrounds. No imported screen textures. |
| Survivant.ttf | Approved private global font; rights verification required before public distribution. Noto Sans remains the licensed public/glyph fallback. |

The Phase 4A UI staging helper does not ingest contestant likenesses. Phase 4B adds a
separate explicit private cast stage, described below. No reference artwork directory is imported wholesale. No production/commercial affiliation or clearance is claimed.

Verification: Godot 4.7.2 Compatibility Web export; foundation, Tonsai, application,
title-boundary, credential-mock and all 16 benchmark configurations passed. Six warm
home/game cycles had stable node/object counts. Title initialization measured 0.4–1.9 seconds
in headless runs (varying CPU load); a cold local software-rendered Chromium Web launch took 8–12 seconds
including engine download/initialization. These are development-machine observations,
not iPhone GPU or network measurements. Browser viewport/interaction checks and the
private HTTPS preview are recorded in the draft PR. Live Supabase account mutation,
physical Safari keyboard/safe-area behavior, native signed installs and physical
multiplayer were not certified by this change. Existing developer benchmark and Phase 0 /
character-lab destinations remain separate and unchanged.

### Phase 4A visual revision

Permanent visual materials: carved tropical wood, weathered stone, rope, leather,
aged parchment and tribe-colored woven fabrics with restrained foliage. White Survivant
button/HUD/name lettering uses proportionate black outlines; parchment uses dark brown. Tribe-name labels use the corresponding tribe color with a contrasting outline.
Survivant is approved for private review, not established as commercially licensed.
Existing Noto notices remain for the public/unsupported-glyph fallback. Main has no slogans.

Future artwork uses (reference only, not imported): parch-portrait/parch-landscape for
profiles, journals, statistics and Tree Mail; menu-card for player/in-game navigation;
inventory1 for resources and inventory2 for items/tools/advantages. Preserve the backpack
concept with dynamic functional item slots. clock is the day/phase/time display; beat-ui
is for narrative announcements/journeys; Buttons is the navigation/control vocabulary.
No future systems are implemented by this revision.

The title removes gray overlay/fog, reduces ambient fill, restores warm directional
sunlight and tunes the existing ocean's turquoise/deep-blue colors and moving highlights.
Motion/shimmer uniforms keep gameplay defaults unchanged. Geometry, collision, navigation,
water level/depth and swimming are unchanged. Later environmental polish: realistic
shoreline waves and moving foam, palm/foliage wind, improved gameplay ocean motion and
dynamic weather. These are presentation targets, not current simulation features.

CI run 45689748366 failed at review_web.py:333: the test tapped New Game and waited for
SLOTS, while the deliberate Phase 4A boundary correctly returned NEW_GAME. The test now
asserts that screen has no season, taps Choose Save Slot, then preserves all existing
save/Continue, movement, swimming and touch-corruption assertions.

## Phase 4B — contestant selection and Phase 4C boundary

Base: main `7435d56`, merged PR #11, including approved Phase 4A head
`ffc1622f1303b7de3e2d824081c62deb4726ca86`. Godot 4.7.2 / Compatibility, single-threaded Web.

The immutable catalog is reconciled by `tools/selection/stage_private_cast.py` against
SurvivorIsland2025 `cf894e578d77fce1e588d793dfc8d14f61ec7628` (`GameData.js`, approved
#344 fixture, protected fixture and calibration document) and SurvivorIsland3Dprototype
`708a21c43b4b2969aa28bf2142005e4f5df0bcdf` (`cast.json`, `CAST_MATRIX.md`). All current
source fields must agree; the older approved fixture omits only campcraft. No rating,
trait class, gameplay style or runtime starting default is recalibrated. The private
manifest records inspected revisions and SHA256s. Original IDs 1–18 do not depend on art.
The loader validates all 27 original field mappings, category sums /50 and ratings /10,
and returns deep copies. Mutable health, hunger, water, rest, threat, vote state, roles
and resource starting defaults are separate from catalog attributes. Future relationships
and inventory belong to season state; browsing never creates them or a simulation.

Debut season and visual reference season are independent metadata. The developer's
Heroes vs. Villains overrides apply to IDs 4, 10, 11, 13, 16 and 18; the other twelve
retain their approved Cast Matrix looks. Portraits are existing presentation fallbacks,
not assertions that their current clothing realizes the future model specification.

New Game opens the landscape selection screen directly. Trait and gender filters
intersect; changing filters selects the first eligible contestant when necessary. Random
uses only eligible IDs and reveals its selected row. The prospective player's own full
ratings remain inspectable in both modes. `SurvivorNewSeasonSetup` retains selected_id,
information_mode (Detailed/Immersive), trait_filter and gender_filter in memory across
Home navigation. `validate(catalog)` is the Phase 4C acceptance boundary. Confirmation
labels the result as retained selection for Phase 4C and explicitly creates no season
or save. Phase 4C must validate the ID again before creating its configured ruleset,
tribes and compatible save. No existing technical ruleset, save, server protocol or
Supabase schema changes. The playable technical season has a separate **Technical
Season Test** action under Credits & notices, followed by the existing empty-slot flow.

`ratings_for(entry, is_player)` exposes only catalog ratings: Detailed permits opponent
numbers, Immersive withholds opponent numbers; own ratings remain available.
`impressions_for(entry)` exposes catalog trait/style and relative strongest/weakest
Physical/Mental/Social categories without numbers (equal totals imply no relative weakness). Neither projection accepts or
reveals actual alliances, conversations, idol locations or voting intentions. Information
mode is presentation only and must never change simulation or NPC intelligence.

The reusable `SurvivorCharacterPreview` owns one isolated SubViewport and at most one
selected model. It frees the prior model synchronously, coalesces deferred synchronous
loads with a generation token, finds idle clips without changing source animations,
frames nested mesh bounds and supports mouse/touch yaw rotation. It disables rendering
without a model and releases its viewport/input/children on exit. No threaded loading
is assumed. Only an explicitly staged ID-bound model may be loaded. No approved actual
contestant model was available in this workspace; all 18 use their own existing portrait
as the intentional temporary presentation, without an unavailable overlay. No rejected model is reused as a contestant.

Private build procedure (never public Actions): stage the reconciled catalog and
optimized 512px portraits into an ignored dedicated build directory, then set
`SURVIVOR_PRIVATE_CAST` to that directory and `SURVIVOR_PRIVATE_UI` to the approved
Assets directory. The UI helper narrowly adds parch-portrait/parch-landscape to Phase
4A's existing allowlist; image proportions/transparency are retained. Explicit optional
`--approved-model-dir` accepts ID-named GLBs from authorized external staging only; it
never searches reference repositories for models. Private catalog, portraits, font,
artwork, screenshots and export pack remain outside public commits and public Actions
artifacts. Public builds retain the licensed font/surface fallbacks and an unavailable
catalog state, never a fictional replacement cast. Public tests use technical fixtures.
The title environment is released on selection entry and rebuilt on Home return.

Validation: source reconciliation passed for 18 unique IDs and 486 unchanged individual
ratings, current campcraft, all existing styles/defaults and six contestants per trait.
The focused Godot selection gate passed with private staging and with it removed;
it covers every handoff, information projections, intersecting filters/random, missing
previews, all portraits, a technical model's idle/rotation/framing, rapid replacement,
resource teardown and repeated Home navigation. Web export is single-threaded.
Landscape captures and the focused browser regression are linked from the draft PR,
kept outside public artifacts. Physical iPhone Safari, live account/cloud mutation and
production contestant models remain unverified; no native certification or complete
performance benchmark was rerun for this presentation change.

The private static host limits individual files to 25 MiB. The existing preview
packager now streams consecutive 20 MiB gzip parts through DecompressionStream when
needed, rather than reducing approved asset quality. It verifies byte-exact pack/engine
reconstruction before publication; this adapter does not change Godot's single-threaded
export or public hosting destinations.

### Phase 4B mobile input hotfix

Trait, gender and information mode now use inline themed cycling buttons. No
OptionButton/PopupMenu is created: the existing Web touch-to-mouse emulation remains
disabled, and selection must not depend on mouse-only modal popup dismissal. Touch
regression cycles all filter combinations repeatedly and changes mode using actual
taps, without keyboard input. Selection tooltips are removed. Valid portraits have
no unavailable overlay; absent portraits/models retain the error state and the
isolated 3D preview architecture is unchanged.

### Phase 4C configurable local seasons

`SurvivorSeasonConfiguration` owns transient seeded division and exact membership
validation. Ordinary Standard formats use balanced assignment; Random is Fisher–Yates;
Balanced accepts improving equal-capacity swaps for at most 600 attempts, minimizing
pairwise gender and Physical/Mental/Social total variance. Themed labels remain separate
from tribe names. Manual uses two taps to swap. Confirm then an empty slot is the only
creation boundary. No catalog rating or default is recalibrated.

`configurable-single-player` v1 persists the catalog fingerprint, seed, selected original
ID, information preference, named/color tribes and their confirmed membership/locations.
Roster attributes and copied mutable starting state are separate. The selected logical
tribe occupies Tonsai; other tribes simulate independently offscreen. The existing rig
is temporary. Additional spawn positions serve nine-person tribes. The technical
ruleset and wire protocol retain their versions. SaveCodec dispatches validation by
ruleset and normalizes whole JSON numbers before configurable validation. Restoration
rebuilds catalog order before restoring camp state and deterministic RNG. Current v1
requires catalog defaults for mutable fields because this phase does not change them;
future mechanics must version their transition validation.

Configurable creation requires explicit guest mode. It neither signs out an account nor
moves its saves. Cloud scheduling rejects unsupported rulesets. Follow-up: introduce a
server-owned, immutable approved catalog/fingerprint and a separate configurable v1
validator in the hosted save RPC; validate complete membership, controller ownership,
locations, participant journals, pose and RNG against it; retain technical v1 dispatch
and existing account namespace/revision/conflict checks. Add server/client cross-codec
fixtures before enabling account creation or configurable uploads. No hosted migration,
service or multiplayer deployment is included here. Future ruleset versions may implement
merge at 12, Final Three, swaps, idols and advantages; none are selectable now.

Targeted checks: stage private inputs with the existing Phase 4B helper, then run
`tests/phase4c_test.gd` and `tests/phase4c_camp_test.gd` in the Tonsai stage. The former
covers representative seeds, themed formats, manual swap/rejection, exact attributes,
6/9 projections, codec restore and deterministic continuation, plus technical saves.
The latter loads both actual camp sizes and verifies spawn clearance, conversations,
selected participant journals and saved pose. Keep private captures and catalogs out
of public Git and Actions artifacts. Mobile Chromium emulation is a regression aid;
physical iPhone Safari still requires device review.

The configurable codec uses sorted JSON keys for canonical output; the technical
encoder retains its existing ordering. Configurable guest saves are excluded from
account import and rejected again at import and upload boundaries. Private UI staging
also allowlists the five existing `Assets/Tribe/*-banner.png` files, reduced with their
original proportions intact. The review uses parallel tribe columns and banner icons.
`tools/selection/review_season_web.py` runs one touch-only Chromium landscape flow
against a temporary authenticated loopback server, capturing setup and both camp sizes
and exercising Save, Exit, Continue, Reload and Load Game without cloud mutation.

### Phase 4C compatibility hotfix

Catalog compatibility now hashes an explicit, ID-sorted gameplay projection (`id`,
`name`, gender, trait, style, attributes, totals and starting defaults), tagged
`gameplay-v1`. Portrait/model paths and original/appearance season metadata are
excluded. The exact shipped Phase 4C preview digest has a pinned migration to its
approved gameplay digest; it is accepted only when the current gameplay digest still
matches that pin. Unknown old digests and changed gameplay calibrations fail closed.
Decode upgrades the in-memory configuration; the existing local save flow writes the
new digest on its next checkpoint. No account/cloud migration is involved.

Initial tribe names and compatible unique colors use a separate seeded shuffle,
leaving seeded membership behavior unchanged. Later membership rerolls retain the
current customized identities. The red/orange exclusion is enforced before color
selection and remains independently validated.

The failed Tonsai run 45739892691 omitted the shared simulation's three typed
catalog/setup/configuration dependencies from the dedicated server stage. The stage
now explicitly copies only those scripts, without selection UI or restricted data,
portraits, models, fonts or other artwork. The server still runs the unchanged
technical multiplayer ruleset. No hosted server deployment is part of this fix.
Public synthetic compatibility fixtures run in the isolated simulation stage; private
Phase 4C tests additionally exercise the exact shipped-preview migration pin.

After the Docker gate passed, the previously unreachable Web regression exposed an
older navigation assumption: its technical-season Credits button was below the
visible scroll panel (normalized Y about 1.89). The browser helper now reveals Credits
actions with touch swipes before tapping. Product UI and gameplay remain unchanged.

### Phase 4C.1 configurable cloud compatibility

The additive migration `20261126083432_configurable_cloud_v1.sql` keeps the technical
validator unchanged and dispatches configurable v1 snapshots to their own validator.
The server-owned `survivor_private.gameplay_catalogs` table binds exact canonical
Godot gameplay JSON to its `gameplay-v1` fingerprint. It has RLS, a restrictive deny
policy, no client/service-role table grants, and no client registration endpoint.
No contestant data is included in the public migration. `tools/cloud/stage_configurable.gd`
requires an explicit private approved catalog, verifies its approved fingerprint, and
writes the private seed and fixture snapshots only to an ignored `build/private-cloud`
directory; public Actions staging is prohibited. Artwork metadata is never stored in
the server catalog or used for compatibility.

The configurable validator checks checksum/envelope bounds, canonical integer RNG
text, approved attributes/defaults, exact 18-member ownership and tribe capacities,
seed/configuration, identities/colors/themes, canonical membership order, logical
tribe/location mapping, camp state, participant journals and bounded Tonsai pose.
The RPC preserves the existing verified-session guard, per-account locks and isolation,
quotas, revision conflicts, operation idempotency and revision retention. Updates to
configurable seasons additionally freeze confirmed configuration, seed and principal.
Legacy clients and technical snapshots retain their existing validation and RPC shape.

Clients enable both supported v1 rulesets for account creation/scheduling/conflict
resolution and explicit guest import. The existing empty-slot and deletion checks
remain in place; imports preserve the guest checkpoint and its simulation principal
inside the account's separately authorized save row. Account and guest stores are not
silently switched or combined. Cloud/local restores still require SaveCodec validation.

Local validation: use a disposable PostgreSQL 17 database with the existing Auth
uid/JWT/session contract, install migrations in order, then provision the private catalog.
`supabase/tests/configurable_rpc.py PRIVATE_STAGE IGNORED_SQL_PATH` generates rollback-only
SQL for 39 focused checks covering configurable 2/3-tribe and technical round trips,
guest import, malformed snapshots/types, confirmed configuration, isolation, conflicts
and quotas. Test identities and saves are rolled back; no verification emails are sent.
`tests/configurable_cloud_test.gd` verifies account import intent, supported rulesets,
local guest preservation and occupied-slot protection against the privately staged
fixtures. Existing Phase 4C/local compatibility gates remain applicable.

Deployment target is exclusively `survivor-island-dev`, reference
`hjmhgibfbxgzqvfdomoj`. Merged PR #13 was verified on main at
`ddb9d1c2f008394685c4a4b12b518bbe85e574b1`. After explicit user approval, the
additive migration was applied and verified in hosted migration history as
`20261126083432` / `configurable_cloud_v1`. The public filename matches that recorded
version. The privately provisioned catalog contains exactly 18 approved contestants
and fingerprint `gameplay-v1:3b8c699247b5a997dfe0ed15dc23bddf446e99c7c63f1262ba42dca294373804`.
Catalog RLS is enabled; authenticated table SELECT and direct private-validator
EXECUTE are denied. The same 39 rollback-only RPC checks passed against the real
development Auth/session/RPC contract; all test accounts, sessions and saves were
rolled back. The configurable client gate and existing Phase 4C/local-save compatibility
gates also passed locally. Restricted catalog and generated test SQL remain ignored.

The private preview uses the existing owner-only Phase 4C HTTPS destination. No
Passport project, Render service, multiplayer deployment, artwork or gameplay system
was changed. Security advisors reported no new findings: the existing multiplayer
recovery RLS/no-policy info and disabled leaked-password-protection warning predate
this assignment and remain unchanged. Reference remediation guidance:
[RLS policy advisor](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
and [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

### Phase 4D.1 marooning environment preview

The confirmed tribe review exposes **Private Marooning Preview · No Save** only for
an existing validated Phase 4C configuration. `MarooningPreview` receives a deep copy
and the read-only catalog; it creates no session, save provider or cloud transport.
Exit frees the preview and returns to that same tribe review. Ordinary confirmation
and empty-slot creation are unchanged. Missing private catalogs retain the existing
unavailable selection state; there is no production fixture cast.

`marooning/preview.tscn` composes an independent `MarooningBay`, existing temporary
actors, CampThirdPerson and CampTouch. The existing motors, camera steering sensitivity
and absolute per-finger input code are unchanged. Both skip and natural intro completion
cancel touch, blend to the orbit camera and unlock control. Focus loss cancels input.
There are exactly 18 ID-bound contestants plus a temporary host. Names and tribe accents
come from configuration/catalog; information mode remains in the transient configuration.

`marooning/layout.tres` is editable layout data in metres. Stable semantic markers cover
ship, deck, host, cargo kinds, spawn groups, active raft mounts, reward dock/reward ID,
player landing, two rival exits and future camp transition. `layout.routes(config)` maps
the controlled tribe to the one landing and each rival to a separate configurable exit;
no rival beach or full camp scene loads. The seabed sampler supplies the existing swimming
motor and the same vertices supply rendering and collision. Clearly labeled preview-only
relocation supports inspection of beach/dock and return to deck. Physical platforms stay
stationary. Navigation is generated offline by tools/marooning/bake_nav.gd; build staging
rebakes it. Ship source conversion and license details are in marooning/assets/PROVENANCE.txt.
The server build allowlist is unchanged. Private staged data stays out of public exports.

Deferred to 4D.2: scramble timing, pickup/throw, cargo ownership, release/paddling,
competitive AI, reward claims, social consequences, camp inventory and save schema.
No frame-rate claim is established by headless tests; browser review records wall-clock
render intervals only, and physical iPhone performance remains owner-tested.
