shader_type spatial;
render_mode cull_back;

// Airport buildings. UV are face dimensions in metres (MeshBuilder uv_world boxes).
// kind: 0 glass curtain wall, 1 concrete, 2 corrugated metal, 3 tower cab glass, 4 painted
uniform int kind = 1;
uniform vec3 base_color : source_color = vec3(0.7);
uniform vec3 accent : source_color = vec3(0.2, 0.3, 0.5);
uniform float night = 0.0;
uniform float glow = 1.0;

varying vec3 onrm;

void vertex() {
	onrm = NORMAL;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec3 col = base_color;
	float rough = 0.8;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	bool roof = onrm.y > 0.5;
	if (kind == 0 && !roof) {
		vec2 g = UV / vec2(3.2, 4.2);
		vec2 f = fract(g);
		float mull = 1.0 - step(0.05, f.x) * step(f.x, 0.95) * step(0.06, f.y) * step(f.y, 0.94);
		vec3 glass = mix(vec3(0.05, 0.09, 0.12), vec3(0.22, 0.3, 0.36), clamp(UV.y / 30.0, 0.0, 1.0));
		col = mix(glass, vec3(0.75, 0.77, 0.8), mull);
		rough = mix(0.06, 0.5, mull);
		metal = mix(0.35, 0.6, mull);
		float lit = step(0.25, hash12(floor(g) + 3.0));
		emit = (1.0 - mull) * night * glow * vec3(1.0, 0.86, 0.62) * (0.55 + 0.45 * lit);
	} else if (kind == 2 && !roof) {
		float corr = 0.5 + 0.5 * sin(UV.x * 9.0);
		col = base_color * (0.82 + 0.18 * corr);
		rough = 0.5;
		metal = 0.4;
	} else if (kind == 3) {
		col = vec3(0.04, 0.07, 0.08);
		rough = 0.05;
		metal = 0.5;
		emit = night * vec3(0.25, 0.3, 0.2) * glow;
	} else if (kind == 1 && !roof) {
		vec2 g = abs(fract(UV / vec2(6.0, 3.5)) - 0.5);
		col *= 1.0 - smoothstep(0.47, 0.5, max(g.x, g.y)) * 0.15;
	}
	if (roof) {
		col = base_color * 0.65;
		rough = 0.9;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
