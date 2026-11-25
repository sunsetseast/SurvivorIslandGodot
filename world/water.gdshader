// Adapted from GodotLearning Stylized Water (CC0 1.0).
// https://godotlearning.com/shaders/stylized-water
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D ripples : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 shallows : source_color = vec4(.25, .52, .41, .30);
uniform vec4 offshore : source_color = vec4(.055, .24, .30, .96);
uniform float motion_strength = 1.0;
uniform float shimmer_strength = 0.0;
uniform vec3 reflection_tint : source_color = vec3(.34, .49, .54);
uniform vec3 foam_color : source_color = vec3(.68, .77, .70);
varying vec3 world_position;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float raw = textureLod(scene_depth, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    vec3 ndc = vec3(SCREEN_UV, raw) * 2.0 - 1.0;
#else
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw);
#endif
    vec4 bed = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    // Convert only the height component to world space.
    float bed_y = (INV_VIEW_MATRIX * vec4(bed.xyz / bed.w, 1.0)).y;
    float depth = raw > .000001 ? max(world_position.y - bed_y, 0.0) : 18.0;

    vec2 p = world_position.xz;
    float clock = TIME * motion_strength;
    vec2 a = texture(ripples, p * .12 + vec2(-.028, .017) * clock).rg * 2.0 - 1.0;
    vec2 b = texture(ripples, vec2(p.y, -p.x) * .23 + vec2(.021, .031) * clock).rg * 2.0 - 1.0;
    float swell = sin(p.x * .59 + sin(p.y * .46) * 1.7 + clock * .94);
    float patches = smoothstep(.14, .66, a.x + b.y * .65 + swell * .35);
    float foam = patches * (1.0 - smoothstep(.04, .33, depth)) * .34;
    vec4 water = mix(shallows, offshore, smoothstep(.02, 5.5, depth));
    float fresnel = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 4.0);
    vec3 water_color = water.rgb * (1.0 + (a.x + b.y + swell * .5) * .10);
    water_color = mix(water_color, reflection_tint, fresnel * .40);
    ALBEDO = mix(water_color, foam_color, foam);
    // Small moving sun glints, independent of screen-space reflection support.
    float glint = pow(max(0.0, (a.x + b.y) * .52), 8.0);
    EMISSION = vec3(.85, .97, 1.0) * glint * shimmer_strength;
    ALPHA = min(1.0, water.a + foam + fresnel * .15);
    NORMAL_MAP = vec3((a + b * .62) * .42 + .5, 1.0);
    NORMAL_MAP_DEPTH = .26;
    if (!FRONT_FACING) {
        ALBEDO = mix(vec3(.13, .46, .48), vec3(.59, .81, .73), patches * .32 + fresnel * .35);
        ALPHA = .55 + fresnel * .29;
    }
    ROUGHNESS = mix(.30, .79, foam);
    SPECULAR = .21;
}
