shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
uniform sampler2D coast : filter_linear, repeat_disable;
uniform vec2 interval = vec2(-88., 236.);
varying vec3 world;

void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float coast_x = texture(coast, vec2((world.z - interval.x) / interval.y, .5)).r;
    float distance_to_shore = coast_x - world.x;
    if (distance_to_shore < -0.2) { discard; }
    float ripple = sin(world.z * 1.31 + world.x * 2.6 - TIME * 1.45) * sin(world.z * 2.08 - world.x * 1.4 + TIME * 1.35);
    float broad = sin(world.z * .37 + world.x * .44 - TIME * 1.08);
    float foam = smoothstep(.66,.98,sin(distance_to_shore * 5.5 + TIME * 1.8 + sin(world.z * .5))) *
        (1. - smoothstep(.05,1.25,distance_to_shore)) * (.57 + broad * .16);
    vec3 turquoise = mix(vec3(.26,.58,.48), vec3(.026,.23,.31), smoothstep(0.,30.,distance_to_shore));
    ALBEDO = mix(turquoise + ripple * .019 + broad * .012, vec3(.84,.91,.83), foam);
    NORMAL = normalize(NORMAL + vec3(ripple * .07, broad * .05, 0.0));
    ROUGHNESS = .31 + ripple * .07;
    SPECULAR = .27;
}
