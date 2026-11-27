shader_type spatial;
uniform vec4 tint : source_color = vec4(0.6,0.45,0.3,1.0);
uniform float weave = 0.0;
varying vec3 point;
void vertex() { point = VERTEX; }
void fragment() {
    float grain = sin(point.x*217.0 + sin(point.z*31.0)*2.0)*sin(point.z*163.0+point.y*53.0);
    float fibre = sin(point.x*175.0)*sin(point.y*175.0+point.z*175.0);
    float wear = sin(point.x*23.0+point.y*14.0)*sin(point.z*37.0-point.y*19.0);
    ALBEDO = tint.rgb*(0.92+grain*0.055+fibre*weave*.09+wear*.06);
    ROUGHNESS = 0.78 + weave*.16;
}
