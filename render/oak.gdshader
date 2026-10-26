shader_type spatial;
#include "res://render/surface_noise.gdshaderinc"
uniform sampler2D oak_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool grain_along_x = false;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 p = grain_along_x ? world_position.zyx : world_position;
	vec3 weights = pow(abs(grain_along_x ? world_normal.zyx : world_normal), vec3(8.0));
	weights /= max(dot(weights, vec3(1.0)), 0.001);
	// World-scale projection keeps the grain running along each board. Side
	// faces retain natural pores rather than vertically stretched stripes.
	vec3 oak = texture(oak_texture, p.yz * vec2(1.667, 0.417)).rgb * weights.x
		+ texture(oak_texture, p.xz * vec2(1.667, 0.417)).rgb * weights.y
		+ texture(oak_texture, p.xy * 1.667).rgb * weights.z;
	float grain = dot(oak, vec3(0.2126, 0.7152, 0.0722));
	ALBEDO = oak * 0.82;
	ROUGHNESS = 0.43 + grain * 0.14;
}
