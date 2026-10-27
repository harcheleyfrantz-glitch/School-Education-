shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Motion-blurred propeller disc shown at high RPM.
uniform float rpm_k = 1.0;
uniform float blades = 4.0;

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float a = atan(p.y, p.x);
	float bands = 0.5 + 0.5 * cos(a * blades + TIME * 3.0);
	float alpha = smoothstep(1.0, 0.94, r) * smoothstep(0.08, 0.16, r) * (0.1 + 0.12 * bands) * rpm_k;
	ALBEDO = vec3(0.12);
	ALPHA = alpha;
	ROUGHNESS = 0.6;
}
