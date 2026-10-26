shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://render/surface_noise.gdshaderinc"

uniform float lane_center = 0.0;
uniform sampler2D ice_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D pebble_texture : filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz - vec2(lane_center, 0.0);
	float radius = length(vec2(p.x, min(abs(p.y), abs(p.y - 34.75))));
	float aa = max(fwidth(radius), 0.001);
	vec3 paint = vec3(0.72, 0.75, 0.76);
	paint = mix(paint, vec3(0.055, 0.19, 0.30), 1.0 - smoothstep(1.829-aa, 1.829+aa, radius));
	paint = mix(paint, vec3(0.72, 0.75, 0.76), 1.0 - smoothstep(1.219-aa, 1.219+aa, radius));
	paint = mix(paint, vec3(0.59, 0.075, 0.105), 1.0 - smoothstep(0.610-aa, 0.610+aa, radius));
	paint = mix(paint, vec3(0.72, 0.75, 0.76), 1.0 - smoothstep(0.152-aa, 0.152+aa, radius));
	float line_aa = max(fwidth(p.y), 0.001);
	float hog = min(abs(p.y - 6.35), abs(p.y - 28.40));
	paint = mix(paint, vec3(0.55, 0.08, 0.10), 1.0 - smoothstep(0.051-line_aa, 0.051+line_aa, hog));
	float cross_line = min(min(abs(p.y), abs(p.y - 34.75)), min(abs(p.y + 1.8225), abs(p.y - 36.5725)));
	float tee = 1.0 - smoothstep(0.0065-line_aa, 0.0065+line_aa, cross_line);
	float center = 1.0 - smoothstep(0.0065-max(fwidth(p.x), 0.001), 0.0065+max(fwidth(p.x), 0.001), abs(p.x));
	paint = mix(paint, vec3(0.20, 0.27, 0.30), max(tee, center) * 0.65);
	// A linear packed material lets anisotropic mip filtering preserve the
	// shallow nipped droplets without a distance band or subpixel cell search.
	vec4 pebble = texture(pebble_texture, p * 2.0);
	float ice_grain = texture(ice_texture, p * 2.0).r;
	float cloud = surface_noise(p * 2.0) * 0.018 + surface_noise(p * 9.0) * 0.012;
	float frost = pebble.b;
	vec3 frozen_paint = mix(paint, vec3(0.64, 0.68, 0.70), 0.035) + cloud - 0.015;
	frozen_paint = mix(frozen_paint, vec3(0.82, 0.85, 0.86), frost * 0.03);
	ALBEDO = frozen_paint * mix(0.93, 1.07, ice_grain) * mix(0.98, 1.035, frost);
	ROUGHNESS = 0.27 + ice_grain * 0.10 + frost * 0.14 - pebble.a * 0.12;
	SPECULAR = 0.38;
	// BoxMesh top tangent points toward -X; the packed field uses world +X/+Z.
	NORMAL_MAP = vec3(1.0 - pebble.r, pebble.g, 1.0);
	NORMAL_MAP_DEPTH = 1.0;
}
