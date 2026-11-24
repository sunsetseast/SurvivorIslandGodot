shader_type spatial;
render_mode cull_disabled;
uniform sampler2D limestone : source_color, repeat_enable, filter_linear_mipmap;
varying vec3 world;
varying vec3 normal_world;

void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    normal_world = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
    vec3 n = pow(abs(normalize(normal_world)), vec3(3.0));
    n /= max(.001,n.x + n.y + n.z);
    vec3 s = texture(limestone, world.yz * .26).rgb * n.x +
        texture(limestone,world.xz * .26).rgb * n.y + texture(limestone,world.xy * .26).rgb * n.z;
    float runoff = sin(world.x * .69 + world.z * .41 + sin(world.y * .19) * 1.4);
    float stain = smoothstep(.32,.93,sin(world.x * .31 - world.z * .20 + world.y * .092));
    vec3 mineral = mix(s * 1.42 + .13, s * vec3(1.41,1.13,.91) + .11, stain * .65);
    ALBEDO = mineral * (1.0 - smoothstep(.65,.98,runoff) * .21) * COLOR.rgb;
    ROUGHNESS = .91;
}
