shader_type spatial;
#include "res://render/surface_noise.gdshaderinc"
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float grain = surface_noise(world_position.xz * vec2(75.0, 0.6));
	float pores = surface_noise(world_position.xz * vec2(320.0, 3.0));
	ALBEDO = mix(vec3(0.22, 0.12, 0.059), vec3(0.43, 0.29, 0.15), grain) + (pores - 0.5) * 0.035;
	ROUGHNESS = 0.43 + grain * 0.15;
}
