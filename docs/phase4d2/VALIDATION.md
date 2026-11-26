# Phase 4D.2 validation

Main verified before branching: `2cbc9d8a53458ac854bf6437a8016b74abc38019`.
Pinned Godot 4.7.2 stable `ed1daf0bf`, Compatibility, single-threaded Web export.
Private catalog rebuilt using the existing stage_private_cast.py pipeline against
both documented reference commits: 18 original identities, 27 attributes each,
existing portraits, no new likenesses or recalibration. Restricted files/exports
and captures remain under ignored build directories, outside public commits/Actions.

Passing local gates:

- Simulation foundation and season save compatibility.
- Scramble authority: contested completion/ties, duplicate input, remote/blocked
  pickup rejection, rival ownership rejection, drop, throw/floating vs secured,
  loading, strength modifier bounds, suspension, expiry, 50-instance conservation,
  and exact seeded command replay.
- Two/three-tribe physical marooning: preserved 18 IDs/selected actor/configuration,
  real dual-touch motor/orbit with corrupted reported deltas, continuous deck,
  actual upper-deck stair arrival, cabin/rail penetration rejection, all 50 anchor
  paths, beach/dock support, full 120-second NPC scrambles, all 17 NPCs collecting,
  all tribes delivering, unchanged transient configuration and teardown.
- Existing Tonsai: 668.98m continuously walked, 59 NPC arrivals, both camera and
  water controllers, all four controller/steering touch combinations, 0 failures.
- Existing application lifecycle, selection, title, credential mock and 16-scenario
  benchmark gates: 0 failures. No new production save/provider behavior.
- Private Web export succeeds; no thread-enabled export template is used.

A private Chromium 956x440 landscape run used actual CDP touch points concurrently
for movement and camera. It completed the full gameplay timer with active NPCs,
showed secured/remaining results, restarted the preview and exited safely. Browser
errors: none. Season ID empty, slot/revision zero throughout. Private screenshots
and observed JSON stay in build/scramble-captures (and final asset delivery captures).

Observed software-rendered Chromium frame intervals in the full run were commonly
1.2–2.3 seconds per frame, with a 5.1-second entry frame. This is a slow CPU-rendered
Cloud browser, not an iPhone Safari performance measurement. No mobile frame-rate
estimate is presented as observed. Owner physical iPhone testing remains required.

Reproduce privately after staging catalog/UI:

```
python3 tools/marooning/review_scramble.py http://127.0.0.1:3000 build/private-scramble-review
```

Known limits: temporary character rigs, basic carrying attachment without a new
animation pipeline; NPCs prioritize loading, not deliberate overboard strategy;
nearby event witnesses are proximity candidates; inventory utility and congestion
need owner playtesting. The browser acceptance covers dual touch and results; pickup/drop/load/throw
ownership contracts are covered by deterministic command tests rather than a
complete owner-device interaction recording. Physical hull,
pole and railing coverage uses the imported mesh collision plus focused traversal
checks; this is not exhaustive device certification.

Hosting: the staged export is served on configured owner-only port 3000. Cloud
status currently returns this HTTP portal without a hosted URL. A playable owner
HTTPS link cannot be delivered until the environment exposes its URL. No public
host, restricted artifact upload, infrastructure deployment or ZIP substitution
was used. Raft movement, recovery, persistent cargo and Day 1 remain deferred.
