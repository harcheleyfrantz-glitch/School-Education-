shader_type spatial;
render_mode cull_back;

// Instanced unit-cube buildings. INSTANCE_CUSTOM.rgb = facade colour, .a = random seed.
uniform float night = 0.0;

varying vec3 lpos;
varying vec3 onrm;
varying vec3 facade;
varying float seed;

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
}

void fragment() {
	vec3 col = facade;
	vec3 emit = vec3(0.0);
	float rough = 0.85;
	if (onrm.y > 0.5) {
		col = vec3(0.18, 0.18, 0.19) + facade * 0.15;
	} else if (onrm.y > -0.5) {
		float u = abs(onrm.x) > 0.5 ? lpos.z : lpos.x;
		float v = lpos.y;
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
	ALBEDO = col;
	ROUGHNESS = rough;
	EMISSION = emit;
}
