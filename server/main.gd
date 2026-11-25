extends SceneTree

const Body := preload("res://server/contestant_body.gd")
const LiveAuth := preload("res://server/live_auth.gd")
const CheckpointStore := preload("res://server/checkpoint_store.gd")
const Wire := preload("res://multiplayer/wire.gd")
const LOCATION := "tonsai"
const FIRST := "explorer"
const SECOND := "jeremy"
const MAX_CONNECTIONS := 8
const AUTH_MS := 12_000
const VERIFY_MS := 45_000
const HEARTBEAT_MS := 12_000
const LOAD_TIMEOUT_MS := 45_000
const GRACE_MS := 5_000
const CHECKPOINT_MS := 15_000
const SNAPSHOT_STEPS := 3

class Connection extends RefCounted:
    var socket := WebSocketPeer.new()
    var opened := Time.get_ticks_msec()
    var last_seen := opened
    var check_at := opened + AUTH_MS
    var rate_at := opened
    var received := 0
    var account := ""
    var token := ""
    var session_id := ""
    var expires := 0
    var verifying := false
    var verify_deadline := 0
    var closed := false
    var move_seq := 0
    var ready := false
    var initial_state_at := 0
    var last_talk: Dictionary = {}
    var knowledge_dirty := true
    var last_camp := {}

var listener := TCPServer.new()
var peers: Array[Connection] = []
var by_account: Dictionary = {}
var operation_at: Dictionary = {}
var auth_in_flight := 0
var transport := SurvivorSupabaseTransport.new()
var verifier := LiveAuth.new(transport)
var store: CheckpointStore
var site := TonsaiSiteData.new()
var world := Node3D.new()
var water: CampWaterSurface
var destinations: Dictionary = {}
var bodies: Dictionary[String, Body] = {}
var simulation: SeasonSimulation
var owners: Dictionary = {}
var durable_receipts: Dictionary = {}
var code := ""
var grace_until := 0
var next_checkpoint := 0
var critical := false
var metadata_deferred := false
var writing := false
var stopping := false
var shutdown_file := OS.get_environment("SURVIVOR_SHUTDOWN_FILE")
var reported_active := false
var steps := 0
var semantic_elapsed := 0.0
var physical_usec := 0
var semantic_usec := 0
var semantic_steps := 0
var broadcasts := 0
var stats_at := 0
var suspension_checkpoint := false
var started_at := Time.get_ticks_msec()

func _initialize() -> void:
    call_deferred("_boot")

func _boot() -> void:
    Engine.physics_ticks_per_second = 30
    Engine.max_fps = 30
    var port := OS.get_environment("SURVIVOR_WS_PORT").to_int()
    if port == 0:
        port = 8061
    var key := OS.get_environment("SURVIVOR_CHECKPOINT_KEY")
    var local_api := OS.get_environment("SURVIVOR_LOCAL_SUPABASE")
    if not local_api.is_empty():
        if local_api not in ["http://127.0.0.1:54321", "http://localhost:54321"]:
            _fail("Local Supabase override must be loopback")
            return
        transport.endpoint = local_api
        transport.publishable_key = OS.get_environment("SURVIVOR_TEST_PUBLIC_KEY")
    if key.length() != 64 or not key.is_valid_hex_number(false) or not site.load_inputs():
        _fail("Server configuration or Tonsai data missing")
        return
    root.add_child(transport)
    root.add_child(world)
    water = CampWaterSurface.new(.03, site.height)
    var collision := load(TonsaiSiteData.DIR + "server_collision.scn") as PackedScene
    var navigation := NavigationRegion3D.new()
    navigation.navigation_mesh = load(TonsaiSiteData.DIR + "navigation.res") as NavigationMesh
    if collision == null or navigation.navigation_mesh == null:
        _fail("Missing server collision or navigation")
        return
    world.add_child(collision.instantiate())
    world.add_child(navigation)
    destinations = {"fire": site.ground(-9.6, -33.45),
        "shelter": Vector3(12.9, site.layout.shelter.deck.y, -43.3), "shore": site.ground(-45.2, -25.3),
        "spring": site.well_anchor(&"conversation"), "trail": site.ground(36, 4), "work": site.ground(2, -39.6)}
    store = CheckpointStore.new(transport, key)
    var restored := await store.read_latest()
    if restored.is_empty() or not _restore(restored.get("state")):
        _fail("Unable to read authoritative checkpoint")
        return
    if listener.listen(port, "127.0.0.1") != OK:
        _fail("Unable to listen")
        return
    next_checkpoint = Time.get_ticks_msec() + CHECKPOINT_MS
    stats_at = Time.get_ticks_msec() + 10_000
    physics_frame.connect(_step)
    process_frame.connect(_poll)
    print("Phase 3C ready, startup_ms=", Time.get_ticks_msec() - started_at, " revision=", store.revision)

func _poll() -> void:
    var now := Time.get_ticks_msec()
    if not stopping and not shutdown_file.is_empty() and FileAccess.file_exists(shutdown_file):
        _shutdown()
    for _index in MAX_CONNECTIONS:
        if not listener.is_connection_available():
            break
        var incoming := listener.take_connection()
        if incoming == null:
            break
        if peers.size() >= MAX_CONNECTIONS:
            incoming.disconnect_from_host()
            break
        var peer := Connection.new()
        Wire.configure(peer.socket)
        incoming.set_no_delay(true)
        if peer.socket.accept_stream(incoming) == OK:
            peers.append(peer)
    for peer: Connection in peers.duplicate():
        peer.socket.poll()
        if peer.closed or peer.socket.get_ready_state() >= WebSocketPeer.STATE_CLOSING:
            _drop(peer)
            continue
        var loading := peer.initial_state_at > 0 and not peer.ready
        if (loading and now - peer.initial_state_at > LOAD_TIMEOUT_MS) \
                or (not loading and now - peer.last_seen > HEARTBEAT_MS) \
                or (peer.account.is_empty() and now > peer.opened + AUTH_MS) \
                or (peer.verifying and now > peer.verify_deadline) \
                or (peer.expires > 0 and peer.expires <= int(Time.get_unix_time_from_system())):
            _drop(peer)
            continue
        if not peer.account.is_empty() and now >= peer.check_at and not peer.verifying:
            _verify(peer, peer.token)
        for _index in 12:
            if peer.closed or peer.socket.get_available_packet_count() == 0:
                break
            var packet := peer.socket.get_packet()
            var request := Wire.decode(packet, Wire.REQUEST_BYTES)
            if not peer.socket.was_string_packet() or request.is_empty() or not Wire.valid_request(request):
                _drop(peer)
                break
            if now - peer.rate_at >= 1000:
                peer.rate_at = now
                peer.received = 0
            peer.received += 1
            if peer.received > 40:
                _drop(peer)
                break
            peer.last_seen = now
            _request(peer, request, now)
    if not stopping and simulation != null and not writing and (suspension_checkpoint or (now >= next_checkpoint and _active(now))):
        suspension_checkpoint = false
        _checkpoint()
    if now >= stats_at:
        if simulation != null and steps > 0:
            print("Phase 3C metrics tick=", simulation.tick, " physics_us_avg=", physical_usec / float(steps),
                " semantic_us_avg=", semantic_usec / float(maxi(1, semantic_steps)),
                " projections=", broadcasts, " checkpoint_bytes=", store.last_bytes, " checkpoint_us=", store.last_usec)
        stats_at = now + 10_000
        physical_usec = 0
        semantic_usec = 0
        semantic_steps = 0
        broadcasts = 0
        steps = 0

func _request(peer: Connection, request: Dictionary, now: int) -> void:
    match request.type:
        "ping":
            _send(peer, "pong")
        "auth", "renew":
            if (request.type == "auth") != peer.account.is_empty() or peer.verifying \
                    or (request.type == "renew" and now < peer.check_at - 40_000):
                return
            _verify(peer, request.token)
        _:
            if peer.account.is_empty() or by_account.get(peer.account) != peer or stopping:
                _send(peer, "error", {"reason": "sign_in_required"})
                return
            match request.type:
                "ready":
                    if peer.initial_state_at > 0:
                        peer.ready = true
                "move":
                    if peer.ready and not critical and _active(now):
                        var actor := _actor(peer)
                        if not actor.is_empty() and int(request.seq) > peer.move_seq:
                            peer.move_seq = int(request.seq)
                            bodies[actor].last_input = request
                            bodies[actor].received_at = now
                "talk":
                    _talk(peer, request)
                _:
                    _room_request(peer, request, now)

func _verify(peer: Connection, token: String) -> void:
    if auth_in_flight >= MAX_CONNECTIONS:
        _drop(peer)
        return
    auth_in_flight += 1
    peer.verifying = true
    peer.verify_deadline = Time.get_ticks_msec() + AUTH_MS
    var checked := await verifier.verify(token)
    auth_in_flight -= 1
    peer.verifying = false
    if peer.closed or Time.get_ticks_msec() > peer.verify_deadline:
        return
    if checked.is_empty() or (not peer.account.is_empty() and
            (peer.account != checked.account or peer.session_id != checked.session)):
        _send(peer, "fatal", {"reason": "authorization_lost"})
        _drop(peer)
        return
    var admission := peer.account.is_empty()
    if admission:
        var previous: Connection = by_account.get(checked.account)
        if previous != null:
            _send(previous, "fatal", {"reason": "connection_replaced"})
            _drop(previous)
        peer.account = checked.account
        by_account[peer.account] = peer
    peer.token = token
    peer.session_id = checked.session
    peer.expires = checked.expires
    peer.check_at = Time.get_ticks_msec() + VERIFY_MS
    _send(peer, "authorized")
    if admission:
        _metadata()

func _room_request(peer: Connection, request: Dictionary, now: int) -> void:
    if request.type == "join" and not _limit_join(peer.account, now):
        _send(peer, "error", {"reason": "try_again"})
        return
    var actor := _actor(peer)
    if critical or writing:
        _send(peer, "error", {"reason": "checkpoint_pending"})
        return
    match request.type:
        "create":
            if not owners.is_empty():
                _send(peer, "error", {"reason": "room_in_use"})
                return
            code = Crypto.new().generate_random_bytes(6).hex_encode().to_upper()
            owners[FIRST] = peer.account
        "join":
            if not actor.is_empty():
                _metadata()
                return
            if code.is_empty() or code != String(request.code).to_upper() or owners.size() != 1:
                _send(peer, "error", {"reason": "room_unavailable"})
                return
            owners[SECOND] = peer.account
        "resume":
            if actor.is_empty():
                _send(peer, "error", {"reason": "room_unavailable"})
            else:
                _metadata()
            return
        "start":
            if actor != FIRST or _available() != 2 or simulation != null:
                _send(peer, "error", {"reason": "two_players_required"})
                return
            simulation = SeasonSimulation.new(owners[FIRST], GameStateData.new_id(), randi(), owners)
            _spawn()
        _:
            return
    critical = true
    var saved := await _checkpoint()
    critical = false
    if saved:
        _metadata()

func _limit_join(account: String, now: int) -> bool:
    if now < int(operation_at.get(account, 0)):
        return false
    if operation_at.size() >= 128:
        for expired: String in operation_at.keys():
            if int(operation_at[expired]) <= now:
                operation_at.erase(expired)
        if operation_at.size() >= 128:
            return false
    operation_at[account] = now + 2000
    return true

func _actor(peer: Connection) -> String:
    if peer.account.is_empty():
        return ""
    for actor: String in owners:
        if owners[actor] == peer.account:
            return actor
    return ""

func _available(require_ready := false) -> int:
    var count := 0
    for account: String in owners.values():
        var peer: Connection = by_account.get(account)
        count += int(peer != null and (not require_ready or peer.ready))
    return count

func _controller_ready(actor: String) -> bool:
    var peer: Connection = by_account.get(owners[actor])
    return peer != null and peer.ready

func _active(now: int) -> bool:
    var available := _available(true)
    return simulation != null and not stopping and (available == 2 or (available == 1 and now < grace_until))

func _drop(peer: Connection) -> void:
    if peer.closed:
        return
    peer.closed = true
    peer.token = ""
    peer.socket.close(1008, "connection closed")
    peers.erase(peer)
    if peer.account.is_empty() or by_account.get(peer.account) != peer:
        return
    var actor := _actor(peer)
    by_account.erase(peer.account)
    if simulation != null and not actor.is_empty():
        if peer.ready and _available(true) == 1 and reported_active:
            grace_until = Time.get_ticks_msec() + GRACE_MS
        bodies[actor].clear_input()
        simulation.camps[LOCATION].conversations.erase(actor)
    _metadata()

func _metadata() -> void:
    if critical:
        metadata_deferred = true
        return
    metadata_deferred = false
    for account: String in by_account.keys():
        var peer: Connection = by_account[account]
        var actor := _actor(peer)
        if actor.is_empty():
            continue
        var roster := []
        for id: String in [FIRST, SECOND]:
            if owners.has(id):
                roster.append({"contestant": id, "online": by_account.has(owners[id])})
        _send(peer, "room", {"code": code, "roster": roster, "controlled": actor,
            "started": simulation != null, "host": actor == FIRST})
        peer.knowledge_dirty = true

func _step() -> void:
    if simulation == null or critical or stopping:
        return
    var now := Time.get_ticks_msec()
    var active := _active(now)
    if active != reported_active:
        reported_active = active
        if not active:
            simulation.camps[LOCATION].conversations.clear()
            suspension_checkpoint = true
        else:
            _metadata()
    var started := Time.get_ticks_usec()
    steps += 1
    if active:
        var delta := 1.0 / Engine.physics_ticks_per_second
        var camp := simulation.camps[LOCATION]
        for id: String in bodies:
            var body := bodies[id]
            if body.human:
                if _controller_ready(id):
                    body.drive(delta, bodies.get(camp.conversations.get(id, "")))
            else:
                var conversation_actor: Variant = camp.conversations.find_key(id)
                var assignment: Dictionary = camp.people[id]
                var travel := body.follow(assignment, destinations.get(assignment.activity, body.position),
                    delta, bodies.get(String(conversation_actor) if conversation_actor != null else ""))
                if travel != 0:
                    simulation.observe_travel(LOCATION, id, assignment.activity, travel > 0)
        semantic_elapsed += delta
        if semantic_elapsed >= SeasonSimulation.TICK_SECONDS:
            semantic_elapsed -= SeasonSimulation.TICK_SECONDS
            var semantic_started := Time.get_ticks_usec()
            simulation.advance(LOCATION)
            semantic_usec += Time.get_ticks_usec() - semantic_started
            semantic_steps += 1
    physical_usec += Time.get_ticks_usec() - started
    if Engine.get_physics_frames() % (SNAPSHOT_STEPS if active else 15) == 0:
        _broadcast(active)

func _broadcast(active: bool) -> void:
    var camp := simulation.camps[LOCATION]
    var movement := {}
    for id: String in bodies:
        var body := bodies[id]
        var velocity := body.get_real_velocity() if active else Vector3.ZERO
        movement[id] = [snappedf(body.position.x, .01), snappedf(body.position.y, .01),
            snappedf(body.position.z, .01), snappedf(body.travel_heading, .001),
            body.locomotion, body.dive_requested, snappedf(velocity.x, .01),
            snappedf(velocity.y, .01), snappedf(velocity.z, .01),
            camp.conversations.has(id) or camp.conversations.values().has(id)]
    for account: String in owners.values():
        var peer: Connection = by_account.get(account)
        if peer == null or (not peer.ready and peer.initial_state_at != 0):
            continue
        if peer.initial_state_at == 0:
            peer.initial_state_at = Time.get_ticks_msec()
        var actor := _actor(peer)
        var projection := simulation.project(account, LOCATION, peer.knowledge_dirty)
        var knowledge: Variant = projection.get("knowledge")
        projection.erase("knowledge")
        if peer.knowledge_dirty:
            # Split independently bounded journal batches out of movement snapshots.
            _send(peer, "journal_reset")
            if knowledge is Array:
                for index in range(0, knowledge.size(), 64):
                    _send(peer, "journal", {"records": knowledge.slice(index, index + 64)})
            peer.knowledge_dirty = false
        var receipt: Dictionary = durable_receipts.get(actor, {})
        var public_camp := {"cast": projection.cast, "objects": projection.objects}
        if public_camp != peer.last_camp:
            _send(peer, "camp", public_camp)
            peer.last_camp = public_camp
        _send(peer, "state", {"view": {"tick": projection.tick, "day": projection.day,
            "phase": projection.phase}, "movement": movement, "active": active and peer.ready,
            "ack_move": bodies[actor].applied, "next_command": int(receipt.get("seq", 0)) + 1})
        broadcasts += 1

func _talk(peer: Connection, request: Dictionary) -> void:
    var actor := _actor(peer)
    if simulation == null or actor.is_empty() or not peer.ready:
        return
    if critical:
        _reject(peer, request.id, "checkpoint_pending")
        return
    var last: Dictionary = durable_receipts.get(actor, {})
    if last.get("id") == request.id and int(last.get("seq", 0)) == int(request.seq):
        _send(peer, "receipt", {"result": last.result})
        return
    if peer.last_talk.get("id") == request.id:
        _send(peer, "receipt", {"result": peer.last_talk})
        return
    if critical or not _active(Time.get_ticks_msec()) or (writing and request.kind == "talk.respond"):
        _reject(peer, request.id, "checkpoint_pending")
        return
    if int(request.seq) != int(last.get("seq", 0)) + 1:
        _reject(peer, request.id, "invalid_sequence")
        return
    var target: String = request.target
    if not bodies.has(target):
        _reject(peer, request.id, "invalid_target")
        return
    var player := bodies[actor]
    var npc := bodies[target]
    var distance := player.position.distance_to(npc.position)
    var accessible := false
    if request.kind != "talk.end" and distance <= SeasonSimulation.REACH and not player.swimming() and not npc.human:
        var eye := Vector3.UP * 1.35
        var sight := PhysicsRayQueryParameters3D.create(player.position + eye, npc.position + eye, 1 | 4)
        accessible = distance < .001 or world.get_world_3d().direct_space_state.intersect_ray(sight).is_empty()
    if not accessible and request.kind != "talk.end":
        _reject(peer, request.id, "unavailable")
        return
    var result := simulation.command(peer.account,
        {"id": request.id, "actor": actor, "kind": request.kind, "target": target, "topic": request.topic},
        {"location": LOCATION, "target": target, "distance": distance, "accessible": accessible})
    peer.last_talk = result
    if result.ok and request.kind == "talk.respond":
        durable_receipts[actor] = {"seq": int(request.seq), "id": request.id, "result": result}
        critical = true
        var saved := await _checkpoint()
        critical = false
        if not saved:
            return
        if metadata_deferred:
            _metadata()
        var journal: Array = simulation.camps[LOCATION].people[actor].journal
        _send(peer, "journal", {"records": [journal.back()]})
    _send(peer, "receipt", {"result": result})

func _reject(peer: Connection, id: String, reason: String) -> void:
    _send(peer, "receipt", {"result": {"id": id, "ok": false, "reason": reason, "event": {}}})

func _send(peer: Connection, type: String, fields := {}) -> void:
    if not peer.closed and not Wire.send(peer.socket, type, fields):
        peer.socket.close(1008, "send buffer unavailable")
        # Leave collection and membership cleanup to the next poll.
        peer.last_seen = 0

func _spawn() -> void:
    var entries := [Vector3(-7.4, 4.8, -25.9), Vector3(.2, 1.3, -30),
        Vector3(-22, .2, -27.8), Vector3(11.5, 2.5, -31), Vector3(-5, 3.1, -34)]
    var index := 0
    for id: String in simulation.camps[LOCATION].people:
        var body := Body.new()
        body.human = owners.has(id)
        body.water = water
        var spawn: Vector3 = site.point(site.layout.spawn)
        if id == SECOND:
            spawn = site.ground(spawn.x + 1.6, spawn.z)
        elif not body.human:
            spawn = site.ground(entries[index].x, entries[index].z)
            body.delay = entries[index].y if simulation.tick == 0 else .2
        if id != FIRST:
            index += 1
        body.position = spawn + Vector3.UP * .13
        world.add_child(body)
        bodies[id] = body

func _restore(saved: Variant) -> bool:
    if saved == null:
        return true
    if saved is not Dictionary or saved.get("version") != 1:
        return false
    code = saved.code
    owners = saved.owners
    durable_receipts = saved.receipts
    if saved.season == null:
        return true
    simulation = SeasonSimulation.restore(saved.season)
    _spawn()
    for id: String in bodies:
        var row: Array = saved.positions[id]
        bodies[id].position = Wire.position_from(row)
        bodies[id].set_heading(row[3])
        bodies[id].locomotion = int(row[4])
        bodies[id].restore_dive(row[5])
    return true

func _checkpoint() -> bool:
    if writing:
        return false
    writing = true
    var positions := {}
    for id: String in bodies:
        var body := bodies[id]
        positions[id] = [body.position.x, body.position.y, body.position.z,
            body.travel_heading, body.locomotion, body.dive_requested]
    var data := {"version": 1, "code": code, "owners": owners, "positions": positions,
        "receipts": durable_receipts, "season": simulation.snapshot() if simulation != null else null}
    var saved := await store.write_latest(data)
    writing = false
    next_checkpoint = Time.get_ticks_msec() + CHECKPOINT_MS
    if not saved:
        _fail("Authoritative checkpoint rejected or unavailable")
    return saved

func _shutdown() -> void:
    stopping = true
    listener.stop()
    for peer: Connection in peers.duplicate():
        _drop(peer)
    while writing:
        await process_frame
    if not owners.is_empty():
        if not await _checkpoint():
            return
    quit()

func _fail(reason: String) -> void:
    printerr("Phase 3C server: ", reason)
    listener.stop()
    quit(1)
