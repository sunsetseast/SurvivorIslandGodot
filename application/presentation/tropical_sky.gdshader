shader_type sky;
uniform sampler2D cloud_panorama : source_color, filter_linear;

void sky() {
    // Retain the existing photographic cloud shapes; restore blue in clear sky.
    vec3 photograph = texture(cloud_panorama, SKY_COORDS).rgb;
    float cloud = smoothstep(.46, .82, dot(photograph, vec3(.2126, .7152, .0722)));
    float elevation = pow(max(EYEDIR.y, 0.0), .45);
    vec3 tropical_blue = mix(vec3(.27, .66, .88), vec3(.045, .27, .62), elevation);
    COLOR = mix(tropical_blue, vec3(.97, .98, 1.0), cloud * .92);
}
