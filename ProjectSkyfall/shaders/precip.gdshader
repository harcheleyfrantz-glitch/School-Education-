shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Camera-attached rain / snow curtain made of scrolling streak layers.
uniform float intensity = 0.0;
uniform float snow = 0.0;
uniform vec3 light_col : source_color = vec3(0.8);
uniform vec3 drift = vec3(0.0);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = UV * vec2(90.0, 9.0);
	float speed = mix(1.9, 0.22, snow);
	float a = 0.0;
	for (int layer = 0; layer < 3; layer++) {
		float fl = float(layer);
		vec2 q = uv * (1.0 + fl * 0.45) + vec2(fl * 0.37 + drift.x * 0.01 * TIME, TIME * speed * (1.0 + fl * 0.35));
		vec2 cell = floor(q);
		vec2 f = fract(q);
		float h = hash12(cell + fl * 17.0);
		float x = abs(f.x - (0.15 + 0.7 * hash12(cell + 2.3)));
		float streak;
		if (snow > 0.5) {
			float y0 = hash12(cell + 7.1);
			streak = smoothstep(0.07, 0.0, length(vec2(x, (f.y - y0) * 0.35)));
		} else {
			float len = 0.05 + 0.08 * hash12(cell + 3.3);
			float y0 = hash12(cell + 7.1) * (1.0 - len);
			float along = clamp((f.y - y0) / len, 0.0, 1.0);
			streak = smoothstep(0.03, 0.0, x) * step(y0, f.y) * step(f.y, y0 + len) * (0.3 + 0.7 * along);
		}
		a += streak * step(1.0 - intensity * 0.85, h);
	}
	ALBEDO = light_col;
	ALPHA = clamp(a, 0.0, 1.0) * mix(0.22, 0.75, snow) * clamp(intensity * 1.4, 0.0, 1.0);
}
