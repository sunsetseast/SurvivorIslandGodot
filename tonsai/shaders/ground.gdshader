shader_type spatial;
render_mode cull_back;
uniform sampler2D sand : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D litter : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
varying vec3 world;

void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
    vec2 p = world.xz;
    vec3 beach = texture(sand, p * 0.44).rgb;
    vec3 forest = texture(litter, p * 0.51).rgb;
    float pattern = sin(p.x * .79 + sin(p.y * .19) * 3.) * sin(p.y * .56);
    beach *= (0.93 + .15 * COLOR.b) * (0.97 + .06 * pattern);
    forest *= vec3(1.08, 1.06, .9) * (0.90 + .12 * pattern);
    float trail = COLOR.g;
    vec3 earth = mix(forest, beach * vec3(.76,.68,.53), trail * 0.77);
    ALBEDO = mix(beach, earth, COLOR.r) * mix(.90, 1.03, COLOR.b) * COLOR.a;
    ROUGHNESS = .93;
}
