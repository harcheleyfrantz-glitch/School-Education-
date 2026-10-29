shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Aircraft light glow sprite (camera-facing). One shared material; each light sets its own
// instance parameters. pattern: 0 steady, 1 strobe (double flash), 2 beacon (rotating pulse),
// 3 steady and directional (landing / taxi lights: bright when looked into).
instance uniform vec3 color : source_color = vec3(1.0, 0.1, 0.05);
instance uniform int pattern = 0;
instance uniform float phase = 0.0;
instance uniform float on = 1.0;
instance uniform float size = 0.35;
instance uniform float night = 1.0;
instance uniform vec3 aim = vec3(0.0, 0.0, -1.0);
uniform float min_px = 0.0022;

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
	} else if (pattern == 3) {
		vec3 dir = normalize((MODEL_MATRIX * vec4(aim, 0.0)).xyz);
		float facing = max(dot(dir, normalize(cam - center)), 0.0);
		inten = 0.25 + 1.6 * pow(facing, 6.0);
		s *= 0.7 + 1.3 * pow(facing, 4.0);
	}
	k = inten * on * mix(0.35, 1.0, night);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	// pull the sprite slightly towards the camera so it is not buried in its housing
	vec3 wp = center + normalize(cam - center) * min(size * 0.6, 0.4) + (right * VERTEX.x + up * VERTEX.y) * s;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(wp, 1.0));
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float c = smoothstep(1.0, 0.0, d);
	ALBEDO = color * (c * c * 2.5 + smoothstep(1.0, 0.5, d) * 0.3) * k;
}
