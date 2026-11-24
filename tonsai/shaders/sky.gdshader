shader_type sky;
uniform sampler2D clouds : source_color, filter_linear, repeat_enable;
void sky() {
    float elevation = max(0., EYEDIR.y);
    vec3 tint = mix(vec3(.79,.88,.85), vec3(.25,.59,.80), smoothstep(0., .68, elevation));
    vec2 uv = EYEDIR.xz / max(.17, elevation + .22) * .21 + vec2(.53,.29);
    float cloud = smoothstep(.35,.85,texture(clouds,uv).a) * smoothstep(.015,.23,elevation);
    COLOR = mix(tint,vec3(.94,.94,.88),cloud * .51);
}
