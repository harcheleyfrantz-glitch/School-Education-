shader_type spatial;
render_mode cull_back;

// Terminal interior surfaces, patterned in model space (metres):
// 0 terrazzo floor, 1 gate carpet, 2 slatted ceiling, 3 wall panels,
// 4 vertex colour (sRGB; alpha picks the finish: 1 matte, 0.75 satin, 0.55 gloss, 0.3 chrome),
// 5 emissive vertex colour (light strips, signs, screens).
uniform int kind = 0;
uniform vec3 base_color : source_color = vec3(0.78, 0.77, 0.74);
uniform vec3 accent : source_color = vec3(0.2, 0.27, 0.36);
uniform float emit_energy = 2.2;
uniform float night = 0.0;

varying vec3 mpos;
varying vec4 vcol;

void vertex() {
	mpos = VERTEX;
	vcol = COLOR;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// anti-aliased line mask: 1 on a line of width w (in cells) repeating every cell
float grid_line(float x, float w) {
	float fw = max(fwidth(x), 1e-4);
	float d = abs(fract(x + 0.5) - 0.5);
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + fw, d);
}

vec3 srgb_to_linear(vec3 c) {
	return pow(c, vec3(2.2));
}

void fragment() {
	vec3 col = base_color;
	float rough = 0.7;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	if (kind == 0) {
		// polished terrazzo in 1.2 m tiles: per-tile tone, aggregate speckle, fine joints
		vec2 t = mpos.xz / 1.2;
		vec2 cell = floor(t);
		float tone = hash12(cell * 1.7 + 4.0);
		col = base_color * (0.95 + 0.08 * tone);
		float sp = hash12(floor(mpos.xz * 90.0));
		float speck = step(0.93, sp) * 0.25 - step(sp, 0.05) * 0.18;
		float big = smoothstep(0.55, 0.7, noise(mpos.xz * 9.0)) * 0.06;
		col *= 1.0 + speck * (1.0 - smoothstep(0.0, 0.01, fwidth(mpos.x * 90.0) - 0.5)) - big;
		float joint = max(grid_line(t.x, 0.012), grid_line(t.y, 0.012));
		col = mix(col, col * 0.72, joint);
		rough = mix(0.16, 0.42, noise(mpos.xz * 0.35)) + joint * 0.4;
	} else if (kind == 1) {
		// tufted carpet: a quiet two-tone pattern of offset bars
		vec2 q = mpos.xz * vec2(1.6, 0.8);
		float bar = step(0.5, fract(q.x + floor(q.y) * 0.5));
		col = mix(base_color, accent, bar * 0.35);
		col *= 0.92 + 0.12 * noise(mpos.xz * 14.0);
		rough = 0.97;
	} else if (kind == 2) {
		// linear metal slat ceiling with shadow gaps
		float slat = grid_line(mpos.x / 0.2, 0.22);
		col = mix(base_color, base_color * 0.35, slat);
		rough = 0.45;
		metal = 0.25;
	} else if (kind == 3) {
		// large-format wall panels with recessed joints
		float j = max(grid_line(mpos.z / 2.4, 0.008), grid_line(mpos.y / 3.0, 0.006));
		col = mix(base_color, base_color * 0.6, j);
		rough = 0.6;
	} else if (kind == 4) {
		col = srgb_to_linear(vcol.rgb);
		float a = vcol.a;
		if (a < 0.4) {
			metal = 1.0;
			rough = 0.22;
		} else {
			rough = a > 0.9 ? 0.82 : (a > 0.65 ? 0.45 : 0.18);
		}
	} else {
		col = srgb_to_linear(vcol.rgb) * 0.2;
		emit = srgb_to_linear(vcol.rgb) * emit_energy * mix(1.0, 1.25, night);
		rough = 0.4;
	}
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = metal;
	EMISSION = emit;
}
