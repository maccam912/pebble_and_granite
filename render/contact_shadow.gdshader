shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;
void fragment() {
	float radius = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.025, 0.035, 0.04);
	ALPHA = (1.0 - smoothstep(0.35, 1.0, radius)) * 0.28;
}
