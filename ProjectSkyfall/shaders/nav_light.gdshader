shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Aircraft navigation/strobe/beacon light sprite. pattern: 0 steady, 1 strobe (double flash), 2 beacon
uniform vec3 color : source_color = vec3(1.0, 0.1, 0.05);
uniform int pattern = 0;
uniform float phase = 0.0;
uniform float on = 1.0;
uniform float size = 0.35;
uniform float min_px = 0.0022;
uniform float night = 1.0;

varying float k;

void vertex() {
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float dist = length(cam - center);
	float s = max(size, dist * min_px);
	float t = fract(TIME * (pattern == 1 ? 0.83 : 0.95) + phase);
	float inten = 1.0;
	if (pattern == 1) {
		inten = step(t, 0.04) + step(0.12, t) * step(t, 0.16);
		s *= 1.6;
	} else if (pattern == 2) {
		inten = smoothstep(0.0, 0.08, t) * smoothstep(0.32, 0.12, t);
	}
	k = inten * on * mix(0.35, 1.0, night);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 wp = center + (right * VERTEX.x + up * VERTEX.y) * s;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(wp, 1.0));
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float c = smoothstep(1.0, 0.0, d);
	ALBEDO = color * (c * c * 2.5 + smoothstep(1.0, 0.5, d) * 0.3) * k;
}
