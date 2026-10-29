shader_type spatial;
render_mode cull_back;

// Instanced buildings (unit meshes scaled per instance). INSTANCE_CUSTOM.rgb = facade colour,
// .a = random seed. Vertex colour r = facade kind (1 offices/flats, 0.5 glass curtain wall,
// 0.2 house), a = surface (1 wall, 0.5 pitched roof, 0.25 rooftop plant, 0 flat roof).
uniform float night = 0.0;

varying vec3 lpos;
varying vec3 onrm;
varying vec3 facade;
varying float seed;
varying vec2 vkind;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	lpos = VERTEX * sc;
	onrm = NORMAL;
	facade = pow(INSTANCE_CUSTOM.rgb, vec3(2.2));
	seed = INSTANCE_CUSTOM.a;
	vkind = vec2(COLOR.r, COLOR.a);
}

void fragment() {
	vec3 col = facade;
	vec3 emit = vec3(0.0);
	float rough = 0.85;
	float metal = 0.0;
	float surf = vkind.y;
	float kind = vkind.x;
	if (surf < 0.12) {
		// flat roof: gravel and membrane
		col = vec3(0.17, 0.17, 0.18) + facade * 0.12;
		col *= 0.9 + 0.2 * hash12(floor(lpos.xz * 0.5));
	} else if (surf < 0.4) {
		// rooftop plant: grey metal boxes, chimneys, masts
		col = vec3(0.45, 0.46, 0.47);
		rough = 0.5;
		metal = 0.4;
	} else if (surf < 0.7) {
		// pitched roof: clay tiles, slate or metal, with tile courses
		float pick = fract(seed * 7.31);
		vec3 tiles = pick < 0.45 ? vec3(0.42, 0.16, 0.1) : (pick < 0.72 ? vec3(0.2, 0.21, 0.23) : (pick < 0.88 ? vec3(0.32, 0.23, 0.16) : vec3(0.36, 0.38, 0.4)));
		float course = smoothstep(0.35, 0.5, abs(fract(lpos.y * 3.2) - 0.5) * 2.0);
		col = pow(tiles, vec3(2.2)) * (0.85 + 0.15 * course) * (0.92 + 0.16 * hash12(floor(lpos.xz * 2.0)));
		rough = 0.75;
	} else if (onrm.y > -0.5 && onrm.y < 0.5) {
		float u = abs(onrm.x) > 0.5 ? lpos.z : lpos.x;
		float v = lpos.y;
		if (kind < 0.35) {
			// house: two storeys of sash windows, a front door
			float wx = fract(u / 3.6);
			float wy = fract(v / 2.8);
			float win = step(0.3, wx) * step(wx, 0.7) * step(0.32, wy) * step(wy, 0.82) * step(0.4, v);
			vec2 cell = floor(vec2(u / 3.6, v / 2.8)) + seed * 71.0;
			col = mix(col, vec3(0.04, 0.05, 0.07), win * 0.85);
			col = mix(col, vec3(0.9), (step(0.27, wx) - step(0.3, wx) + step(0.7, wx) - step(0.73, wx)) * step(0.32, wy) * step(wy, 0.82) * step(0.4, v) * 0.8);
			rough = mix(0.9, 0.2, win);
			emit = win * night * step(0.45, hash12(cell)) * vec3(1.0, 0.72, 0.42) * 1.3;
		} else if (kind < 0.7) {
			// glass curtain wall: reflective panels, mullion grid, spandrels at each floor
			float mx = abs(fract(u / 1.5) - 0.5);
			float my = fract(v / 3.6);
			float mull = step(0.47, mx) + step(my, 0.07);
			vec2 cell = floor(vec2(u / 1.5, v / 3.6)) + seed * 37.0;
			vec3 glass = facade * vec3(0.55, 0.65, 0.75) + vec3(0.02, 0.03, 0.04) * hash12(cell);
			col = mix(glass, vec3(0.6, 0.62, 0.64), clamp(mull, 0.0, 1.0));
			rough = mix(0.06, 0.5, clamp(mull, 0.0, 1.0));
			metal = mix(0.75, 0.3, clamp(mull, 0.0, 1.0));
			float lit = step(0.42, hash12(floor(vec2(u / 6.0, v / 3.6)) + seed * 13.0));
			emit = (1.0 - clamp(mull, 0.0, 1.0)) * lit * night * vec3(0.85, 0.9, 1.0) * 1.1;
		} else {
			float wx = fract(u / 2.9);
			float wy = fract(v / 3.4);
			float win = step(0.18, wx) * step(wx, 0.82) * step(0.28, wy) * step(wy, 0.86) * step(4.2, v);
			vec2 cell = floor(vec2(u / 2.9, v / 3.4)) + seed * 113.0;
			float lit = step(0.52, hash12(cell));
			vec3 glass = mix(vec3(0.05, 0.07, 0.1), vec3(0.16, 0.2, 0.26), hash12(cell * 1.7));
			col = mix(col, glass, win);
			rough = mix(0.85, 0.15, win);
			float warm = hash12(cell + 3.1);
			emit = win * lit * night * mix(vec3(1.0, 0.75, 0.45), vec3(0.75, 0.85, 1.0), step(0.75, warm)) * 1.6;
			// ground-floor shopfronts
			float shop = step(v, 4.0) * step(0.6, v) * step(0.1, wx) * step(wx, 0.9);
			emit += shop * night * vec3(1.0, 0.85, 0.6) * 0.8 * step(0.4, hash12(cell + 9.0));
		}
		// a little grime toward the ground
		col *= 0.82 + 0.18 * smoothstep(0.0, 6.0, v);
	} else if (onrm.y >= 0.5) {
		col = vec3(0.18, 0.18, 0.19) + facade * 0.15;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
