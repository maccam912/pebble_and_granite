shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://render/surface_noise.gdshaderinc"

uniform float lane_center = 0.0;
uniform sampler2D ice_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
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
	// A thin frozen layer softens the painted rings. Pebble is kept subtle,
	// and fades with pixel footprint while retaining texture in close views.
	float cloud = surface_noise(p * 2.0) * 0.018 + surface_noise(p * 9.0) * 0.012;
	float detail = 1.0 - smoothstep(0.35, 1.0, length(fwidth(p * 160.0)));
	vec2 pebble_normal = vec2(0.0);
	if (detail > 0.0) {
		vec2 pebble_cell = floor(p * 160.0);
		vec2 local = fract(p * 160.0);
		float highest_cap = 0.0;
		// Full-cell scatter breaks visible rows. Neighbours keep droplets
		// continuous across cell edges; distant fragments skip this search.
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 neighbour = vec2(float(x), float(y));
				vec2 seed = pebble_cell + neighbour;
				vec2 center = neighbour + vec2(hash21(seed), hash21(seed + 17.7));
				float radius = 0.20 + hash21(seed + 8.1) * 0.12;
				vec2 offset = (local - center) / radius;
				float cap = 1.0 - dot(offset, offset);
				if (cap > highest_cap) {
					highest_cap = cap;
					pebble_normal = offset * smoothstep(0.0, 0.25, cap);
				}
			}
		}
	}
	float ice_grain = texture(ice_texture, p * 2.0).r;
	ALBEDO = (mix(paint, vec3(0.64, 0.68, 0.70), 0.035) + cloud - 0.015) * mix(0.96, 1.025, ice_grain);
	ROUGHNESS = 0.30 + ice_grain * 0.12;
	SPECULAR = 0.38;
	NORMAL_MAP = vec3(vec2(0.5) + pebble_normal * 0.09 * detail, 1.0);
	NORMAL_MAP_DEPTH = 0.65;
}
