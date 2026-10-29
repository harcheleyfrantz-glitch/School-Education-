shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Paint shader for the whole procedural airframe (AircraftModel). Vertex COLOR.r * 64 selects the
// part (AircraftModel.P_*), COLOR.g / COLOR.b carry part data (surface side, engine paint mask...),
// COLOR.a is baked occlusion.
// UV  fuselage: x = angle around (0 crown, .25 right, .5 keel, .75 left), y = station 0 nose .. 1 tail
//     lifting surfaces: x = chord fraction, y = span fraction; revolved parts: x = around, y = profile
// UV2 paint coordinates in metres: fin, rudder, winglets = body (z, y); wings, stabilisers = body (x, z)

const int P_BODY = 0;
const int P_WING = 1;
const int P_TAIL = 2;
const int P_NACELLE = 3;
const int P_METAL = 4;
const int P_DARK = 5;
const int P_GLASS = 6;
const int P_GEAR = 7;
const int P_INLET = 8;
const int P_EXHAUST = 9;
const int P_LIP = 10;
const int P_FAN = 11;
const int P_SPINNER = 12;
const int P_PLUG = 13;
const int P_TYRE = 14;
const int P_HUB = 15;
const int P_CHROME = 16;
const int P_BELLY = 17;
const int P_FLAT = 18;
const int P_WINGLET = 19;
const int P_LENS = 20;
const int P_WELL = 21;
const int P_PROP = 22;
const int P_BOOT = 23;
const int P_PYLON = 24;
const int P_STAB = 25;

// ---- livery colours
uniform vec3 body_col : source_color = vec3(0.96);
uniform vec3 belly_col : source_color = vec3(0.1, 0.25, 0.45);
uniform vec3 stripe_col : source_color = vec3(0.95, 0.55, 0.15);
uniform vec3 stripe2_col : source_color = vec3(0.95, 0.55, 0.15);
uniform vec3 stripe3_col : source_color = vec3(0.95, 0.55, 0.15);
uniform vec3 tail_col : source_color = vec3(0.1, 0.25, 0.45);
uniform vec3 tail2_col : source_color = vec3(0.1, 0.25, 0.45);
uniform vec3 logo_col : source_color = vec3(0.95, 0.6, 0.2);
uniform vec3 engine_col : source_color = vec3(0.1, 0.25, 0.45);
uniform vec3 engine2_col : source_color = vec3(0.95);
uniform vec3 wing_col : source_color = vec3(0.72, 0.74, 0.76);
uniform vec3 tip_col : source_color = vec3(0.1, 0.25, 0.45);
uniform vec3 gear_col : source_color = vec3(0.8, 0.81, 0.82);
uniform vec3 art_col : source_color = vec3(1.0);
uniform int logo_shape = 0;
uniform int engine_style = 0;        // 0 plain, 1 front band, 2 chevron, 3 tail-colour lip band
// ---- livery layout (normalised height hn: -1 keel .. 1 crown; station t: 0 nose .. 1 tail)
uniform float belly_h = -0.55;       // belly line, relative to the window line
uniform float win_hn = 0.15;         // window line (normalised height) of this type
uniform float nose_dip = 0.0;        // belly line offset towards the nose (+ up)
uniform float rise_t = 0.72;         // belly line starts climbing here...
uniform float rise_h = 0.25;         // ...and climbs this much by the tail
uniform vec4 stripes = vec4(0.12, 0.03, 0.0, 0.0);  // stripe 1 offset / half width, stripe 2 offset / half width (from the belly line)
uniform vec2 stripe3 = vec2(0.0, 0.0);
uniform vec2 stripe_t = vec2(0.05, 0.98);           // stations where the cheatlines start / end
uniform float flow_t = 2.0;          // tail colour flows down the rear fuselage from this station
uniform float flow_h = 0.0;          // ...reaching this far down (normalised) at the tail
uniform float tail_band = 0.0;       // fraction of fin height kept in body colour at the root
uniform float mask = 0.0;            // painted surround around the flight deck windows
uniform float metal_belly = 0.0;     // bare polished belly (retro)
uniform float nose_paint = 0.0;      // radome painted in belly colour up to this station
uniform float event_art = 0.0;       // special scheme artwork on the fuselage
uniform float boots = 0.0;           // black de-icing boots on leading edges (turboprops)
uniform float wing_body = 0.0;       // wings painted like the body (GA)
// ---- airframe geometry (metres, body frame: +x right, +y up, -z forward)
uniform float fuse_rw = 2.0;
uniform float fuse_rh = 2.0;
uniform float nose_z = -18.0;
uniform float fuse_len = 37.0;
uniform float floor_y = -0.7;
uniform vec4 win = vec4(0.3, 0.17, 0.115, 0.53);    // centre y, half height, half width, pitch
uniform vec2 win_range = vec2(-14.0, 14.0);         // first / last window centre (body z)
uniform float win_shape = 2.6;                      // superellipse exponent of the windows
uniform vec4 door_z = vec4(-1e4);                   // passenger doors (body z)
uniform vec4 door_w = vec4(0.5);                    // their half widths
uniform float door_h = 1.9;
uniform vec4 exit_z = vec4(-1e4);                   // overwing exits
uniform vec4 cargo_z = vec4(-1e4);                  // lower deck cargo doors (right side)
uniform vec4 cargo_w = vec4(0.9);
uniform float cargo_h = 1.25;
uniform vec4 main_door = vec4(-1e4, 1.7, 1.6, 0.0); // freighter main deck door: z, half w, half h, centre y
uniform float nose_door = -1e4;                     // freighter visor nose door split station (body z)
uniform float cockpit_z1 = -1e4;                    // flight deck glazing lives ahead of this
uniform int pane_count = 0;
uniform vec3 pane_o[5];
uniform vec3 pane_u[5];
uniform vec3 pane_v[5];
uniform vec4 pane_a[5];
uniform vec4 pane_b[5];
uniform float pane_r[5];
uniform vec4 logo_xf = vec4(15.0, 5.0, 2.0, 0.0);  // fin art centre (body z, y), scale
uniform vec4 fin_geo = vec4(10.0, 2.0, 6.0, 0.8);  // fin root LE z, root y, height, LE slope
uniform vec2 fin_chord = vec2(6.0, 2.5);
uniform vec2 static_port = vec2(-12.0, 0.1);       // static port patch (body z, y)
// ---- per aircraft state
instance uniform float cabin_lights = 0.0;
instance uniform float logo_light = 0.0;
instance uniform float deck_glow = 0.0;
instance uniform float door_open = 0.0;
instance uniform float gear_down = 0.0;
uniform vec4 main_well = vec4(0.0, 0.0, -1e4, 0.0);   // open main wheel wells: |x| centre, half width, z centre, half length
uniform vec4 nose_well = vec4(0.0, -1e4, 0.0, 0.0);   // nose bay: half width, z centre, half length
instance uniform float dirt = 0.25;
instance uniform float scorch = 0.0;

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 1 inside (d < 0), anti-aliased over one pixel
float fill(float d) {
	float w = max(fwidth(d), 1e-5);
	return clamp(0.5 - d / w, 0.0, 1.0);
}

// thin line of half width hw along d = 0, faded out once it gets thinner than a pixel
float line(float d, float hw) {
	float w = max(fwidth(d), 1e-5);
	float k = clamp(0.5 - (abs(d) - hw) / w, 0.0, 1.0);
	return k * clamp(hw * 2.0 / w, 0.0, 1.0);
}

float sd_rbox(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float sd_seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

float sd_quad(vec2 p, vec2 v0, vec2 v1, vec2 v2, vec2 v3) {
	vec2 v[4] = vec2[4](v0, v1, v2, v3);
	float d = dot(p - v0, p - v0);
	float s = 1.0;
	for (int i = 0; i < 4; i++) {
		int j = (i + 3) % 4;
		vec2 e = v[j] - v[i];
		vec2 w = p - v[i];
		vec2 b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
		d = min(d, dot(b, b));
		float c1 = p.y >= v[i].y ? 1.0 : 0.0;
		float c2 = p.y < v[j].y ? 1.0 : 0.0;
		float c3 = e.x * w.y > e.y * w.x ? 1.0 : 0.0;
		float sum = c1 + c2 + c3;
		if (sum > 2.5 || sum < 0.5) {
			s = -s;
		}
	}
	return s * sqrt(d);
}

// superellipse window: approximate distance in metres
float sd_window(vec2 q, vec2 hs, float n) {
	vec2 a = abs(q) / hs;
	float f = pow(pow(a.x, n) + pow(a.y, n), 1.0 / n);
	return (f - 1.0) * min(hs.x, hs.y);
}

// seven-segment style digit with rounded strokes; p in a 1 x 2 cell centred on 0
float sd_digit(vec2 p, int dg) {
	// segment bits: a top, b top right, c bottom right, d bottom, e bottom left, f top left, g middle
	int m = 0;
	if (dg == 0) m = 63; else if (dg == 1) m = 6; else if (dg == 2) m = 91; else if (dg == 3) m = 79;
	else if (dg == 4) m = 102; else if (dg == 5) m = 109; else if (dg == 6) m = 125; else if (dg == 7) m = 7;
	else if (dg == 8) m = 127; else m = 111;
	float d = 1e3;
	vec2 sl = vec2(0.05, 0.0);
	if ((m & 1) != 0) d = min(d, sd_seg(p, vec2(-0.32, 0.9), vec2(0.32, 0.9)));
	if ((m & 2) != 0) d = min(d, sd_seg(p, vec2(0.4, 0.82), vec2(0.4, 0.08)));
	if ((m & 4) != 0) d = min(d, sd_seg(p, vec2(0.4, -0.08), vec2(0.4, -0.82)));
	if ((m & 8) != 0) d = min(d, sd_seg(p, vec2(-0.32, -0.9), vec2(0.32, -0.9)));
	if ((m & 16) != 0) d = min(d, sd_seg(p, vec2(-0.4, -0.08), vec2(-0.4, -0.82)));
	if ((m & 32) != 0) d = min(d, sd_seg(p, vec2(-0.4, 0.82), vec2(-0.4, 0.08)));
	if ((m & 64) != 0) d = min(d, sd_seg(p, vec2(-0.32, 0.0), vec2(0.32, 0.0)));
	return d - 0.13;
}

float sd_star(vec2 p, float r, float n, float inner) {
	float a = atan(p.y, p.x);
	float seg = TAU / n;
	float k = abs(mod(a + seg * 0.5 + PI * 0.5, seg) - seg * 0.5) / (seg * 0.5);
	float rr = mix(r * inner, r, pow(1.0 - k, 1.6));
	return (length(p) - rr) * 0.7;
}

// Fin artwork. a: art coordinates (x towards the nose, y up, ~ -1..1), s: reading coordinates
// (x reads left to right on either side). Returns colour weights: x = logo colour, y = art colour.
vec2 fin_art(vec2 a, vec2 s, float span) {
	float lg = 0.0;
	float ar = 0.0;
	if (logo_shape == 0) {
		// rising sun: a disc sliced by horizon lines, seven tapered rays fanning upward
		vec2 c = a - vec2(0.0, -0.3);
		float r = length(c);
		float disc = fill(r - 0.44);
		float cuts = fill(abs(fract(c.y * 5.0 + 0.5) - 0.5) - 0.3) * step(c.y, -0.04);
		disc *= 1.0 - cuts;
		float ang = atan(c.x, c.y);
		float kk = ang / (PI / 8.0);
		float lat = abs(kk - round(kk)) * (PI / 8.0) * r;
		float rays = fill(lat - 0.05 * (1.3 - r * 0.55)) * step(0.58, r) * fill(r - 1.18) * step(abs(ang), PI * 0.42);
		lg = max(disc, rays);
	} else if (logo_shape == 1) {
		// three breaking waves
		float w = 0.0;
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			float yy = a.y + 0.55 - fi * 0.48 - 0.16 * sin(a.x * 3.0 + fi * 1.3);
			w = max(w, fill(abs(yy) - (0.09 - fi * 0.015)) * fill(abs(a.x) - 1.1 + fi * 0.15));
		}
		lg = w;
	} else if (logo_shape == 2) {
		// bold forward-pointing chevrons
		vec2 q = vec2(a.x + 0.1, abs(a.y));
		float c1 = abs(q.x + q.y * 0.9 - 0.25) - 0.17;
		float c2 = abs(q.x + q.y * 0.9 + 0.35) - 0.1;
		float lim = fill(q.y - 0.95) * fill(abs(a.x) - 1.3);
		lg = fill(c1) * lim;
		ar = fill(c2) * lim;
	} else if (logo_shape == 3) {
		// compass star with a ring
		float st = sd_star(a, 0.95, 4.0, 0.22);
		float st2 = sd_star(vec2(a.x * 0.7071 - a.y * 0.7071, a.x * 0.7071 + a.y * 0.7071), 0.5, 4.0, 0.3);
		lg = max(fill(st), fill(st2));
		ar = fill(abs(length(a) - 0.62) - 0.035) * (1.0 - lg);
	} else if (logo_shape == 4) {
		// stylised wing: three crescent feathers sweeping up and forward
		float acc = 0.0;
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			vec2 q = a - vec2(-0.35 + fi * 0.16, -0.7 + fi * 0.16);
			float r1 = 1.2 - fi * 0.22;
			float d1 = length(q) - r1;
			float d2 = length(q - vec2(0.16, -0.12)) - (r1 - 0.04);
			float cres = max(d1, -d2);
			acc = max(acc, fill(cres) * step(0.02, q.y) * step(-0.1, q.x));
		}
		lg = acc;
		ar = fill(length(a - vec2(0.55, -0.62)) - 0.09);
	} else if (logo_shape == 5) {
		// diagonal speed bands
		float b = a.y - a.x * 0.55;
		lg = fill(abs(b - 0.15) - 0.13);
		ar = fill(abs(b + 0.32) - 0.07);
	} else if (logo_shape == 6) {
		// five-point star in a disc
		float disc = fill(length(a) - 0.72);
		float st = fill(sd_star(a, 0.6, 5.0, 0.42));
		lg = disc * (1.0 - st);
		ar = st;
	} else if (logo_shape == 7) {
		// tanker number and a white flash
		vec2 q = s * vec2(1.0, 1.0) - vec2(0.0, 0.18);
		float d = 1e3;
		d = min(d, sd_digit((q - vec2(-0.62, 0.0)) * vec2(2.6, 2.6), 9));
		d = min(d, sd_digit((q - vec2(0.0, 0.0)) * vec2(2.6, 2.6), 1));
		d = min(d, sd_digit((q - vec2(0.62, 0.0)) * vec2(2.6, 2.6), 0));
		lg = fill(d / 2.6);
		float fl = a.y + 0.95 + a.x * 0.35;
		ar = fill(abs(fl) - 0.09);
	} else if (logo_shape == 8) {
		// retro: three sweeping bands and a small sun
		float b = a.y + a.x * 0.6;
		lg = fill(abs(b + 0.55) - 0.08);
		ar = fill(abs(b + 0.25) - 0.08) + fill(abs(b + 0.85) - 0.08) * 0.0;
		float sun = fill(length(a - vec2(-0.1, 0.45)) - 0.28);
		lg = max(lg, sun);
		ar = max(ar, fill(abs(b + 0.85) - 0.08));
	} else if (logo_shape == 9) {
		// anniversary: "100" ringed by stars
		vec2 q = s - vec2(0.0, 0.05);
		float d = 1e3;
		d = min(d, sd_digit((q - vec2(-0.6, 0.0)) * 2.4, 1));
		d = min(d, sd_digit((q - vec2(0.0, 0.0)) * 2.4, 0));
		d = min(d, sd_digit((q - vec2(0.6, 0.0)) * 2.4, 0));
		lg = fill(d / 2.4);
		float stars = 0.0;
		for (int i = 0; i < 7; i++) {
			float ang = PI * (0.12 + 0.76 * float(i) / 6.0);
			vec2 sc = vec2(cos(ang), sin(ang)) * vec2(1.05, 0.85) + vec2(0.0, -0.1);
			stars = max(stars, fill(sd_star(s - sc, 0.12, 5.0, 0.45)));
		}
		ar = stars;
	} else {
		lg = fill(abs(length(a) - 0.6) - 0.14);
	}
	return vec2(clamp(lg, 0.0, 1.0), clamp(ar, 0.0, 1.0));
}

void fragment() {
	int pid = int(COLOR.r * 64.0 + 0.5);
	vec3 col = body_col;
	float rough = 0.3;
	float metal = 0.0;
	float spec = 0.5;
	float cc = 0.0;
	vec3 emit = vec3(0.0);
	float ao = COLOR.a;
	float dirt_k = 0.0;
	float px = length(fwidth(lpos));        // metres per pixel, for detail fading
	float detail = clamp(1.0 - (px - 0.004) / 0.012, 0.0, 1.0);

	if (pid == P_BODY) {
		float t = UV.y;
		float hn = cos(UV.x * TAU);
		float side = lpos.x >= 0.0 ? 1.0 : -1.0;
		float aa = fwidth(hn) + 1e-4;
		rough = 0.24;
		cc = 0.6;
		// ---- belly
		float bl = win_hn + belly_h + nose_dip * (1.0 - smoothstep(0.03, 0.32, t)) + rise_h * pow(smoothstep(rise_t, 1.0, t), 1.25);
		vec3 bc = belly_col;
		float belly = smoothstep(bl + aa, bl - aa, hn);
		col = mix(col, bc, belly);
		if (metal_belly > 0.5) {
			metal = mix(metal, 0.9, belly);
			rough = mix(rough, 0.2 + 0.08 * vnoise(lpos.zy * 0.6), belly);
			cc = mix(cc, 0.0, belly);
		}
		// ---- cheatlines (follow the belly line)
		float st = smoothstep(stripe_t.x, stripe_t.x + 0.02, t + (hn - bl) * 0.02) * (1.0 - smoothstep(stripe_t.y - 0.02, stripe_t.y, t));
		if (stripes.y > 0.0) {
			float s1 = smoothstep(stripes.y + aa, stripes.y - aa, abs(hn - bl - stripes.x)) * st;
			col = mix(col, stripe_col, s1);
		}
		if (stripes.w > 0.0) {
			float s2 = smoothstep(stripes.w + aa, stripes.w - aa, abs(hn - bl - stripes.z)) * st;
			col = mix(col, stripe2_col, s2);
		}
		if (stripe3.y > 0.0) {
			float s3 = smoothstep(stripe3.y + aa, stripe3.y - aa, abs(hn - bl - stripe3.x)) * st;
			col = mix(col, stripe3_col, s3);
		}
		// ---- tail colour flowing down the rear fuselage into the fin
		if (t > flow_t) {
			float k = (t - flow_t) / max(1.0 - flow_t, 0.01);
			float fl = 1.02 - flow_h * pow(k, 0.85);
			float flow = smoothstep(fl - aa, fl + aa, hn);
			col = mix(col, tail_col, flow);
			// accent edge along the flow
			col = mix(col, tail2_col, smoothstep(aa * 1.5, 0.0, abs(hn - fl + 0.05) - 0.025) * step(0.05, k));
		}
		// ---- painted radome
		if (nose_paint > 0.0) {
			float nb = nose_paint - 0.01 * hn;
			col = mix(col, belly_col, smoothstep(nb + 0.002, nb - 0.002, t));
		}
		// ---- special scheme artwork: a sweeping aurora band with stars
		if (event_art > 0.5) {
			float k = smoothstep(0.25, 0.95, t);
			float band = hn - (-0.15 + 0.9 * k * k) + 0.1 * sin(t * 18.0);
			float a1 = smoothstep(0.35, -0.35, band) * smoothstep(0.18, 0.4, t);
			vec3 g = mix(stripe_col, stripe2_col, smoothstep(-0.8, 0.6, hn));
			g = mix(g, stripe3_col, smoothstep(0.55, 0.95, t) * 0.6);
			col = mix(col, g, a1 * (1.0 - belly));
			vec2 sp = vec2(lpos.z * 1.6, hn * fuse_rh * 1.6);
			float star = step(0.985, hash12(floor(sp))) * fill(length(fract(sp) - 0.5) - 0.12);
			col = mix(col, vec3(1.0, 0.95, 0.8), star * a1 * (1.0 - belly));
		}
		// ---- tail cone
		col = mix(col, col * 0.55, smoothstep(0.985, 1.0, t) * 0.6);
		float zz = lpos.z;
		float yy = lpos.y;
		// ---- panel lines and rivets
		if (detail > 0.0) {
			float zr = zz - nose_z;
			float fz = fract(zr / 2.667);
			float joint = line(min(fz, 1.0 - fz) * 2.667, 0.0018) * step(0.07, t) * step(t, 0.93);
			float arc = acos(clamp(hn, -1.0, 1.0)) * fuse_rh;
			float lap = line(abs(arc - 1.15 * fuse_rh) , 0.0015) + line(abs(arc - 2.35 * fuse_rh), 0.0015);
			float fr = fract(zr / 0.5334);
			float rivet_row = line(min(fr, 1.0 - fr) * 0.5334, 0.003);
			float rv = fract(arc / 0.035);
			float rivets = rivet_row * smoothstep(0.32, 0.18, abs(rv - 0.5) ) * 0.5;
			float pl = clamp(joint * 0.5 + lap * 0.35 + rivets * 0.25, 0.0, 1.0) * detail;
			col *= 1.0 - pl * 0.35;
		}
		// ---- passenger windows
		if (abs(lpos.x) > fuse_rw * 0.3 && zz > win_range.x - 0.5 && zz < win_range.y + 0.5 && win.w > 0.0) {
			float k = floor((zz - win_range.x) / win.w + 0.5);
			float wz = win_range.x + k * win.w;
			float ok = step(-0.5, k) * step(wz, win_range.y + 0.01);
			for (int i = 0; i < 4; i++) {
				ok *= step(0.76, abs(wz - door_z[i]));
				ok *= step(0.55, abs(wz - exit_z[i]));
			}
			if (ok > 0.5) {
				vec2 q = vec2(zz - wz, yy - win.x);
				float d = sd_window(q, win.zy, win_shape);
				float glass = fill(d);
				float seal = fill(d - 0.022) * (1.0 - glass);
				float rim = fill(d - 0.045) * (1.0 - glass - seal);
				col = mix(col, col * 0.82, rim * 0.6);
				col = mix(col, vec3(0.32, 0.33, 0.35), seal);
				float shade = step(0.86, hash12(vec2(k, side * 3.1)));
				vec3 gl = mix(vec3(0.006, 0.008, 0.011), vec3(0.03, 0.032, 0.036), shade);
				col = mix(col, gl, glass);
				rough = mix(rough, 0.04, glass + seal * 0.5);
				cc = mix(cc, 0.0, glass);
				spec = mix(spec, 0.65, glass);
				float lit = (0.65 + 0.35 * hash12(vec2(k * 1.7, side))) * (1.0 - shade * 0.85);
				emit += glass * cabin_lights * vec3(1.0, 0.8, 0.52) * 1.6 * lit;
			}
		}
		// ---- passenger / service doors (both sides)
		for (int i = 0; i < 4; i++) {
			if (door_z[i] < -1e3) continue;
			vec2 q = vec2(zz - door_z[i], yy - (floor_y + door_h * 0.5 + 0.03));
			if (abs(q.x) > 1.5 || abs(q.y) > 1.6) continue;
			float d = sd_rbox(q, vec2(door_w[i] + 0.035, door_h * 0.5 + 0.05), 0.17);
			float gap = line(d, 0.007);
			float inside = fill(d);
			if (i == 0 && side < 0.0 && door_open > 0.01) {
				vec3 hole = mix(vec3(0.012), vec3(0.06, 0.05, 0.04), smoothstep(0.6, -0.9, q.y));
				col = mix(col, hole, inside * door_open);
				rough = mix(rough, 0.9, inside * door_open);
				cc = mix(cc, 0.0, inside * door_open);
				emit += inside * door_open * cabin_lights * vec3(0.12, 0.1, 0.07) * smoothstep(1.0, -0.6, q.y);
				continue;
			}
			col = mix(col, col * 0.18, gap);
			// porthole
			float pw = length(vec2(q.x, yy - win.x - 0.05)) - 0.1;
			col = mix(col, vec3(0.32, 0.33, 0.35), fill(pw - 0.02) * (1.0 - fill(pw)) * inside);
			col = mix(col, vec3(0.008, 0.01, 0.013), fill(pw) * inside);
			emit += fill(pw) * inside * cabin_lights * vec3(1.0, 0.8, 0.52) * 0.8;
			// handle recess and arming marker
			float hd = sd_rbox(vec2(q.x, yy - (floor_y + 1.05)), vec2(0.13, 0.045), 0.02);
			col = mix(col, col * 0.45, fill(hd) * inside);
			float mk = sd_rbox(vec2(q.x - 0.22 * side, yy - (floor_y + 1.32)), vec2(0.045, 0.035), 0.008);
			col = mix(col, vec3(0.7, 0.06, 0.04), fill(mk) * inside * detail);
		}
		// overwing exits
		for (int i = 0; i < 4; i++) {
			if (exit_z[i] < -1e3) continue;
			vec2 q = vec2(zz - exit_z[i], yy - (floor_y + 0.83));
			if (abs(q.x) > 0.8 || abs(q.y) > 0.9) continue;
			float d = sd_rbox(q, vec2(0.28, 0.5), 0.1);
			col = mix(col, col * 0.2, line(d, 0.006));
			// red handle marker
			float hm = sd_rbox(vec2(q.x, yy - (floor_y + 1.25)), vec2(0.06, 0.02), 0.01);
			col = mix(col, vec3(0.65, 0.05, 0.04), fill(hm) * detail);
			// the exit keeps a window
			vec2 wq = vec2(zz - exit_z[i], yy - win.x);
			float wd = sd_window(wq, win.zy, win_shape);
			float glass = fill(wd);
			col = mix(col, vec3(0.32, 0.33, 0.35), fill(wd - 0.022) * (1.0 - glass));
			col = mix(col, vec3(0.006, 0.008, 0.011), glass);
			rough = mix(rough, 0.04, glass);
			cc = mix(cc, 0.0, glass);
			emit += glass * cabin_lights * vec3(1.0, 0.8, 0.52) * 1.4;
		}
		// lower deck cargo doors (right side)
		if (side > 0.0) {
			for (int i = 0; i < 4; i++) {
				if (cargo_z[i] < -1e3) continue;
				vec2 q = vec2(zz - cargo_z[i], yy - (floor_y - cargo_h * 0.5 - 0.3));
				if (abs(q.x) > cargo_w[i] + 0.4 || abs(q.y) > cargo_h) continue;
				float d = sd_rbox(q, vec2(cargo_w[i], cargo_h * 0.5), 0.14);
				col = mix(col, col * 0.2, line(d, 0.007));
				float hd = sd_rbox(q - vec2(0.0, -cargo_h * 0.33), vec2(0.12, 0.04), 0.02);
				col = mix(col, col * 0.4, fill(hd));
			}
		}
		// freighter main deck door (left side) and visor nose split
		if (main_door.x > -1e3 && side < 0.0) {
			vec2 q = vec2(zz - main_door.x, yy - main_door.w);
			float d = sd_rbox(q, main_door.yz, 0.2);
			col = mix(col, col * 0.2, line(d, 0.008));
		}
		if (nose_door > -1e3) {
			float d = zz - nose_door + 0.12 * (1.0 - hn);
			col = mix(col, col * 0.2, line(d, 0.007) * step(-0.75, hn));
		}
		// static ports in their red RVSM outlines
		{
			vec2 q = vec2(zz - static_port.x, yy - static_port.y);
			float d = sd_rbox(q, vec2(0.28, 0.16), 0.03);
			col = mix(col, vec3(0.75, 0.08, 0.06), line(d, 0.008) * detail);
			float pd = min(length(q - vec2(-0.09, 0.0)), length(q - vec2(0.09, 0.0))) - 0.035;
			col = mix(col, vec3(0.45, 0.46, 0.47), fill(pd) * detail);
			col = mix(col, vec3(0.05), fill(length(q - vec2(-0.09, 0.0)) - 0.008) * detail);
		}
		// ---- flight deck glazing
		if (zz < cockpit_z1 && pane_count > 0) {
			vec3 q3 = vec3(abs(lpos.x), lpos.y, lpos.z);
			float d = 1e3;
			for (int i = 0; i < pane_count; i++) {
				vec3 r = q3 - pane_o[i];
				vec3 pn = cross(pane_u[i], pane_v[i]);
				if (abs(dot(r, pn)) > 0.3) continue;
				vec2 s = vec2(dot(r, pane_u[i]), dot(r, pane_v[i]));
				d = min(d, sd_quad(s, pane_a[i].xy, pane_a[i].zw, pane_b[i].xy, pane_b[i].zw) - pane_r[i]);
			}
			if (d < 0.5) {
				float glass = fill(d);
				float seal = fill(d - 0.03) * (1.0 - glass);
				float frame = fill(d - 0.075) * (1.0 - glass - seal);
				float mk = mask * fill(d - 0.2);
				col = mix(col, vec3(0.012, 0.013, 0.015), max(mk, 0.0));
				col = mix(col, col * 0.75, frame * (1.0 - mask));
				col = mix(col, vec3(0.025, 0.026, 0.028), seal);
				float refl = smoothstep(-0.25, 0.2, yy - win.x);
				vec3 gc = mix(vec3(0.004, 0.006, 0.01), vec3(0.012, 0.016, 0.024), refl);
				col = mix(col, gc, glass);
				rough = mix(rough, 0.02, glass);
				spec = mix(spec, 0.75, glass);
				cc = mix(cc, 0.0, glass);
				rough = mix(rough, 0.35, seal);
				emit += glass * deck_glow * vec3(0.03, 0.05, 0.08);
			}
		}
		// ---- wheel wells open while the gear is down
		if (gear_down > 0.01 && hn < -0.5) {
			float wm = fill(sd_rbox(vec2(abs(lpos.x) - main_well.x, zz - main_well.z), main_well.yw, 0.3));
			float wn = fill(sd_rbox(vec2(lpos.x, zz - nose_well.y), vec2(nose_well.x, nose_well.z), 0.1));
			float wl = max(wm, wn) * smoothstep(0.0, 0.3, gear_down);
			col = mix(col, vec3(0.045, 0.047, 0.046), wl);
			rough = mix(rough, 0.8, wl);
			cc = mix(cc, 0.0, wl);
			ao *= 1.0 - 0.6 * wl;
		}
		// ---- weathering
		dirt_k = smoothstep(-0.45, -0.95, hn) * (0.4 + 0.6 * t) + smoothstep(0.975, 1.0, t) * 0.8;
	} else if (pid == P_WING || pid == P_STAB) {
		col = wing_body > 0.5 ? body_col : wing_col;
		rough = 0.36;
		cc = 0.25;
		float x = UV.x;
		float sp = UV.y;
		float upper = COLOR.g;
		// metallic leading edge
		float le = 1.0 - smoothstep(0.02, 0.05, x);
		if (boots > 0.5) {
			col = mix(col, vec3(0.02), 1.0 - smoothstep(0.075, 0.085, x));
			rough = mix(rough, 0.75, 1.0 - smoothstep(0.075, 0.085, x));
		} else {
			col = mix(col, vec3(0.72, 0.73, 0.75), le * 0.8);
			metal = mix(metal, 0.85, le * 0.8);
			rough = mix(rough, 0.22, le);
		}
		if (detail > 0.0) {
			// spar lines, rib rivets and skin joints
			float pl = line(x - 0.155, 0.002) + line(x - 0.62, 0.002) * upper;
			float rib = fract(UV2.x / 0.62);
			pl += line(min(rib, 1.0 - rib) * 0.62, 0.0015) * 0.5;
			float jt = fract(UV2.x / 3.1 + 0.3);
			pl += line(min(jt, 1.0 - jt) * 3.1, 0.002);
			col *= 1.0 - clamp(pl, 0.0, 1.0) * 0.3 * detail;
		}
		if (pid == P_WING && upper > 0.5 && wing_body < 0.5) {
			// walkway on the inner wing
			float ww = step(0.08, sp) * step(sp, 0.3) * step(0.24, x) * step(x, 0.6);
			col = mix(col, col * 0.82, ww);
			float edge = line(sd_rbox(vec2(x - 0.42, sp - 0.19), vec2(0.18, 0.11), 0.0), 0.0012 * 6.0);
			col = mix(col, vec3(0.05), edge * 0.5 * detail);
		}
		if (upper < 0.5) {
			col *= 0.92;
			dirt_k = 0.5;
		}
	} else if (pid == P_TAIL) {
		col = tail_col;
		rough = 0.24;
		cc = 0.6;
		float side = COLOR.b > 0.5 ? 1.0 : -1.0;
		vec2 bp = UV2;     // body z, y
		float span = UV.y;
		float h = bp.y - fin_geo.y;
		// root band in body colour
		col = mix(col, body_col, fill(h - tail_band * fin_geo.z) * step(0.001, tail_band));
		vec2 a = vec2(-(bp.x - logo_xf.x), bp.y - logo_xf.y) / logo_xf.z;
		vec2 s = vec2(-side * (bp.x - logo_xf.x), bp.y - logo_xf.y) / logo_xf.z;
		vec2 w = fin_art(a, s, span);
		col = mix(col, art_col, w.y);
		col = mix(col, logo_col, w.x);
		// logo lights wash the fin from the stabiliser
		emit += col * logo_light * 0.55 * smoothstep(1.0, 0.0, span) * smoothstep(-0.2, 0.25, span);
		dirt_k = 0.1;
	} else if (pid == P_NACELLE) {
		col = engine_col;
		rough = 0.22;
		cc = 0.55;
		float ax = UV.y;
		float ar = UV.x;
		if (engine_style == 1) {
			col = mix(col, engine2_col, step(0.03, ax) * step(ax, 0.16));
		} else if (engine_style == 2) {
			float a = abs(fract(ar + 0.25) - 0.5);
			float chev = abs(ax - 0.12 - a * 0.9) - 0.05;
			col = mix(col, engine2_col, fill(chev * 4.0) * step(a, 0.32));
		} else if (engine_style == 3) {
			col = mix(col, tail_col, step(ax, 0.1));
		}
		// fan cowl / reverser seams and the hinge line
		if (detail > 0.0) {
			float sm = line(ax - 0.2, 0.0015) + line(ax - 0.56, 0.0012) + line(abs(fract(ar + 0.5) - 0.5) - 0.002, 0.0006) * 0.6;
			col *= 1.0 - clamp(sm, 0.0, 1.0) * 0.45 * detail;
		}
		dirt_k = smoothstep(0.6, 1.0, ax) * 0.8;
	} else if (pid == P_LIP) {
		col = vec3(0.86, 0.87, 0.89);
		metal = 1.0;
		rough = 0.1 + 0.05 * vnoise(UV * vec2(40.0, 4.0));
	} else if (pid == P_INLET) {
		col = vec3(0.42, 0.43, 0.45);
		metal = 0.35;
		rough = 0.45;
		float ax = UV.y;
		col = mix(col, vec3(0.18, 0.18, 0.19), smoothstep(0.55, 1.0, ax));
		// acoustic liner panel joints
		col *= 1.0 - line(abs(fract(UV.x * 12.0) - 0.5) - 0.48, 0.002) * 0.3;
	} else if (pid == P_FAN) {
		col = vec3(0.16, 0.17, 0.19);
		metal = 0.8;
		rough = 0.28;
		col = mix(col, vec3(0.55, 0.56, 0.58), smoothstep(0.08, 0.0, UV.x));
	} else if (pid == P_SPINNER) {
		col = vec3(0.02, 0.022, 0.025);
		rough = 0.2;
		cc = 0.8;
		float sw = abs(fract(UV.x + UV.y * 0.9) - 0.5) - 0.035;
		col = mix(col, vec3(0.92), fill(sw * 0.5) * step(0.12, UV.y) * step(UV.y, 0.93));
		col = mix(col, vec3(0.6, 0.61, 0.63), step(0.93, UV.y));
	} else if (pid == P_EXHAUST) {
		col = vec3(0.38, 0.37, 0.36);
		metal = 0.85;
		rough = 0.38;
		col = mix(col, vec3(0.24, 0.2, 0.17), smoothstep(0.4, 1.0, UV.y));
		dirt_k = 0.3;
	} else if (pid == P_PLUG) {
		col = vec3(0.17, 0.15, 0.13);
		metal = 0.7;
		rough = 0.55;
	} else if (pid == P_METAL) {
		col = vec3(0.6, 0.61, 0.63);
		metal = 0.85;
		rough = 0.3;
	} else if (pid == P_DARK) {
		col = vec3(0.03, 0.03, 0.033);
		rough = 0.7;
	} else if (pid == P_GLASS) {
		col = vec3(0.01, 0.012, 0.016);
		rough = 0.03;
		spec = 0.7;
	} else if (pid == P_GEAR) {
		col = gear_col;
		rough = 0.42;
		cc = 0.2;
		dirt_k = 0.6;
	} else if (pid == P_CHROME) {
		col = vec3(0.92, 0.93, 0.95);
		metal = 1.0;
		rough = 0.06;
	} else if (pid == P_TYRE) {
		col = vec3(0.028, 0.028, 0.03);
		rough = 0.82;
		float pr = UV.y;
		// tread grooves across the crown, a slightly glossier sidewall
		float tread = step(0.3, pr) * step(pr, 0.7);
		float g = abs(fract((pr - 0.3) / 0.4 * 4.0) - 0.5);
		col = mix(col, vec3(0.012), tread * fill(0.06 - g) * detail);
		rough = mix(rough, 0.6, 1.0 - tread);
		col = mix(col, vec3(0.045, 0.045, 0.047), (1.0 - tread) * 0.5);
	} else if (pid == P_HUB) {
		col = vec3(0.58, 0.59, 0.6);
		metal = 0.6;
		rough = 0.35;
		dirt_k = 0.7;
	} else if (pid == P_BELLY) {
		col = belly_col;
		rough = 0.26;
		cc = 0.5;
		if (metal_belly > 0.5) {
			metal = 0.9;
			rough = 0.22;
			cc = 0.0;
		}
		dirt_k = 0.5;
	} else if (pid == P_FLAT) {
		col = body_col;
		rough = 0.24;
		cc = 0.6;
	} else if (pid == P_WINGLET) {
		col = tip_col;
		rough = 0.24;
		cc = 0.6;
		vec2 bp = UV2;
		float span = UV.y;
		float side = COLOR.b > 0.5 ? 1.0 : -1.0;
		// small logo near the top of the winglet
		vec2 a = vec2(0.0, 0.0);
		float lg = fill(length(vec2(UV.x - 0.45, (span - 0.62) * 1.6)) - 0.16) * step(COLOR.g, 0.5);
		col = mix(col, logo_col, lg);
	} else if (pid == P_LENS) {
		vec3 tint = vec3(0.95);
		float hue = COLOR.g;
		if (hue > 0.15 && hue < 0.4) tint = vec3(0.9, 0.05, 0.03);
		else if (hue >= 0.4 && hue < 0.65) tint = vec3(0.05, 0.8, 0.2);
		else if (hue >= 0.65) tint = vec3(1.0, 0.55, 0.1);
		col = tint * 0.35;
		rough = 0.05;
		spec = 0.8;
		cc = 0.0;
	} else if (pid == P_WELL) {
		col = vec3(0.16, 0.17, 0.165);
		rough = 0.7;
		ao *= 0.6;
	} else if (pid == P_PROP) {
		col = vec3(0.03, 0.03, 0.032);
		rough = 0.45;
		float tip = smoothstep(0.9, 0.92, UV.y);
		col = mix(col, vec3(0.95, 0.75, 0.05), tip);
	} else if (pid == P_BOOT) {
		col = vec3(0.02);
		rough = 0.75;
	} else if (pid == P_PYLON) {
		col = wing_col * 0.95;
		rough = 0.35;
		cc = 0.3;
		col = mix(col, vec3(0.3, 0.29, 0.28), step(0.75, UV.y) * 0.7);
		metal = mix(metal, 0.6, step(0.75, UV.y));
	}
	// subtle large-scale paint variation, grime and fire damage
	float n = vnoise(lpos.xz * 0.35 + lpos.y * 0.2);
	col *= 0.97 + 0.06 * n;
	float grime = dirt * dirt_k * (0.5 + 0.5 * vnoise(lpos.zx * vec2(0.6, 3.0)));
	col = mix(col, col * vec3(0.55, 0.5, 0.45), clamp(grime, 0.0, 0.6));
	rough = mix(rough, 0.6, clamp(grime, 0.0, 1.0) * 0.5);
	col = mix(col, vec3(0.03, 0.025, 0.02), scorch * smoothstep(0.3, 0.8, hash12(floor(lpos.xz * 1.3) + 7.0)));
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	CLEARCOAT = cc;
	CLEARCOAT_ROUGHNESS = 0.08;
	EMISSION = emit;
	AO = ao;
	AO_LIGHT_AFFECT = 0.25;
}
