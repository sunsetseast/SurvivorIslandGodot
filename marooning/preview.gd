class_name MarooningPreview
extends Node3D
signal exited
const Actor := preload("res://character_lab/actor.gd")
@export var layout: MarooningLayout=preload("res://marooning/layout.tres")
var configuration: Dictionary
var catalog: SurvivorContestantCatalog
var preferences: Dictionary={}
var bay: MarooningBay
var player: MarooningPlayer
var touch: MarooningTouch
var cast: Dictionary={}
var routes: Dictionary
var cinematic: Camera3D
var elapsed := 0.0
var introducing := true
var shots: Array[Dictionary]=[]
var actions: Dictionary={}
var old_max_steps := 8
var session := MarooningSession.new()
var scramble: MarooningScrambleAdapter
var race: MarooningRaceAdapter
var hud: MarooningHUD
var subtitle: Label
var _capture_callback: JavaScriptObject
var _focus_callback: JavaScriptObject
var _frame_usec := 0
var frame_intervals: Array[float]=[]
var brain_elapsed := 0.0
var brain_index := 0
func _ready() -> void:
    old_max_steps=Engine.max_physics_steps_per_frame
    Engine.max_physics_steps_per_frame=mini(old_max_steps,8)
    bay=MarooningBay.new()
    add_child(bay)
    bay.build(layout,configuration.tribes.size())
    var navigation := NavigationRegion3D.new()
    navigation.navigation_mesh=load("res://marooning/navigation.res")
    add_child(navigation)
    routes=layout.routes(configuration)
    _cast()
    cinematic=Camera3D.new()
    cinematic.far=700
    add_child(cinematic)
    cinematic.current=true
    var layer := CanvasLayer.new()
    add_child(layer)
    touch=MarooningTouch.new()
    touch.motor=player
    layer.add_child(touch)
    scramble=MarooningScrambleAdapter.new()
    scramble.preview=self
    add_child(scramble)
    race=MarooningRaceAdapter.new()
    race.preview=self
    add_child(race)
    hud=MarooningHUD.new()
    hud.preview=self
    layer.add_child(hud)
    subtitle=hud.message
    actions=hud.actions
    get_viewport().size_changed.connect(_layout_hud_safe)
    _layout_hud_safe()
    shots=[
        {"eye":Vector3(34,23,32),"target":Vector3(0,7,1),"text":"Welcome to Survivor Island. Your marooning begins aboard this ship."},
        {"eye":Vector3(4,5,7),"target":Vector3(-2,2.4,1),"text":"Collect for up to 60 seconds. Pick up one supply and carry it to your tribe's colored basket."},
        {"eye":Vector3(19,6,8),"target":Vector3(7,1,1),"text":"Each tribe can leave early. Use the open side ramps, board your raft, then encourage your crew with Let's Go."},
        {"eye":Vector3(17,8,103),"target":layout.reward,"text":"One fishing reward is available from the start. Swim early or paddle in rhythm. Jumping commits you to water travel."},
        {"eye":Vector3(-13,7,157),"target":Vector3(0,2,178),"text":"Bring your people and cargo to this shore. Left thumb moves; right thumb looks. Tap Paddle at the center of the meter."}]
    player.locked=true
    touch.cancel()
    if OS.has_feature("web"):
        _focus_callback=JavaScriptBridge.create_callback(func(args: Array) -> void: _set_suspended(bool(args[0]) if not args.is_empty() else true))
        JavaScriptBridge.get_interface("window").marooningFocus=_focus_callback
        JavaScriptBridge.eval("window._marooningFocusHandler=()=>window.marooningFocus(document.hidden||!document.hasFocus());document.addEventListener('visibilitychange',window._marooningFocusHandler);window.addEventListener('blur',window._marooningFocusHandler);window.addEventListener('focus',window._marooningFocusHandler)")
        if bool(JavaScriptBridge.eval("new URLSearchParams(location.search).has('review')")):
            _capture_callback=JavaScriptBridge.create_callback(_capture)
            JavaScriptBridge.get_interface("window").marooningView=_capture_callback

func _cast() -> void:
    for t in configuration.tribes.size():
        var tribe: Dictionary = configuration.tribes[t]
        for i in tribe.members.size():
            var id := int(tribe.members[i])
            var point := Vector3(-2.15 + (i % 3) * 2.15, layout.deck_y + .12, 1.5 + (i / 3) * 2.1 + t * 6)
            # Three rows per tribe at most, spread longitudinally down the deck.
            point.z = -1.8 + (t * (tribe.members.size() / 3) + i / 3) * 1.8
            var entry := catalog.get_by_id(id)
            var actor: Node3D
            if id == int(configuration.selected):
                player = MarooningPlayer.new()
                player.water = CampWaterSurface.new(0, layout.bed)
                player.water_motion = load("res://world/assets/surface-swimming.res")
                player.position = point
                add_child(player)
                player.floor_block_on_wall = false
                player.platform_floor_layers = 1 | 8
                player.platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
                player.select_controller(true)
                player.camera.far = 700
                player.sensitivity = float(preferences.get("sensitivity", 1.0))
                player.camera_relative_steering = bool(preferences.get("camera_steering", false))
                actor = player
            else:
                actor = MarooningDeckMotor.new()
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
            var skeleton: Skeleton3D=actor.presentation.skeleton
            var attachment := BoneAttachment3D.new()
            attachment.bone_name="neck_01"
            skeleton.add_child(attachment)
            var buff := MeshInstance3D.new()
            var cloth := CylinderMesh.new()
            cloth.top_radius=.091
            cloth.bottom_radius=.098
            cloth.height=.052
            cloth.radial_segments=16
            buff.mesh=cloth
            var fabric := MarooningBay.material(Color(tribe.color).lerp(Color("8b806c"),.22))
            fabric.roughness=1.0
            buff.material_override=fabric
            attachment.add_child(buff)
            var pose := MarooningPose.new()
            skeleton.add_child(pose)
            actor.set_meta("marooning_pose",pose)
            var label := Label3D.new()
            label.text = entry.name
            label.position.y = 2.1
            label.font_size = 32
            label.pixel_size = .004
            label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
            label.modulate = Color(tribe.color).lightened(.4)
            label.hide()
            actor.add_child(label)
    var host := Actor.new()
    host.name = "TemporaryHost"
    host.position = bay.markers.host.position
    add_child(host)


func _layout_hud_safe() -> void:
    if not is_instance_valid(hud): return
    var area := touch.safe
    if OS.has_feature("web"):
        var raw := str(JavaScriptBridge.eval("(()=>{const e=document.createElement('div');e.style.cssText='position:fixed;visibility:hidden;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';document.body.appendChild(e);const s=getComputedStyle(e);const r=JSON.stringify([s.paddingTop,s.paddingRight,s.paddingBottom,s.paddingLeft].map(v=>parseFloat(v)||0));e.remove();return r})()"))
        var insets=JSON.parse_string(raw)
        if insets is Array and insets.size()==4:
            var size := get_viewport().get_visible_rect().size
            var window := JavaScriptBridge.get_interface("window")
            var factor := size/Vector2(maxf(1,float(window.innerWidth)),maxf(1,float(window.innerHeight)))
            var top_left := Vector2(insets[3],insets[0])*factor
            var bottom_right := Vector2(insets[1],insets[2])*factor
            area=area.intersection(Rect2(top_left,size-top_left-bottom_right))
    touch.safe=area
    touch.stick_center=touch.home()
    touch.queue_redraw()
    hud.layout_safe(area)
func _process(delta: float) -> void:
    var now := Time.get_ticks_usec()
    if _frame_usec>0:
        frame_intervals.append((now-_frame_usec)/1000.0)
        if frame_intervals.size()>300: frame_intervals.pop_front()
    _frame_usec=now
    if introducing and not session.suspended:
        elapsed+=delta
        var shot: Dictionary=shots[mini(int(elapsed/4),shots.size()-1)]
        cinematic.position=shot.eye if elapsed<.1 else cinematic.position.lerp(shot.eye,1-exp(-delta*2))
        cinematic.look_at(shot.target)
        subtitle.text=shot.text
        if elapsed>=20: finish_intro()
    hud.update_state()
func finish_intro() -> void:
    if not introducing: return
    introducing=false
    session.ready()
    player.camera.current=true
    touch.cancel()
    subtitle.text="Collect supplies, board early or swim. Jumping from the ship commits to water travel."
func _physics_process(delta: float) -> void:
    if not is_instance_valid(race) or session.suspended: return
    race.prepare(delta)
    scramble.traffic.update_player()
    if session.state==MarooningSession.State.ACTIVE:
        brain_elapsed+=delta
        if brain_elapsed>=.05:
            brain_elapsed=0
            var ids := scramble.agents.keys()
            for iteration in 3:
                var id := int(ids[brain_index%ids.size()])
                if not session.wants_departure(id): scramble.decide(id)
                brain_index+=1
        for id: int in scramble.agents:
            if session.race.actors[id].place=="deck" and not session.wants_departure(id): scramble.traffic.step(id,delta)
        player.movement_speed_multiplier=session.scramble.multiplier(int(configuration.selected)) if session.race.actors[int(configuration.selected)].place=="deck" else player.movement_speed_multiplier
    session.advance(delta,scramble.accessible,race.access)
    player.locked=introducing or session.state in [MarooningSession.State.READY,MarooningSession.State.COUNTDOWN]
    scramble.update_visuals(delta)
    race.present(delta)
    touch.set_movement(not player.raft_attached and not player.locked)
func _set_suspended(value: bool) -> void:
    session.set_suspended(value)
    if is_instance_valid(touch): touch.cancel()
    for body: CampPhysicalMotor in cast.values(): body.locomotion_suspended=value
func _notification(what: int) -> void:
    if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_WM_WINDOW_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]: _set_suspended(true)
    elif what in [NOTIFICATION_APPLICATION_FOCUS_IN,NOTIFICATION_WM_WINDOW_FOCUS_IN,NOTIFICATION_APPLICATION_RESUMED]: _set_suspended(false)
func _exit() -> void:
    touch.cancel()
    player.locked=true
    exited.emit()
func _exit_tree() -> void:
    Engine.max_physics_steps_per_frame=old_max_steps
    _clear_browser_callbacks()
    if is_instance_valid(touch): touch.motor=null
func _clear_browser_callbacks() -> void:
    if _capture_callback!=null: JavaScriptBridge.get_interface("window").marooningView=null
    if _focus_callback!=null:
        JavaScriptBridge.eval("document.removeEventListener('visibilitychange',window._marooningFocusHandler);window.removeEventListener('blur',window._marooningFocusHandler);window.removeEventListener('focus',window._marooningFocusHandler);window.marooningFocus=null;window._marooningFocusHandler=null")
    _focus_callback=null
    _capture_callback=null
func restart_scramble() -> void:
    _clear_browser_callbacks()
    for key: String in ["scramble_result","marooning_result"]:
        if has_meta(key): remove_meta(key)
    touch.cancel()
    Engine.max_physics_steps_per_frame=old_max_steps
    if get_viewport().size_changed.is_connected(_layout_hud_safe): get_viewport().size_changed.disconnect(_layout_hud_safe)
    for child in get_children(): child.free()
    cast.clear()
    actions.clear()
    session=MarooningSession.new()
    elapsed=0
    introducing=true
    brain_elapsed=0
    brain_index=0
    frame_intervals.clear()
    _frame_usec=0
    _ready()
func review_state() -> Dictionary:
    var controls := {}
    var size := get_viewport().get_visible_rect().size
    for key: String in hud.actions:
        var button: Button=hud.actions[key]
        if button.is_visible_in_tree():
            var center := button.get_global_rect().get_center()/size
            controls[key]=[center.x,center.y]
    for pair: Array in [[hud.command,hud.primary],[hud.second_command,hud.secondary],[hud.third_command,hud.tertiary]]:
        if not str(pair[0]).is_empty() and pair[1].is_visible_in_tree():
            var center: Vector2=pair[1].get_global_rect().get_center()/size
            controls[str(pair[0])]=[center.x,center.y]
    controls["stick"]=[touch.home().x/size.x,touch.home().y/size.y]
    var actor: Dictionary=session.race.actors[int(configuration.selected)]
    var point := session.race.boarding_access(int(configuration.selected))
    var actor_review := {}
    for key: String in ["place","mode","raft","arrived","boardings","departures","strokes","perfect","good","missed","swim_distance","fatigue","paddling","impulse_total_ns","unloaded_count"]: actor_review[key]=actor[key]
    var vessels := {}
    for tribe: String in session.race.rafts:
        var vessel: Dictionary=session.race.rafts[tribe]
        vessels[tribe]={"position":[vessel.position.x,vessel.position.y,vessel.position.z],"state":vessel.state,"crew":vessel.crew,"launch_time":vessel.launch_time,"cargo_ids":vessel.cargo_ids,"delivered":vessel.delivered_ids.size(),"distance":vessel.distance,"speed":vessel.speed}
    return {"implementation_sha":ProjectSettings.get_setting("marooning_build/implementation_sha",""),"actors":cast.size(),"selected":configuration.selected,"tribes":configuration.tribes.size(),"supply_state":scramble.review_state(),"race_actor":actor_review,"vessels":vessels,"suspended":session.suspended,"reward_status":session.race.reward.status,"feedback":race.feedback,"deck_access":[routes[actor.tribe].deck_access.x,routes[actor.tribe].deck_access.z],"intro":introducing,"locked":player.locked,"x":player.position.x,"y":player.position.y,"z":player.position.z,"yaw":player.yaw,"pitch":player.pitch,"rendered_yaw":player.rendered_yaw(),"move_heading":player._stick_yaw if player._stick_active else player.rendered_yaw(),"travel":player.travel_distance,"move_finger":touch.move_finger,"look_finger":touch.look_finger,"controls":controls,"frame_intervals_ms":frame_intervals,"scramble_phase":session.scramble.phase,"scramble_elapsed":session.scramble.elapsed,"events":session.events.size(),"race_phase":session.race.phase,"race_elapsed":session.elapsed,"reward":session.race.reward.tribe,"aboard":actor.raft,"boarding_position":[point.x,point.z],"arrival_position":[session.race.arrival_point(int(configuration.selected)).x,session.race.arrival_point(int(configuration.selected)).z],"session_state":session.state,"countdown":session.countdown}

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
