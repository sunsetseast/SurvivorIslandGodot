class_name MarooningPreview
extends Node3D
signal exited
const Actor := preload("res://character_lab/actor.gd")
@export var layout: MarooningLayout = preload("res://marooning/layout.tres")
var configuration: Dictionary
var catalog: SurvivorContestantCatalog
var preferences: Dictionary = {}
var bay: MarooningBay
var player: CampThirdPerson
var touch: CampTouch
var cast: Dictionary = {}
var routes: Dictionary
var cinematic: Camera3D
var subtitle: Label
var skip: Button
var elapsed := 0.0
var introducing := true
var shots: Array[Dictionary] = []
var intro_tween: Tween
var actions: Dictionary = {}
var old_max_steps := 8
var scramble: MarooningScrambleAdapter
var race: MarooningRaceAdapter
var _capture_callback: JavaScriptObject
var _frame_usec: int = 0
var frame_intervals: Array[float] = []

func _ready() -> void:
    old_max_steps = Engine.max_physics_steps_per_frame
    Engine.max_physics_steps_per_frame = 120
    # This scene never creates a GameSession, SaveProvider or cloud transport.
    bay = MarooningBay.new()
    add_child(bay)
    bay.build(layout, configuration.tribes.size())
    var navigation := NavigationRegion3D.new()
    navigation.navigation_mesh = load("res://marooning/navigation.res")
    add_child(navigation)
    routes = layout.routes(configuration)
    _cast()
    cinematic = Camera3D.new()
    cinematic.far = 700
    add_child(cinematic)
    cinematic.current = true
    _hud()
    scramble = MarooningScrambleAdapter.new()
    scramble.preview = self
    add_child(scramble)
    race = MarooningRaceAdapter.new()
    race.preview = self
    add_child(race)
    shots = [
        {"eye":Vector3(42, 29, 48), "target":Vector3(0, 9, 0), "text":"Welcome aboard. Eighteen castaways, one new adventure."},
        {"eye":Vector3(8, 12, 15), "target":Vector3(0, layout.deck_y + 1, 0), "text":"Take a look around. These are the people who will share your journey."},
        {"eye":Vector3(3, layout.deck_y + 4, -5), "target":bay.markers.host.position + Vector3.UP, "text":"Your tribes begin here, with the supplies on this deck."},
    ]
    for tribe: Dictionary in configuration.tribes:
        shots.append({"eye":Vector3(12, 13, 14), "target":Vector3(0, 6, 0), "text":"%s · %s · %d castaways" % [tribe.name, tribe.color.capitalize(), tribe.members.size()]})
    shots.append({"eye":Vector3(46, 16, 35), "target":layout.reward, "text":"Later, you will gather supplies and paddle to camp. A single bonus reward will tempt tribes to leave early."})
    shots.append({"eye":Vector3(-18, 10, 143), "target":layout.landing, "text":"Gather what your tribe needs. Load at your tribe’s station before time runs out. Your season save stays untouched."})
    player.locked = true
    touch.cancel()
    if OS.has_feature("web") and bool(JavaScriptBridge.eval("new URLSearchParams(location.search).has('review')")):
        _capture_callback = JavaScriptBridge.create_callback(_capture)
        JavaScriptBridge.get_interface("window").marooningView = _capture_callback

func _cast() -> void:
    for t in configuration.tribes.size():
        var tribe: Dictionary = configuration.tribes[t]
        for i in tribe.members.size():
            var id := int(tribe.members[i])
            var point := Vector3(-2.3 + (i % 3) * 2.3, layout.deck_y + .12, 1.5 + (i / 3) * 2.1 + t * 6)
            # Three rows per tribe at most, spread longitudinally down the deck.
            point.z = -1.8 + (t * (tribe.members.size() / 3) + i / 3) * 1.8
            var entry := catalog.get_by_id(id)
            var actor: Node3D
            if id == int(configuration.selected):
                player = CampThirdPerson.new()
                player.water = CampWaterSurface.new(0, layout.bed)
                player.water_motion = load("res://world/assets/surface-swimming.res")
                player.position = point
                add_child(player)
                player.floor_block_on_wall = false
                player.select_controller(true)
                player.camera.far = 700
                player.sensitivity = float(preferences.get("sensitivity", 1.0))
                player.camera_relative_steering = bool(preferences.get("camera_steering", false))
                actor = player
            else:
                actor = CampHumanoidMotor.new()
                actor.collision_layer = 4
                actor.collision_mask = 1
                actor.water_motion = load("res://world/assets/surface-swimming.res")
                actor.floor_block_on_wall = false
                actor.position = point
                add_child(actor)
            actor.set_meta("contestant_id", id)
            actor.set_meta("tribe_id", tribe.id)
            actor.set_meta("display_name", entry.name)
            cast[id] = actor
            var buff := MeshInstance3D.new()
            var cloth := CylinderMesh.new()
            cloth.top_radius = .18
            cloth.bottom_radius = .18
            cloth.height = .16
            cloth.radial_segments = 8
            buff.mesh = cloth
            buff.material_override = MarooningBay.material(Color(tribe.color))
            buff.position.y = 1.38
            actor.add_child(buff)
            var label := Label3D.new()
            label.text = entry.name
            label.position.y = 2.1
            label.font_size = 32
            label.pixel_size = .004
            label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
            label.modulate = Color(tribe.color).lightened(.4)
            actor.add_child(label)
    var host := Actor.new()
    host.name = "TemporaryHost"
    host.position = bay.markers.host.position
    add_child(host)

func _hud() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    touch = CampTouch.new()
    touch.motor = player
    layer.add_child(touch)
    var panel := VBoxContainer.new()
    panel.position = Vector2(18, 12)
    panel.theme = IslandTheme.create()
    layer.add_child(panel)
    for action: Array in [["Exit Preview", _exit], ["Preview only · Return to deck", reset_deck], ["Preview only · Inspect landing", inspect_landing], ["Preview only · Inspect reward dock", inspect_dock]]:
        var button := Button.new()
        button.text = action[0]
        button.pressed.connect(action[1])
        panel.add_child(button)
        actions[action[0]] = button
    for key: String in actions:
        if key.begins_with("Preview only"):
            actions[key].hide()
    skip = Button.new()
    skip.text = "Skip introduction"
    skip.pressed.connect(finish_intro)
    panel.add_child(skip)
    actions["skip"] = skip
    subtitle = Label.new()
    subtitle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    subtitle.offset_top = -100
    subtitle.offset_left = 155
    subtitle.offset_right = -155
    subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    subtitle.add_theme_font_size_override("font_size", 22)
    subtitle.add_theme_color_override("font_outline_color", Color.BLACK)
    subtitle.add_theme_constant_override("outline_size", 8)
    layer.add_child(subtitle)

func _process(delta: float) -> void:
    var now := Time.get_ticks_usec()
    if _frame_usec > 0:
        frame_intervals.append((now - _frame_usec) / 1000.0)
        if frame_intervals.size() > 300:
            frame_intervals.pop_front()
    _frame_usec = now
    if player.position.y < -20 or absf(player.position.x) > 200 or absf(player.position.z) > 205:
        if not race.started:
            reset_deck()
    if not introducing:
        return
    elapsed += delta
    var index := mini(int(elapsed / 5), shots.size() - 1)
    var shot: Dictionary = shots[index]
    var destination: Vector3 = shot.eye
    cinematic.position = destination if elapsed < .1 else cinematic.position.lerp(destination, 1 - exp(-delta * 2))
    cinematic.look_at(shot.target)
    subtitle.text = shot.text
    if elapsed >= shots.size() * 5:
        finish_intro()

func finish_intro() -> void:
    if not introducing:
        return
    introducing = false
    touch.cancel()
    # Blend the last shot into the existing orbit camera before unlocking input.
    intro_tween = create_tween()
    intro_tween.tween_property(cinematic, "global_transform", player.camera.global_transform, .65)
    intro_tween.finished.connect(func() -> void:
        if not is_inside_tree():
            return
        player.camera.current = true
        player.locked = false
        touch.cancel())
    skip.hide()
    subtitle.text = "WASD / left thumb: walk · Right drag / right thumb: look\nPress Start Supply Scramble when ready."

func _relocate(point: Vector3) -> void:
    if introducing:
        return
    touch.cancel()
    player.velocity = Vector3.ZERO
    player.planar = Vector3.ZERO
    player.position = point
    player.sync_camera()

func reset_deck() -> void:
    _relocate(Vector3(0, layout.deck_y + .15, 7))

func inspect_landing() -> void:
    _relocate(Vector3(layout.landing.x, layout.bed(layout.landing.x, layout.landing.z) + .15, layout.landing.z))

func inspect_dock() -> void:
    _relocate(layout.reward + Vector3(-1, .3, 0))

func _notification(what: int) -> void:
    if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED] and is_instance_valid(touch):
        touch.cancel()
        for actor: CampPhysicalMotor in cast.values():
            actor.locomotion_suspended = true
        if is_instance_valid(race):
            race.simulation.suspended = true
        if is_instance_valid(scramble):
            scramble.simulation.suspended = true
    if what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED] and is_instance_valid(scramble):
        scramble.simulation.suspended = false
        for actor: CampPhysicalMotor in cast.values():
            actor.locomotion_suspended = false
        if is_instance_valid(race):
            race.simulation.suspended = false

func _exit() -> void:
    touch.cancel()
    player.locked = true
    exited.emit()

func _exit_tree() -> void:
    if intro_tween != null and intro_tween.is_valid():
        intro_tween.kill()
    Engine.max_physics_steps_per_frame = old_max_steps
    if _capture_callback != null:
        JavaScriptBridge.get_interface("window").marooningView = null
    if is_instance_valid(touch):
        touch.motor = null

func review_state() -> Dictionary:
    var controls := {}
    var size := get_viewport().get_visible_rect().size
    for id: String in actions:
        if actions[id].visible:
            var point: Vector2 = actions[id].get_global_rect().get_center() / size
            controls[id] = [point.x, point.y]
    if is_instance_valid(scramble):
        for key: String in {"start":scramble.start_button,"interact":scramble.action_button,"drop":scramble.drop_button,"restart":scramble.restart_button}:
            var control: Button = {"start":scramble.start_button,"interact":scramble.action_button,"drop":scramble.drop_button,"restart":scramble.restart_button}[key]
            if control.visible:
                var center := control.get_global_rect().get_center() / size
                controls[key] = [center.x,center.y]
    if is_instance_valid(scramble) and scramble.steal_button.is_visible_in_tree():
        var center := scramble.steal_button.get_global_rect().get_center() / size
        controls["steal"] = [center.x,center.y]
    if is_instance_valid(race) and race.started:
        for key: String in {"board":race.board,"paddle":race.paddle,"rest":race.rest,"jump_off":race.jump,"claim_reward":race.claim_button}:
            var control: Button = {"board":race.board,"paddle":race.paddle,"rest":race.rest,"jump_off":race.jump,"claim_reward":race.claim_button}[key]
            if control.is_visible_in_tree():
                var center := control.get_global_rect().get_center() / size
                controls[key] = [center.x,center.y]
    var stick := touch.home() / size
    controls["stick"] = [stick.x, stick.y]
    return {"actors":cast.size(), "selected":configuration.selected, "tribes":configuration.tribes.size(),
        "intro":introducing, "locked":player.locked, "x":player.position.x, "y":player.position.y,
        "z":player.position.z, "yaw":player.yaw, "travel":player.travel_distance,
        "move_finger":touch.move_finger, "look_finger":touch.look_finger,
        "controls":controls, "frame_intervals_ms":frame_intervals, "scramble_phase":scramble.simulation.phase, "scramble_elapsed":scramble.simulation.elapsed, "events":scramble.simulation.events.size(),"race_phase":race.simulation.phase,"race_elapsed":race.simulation.elapsed,"reward":race.simulation.reward.tribe,"aboard":race.simulation.actors[int(configuration.selected)].raft,"boarding_position":[race.simulation.boarding_point(race.simulation.actors[int(configuration.selected)].tribe).x,race.simulation.boarding_point(race.simulation.actors[int(configuration.selected)].tribe).z]}

func _capture(arguments: Array) -> void:
    if arguments.is_empty():
        return
    var views := {
        "exterior":[Vector3(40, 24, 45), Vector3(0, 10, 0)],
        "deck":[Vector3(7, 7, 10), Vector3(0, 3.5, 0)],
        "rafts":[Vector3(20, 7, -19), Vector3(0, 1.5, -5)],
        "dock":[Vector3(86, 5, 28), layout.reward],
        "landing":[Vector3(-18, 7, 154), Vector3(0, 3, 189)]}
    var id := String(arguments[0])
    if id in ["raft-side","raft-overhead","race"] and is_instance_valid(race):
        var tribe: String = race.simulation.actors[int(configuration.selected)].tribe
        var target: Vector3 = race.vessels[tribe].position
        cinematic.position = target + (Vector3(0,18,0.01) if id == "raft-overhead" else Vector3(12,5,9))
        cinematic.look_at(target)
        cinematic.current = true
    elif id == "follow":
        player.camera.current = true
    elif views.has(id):
        cinematic.position = views[id][0]
        cinematic.look_at(views[id][1])
        cinematic.current = true

func restart_scramble() -> void:
    if intro_tween != null and intro_tween.is_valid():
        intro_tween.kill()
    for key: String in ["scramble_result","marooning_result"]:
        if has_meta(key):
            remove_meta(key)
    frame_intervals.clear()
    _frame_usec = 0
    Engine.max_physics_steps_per_frame = old_max_steps
    touch.cancel()
    for child in get_children():
        child.free()
    cast.clear()
    actions.clear()
    shots.clear()
    elapsed = 0
    introducing = true
    _ready()
