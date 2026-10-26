shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://render/surface_noise.gdshaderinc"
uniform vec4 fabric_color : source_color = vec4(0.12, 0.20, 0.25, 1.0);
varying vec3 fabric_position;
void vertex() {
	fabric_position = VERTEX;
}
void fragment() {
	float detail = 1.0 - smoothstep(0.25, 0.9, length(fwidth(fabric_position * 650.0)));
	float weave = sin(fabric_position.x * 4100.0) * sin(fabric_position.z * 4100.0);
	float fleck = surface_noise(fabric_position.xz * 650.0) - 0.5;
	ALBEDO = fabric_color.rgb * (1.0 + (weave * 0.035 + fleck * 0.08) * detail);
	ROUGHNESS = 0.91;
	SPECULAR = 0.18;
}
