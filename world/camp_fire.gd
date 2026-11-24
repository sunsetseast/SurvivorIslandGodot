class_name CampFire
extends Node3D

enum Quality { ECONOMY, FULL }
const FLAME := preload("res://world/fire_flipbook.gdshader")
const ATLAS := preload("res://world/assets/flame02.webp")

@export_range(.15, 8.0) var fire_size := 1.0:
    set(value):
        fire_size = value
        _sync()
@export_range(0.0, 2.5) var intensity := 1.0:
    set(value):
        intensity = value
        _sync()
@export var lit := true:
    set(value):
        lit = value
        _sync()
@export var quality := Quality.FULL:
    set(value):
        quality = value
        _sync()

var _effects: Node3D
var _flames: Array[MeshInstance3D] = []
var _smoke: CPUParticles3D
var _sparks: CPUParticles3D
var _light: OmniLight3D
var _time := 0.0

func _ready() -> void:
    _effects = Node3D.new()
    add_child(_effects)
    _add_flame(Vector3(0, .49, 0), Vector2(.83, .98), 0.0, 25.0)
    _add_flame(Vector3(-.17, .36, .14), Vector2(.56, .72), 27.0, 22.0)
    _smoke = _particles(false)
    _sparks = _particles(true)
    _light = OmniLight3D.new()
    _light.light_color = Color("#ffad62")
    _light.omni_attenuation = 1.35
    add_child(_light)
    _sync()

func _sync() -> void:
    if _light == null:
        return
    var active := lit and intensity > 0.0
    _effects.scale = Vector3.ONE * fire_size
    _flames[0].visible = active
    _flames[1].visible = active and quality == Quality.FULL
    for flame in _flames:
        (flame.material_override as ShaderMaterial).set_shader_parameter("strength", minf(intensity, 1.65))
    _smoke.emitting = active and quality == Quality.FULL
    _sparks.emitting = active and quality == Quality.FULL
    _smoke.visible = _smoke.emitting
    _sparks.visible = _sparks.emitting
    _light.visible = active
    _light.position.y = .46 * fire_size
    _light.omni_range = 4.15 * fire_size
    set_process(active)

func _process(delta: float) -> void:
    _time += delta
    var flicker := .83 + .13 * sin(_time * 9.1) + .10 * sin(_time * 16.3) + .045 * cos(_time * 31.4)
    _light.light_energy = intensity * flicker

func _add_flame(at: Vector3, dimensions: Vector2, phase: float, rate: float) -> void:
    var quad := QuadMesh.new()
    quad.size = dimensions
    var material := ShaderMaterial.new()
    material.shader = FLAME
    material.set_shader_parameter("atlas", ATLAS)
    material.set_shader_parameter("phase", phase)
    material.set_shader_parameter("rate", rate)
    var flame := MeshInstance3D.new()
    flame.mesh = quad
    flame.position = at
    flame.material_override = material
    flame.extra_cull_margin = dimensions.x
    flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _effects.add_child(flame)
    _flames.append(flame)

func _particles(sparks: bool) -> CPUParticles3D:
    var dust := CPUParticles3D.new()
    dust.amount = 7 if sparks else 6
    dust.lifetime = 1.2 if sparks else 2.5
    dust.randomness = .72
    dust.local_coords = true
    dust.position.y = .18 if sparks else .58
    dust.direction = Vector3(.16, 1, .12)
    dust.spread = 29.0 if sparks else 14.0
    dust.gravity = Vector3(.07, -.48 if sparks else .12, .15)
    dust.initial_velocity_min = .44 if sparks else .20
    dust.initial_velocity_max = 1.45 if sparks else .38
    dust.scale_amount_min = .62
    dust.scale_amount_max = 1.55
    var opacity := Gradient.new()
    opacity.offsets = PackedFloat32Array([0.0, .18, .67, 1.0])
    opacity.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE,
        Color(1, 1, 1, .38), Color(1, 1, 1, 0)])
    dust.color_ramp = opacity
    var feather := Gradient.new()
    var tint := Color(1, .46, .08, .94) if sparks else Color(.32, .32, .31, .22)
    feather.colors = PackedColorArray([tint, Color(tint, 0)])
    var texture := GradientTexture2D.new()
    texture.width = 32
    texture.height = 32
    texture.fill = GradientTexture2D.FILL_RADIAL
    texture.fill_from = Vector2(.5, .5)
    texture.fill_to = Vector2(1, .5)
    texture.gradient = feather
    var material := StandardMaterial3D.new()
    material.albedo_texture = texture
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    material.billboard_keep_scale = true
    material.vertex_color_use_as_albedo = true
    var quad := QuadMesh.new()
    quad.size = Vector2(.052, .076) if sparks else Vector2(.71, .72)
    quad.material = material
    dust.mesh = quad
    dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _effects.add_child(dust)
    return dust
