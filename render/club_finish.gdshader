shader_type spatial;
#include "res://render/surface_noise.gdshaderinc"
uniform vec4 paint_color : source_color = vec4(0.65, 0.68, 0.68, 1.0);
uniform bool ceiling = false;
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = ceiling ? world_position.xz : vec2(world_position.x + world_position.z, world_position.y);
	float grain = surface_noise(p * 54.0) - 0.5;
	float cloud = surface_noise(p * 1.8) - 0.5;
	float joint = min(fract(p.x / 1.2), 1.0 - fract(p.x / 1.2));
	float seam = 1.0 - smoothstep(0.002, 0.006 + fwidth(p.x), joint);
	ALBEDO = paint_color.rgb * (1.0 - seam * 0.12) + grain * 0.012 + cloud * 0.015;
	if (!ceiling) {
		// 15 cm pitch, 4 mm amplitude; fade before ribs become subpixel.
		float rib_phase = p.x / 0.15;
		float rib_visibility = 1.0 - smoothstep(0.22, 0.65, fwidth(rib_phase));
		float rib = cos(rib_phase * 6.2831853);
		float rib_slope = -sin(rib_phase * 6.2831853) * 0.16755 * rib_visibility;
		vec3 gradient = (VIEW_MATRIX * vec4(1.0, 0.0, 1.0, 0.0)).xyz;
		gradient -= NORMAL * dot(gradient, NORMAL);
		NORMAL = normalize(NORMAL - gradient * rib_slope);
		ALBEDO *= 1.0 - (1.0 - rib) * 0.018 * rib_visibility;
	}
	ROUGHNESS = ceiling ? 0.84 : 0.74;
	// Restrained baked material occlusion where the cladding meets structure.
	float structure = ceiling ? min(abs(mod(world_position.z + 2.0, 6.0)), abs(mod(world_position.z + 2.0, 6.0) - 6.0))
		: min(abs(mod(world_position.x + world_position.z, 6.0)), abs(mod(world_position.x + world_position.z, 6.0) - 6.0));
	float beam_ao = mix(0.77, 1.0, smoothstep(0.0, 0.45, structure));
	float edge_ao = ceiling ? 1.0 : smoothstep(0.0, 1.2, world_position.y) * (1.0 - smoothstep(3.4, 3.95, world_position.y));
	AO = beam_ao * mix(0.62, 1.0, edge_ao);
	AO_LIGHT_AFFECT = 0.4;
}
