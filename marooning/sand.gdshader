shader_type spatial;
uniform sampler2D sand_detail : source_color, filter_linear_mipmap, repeat_enable;
void fragment() {
    float grain = texture(sand_detail, UV * 0.5).r;
    ALBEDO = vec3(0.64, 0.55, 0.37) * (0.94 + grain * 0.2);
    ROUGHNESS = 0.96;
}
