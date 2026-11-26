shader_type spatial;
varying vec3 world;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    float seams = smoothstep(0.018, 0.034, min(fract(world.x * 3.2), 1.0 - fract(world.x * 3.2)));
    float grain = sin(world.z * 27.0 + sin(world.x * 41.0) * 3.0) * 0.025;
    float board = fract(sin(floor(world.x * 3.2) * 73.13) * 415.71) * 0.06;
    ALBEDO = mix(vec3(0.12, 0.075, 0.04), vec3(0.29 + board + grain, 0.17 + board, 0.085 + board), seams);
    ROUGHNESS = 0.9;
}
