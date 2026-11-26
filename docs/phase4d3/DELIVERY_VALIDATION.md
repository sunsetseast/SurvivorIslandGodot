# Private delivery validation follow-up

Gameplay implementation remains `1747946244753017e2a9b865b867df59aff474fc`.
This follow-up instruments only a private staging copy; production navigation and
race rules are unchanged. PR #17 remains draft; Phase 4D.4 is untouched.

## Navigation recovery investigation

Replayed the full loaded two- and three-tribe physical acceptance scenarios with
pre-recovery position, path, target, velocity and collision diagnostics. All physical
arrival/restart gates passed again. The original 1/3 incident counts reproduced.

- Two tribes: actor 17, departure elapsed 40s, stage 0, position
  (1.813585,1.920250,-3.063124). The current waypoint was
  (1.818710,2.139387,-3.184355), followed by a waypoint at y=2.25.
  Contacts were only the upward-facing OpenDeck floor. The agent uses a .25m
  path waypoint tolerance; raised baked waypoints and the actor's lower foot
  position leave too little or no horizontal tolerance. This supports a waypoint
  height/tolerance stall, not contestant crowd collision.
- Three tribes: actors 8 and 16 stalled near (-1.708,1.920,-2.815), stage 0.
  A next waypoint at y=2.309 lies approximately .389m above the actor's feet,
  exceeding the .25m tolerance even with matching horizontal coordinates.
  Contacts were again only the OpenDeck floor.
- Three tribes: actor 18, the selected contestant driven by the technical test
  pilot, stalled at (1.123439,1.917912,9.079963), stage 1. Contacts included
  a bow-rail face with normal (0,0,-1). Its lateral position lies outside the
  safe centre of the opening for a .36m-radius capsule. The direct forward
  departure handoff starts before the pilot has centred in the access corridor.
  Production player control does not call this NPC helper; this incident is a
  technical-pilot recovery, not an automatic human-player recovery in gameplay.

Thus the three-tribe count is **two NPC recoveries plus one technical-pilot
recovery**, rather than three NPC recoveries. Earlier references to congestion
were too broad; the diagnostics identify waypoint-height and bow-entry alignment
problems. Recovery is currently triggered by accumulated deck time over 40s,
not a progress-aware stall detector, and can therefore also classify a slow but
progressing actor. Each incident relocates once to the deck access point and
records an event. It does not grant cargo, rewards or arrival.

No navigation change was made in this validation-focused follow-up. Targeted future
fixes would account for waypoint vertical offsets, require centring before the bow
handoff, and use measured progress for the recovery timeout. Those changes require
physical regression and race-balance validation before replacing the fallback.

## Screenshot delivery

Created an unparented personal private Page through the authenticated Pages API;
readback confirms personal scope, no inherited shared Space, and the current
account as creator. No sharing action was performed. All 11 uploaded native image
references independently returned file_access_confirmed=true. The Page includes
all nine evidence categories plus overhead and smaller-landscape views. Images
remain excluded from GitHub and the playable pack. Page rendering on the owner's
physical iPhone remains to be checked.

## Playable HTTPS delivery

The Cloud port-3000 portal still supplies no URL, including after a harmless
text-only listener was independently verified. It is not used to serve game assets.

Instead, the existing Site identified by .openai/hosting.json was inspected and
reused. The current account is its owner. Its custom allowlist contains only that
owner, with no editors, groups or external visitors; policy revision 1 was preserved.
Anonymous requests to the existing page and game asset paths returned 403 before
publication. The native owner-private deployment operation independently rechecked
that policy before serving the new build.

The existing preview packaging script produced gzip parts under the static-host
size limit and verified exact reconstruction of the original engine and pack.
The protected Site source repository received commit
`6c8f00f97a58992de81759036126aadece8cf6f7`, containing the packaged game built from
implementation `1747946244753017e2a9b865b867df59aff474fc`. This is a separate
private hosting repository; GitHub main and PR #17 were not merged or modified by
that publishing push. The dedicated source helper was unavailable in this runtime;
ordinary Git used a native Site-scoped credential passed through hidden stdin,
without persisting it. Initial automatic review rejected a hosting-main push due
to concern about PR #17; verification of the distinct remote and draft PR allowed
the authorized private-source publishing retry.

The owner-private deployment succeeded. Authenticated service requests returned
HTTP 200 for source-commit.txt (exactly implementation 1747946), the compressed game
pack and engine (valid gzip prefixes). Anonymous requests to the page, source
marker, game pack and engine all returned 403 after publication. No audience change,
public tunnel, new hosting service or paid infrastructure was introduced. Physical
iPhone Safari owner sign-in and device performance still require owner acceptance.
The direct private URL and private screenshot Page are delivered in the task chat.

## Final deployed-browser arrival acceptance

The protected HTTPS build completed an actual Chromium touch-driven journey through
scramble, deck departure, independent swimming, NPC reward resolution, physical
shallow-water arrival, the results summary and Exit Preview. The browser observed
race phase 3 at 227.3667 seconds; the selected tribe's reward was recorded. Season
remained empty and save slot/revision remained zero. Exit returned to NEW_GAME.
No simulation commands or player relocation hooks drove this journey; review hooks
changed only the evidence camera. The pilot missed the raft while swimming around
the ship, so this run validates the independent-swimmer route rather than claiming
new boarding/paddling coverage. Earlier touch runs cover boarding and paddling.

This run used a 956x440 CSS viewport and device scale factor .5 to reduce the Cloud
software renderer's cost. It is not an iPhone performance measurement or physical
Safari sign-in test. The additional browser summary image was uploaded to the same
private personal Page, with independently confirmed destination access. Twelve
image references now include both native evidence and the HTTPS browser summary.

Two console errors were observed: index.audio.worklet.js and
index.audio.position.worklet.js returned 401 in the scoped-header automation
session. Independently authenticated HTTP requests to both modules returned 200
with JavaScript content types, confirming they exist behind the private gate.
The gameplay/arrival test passed with this automation audio-authentication
limitation; an error-free audio or owner-cookie Safari session is not claimed.
TLS certificate validation remained enabled. Final anonymous checks of the page,
source marker, compressed pack and engine all returned 403.
