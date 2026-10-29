shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Motion-blurred propeller disc shown at high RPM: faint blade bands that drift with the
// rotation, a darker hub region and a coloured ring where the painted tips blur.
uniform float rpm_k = 1.0;
uniform float blades = 4.0;
uniform vec3 tip_col : source_color = vec3(0.95, 0.75, 0.08);

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float a = atan(p.y, p.x);
	float bands = 0.5 + 0.5 * cos(a * blades - TIME * 9.0 + r * 2.5);
	float disc = smoothstep(1.0, 0.975, r) * smoothstep(0.08, 0.18, r);
	float alpha = disc * (0.07 + 0.09 * bands * (1.0 - r * 0.5)) * rpm_k;
	vec3 c = vec3(0.05);
	float tip = smoothstep(0.88, 0.91, r) * smoothstep(1.0, 0.975, r);
	c = mix(c, tip_col, tip);
	alpha += tip * 0.16 * rpm_k;
	ALBEDO = c;
	ALPHA = alpha;
	ROUGHNESS = 0.6;
}
