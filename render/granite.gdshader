shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://render/surface_noise.gdshaderinc"

uniform sampler2D granite_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 stone_position;
varying vec3 stone_normal;

void vertex() {
	stone_position = VERTEX;
	stone_normal = NORMAL;
}

void fragment() {
	vec3 p = stone_position * 310.0;
	vec3 weights = pow(abs(stone_normal), vec3(4.0));
	weights /= max(dot(weights, vec3(1.0)), 0.001);
	float crystals = dot(vec3(surface_noise(p.yz), surface_noise(p.xz), surface_noise(p.xy)), weights);
	float fine = dot(vec3(surface_noise(p.yz * 3.3), surface_noise(p.xz * 3.3), surface_noise(p.xy * 3.3)), weights);
	vec3 uvw = stone_position / 0.35;
	vec3 salt = texture(granite_texture, uvw.yz).rgb * weights.x
		+ texture(granite_texture, uvw.xz).rgb * weights.y
		+ texture(granite_texture, uvw.xy).rgb * weights.z;
	// The broad equatorial striking band is rougher than the polished crown.
	float band = smoothstep(0.039, 0.044, stone_position.y) * (1.0 - smoothstep(0.074, 0.079, stone_position.y));
	ALBEDO = mix(salt * vec3(0.83, 0.86, 0.80), mix(salt, vec3(0.70, 0.72, 0.69), 0.60), band);
	ROUGHNESS = mix(0.23 + crystals * 0.10 + fine * 0.03, 0.61, band);
	SPECULAR = 0.58;
	AO = mix(0.75, 1.0, smoothstep(0.005, 0.045, stone_position.y));
}
