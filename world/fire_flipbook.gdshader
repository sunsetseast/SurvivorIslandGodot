// Unity Labs Flame02 (CC0). Keep blending and billboarding Web-compatible.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
uniform float phase = 0.0;
uniform float rate = 25.0;
uniform float strength = 1.0;

void vertex() {
    vec3 center = MODEL_MATRIX[3].xyz;
    vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
    vec3 at = center + right * VERTEX.x * length(MODEL_MATRIX[0].xyz)
        + vec3(0.0, VERTEX.y * length(MODEL_MATRIX[1].xyz), 0.0);
    VERTEX = (inverse(MODEL_MATRIX) * vec4(at, 1.0)).xyz;
}

vec4 sample_frame(float frame, vec2 uv) {
    vec2 cell = vec2(mod(frame, 8.0), floor(frame / 8.0));
    vec2 inset = vec2(0.5 / 64.0, 0.5 / 128.0);
    return texture(atlas, (cell + mix(inset, 1.0 - inset, uv)) / 8.0);
}

void fragment() {
    float clock = mod(TIME * rate + phase, 64.0);
    vec4 fire = mix(sample_frame(floor(clock), UV),
        sample_frame(mod(floor(clock) + 1.0, 64.0), UV), fract(clock));
    ALBEDO = min(vec3(1.0), fire.rgb * vec3(1.35, 1.19, .91));
    ALPHA = clamp(fire.a * 1.45 * strength * (1.0 - smoothstep(.92, 1.0, UV.y)), 0.0, 1.0);
}
