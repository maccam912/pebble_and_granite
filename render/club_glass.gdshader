shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://render/surface_noise.gdshaderinc"
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = world_position.zy;
	float across = mod(mod(p.x - 0.7, 6.0), 1.8);
	float edge = min(min(across, 1.8 - across), min(p.y - 1.95, 2.95 - p.y));
	float frost = 1.0 - smoothstep(0.0, 0.12, max(edge, 0.0));
	float haze = (surface_noise(p * 5.0) - 0.5) * 0.025;
	vec3 pane = mix(vec3(0.22, 0.33, 0.38), vec3(0.55, 0.67, 0.72), smoothstep(1.9, 3.05, p.y));
	pane = mix(pane, vec3(0.64, 0.69, 0.70), frost * 0.45) + haze;
	ALBEDO = pane;
	ROUGHNESS = mix(0.24, 0.58, frost);
	SPECULAR = 0.45;
	// Restrained transmitted daylight through opaque, diffusing clerestory
	// glass. No fabricated exterior photograph or transparent sorting pass.
	EMISSION = pane * 0.35;
}
