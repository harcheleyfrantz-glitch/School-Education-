shader_type spatial;
render_mode cull_back;

// One material for the whole airframe. Vertex COLOR.r selects the part:
// 0 fuselage, .1 wing, .2 fin/tail, .3 nacelle, .4 metal, .5 dark, .6 glass, .7 white, .8 inlet, .9 exhaust
// Fuselage UV: x = angle around (0 top, .25 right, .5 bottom, .75 left), y = 0 nose .. 1 tail.
// Fin UV: x = chordwise 0..1, y = spanwise 0..1.
uniform vec3 body_col : source_color = vec3(0.95);
uniform vec3 belly_col : source_color = vec3(0.1, 0.25, 0.45);
uniform vec3 stripe_col : source_color = vec3(0.95, 0.55, 0.15);
uniform vec3 tail_col : source_color = vec3(0.1, 0.25, 0.45);
uniform vec3 logo_col : source_color = vec3(0.95, 0.6, 0.2);
uniform vec3 engine_col : source_color = vec3(0.1, 0.25, 0.45);
uniform int logo_shape = 0;
uniform float fuse_len = 37.0;
uniform float win_start = 0.16;
uniform float win_end = 0.8;
uniform float win_pitch = 0.53;
uniform float win_v = 0.057;         // window band centre above the side line (fraction of a turn)
uniform float fuse_r = 2.0;
uniform float cockpit_v = 0.11;      // nose station where the windscreen sits
uniform vec4 doors = vec4(0.07, 0.92, -1.0, -1.0);
uniform vec4 doors2 = vec4(-1.0);
uniform float cabin_lights = 0.0;    // windows glow at night
uniform float dirt = 0.15;
uniform float scorch = 0.0;          // fire damage

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float logo(vec2 p, int shape) {
	// p: fin coordinates, centred around the logo (roughly -1..1)
	float d = length(p);
	if (shape == 0) {            // rising sun disc with rays
		float rays = step(0.5, fract(atan(p.y, p.x) * 1.9)) * step(0.62, d) * step(d, 0.95) * step(-0.05, p.y);
		return max(step(d, 0.48), rays);
	} else if (shape == 1) {     // wave
		float w = sin(p.x * 3.4) * 0.28;
		return step(abs(p.y - w), 0.18) + step(abs(p.y - w + 0.5), 0.1);
	} else if (shape == 2) {     // chevron
		return step(abs(abs(p.x) * 0.9 - p.y + 0.2), 0.22) * step(-0.8, p.y) * step(abs(p.x), 0.9);
	} else if (shape == 3) {     // star
		float a = atan(p.y, p.x);
		float r = 0.55 + 0.35 * cos(a * 5.0);
		return step(d, r * 0.95);
	} else if (shape == 4) {     // feather / bird
		float body = step(length(vec2(p.x * 0.5, p.y + p.x * 0.3)), 0.38);
		float wing = step(abs(p.y - 0.25 * sin(p.x * 2.2) - 0.1), 0.12) * step(abs(p.x), 0.95);
		return max(body, wing);
	}
	return step(abs(d - 0.6), 0.16);   // ring
}

void fragment() {
	float part = COLOR.r * 10.0 + 0.5;
	int pid = int(part);
	vec3 col = body_col;
	float rough = 0.32;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float grime = hash12(floor(lpos.xz * 2.0)) * 0.06;
	if (pid == 0) {
		float u = UV.x;
		float v = UV.y;
		// side coordinate: 0 at the crown, 0.5 at the keel
		float side = min(u, 1.0 - u) * 2.0;     // 0 top .. 1 bottom
		col = body_col;
		// belly below the cheatline, stripe just under the window line
		float belly_line = 0.6 + 0.06 * smoothstep(0.75, 1.0, v);
		col = mix(col, belly_col, smoothstep(belly_line - 0.004, belly_line + 0.004, side));
		float stripe = smoothstep(0.468, 0.472, side) * smoothstep(0.52, 0.516, side) * step(0.03, v) * step(v, 0.88);
		col = mix(col, stripe_col, stripe);
		// passenger windows (both sides), sized in metres
		float zm = v * fuse_len;
		float wb_r = abs(u - (0.25 - win_v)) * 6.2832 * fuse_r;
		float wb_l = abs(u - (0.75 + win_v)) * 6.2832 * fuse_r;
		float wy = min(wb_r, wb_l);
		float wx = (fract(zm / win_pitch) - 0.5) * win_pitch;
		vec2 wq = abs(vec2(wx / 0.125, wy / 0.18));
		float window = step(pow(pow(wq.x, 3.0) + pow(wq.y, 3.0), 1.0 / 3.0), 1.0) * step(win_start, v) * step(v, win_end);
		float wb = wy / fuse_r;
		// door outlines and cutouts in the window row
		float door_line = 0.0;
		for (int i = 0; i < 4; i++) {
			float dv = doors[i];
			if (dv < 0.0) continue;
			float dz = abs(zm - (win_start + dv * (win_end - win_start)) * fuse_len);
			float in_door = step(dz, 0.55) * step(wy, 1.0);
			window *= 1.0 - step(dz, 0.95);
			door_line = max(door_line, in_door * (1.0 - step(dz, 0.5) * step(wy, 0.94)));
		}
		for (int i = 0; i < 4; i++) {
			float dv2 = doors2[i];
			if (dv2 < 0.0) continue;
			float dz2 = abs(zm - (win_start + dv2 * (win_end - win_start)) * fuse_len);
			door_line = max(door_line, step(dz2, 0.38) * step(wy, 0.55) * (1.0 - step(dz2, 0.34) * step(wy, 0.5)));
		}
		col = mix(col, col * 0.35, door_line);
		vec3 glass = vec3(0.04, 0.05, 0.07);
		col = mix(col, glass, window);
		rough = mix(rough, 0.08, window);
		emit = window * cabin_lights * vec3(1.0, 0.86, 0.62) * 1.3;
		// cockpit glazing: windscreen panels and side windows on the upper nose
		float cz = (v - cockpit_v) * fuse_len;
		float cu = min(u, 1.0 - u) * 6.2832 * fuse_r;      // metres from the crown
		float band = step(abs(cz + cu * 0.18), 0.55) * step(cu, fuse_r * 1.05) * step(0.12, cu);
		float post = step(fract(cu / (fuse_r * 0.36)), 0.08);
		float ws = band * (1.0 - post);
		col = mix(col, vec3(0.02, 0.03, 0.045), ws);
		rough = mix(rough, 0.04, ws);
		metal = mix(metal, 0.5, ws);
		// tail cone in tail colour
		col = mix(col, tail_col, smoothstep(0.9, 0.93, v) * step(side, 0.5));
	} else if (pid == 1) {
		col = vec3(0.78, 0.8, 0.83);
		rough = 0.45;
		metal = 0.25;
	} else if (pid == 2) {
		col = tail_col;
		vec2 lp = (UV - vec2(0.42, 0.52)) * vec2(2.6, 2.2);
		float lg = logo(lp, logo_shape);
		col = mix(col, logo_col, clamp(lg, 0.0, 1.0));
	} else if (pid == 3) {
		col = engine_col;
		rough = 0.3;
		metal = 0.1;
	} else if (pid == 4) {
		col = vec3(0.6, 0.62, 0.65);
		rough = 0.35;
		metal = 0.75;
	} else if (pid == 5) {
		col = vec3(0.06, 0.06, 0.065);
		rough = 0.85;
	} else if (pid == 6) {
		col = vec3(0.03, 0.04, 0.05);
		rough = 0.04;
		metal = 0.5;
	} else if (pid == 7) {
		col = vec3(0.85, 0.86, 0.88);
		rough = 0.5;
	} else if (pid == 8) {
		col = vec3(0.12, 0.12, 0.13);
		rough = 0.4;
		metal = 0.6;
	} else {
		col = vec3(0.22, 0.2, 0.19);
		rough = 0.55;
		metal = 0.5;
	}
	col *= 1.0 - grime * dirt * 4.0;
	col = mix(col, vec3(0.03, 0.025, 0.02), scorch * smoothstep(0.3, 0.8, hash12(floor(lpos.xz * 1.3) + 7.0)));
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
