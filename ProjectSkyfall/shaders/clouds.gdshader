shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// 2.5D ray-marched cloud slab rendered on a horizontal plane at the cloud base (seen from below)
// or the cloud top (seen from above). Works on every renderer; step count scales with quality.
uniform vec3 world_origin = vec3(0.0);
uniform float base_y = 1500.0;
uniform float top_y = 2600.0;
uniform float coverage = 0.4;
uniform float density = 1.0;
uniform vec2 wind_off = vec2(0.0);
uniform vec3 sun_dir = vec3(0.3, 0.8, 0.2);
uniform vec3 sun_col : source_color = vec3(1.0);
uniform vec3 amb_col : source_color = vec3(0.6, 0.65, 0.75);
uniform float tile = 14000.0;
uniform float extent = 60000.0;
uniform int steps = 8;
uniform float storm = 0.0;
uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;

float dens(vec3 p) {
	vec2 uv = (p.xz + world_origin.xz) / tile + wind_off;
	vec4 t = texture(cloud_tex, uv);
	float cov = t.r * 0.8 + t.b * 0.35 - 0.075;
	float hf = clamp((p.y - base_y) / max(top_y - base_y, 1.0), 0.0, 1.0);
	float shape = smoothstep(1.0 - coverage, 1.0 - coverage + 0.16, cov);
	float tops = 0.35 + 0.65 * smoothstep(1.0 - coverage, 1.0, cov);
	float profile = smoothstep(0.0, 0.1, hf) * (1.0 - smoothstep(tops * 0.7, tops, hf));
	float detail = texture(cloud_tex, uv * 6.1 + vec2(0.27, 0.71)).g;
	float d = shape * profile - detail * 0.32 * (1.0 - hf * 0.4);
	return clamp(d, 0.0, 1.0) * density;
}

void fragment() {
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 fw = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 rd = normalize(fw - cam);
	float t0;
	float t1;
	if (cam.y < base_y) {
		if (rd.y <= 0.002) discard;
		t0 = (base_y - cam.y) / rd.y;
		t1 = (top_y - cam.y) / rd.y;
	} else if (cam.y > top_y) {
		if (rd.y >= -0.002) discard;
		t0 = (top_y - cam.y) / rd.y;
		t1 = (base_y - cam.y) / rd.y;
	} else {
		t0 = 0.0;
		t1 = rd.y > 0.0 ? (top_y - cam.y) / max(rd.y, 0.002) : (base_y - cam.y) / min(rd.y, -0.002);
	}
	t1 = min(t1, t0 + 7000.0);
	float horiz = length(fw.xz - cam.xz);
	float edge_fade = 1.0 - smoothstep(extent * 0.55, extent * 0.98, horiz);
	if (edge_fade <= 0.0) discard;
	vec4 outc;
	if (steps <= 1) {
		// 2.5D layer: one coverage sample, thickness from the view angle, normal from the gradient
		vec3 p = cam + rd * t0;
		vec2 uv = (p.xz + world_origin.xz) / tile + wind_off;
		vec4 tx = texture(cloud_tex, uv);
		float cov = tx.r * 0.8 + tx.b * 0.35 - 0.075;
		float e = 0.006;
		float cx = texture(cloud_tex, uv + vec2(e, 0.0)).r * 0.8 + tx.b * 0.35 - 0.075;
		float cz = texture(cloud_tex, uv + vec2(0.0, e)).r * 0.8 + tx.b * 0.35 - 0.075;
		float d = smoothstep(1.0 - coverage, 1.0 - coverage + 0.22, cov);
		float det = texture(cloud_tex, uv * 6.1 + vec2(0.27, 0.71)).g;
		d = clamp(d - det * 0.3 * (1.0 - d), 0.0, 1.0) * density;
		float thick = (top_y - base_y) * mix(0.25, 1.0, d);
		float path = thick / max(abs(rd.y), 0.07);
		float a = 1.0 - exp(-d * path * 0.006);
		vec3 n = normalize(vec3((cov - cx) * 9.0, 1.0, (cov - cz) * 9.0));
		float lit = clamp(dot(n, normalize(sun_dir)) * 0.5 + 0.5, 0.0, 1.0);
		vec3 c;
		if (cam.y > top_y) {
			c = amb_col * (0.55 + 0.25 * d) * (1.0 - storm * 0.4) + sun_col * mix(0.55, 1.05, lit);
		} else {
			c = amb_col * mix(0.95, 0.42, d) * (1.0 - storm * 0.5) + sun_col * 0.3 * (1.0 - d) * lit;
		}
		outc = vec4(c, a);
	} else {
		float stepl = (t1 - t0) / float(steps);
		float jitter = 0.5 + (fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715)))) - 0.5) * 0.6;
		float trans = 1.0;
		vec3 acc = vec3(0.0);
		for (int i = 0; i < 24; i++) {
			if (i >= steps) break;
			float t = t0 + (float(i) + jitter) * stepl;
			vec3 p = cam + rd * t;
			float d = dens(p);
			if (d > 0.002) {
				float hf = clamp((p.y - base_y) / max(top_y - base_y, 1.0), 0.0, 1.0);
				float ds = dens(p + sun_dir * 300.0);
				float light = exp(-ds * 4.5) * (0.5 + 0.5 * hf);
				float powder = 1.0 - exp(-d * 6.0);
				vec3 c = amb_col * (0.32 + 0.6 * hf) * (1.0 - storm * 0.5) + sun_col * light * mix(0.6, 1.0, powder);
				float a = 1.0 - exp(-d * stepl * 0.012);
				acc += trans * a * c;
				trans *= 1.0 - a;
				if (trans < 0.03) break;
			}
		}
		float alpha = 1.0 - trans;
		outc = vec4(acc / max(alpha, 0.001), alpha);
	}
	ALBEDO = outc.rgb;
	ALPHA = clamp(outc.a * edge_fade, 0.0, 1.0);
}
