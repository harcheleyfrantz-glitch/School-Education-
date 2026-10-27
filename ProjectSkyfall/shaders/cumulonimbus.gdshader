shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back, shadows_disabled;

// Towering storm cells built from merged spheres. Soft fresnel edges, sun-lit tops.
uniform vec3 sun_dir = vec3(0.3, 0.8, 0.2);
uniform vec3 sun_col : source_color = vec3(1.0);
uniform vec3 amb_col : source_color = vec3(0.5, 0.55, 0.62);
uniform float flash = 0.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 wn;
varying float hgt;
varying vec3 opos;

void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	opos = VERTEX;
	hgt = clamp(VERTEX.y / 11000.0, 0.0, 1.0);
	float n = texture(noise_tex, VERTEX.xz / 2600.0 + VERTEX.y / 3100.0).r;
	VERTEX += NORMAL * (n - 0.5) * 700.0;
}

void fragment() {
	float ndl = clamp(dot(wn, normalize(sun_dir)) * 0.6 + 0.4, 0.0, 1.0);
	float n = texture(noise_tex, opos.xz / 900.0 + opos.y / 1300.0).r;
	vec3 base = amb_col * mix(0.35, 0.95, hgt) * (0.8 + 0.4 * n);
	vec3 c = base + sun_col * ndl * (0.35 + 0.65 * hgt);
	c += vec3(0.75, 0.8, 1.0) * flash * (0.6 + n);
	float rim = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = c;
	ALPHA = smoothstep(0.0, 0.35, rim) * 0.97;
}
