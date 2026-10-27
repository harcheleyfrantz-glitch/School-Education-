shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Instanced point lights drawn as camera-facing sprites that keep a minimum on-screen size.
// INSTANCE_CUSTOM: rgb = colour, a = facing angle in turns (0..1); a < 0 = omnidirectional;
// a in [-9,-5] = PAPI unit with threshold angle (-a - 5) degrees (+0.0 .. +4.0); a < -10 flashing.
uniform float night = 1.0;
uniform float fog_density = 0.00005;
uniform float min_px = 0.0016;
uniform float intensity = 1.0;

varying vec3 lcol;
varying float lvis;

void vertex() {
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = cam - center;
	float dist = length(to_cam);
	float base_size = length(MODEL_MATRIX[0].xyz);
	float size = max(base_size, dist * min_px);
	float a = INSTANCE_CUSTOM.a;
	vec3 c = INSTANCE_CUSTOM.rgb;
	float vis = 1.0;
	if (a >= 0.0) {
		float ang = a * 6.2831853;
		vec2 facing = vec2(sin(ang), -cos(ang));
		vec2 tc = normalize(to_cam.xz + vec2(0.0001));
		vis = smoothstep(-0.05, 0.35, dot(facing, tc));
	} else if (a < -4.5 && a > -10.0) {
		float thr = -a - 5.0;
		float h = to_cam.y;
		float elev = degrees(atan(h, max(length(to_cam.xz), 1.0)));
		c = mix(vec3(1.0, 0.08, 0.04), vec3(1.0, 1.0, 0.95), smoothstep(thr - 0.12, thr + 0.12, elev));
	} else if (a <= -10.0) {
		float ph = fract(TIME * 0.5 - (-a - 10.0) * 0.033);
		vis = step(ph, 0.06);
	}
	float day = 1.0 - night;
	lvis = vis * exp(-dist * fog_density) * mix(1.0, 0.18, day) * intensity;
	lcol = c;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 wp = center + (right * VERTEX.x + up * VERTEX.y) * size;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(wp, 1.0));
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float core = smoothstep(1.0, 0.0, d);
	float k = core * core * 2.2 + smoothstep(1.0, 0.6, d) * 0.4;
	ALBEDO = lcol * k * lvis;
}
