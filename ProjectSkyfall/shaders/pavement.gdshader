shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Runways, taxiways, aprons and roads. UV.x = metres across from the centreline,
// UV.y = metres along from the start; markings are generated procedurally.
uniform int mode = 0;            // 0 runway, 1 taxiway, 2 apron, 3 road, 4 grass strip
uniform float rw_len = 3000.0;
uniform float rw_wid = 45.0;
uniform float wetness = 0.0;
uniform float night = 0.0;
uniform float flood = 0.0;       // apron flood lighting at night
uniform vec3 world_origin = vec3(0.0);
uniform float priority = 0.0;     // pulls the surface toward the camera to win depth ties
uniform ivec3 des0 = ivec3(0, 9, 0);  // designator at the y = 0 end: tens, units, letter (1 L, 2 C, 3 R)
uniform ivec3 des1 = ivec3(2, 7, 0);  // designator at the far end (reads the other way)
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + vec3(world_origin.x, 0.0, world_origin.z);
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vp.xyz *= 1.0 - priority * 0.00025;
	POSITION = PROJECTION_MATRIX * vp;
}

// 7-segment style runway numerals. p in glyph space: x 0..1 (6 m), y 0..1 (18 m, y up)
float seg(vec2 p, vec2 a, vec2 b) {
	vec2 mn = min(a, b) - vec2(0.13, 0.045);
	vec2 mx = max(a, b) + vec2(0.13, 0.045);
	return step(mn.x, p.x) * step(p.x, mx.x) * step(mn.y, p.y) * step(p.y, mx.y);
}

float glyph(vec2 p, int code) {
	if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0) return 0.0;
	// segment endpoints
	vec2 tl = vec2(0.13, 0.955);
	vec2 tr = vec2(0.87, 0.955);
	vec2 ml = vec2(0.13, 0.5);
	vec2 mr = vec2(0.87, 0.5);
	vec2 bl = vec2(0.13, 0.045);
	vec2 br = vec2(0.87, 0.045);
	float sA = seg(p, tl, tr);
	float sB = seg(p, tr, mr);
	float sC = seg(p, mr, br);
	float sD = seg(p, bl, br);
	float sE = seg(p, ml, bl);
	float sF = seg(p, tl, ml);
	float sG = seg(p, ml, mr);
	float m = 0.0;
	if (code == 0) m = sA + sB + sC + sD + sE + sF;
	else if (code == 1) m = sB + sC;
	else if (code == 2) m = sA + sB + sG + sE + sD;
	else if (code == 3) m = sA + sB + sG + sC + sD;
	else if (code == 4) m = sF + sG + sB + sC;
	else if (code == 5) m = sA + sF + sG + sC + sD;
	else if (code == 6) m = sA + sF + sG + sE + sC + sD;
	else if (code == 7) m = sA + sB + sC;
	else if (code == 8) m = sA + sB + sC + sD + sE + sF + sG;
	else if (code == 9) m = sA + sB + sC + sD + sF + sG;
	else if (code == 11) m = sF + sE + sD;                       // L
	else if (code == 12) m = sA + sF + sE + sD;                   // C
	else if (code == 13) {                                    // R
		m = sA + sF + sE + sG + seg(p, tr, mr);
		vec2 q = p - vec2(0.5, 0.0);
		m += step(abs(q.x - (0.5 - p.y) * 0.75), 0.13) * step(p.y, 0.5);
	}
	return clamp(m, 0.0, 1.0);
}

float designator(vec2 p, ivec3 d) {
	// p: x metres from centreline, y metres from the start of the number block (reading upward)
	float h = 18.0;
	float w = 6.0;
	float gap = 2.5;
	float m = 0.0;
	if (d.z > 0) {
		// letter goes below the digits (closer to the threshold)
		m += glyph(vec2((p.x + w * 0.5) / w, (p.y) / h), 10 + d.z);
		p.y -= h + 4.0;
	}
	m += glyph(vec2((p.x + w + gap * 0.5) / w, p.y / h), d.x);
	m += glyph(vec2((p.x - gap * 0.5) / w, p.y / h), d.y);
	return m;
}

float box(float v, float a, float b) {
	return step(a, v) * step(v, b);
}

float runway_marks(vec2 p) {
	float x = p.x;
	float y = p.y;
	float hw = rw_wid * 0.5;
	float ax = abs(x);
	float m = 0.0;
	float yr = min(y, rw_len - y);        // distance from the nearest end
	bool far_half = y > rw_len * 0.5;
	// side stripes
	m += box(ax, hw - 2.0, hw - 1.1) * step(30.0, yr);
	// centreline dashes (30 m stripe, 20 m gap)
	float dash = step(fract((y - 4.0) / 50.0), 0.6);
	m += box(ax, 0.0, 0.46) * dash * step(110.0, yr);
	// threshold piano keys
	float key_zone = box(yr, 6.0, 36.0);
	float kx = mod(ax - 3.0, 3.6);
	m += key_zone * step(kx, 1.8) * box(ax, 3.0, hw - 3.0);
	// threshold bar
	m += box(yr, 0.0, 1.8) * step(ax, hw - 1.0);
	// runway designators, readable from the approach at each end
	float start = 46.0;
	if (!far_half) {
		m += designator(vec2(x, y - start), des0);
	} else {
		m += designator(vec2(-x, (rw_len - y) - start), des1);
	}
	// aiming point
	float aim_at = rw_len > 2400.0 ? 400.0 : 300.0;
	m += box(yr, aim_at, aim_at + 50.0) * box(ax, 6.0, 15.0);
	// touchdown zone bars: 3,3,2,2,1,1 pairs every 150 m
	for (int k = 1; k <= 6; k++) {
		float at = float(k) * 150.0;
		if (abs(at - aim_at) < 60.0) continue;
		float count = k <= 2 ? 3.0 : (k <= 4 ? 2.0 : 1.0);
		float in_y = box(yr, at, at + 22.5);
		float bx = ax - 4.0;
		float bars = step(0.0, bx) * step(bx, count * 3.0 - 1.5) * step(mod(bx, 3.0), 1.5);
		m += in_y * bars * step(rw_len, 9999.0) * step(1800.0, rw_len);
	}
	return clamp(m, 0.0, 1.0);
}

void fragment() {
	vec2 p = UV;
	float n1 = texture(noise_tex, wpos.xz / 37.0).r;
	float n2 = texture(noise_tex, wpos.xz / 6.3).r;
	float n3 = texture(noise_tex, wpos.xz / 251.0).r;
	vec3 col;
	float rough = 0.85;
	float paint = 0.0;
	vec3 paint_col = vec3(0.85);
	if (mode == 0) {
		col = vec3(0.10, 0.10, 0.105) * (0.75 + 0.4 * n1 + 0.15 * n2) * (0.85 + 0.3 * n3);
		paint = runway_marks(p);
		// rubber deposits in the touchdown zones
		float yr = min(p.y, rw_len - p.y);
		float rubber = box(yr, 250.0, 900.0) * smoothstep(12.0, 2.0, abs(p.x) + (n2 - 0.5) * 6.0) * smoothstep(0.35, 0.75, n1 + n2 * 0.4);
		col *= 1.0 - rubber * 0.55;
	} else if (mode == 1) {
		col = vec3(0.12, 0.12, 0.125) * (0.8 + 0.35 * n1 + 0.15 * n2);
		float cl = box(abs(p.x), 0.0, 0.18);
		float edge = box(abs(p.x), rw_wid * 0.5 - 0.9, rw_wid * 0.5 - 0.6);
		paint = max(cl, edge);
		paint_col = vec3(0.8, 0.62, 0.08);
	} else if (mode == 2) {
		col = vec3(0.36, 0.36, 0.35) * (0.82 + 0.25 * n1 + 0.12 * n2);
		vec2 g = abs(fract(wpos.xz / 7.5) - 0.5);
		float joint = smoothstep(0.485, 0.5, max(g.x, g.y));
		col *= 1.0 - joint * 0.35;
		float stain = smoothstep(0.68, 0.9, n1 * 0.7 + n3 * 0.45);
		col *= 1.0 - stain * 0.16;
		rough = 0.9;
	} else if (mode == 3) {
		col = vec3(0.11, 0.11, 0.115) * (0.8 + 0.35 * n1);
		float dash = step(fract(p.y / 12.0), 0.5);
		paint = box(abs(p.x), 0.0, 0.12) * dash + box(abs(p.x), rw_wid * 0.5 - 0.5, rw_wid * 0.5 - 0.35);
	} else {
		col = vec3(0.12, 0.2, 0.06) * (0.75 + 0.5 * n1);
		rough = 0.95;
	}
	paint *= 0.88 + 0.12 * n2;
	col = mix(col, paint_col * (0.85 + 0.15 * n2), clamp(paint, 0.0, 1.0));
	// wet pavement: darker and glossy
	col *= 1.0 - wetness * 0.35;
	rough = mix(rough, 0.18, wetness * (mode == 4 ? 0.2 : 1.0));
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
	EMISSION = (col * 0.6 + vec3(0.09, 0.075, 0.05)) * flood * night * (mode == 2 ? 1.6 : 0.0);
}
