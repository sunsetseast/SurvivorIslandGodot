shader_type spatial;
render_mode cull_disabled;
uniform sampler2D sand_detail : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D leaf_detail : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 world;
void vertex() { world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
    vec3 sand=texture(sand_detail,UV*.5).rgb;
    vec3 litter=texture(leaf_detail,UV*.65).rgb;
    float patch=sin(world.x*.29+sin(world.z*.38))*1.5;
    float forest=smoothstep(176.0,190.0,world.z+patch);
    float wet=1.0-smoothstep(-.4,1.0,world.y);
    ALBEDO=mix(sand*vec3(.87,.83,.72)*(1.0-wet*.24),litter*.75,forest*.87);
    ROUGHNESS=.96;
}
