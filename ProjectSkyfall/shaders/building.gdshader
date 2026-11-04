shader_type spatial;
render_mode cull_back;

// Instanced city buildings (unit meshes scaled per instance). INSTANCE_CUSTOM.rgb = facade colour,
// .a = (roof family or ground plate type + random seed) / 8.
// Vertex colour r = facade kind: 0.05 ground plate, 0.12 wooden house, 0.2 house, 0.28 brick,
// 0.42 stone (Haussmann), 0.5 glass curtain wall, 0.6 residential tower, 0.68 concrete panel,
// 0.78 shed, 0.88 stucco, 1.0 office. Vertex colour a = surface: 0 flat roof, 0.12 water,
// 0.25 rooftop plant, 0.37 ground plate top, 0.5 pitched roof, 0.62 mansard, 0.8 trim, 1 wall.
// Roof families: 0 terracotta, 1 slate, 2 zinc, 3 brown tile, 4 dark glazed, 5 light metal,
// 6 shingle, 7 painted Nordic metal. Plate types: 0 lot, 1 park, 2 plaza, 3 canal, 4 boulevard.
uniform float night = 0.0;
uniform int region = 0;          // 0 default, 1 neon signage (East Asian cities, Las Vegas)

varying vec3 lpos;
varying vec3 onrm;
varying vec3 facade;
varying vec3 vsc;
varying float seed;
varying float fam;
varying vec2 vkind;
varying vec3 v_cam;              // camera position in the instance's frame, in metres

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 roof_color(float id, float sd) {
	vec3 c;
	if (id < 0.5) c = mix(vec3(0.6, 0.28, 0.17), vec3(0.74, 0.42, 0.26), sd);
	else if (id < 1.5) c = mix(vec3(0.2, 0.21, 0.24), vec3(0.3, 0.3, 0.32), sd);
	else if (id < 2.5) c = mix(vec3(0.4, 0.44, 0.48), vec3(0.5, 0.53, 0.56), sd);
	else if (id < 3.5) c = mix(vec3(0.36, 0.22, 0.15), vec3(0.48, 0.3, 0.2), sd);
	else if (id < 4.5) c = mix(vec3(0.15, 0.17, 0.21), vec3(0.26, 0.28, 0.31), sd);
	else if (id < 5.5) c = mix(vec3(0.55, 0.57, 0.59), vec3(0.7, 0.71, 0.71), sd);
	else if (id < 6.5) c = mix(vec3(0.24, 0.23, 0.22), vec3(0.42, 0.36, 0.3), sd);
	else c = sd < 0.3 ? vec3(0.62, 0.12, 0.1) : (sd < 0.55 ? vec3(0.16, 0.32, 0.24) : (sd < 0.8 ? vec3(0.12, 0.12, 0.13) : vec3(0.2, 0.3, 0.52)));
	return pow(c, vec3(2.2));
}

// Interior mapping: the room behind a window cell, traced in the facade's frame. p = point on the
// facade (local metres), rd = view ray, n = outward normal, t = facade tangent, cw x fh = room
// width x storey height, depth = room depth. office 1 adds desks and screens. lit = ceiling on.
vec3 room(vec3 p, vec3 rd, vec3 n, vec3 t, float cw, float fh, float depth, float sd, float lit_p, float office, out float lit) {
	float u = dot(p, t);
	float v = p.y;
	float du = dot(rd, t);
	float dv = rd.y;
	float dn = max(-dot(rd, n), 0.05);
	vec2 cell = vec2(floor(u / cw), floor(v / fh));
	float u0 = cell.x * cw;
	float v0 = cell.y * fh;
	float tb = depth / dn;
	float ts = du > 0.0 ? (u0 + cw - u) / max(du, 1e-4) : (u0 - u) / min(du, -1e-4);
	float tv = dv > 0.0 ? (v0 + fh - v) / max(dv, 1e-4) : (v0 - v) / min(dv, -1e-4);
	float tt = min(tb, min(ts, tv));
	vec3 h = vec3(u + du * tt - u0, v + dv * tt - v0, dn * tt);
	float r1 = hash12(cell + sd * 41.0);
	float r2 = hash12(cell * 1.7 + sd * 17.0);
	float r3 = hash12(cell * 2.3 + sd * 7.0);
	lit = step(1.0 - lit_p, r1);
	// each room its own decor: white offices, warm timber, grey meeting rooms, coloured feature walls
	vec3 wall = r2 < 0.4 ? vec3(0.86, 0.85, 0.82) : (r2 < 0.6 ? vec3(0.62, 0.5, 0.38) : (r2 < 0.8 ? vec3(0.55, 0.58, 0.62) : vec3(0.3, 0.42, 0.55)));
	vec3 c;
	if (tt == tv && dv > 0.0) {
		// ceiling: acoustic tiles and rows of light panels
		vec2 g = fract(vec2(h.x / 1.2, h.z / 1.2));
		float grid = step(0.94, max(g.x, g.y));
		float panel = step(0.25, g.x) * step(g.x, 0.75) * step(0.3, g.y) * step(g.y, 0.7) * step(0.5, fract(h.z / 2.4));
		c = vec3(0.9) * (1.0 - grid * 0.25);
		c = mix(c, mix(vec3(1.0), vec3(2.2, 2.1, 1.85), lit * night), panel);
	} else if (tt == tv) {
		// floor: carpet tiles or timber boards
		float boards = step(0.5, r3) * step(0.92, fract(h.z / 0.2));
		c = mix(mix(vec3(0.16, 0.17, 0.2), vec3(0.24, 0.2, 0.17), step(0.5, r3)), vec3(0.08), boards);
	} else if (tt == ts) {
		c = wall * 0.6;
		// a picture, a cabinet or a door on the side wall
		float art = step(abs(h.z - depth * 0.5), depth * 0.16) * step(1.2, h.y) * step(h.y, 2.0);
		c = mix(c, mix(vec3(0.6, 0.25, 0.15), vec3(0.15, 0.3, 0.45), r3), art * 0.9);
		c = mix(c, vec3(0.32, 0.24, 0.18), step(abs(h.z - depth * 0.8), 0.5) * step(h.y, 2.1) * office);
	} else {
		c = wall * 0.85;
		float bx = fract(h.x / cw * 2.0);
		// desks with partitions and glowing screens in offices
		float desk = step(0.7, h.y) * step(h.y, 0.76) * step(0.08, bx) * step(bx, 0.92);
		float part = step(0.76, h.y) * step(h.y, 1.25) * step(0.48, bx) * step(bx, 0.52);
		float base = step(h.y, 0.7) * (step(0.1, bx) * step(bx, 0.14) + step(0.86, bx) * step(bx, 0.9));
		c = mix(c, vec3(0.2, 0.17, 0.14), clamp(desk + part + base, 0.0, 1.0) * office);
		float screen = step(0.8, h.y) * step(h.y, 1.16) * step(0.22, bx) * step(bx, 0.42) * office;
		c = mix(c, mix(vec3(0.06, 0.08, 0.1), vec3(0.45, 0.65, 1.1), lit * night), screen);
		// bookcase or kitchen units along the back of the flats, a sofa, a lamp
		float units = step(h.y, 2.0) * step(0.62, bx) * step(bx, 0.98) * (1.0 - office);
		c = mix(c, mix(vec3(0.35, 0.26, 0.18), vec3(0.85, 0.85, 0.82), step(0.5, r3)), units * 0.85);
		c = mix(c, mix(vec3(0.3, 0.18, 0.14), vec3(0.18, 0.24, 0.32), r1), step(h.y, 0.82) * step(0.06, bx) * step(bx, 0.55) * (1.0 - office));
		float lamp = (1.0 - smoothstep(0.0, 0.16, length(vec2(bx - 0.58, h.y - 1.5)))) * (1.0 - office);
		c = mix(c, mix(vec3(0.6, 0.55, 0.45), vec3(2.4, 1.9, 1.2), lit * night), lamp);
		// someone in the room now and then
		float pr = hash12(cell + sd * 5.0);
		float px = fract(pr * 7.0) * max(cw - 0.8, 0.2) + 0.4;
		float body = step(abs(h.x - px), 0.21) * step(h.y, 1.42) * step(0.2, h.y);
		float head = 1.0 - step(0.13, length(vec2(h.x - px, h.y - 1.56)));
		c = mix(c, mix(vec3(0.08, 0.08, 0.1), vec3(0.3, 0.12, 0.1), step(0.6, r3)), clamp(body + head, 0.0, 1.0) * step(pr, 0.4));
	}
	// soft shadow in the corners and the room getting darker toward the back
	float corner = smoothstep(0.0, 0.35, min(min(h.x, cw - h.x), min(h.y, fh - h.y)));
	c *= mix(0.55, 1.0, corner);
	return c * (1.0 - 0.55 * clamp(h.z / depth, 0.0, 1.0));
}

vec3 sign_col(float r) {
	return r < 0.18 ? vec3(1.0, 0.12, 0.3) : (r < 0.34 ? vec3(0.1, 0.9, 1.0) : (r < 0.5 ? vec3(1.0, 0.85, 0.15)
		: (r < 0.64 ? vec3(0.2, 1.0, 0.35) : (r < 0.8 ? vec3(1.0, 0.45, 0.1) : (r < 0.9 ? vec3(0.75, 0.3, 1.0) : vec3(1.0))))));
}

vec3 house_tint(vec3 base, float fx, float sd) {
	// houses packed three to an instance each get their own paint
	float third = floor(clamp(fx + 0.5, 0.0, 0.999) * 3.0);
	float h = hash12(vec2(third * 7.0 + 1.0, sd * 113.0));
	vec3 alt = h < 0.2 ? vec3(0.85, 0.84, 0.8) : (h < 0.4 ? vec3(0.78, 0.68, 0.5) : (h < 0.55 ? vec3(0.55, 0.62, 0.68) : (h < 0.7 ? vec3(0.45, 0.2, 0.14) : base)));
	return mix(base, alt, 0.65);
}

void vertex() {
	onrm = NORMAL;
	if (UV2.x > 0.5) {
		// merged ground plates (one plain mesh per chunk): UV = metres from the plate centre,
		// UV2 = plate size, COLOR.rgb = lot colour, COLOR.a = plate type / 8
		lpos = vec3(UV.x, VERTEX.y, UV.y);
		vsc = vec3(UV2.x, 1.0, UV2.y);
		facade = pow(COLOR.rgb, vec3(2.2));
		fam = floor(COLOR.a * 8.0);
		seed = 0.5;
		vkind = vec2(0.05, NORMAL.y > 0.5 ? 0.37 : 1.0);
		v_cam = vec3(0.0);
	} else {
		vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
		facade = pow(INSTANCE_CUSTOM.rgb, vec3(2.2));
		float ra = clamp(INSTANCE_CUSTOM.a, 0.0, 0.9999) * 8.0;
		fam = floor(ra);
		seed = fract(ra);
		vkind = vec2(COLOR.r, COLOR.a);
		// no two skylines alike: some tall glass towers twist or taper as they rise
		if (COLOR.r > 0.46 && COLOR.r < 0.54 && sc.y > 70.0) {
			float hs = fract(seed * 17.13);
			float y01 = clamp(VERTEX.y, 0.0, 1.0);
			if (hs < 0.22) {
				float ang = (fract(seed * 5.3) - 0.5) * 1.7 * smoothstep(0.1, 1.0, y01);
				mat2 rm = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang)));
				VERTEX.xz = rm * VERTEX.xz;
				NORMAL.xz = rm * NORMAL.xz;
			} else if (hs < 0.42) {
				VERTEX.xz *= 1.0 - (0.12 + 0.22 * fract(seed * 9.1)) * smoothstep(0.1, 1.0, y01);
			}
		}
		onrm = NORMAL;
		lpos = VERTEX * sc;
		vsc = sc;
		vec3 cam_m = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
		v_cam = cam_m * sc;
	}
}

void fragment() {
	vec3 col = facade;
	vec3 emit = vec3(0.0);
	float rough = 0.85;
	float metal = 0.0;
	float surf = vkind.y;
	float kind = vkind.x;
	float fine = 1.0 - smoothstep(0.15, 0.6, length(fwidth(lpos)));   // small detail fades with distance
	if (surf < 0.06) {
		// flat roof: gravel and membrane, light on whitewashed and sandy cities
		col = mix(vec3(0.15, 0.15, 0.16), facade * 0.85, 0.4);
		col *= 0.9 + 0.2 * hash12(floor(lpos.xz * 0.5));
	} else if (surf < 0.18) {
		// water: canal or pool
		col = (fam > 2.5 && fam < 3.5) || kind < 0.08 ? vec3(0.03, 0.07, 0.08) : vec3(0.05, 0.3, 0.38);
		col *= 0.9 + 0.2 * sin(lpos.x * 0.7 + lpos.z * 0.4 + TIME) * fine;
		rough = 0.06;
		metal = 0.3;
	} else if (surf < 0.31) {
		// rooftop plant: grey metal boxes, chimneys, masts, water tanks
		col = vec3(0.45, 0.46, 0.47);
		rough = 0.5;
		metal = 0.4;
	} else if (surf < 0.44) {
		// ground plate: half a street at the edge, kerb and pavement, then the lot
		float ex = vsc.x * 0.5 - abs(lpos.x);
		float ez = vsc.z * 0.5 - abs(lpos.z);
		float e = min(ex, ez);
		float along = ex < ez ? lpos.z : lpos.x;
		float sh = clamp(min(vsc.x, vsc.z) * 0.06, 3.5, 8.0);
		vec3 asphalt = vec3(0.07, 0.07, 0.075) * (0.9 + 0.2 * hash12(floor(lpos.xz * 0.3)));
		vec3 pave = vec3(0.36, 0.35, 0.33);
		vec3 lot = facade * (0.85 + 0.25 * hash12(floor(lpos.xz * 0.12)));
		if (fam > 0.5 && fam < 1.5) {
			// park: lawn with gravel paths
			lot = mix(vec3(0.07, 0.15, 0.04), vec3(0.11, 0.2, 0.05), hash12(floor(lpos.xz * 0.08)));
			float path = min(abs(lpos.x - lpos.z * vsc.x / vsc.z), abs(lpos.x + lpos.z * vsc.x / vsc.z));
			path = min(path, min(abs(lpos.x), abs(lpos.z)));
			lot = mix(lot, vec3(0.42, 0.38, 0.3), 1.0 - smoothstep(1.2, 1.8, path));
		} else if (fam > 1.5 && fam < 2.5) {
			// plaza: stone flags
			vec2 fl = fract(lpos.xz / 4.0);
			lot = facade * (0.9 + 0.1 * hash12(floor(lpos.xz / 4.0))) * mix(0.8, 1.0, step(0.06, min(fl.x, fl.y)) * fine + (1.0 - fine));
		} else if (fam > 2.5 && fam < 3.5) {
			// canal
			lot = vec3(0.025, 0.06, 0.065);
			rough = 0.06;
			metal = 0.3;
		} else if (fam > 3.5 && fam < 4.5) {
			// boulevard: gravel alleys under the trees
			lot = vec3(0.42, 0.38, 0.32) * (0.9 + 0.1 * hash12(floor(lpos.xz)));
		}
		float is_street = 1.0 - step(sh, e);
		float is_pave = step(sh, e) * (1.0 - step(sh + 2.8, e));
		col = mix(lot, pave, is_pave);
		col = mix(col, asphalt, is_street);
		if (fam < 2.5 || fam > 3.5) {
			// centre line dashes and kerb
			float dash = (1.0 - step(0.15, e)) * step(0.5, fract(along / 9.0)) * step(5.0, sh) * fine;
			col = mix(col, vec3(0.6, 0.58, 0.5), dash);
			col = mix(col, vec3(0.5, 0.5, 0.48), (1.0 - smoothstep(0.0, 0.3, abs(e - sh))) * fine);
		}
		if (fam < 2.5 || fam > 3.5) rough = 0.9;
		// street lamps along the kerb and their pools of light
		float lamp = (1.0 - smoothstep(0.0, 0.7, abs(e - sh - 0.5))) * (1.0 - smoothstep(0.0, 0.05, abs(fract(along / 26.0) - 0.5) - 0.0));
		float pool = (1.0 - smoothstep(0.0, 6.0, abs(e - sh))) * (1.0 - smoothstep(0.0, 0.3, abs(fract(along / 26.0) - 0.5)));
		emit = night * (lamp * vec3(1.0, 0.8, 0.5) * 3.0 + pool * vec3(1.0, 0.75, 0.45) * 0.08);
		if (onrm.y < 0.5) {
			// plate sides: stone retaining wall
			col = vec3(0.3, 0.29, 0.27) * (0.85 + 0.15 * hash12(floor(lpos.xy * vec2(0.5, 1.0))));
			emit = vec3(0.0);
		}
	} else if (surf < 0.56) {
		// pitched roof: tiles, slate or metal sheet
		vec3 tiles = roof_color(fam, fract(seed * 7.31));
		float courses = (fam > 4.5 && fam < 5.5) || fam > 6.5 ? abs(fract((abs(onrm.x) > abs(onrm.z) ? lpos.z : lpos.x) / 0.9) - 0.5) * 2.0
			: abs(fract(lpos.y * 3.2) - 0.5) * 2.0;
		float course = smoothstep(0.35, 0.5, courses);
		col = tiles * (0.85 + 0.15 * mix(0.5, course, fine)) * (0.92 + 0.16 * hash12(floor(lpos.xz * 2.0)));
		rough = (fam > 4.5 && fam < 5.5) ? 0.45 : 0.75;
		metal = (fam > 4.5 && fam < 5.5) ? 0.4 : 0.0;
	} else if (surf < 0.68) {
		// mansard: zinc or slate with a row of dormer windows
		col = roof_color(fam, fract(seed * 5.7)) * (0.92 + 0.12 * hash12(floor(lpos.xz)));
		rough = 0.55;
		metal = 0.25;
		if (onrm.y < 0.9) {
			float u = abs(onrm.x) > abs(onrm.z) ? lpos.z : lpos.x;
			float dx = fract(u / 3.2);
			float dy = fract(lpos.y / 3.6);
			float dorm = step(0.36, dx) * step(dx, 0.64) * step(0.3, dy) * step(dy, 0.78);
			col = mix(col, vec3(0.05, 0.06, 0.08), dorm * 0.85);
			col = mix(col, vec3(0.85, 0.83, 0.78), (step(0.32, dx) - step(0.36, dx) + step(0.64, dx) - step(0.68, dx)) * step(0.3, dy) * step(dy, 0.86) * 0.8);
			emit = dorm * night * step(0.55, hash12(floor(vec2(u / 3.2, lpos.y / 3.6)) + seed * 31.0)) * vec3(1.0, 0.72, 0.42) * 1.2;
		}
	} else if (surf < 0.9) {
		// trim: cornices, parapets, chimney stacks, garden walls
		col = min(facade * 1.12, vec3(1.0));
		if (kind > 0.24 && kind < 0.34) col = facade * 0.85;
	} else if (onrm.y > -0.5 && onrm.y < 0.5) {
		vec3 ns = normalize(vec3(onrm.x / max(vsc.x, 0.01), 0.0, onrm.z / max(vsc.z, 0.01)));
		vec3 tg = vec3(-ns.z, 0.0, ns.x);
		float u = dot(lpos, tg);
		float v = lpos.y;
		vec3 rd = normalize(lpos - v_cam);
		// interiors show through the glass up close and fade to plain windows in the distance
		float ik = 1.0 - smoothstep(0.22, 0.55, length(fwidth(lpos)));
		float fres = 0.04 + 0.8 * pow(1.0 - clamp(dot(-rd, ns), 0.0, 1.0), 5.0);
		float rdepth = clamp(min(vsc.x, vsc.z) * 0.38, 3.0, 9.0);
		if (kind < 0.08) {
			col = vec3(0.3, 0.29, 0.27);
		} else if (kind < 0.16) {
			// wooden house: painted clapboard, white trim, two storeys of windows
			col = house_tint(col, lpos.x / vsc.x, seed);
			col *= 0.88 + 0.12 * mix(0.5, step(0.5, fract(v / 0.3)), fine);
			float wx = fract(u / 3.4);
			float wy = fract(v / 2.8);
			float win = step(0.3, wx) * step(wx, 0.66) * step(0.3, wy) * step(wy, 0.8) * step(0.5, v);
			float frame = (step(0.26, wx) * step(wx, 0.7) * step(0.24, wy) * step(wy, 0.86)) * (1.0 - win) * step(0.5, v);
			col = mix(col, vec3(0.88, 0.88, 0.85), frame);
			col = mix(col, vec3(0.04, 0.05, 0.07), win * 0.85);
			rough = mix(0.8, 0.2, win);
			emit = win * night * step(0.45, hash12(floor(vec2(u / 3.4, v / 2.8)) + seed * 71.0)) * vec3(1.0, 0.72, 0.42) * 1.3;
		} else if (kind < 0.24) {
			// house: two storeys of sash windows
			col = house_tint(col, lpos.x / vsc.x, seed);
			float wx = fract(u / 3.6);
			float wy = fract(v / 2.8);
			float win = step(0.3, wx) * step(wx, 0.7) * step(0.32, wy) * step(wy, 0.82) * step(0.4, v);
			vec2 cell = floor(vec2(u / 3.6, v / 2.8)) + seed * 71.0;
			col = mix(col, vec3(0.04, 0.05, 0.07), win * 0.85);
			col = mix(col, vec3(0.9), (step(0.27, wx) - step(0.3, wx) + step(0.7, wx) - step(0.73, wx)) * step(0.32, wy) * step(wy, 0.82) * step(0.4, v) * 0.8);
			rough = mix(0.9, 0.2, win);
			emit = win * night * step(0.45, hash12(cell)) * vec3(1.0, 0.72, 0.42) * 1.3;
		} else if (kind < 0.34) {
			// brick terrace and canal houses: brick courses, white sash windows, painted doors
			vec2 bc = vec2(u / 0.45 + floor(v / 0.16) * 0.5, v / 0.16);
			col *= mix(1.0, 0.86 + 0.2 * hash12(floor(bc)), fine);
			col *= mix(1.0, 0.82 + 0.18 * step(0.12, fract(bc.y)), fine);
			float wx = fract(u / 2.8);
			float wy = fract(v / 3.1);
			float win = step(0.3, wx) * step(wx, 0.7) * step(0.22, wy) * step(wy, 0.82) * step(3.0, v);
			float surround = step(0.26, wx) * step(wx, 0.74) * step(0.18, wy) * step(wy, 0.86) * step(3.0, v) * (1.0 - win);
			vec2 cell = floor(vec2(u / 2.8, v / 3.1)) + seed * 91.0;
			col = mix(col, vec3(0.85, 0.84, 0.8), surround);
			col = mix(col, vec3(0.04, 0.05, 0.07), win * 0.85);
			float gx = fract(u / 2.8);
			float door = step(v, 2.6) * step(0.3, gx) * step(gx, 0.62) * step(0.6, hash12(floor(vec2(u / 2.8, 0.0)) + seed * 7.0));
			col = mix(col, pow(vec3(0.1 + 0.5 * hash12(cell), 0.12, 0.1 + 0.4 * hash12(cell + 2.0)), vec3(1.0)), door);
			float gwin = step(v, 2.6) * step(0.6, v) * step(0.3, gx) * step(gx, 0.7) * (1.0 - door);
			col = mix(col, vec3(0.04, 0.05, 0.07), gwin * 0.85);
			rough = mix(0.9, 0.2, win + gwin);
			emit = (win + gwin) * night * step(0.5, hash12(cell)) * vec3(1.0, 0.72, 0.42) * 1.3;
		} else if (kind < 0.46) {
			// Haussmann stone: shopfronts, tall French windows, iron balconies on the 2nd and 5th floors
			col *= mix(1.0, 0.94 + 0.06 * step(0.08, fract(v / 0.55)), fine);
			vec2 cell = floor(vec2(u / 2.7, (v - 4.6) / 3.3)) + seed * 113.0;
			if (v < 4.6) {
				float sx = fract(u / 4.2);
				float shop = step(0.12, sx) * step(sx, 0.88) * step(0.4, v) * step(v, 3.9);
				col = mix(col * 0.9, vec3(0.05, 0.06, 0.07), shop * 0.9);
				emit = shop * night * vec3(1.0, 0.82, 0.55) * 1.2 * step(0.35, hash12(floor(vec2(u / 4.2, 0.0)) + seed * 17.0));
				rough = mix(0.85, 0.15, shop);
			} else {
				float wx = fract(u / 2.7);
				float wy = fract((v - 4.6) / 3.3);
				float win = step(0.32, wx) * step(wx, 0.68) * step(0.12, wy) * step(wy, 0.82);
				col = mix(col, vec3(0.05, 0.06, 0.08), win * 0.85);
				float b2 = 1.0 - step(0.22, abs(v - (4.6 + 3.3 * 1.0 + 0.5)));
				float b5 = 1.0 - step(0.22, abs(v - (4.6 + 3.3 * 4.0 + 0.5)));
				col = mix(col, vec3(0.05, 0.05, 0.05), clamp(b2 + b5, 0.0, 1.0) * 0.9);
				rough = mix(0.85, 0.15, win);
				emit = win * night * step(0.5, hash12(cell)) * vec3(1.0, 0.75, 0.48) * 1.4;
			}
		} else if (kind < 0.55) {
			// glass curtain wall: every tower has its own module, floor height and system (full
			// glazing, ribbon windows, fins, diagrid or chequered panels) with rooms behind it
			float cwm = mix(1.35, 2.25, fract(seed * 13.7));
			float fh = mix(3.4, 4.2, fract(seed * 29.3));
			int gs = int(fract(seed * 7.9) * 5.0);
			float mx = abs(fract(u / cwm) - 0.5);
			float my = fract(v / fh);
			float mull = step(0.47, mx) + step(my, 0.06);
			float opaque = 0.0;
			if (gs == 1) {
				opaque = step(my, 0.3);
			} else if (gs == 2) {
				mull += step(0.4, mx) * step(0.5, fract(u / (cwm * 2.0)));
			} else if (gs == 3) {
				float d1 = abs(fract((u + v) / (fh * 2.4)) - 0.5);
				float d2 = abs(fract((u - v) / (fh * 2.4)) - 0.5);
				mull += step(0.47, max(d1, d2)) * fine;
			} else if (gs == 4) {
				opaque = step(0.55, hash12(floor(vec2(u / cwm, v / fh)) + seed * 3.0)) * 0.85;
			}
			mull = clamp(mull, 0.0, 1.0);
			vec2 cell = floor(vec2(u / cwm, v / fh)) + seed * 37.0;
			vec3 glass = facade * vec3(0.55, 0.65, 0.75) * mix(0.8, 1.15, fract(seed * 3.3)) + vec3(0.02, 0.03, 0.04) * hash12(cell);
			vec3 frame = mix(vec3(0.62, 0.64, 0.66), vec3(0.12, 0.13, 0.15), step(0.55, fract(seed * 3.1)));
			float win = (1.0 - mull) * (1.0 - opaque);
			col = mix(glass * mix(1.0, 0.22, ik * win), frame, mull);
			col = mix(col, facade * 0.55 + frame * 0.2, opaque * (1.0 - mull));
			rough = mix(0.05, 0.5, clamp(mull + opaque, 0.0, 1.0));
			metal = mix(mix(0.75, 0.22, ik * win), 0.3, mull);
			float lit_far = step(0.5, hash12(floor(vec2(u / 6.0, v / fh)) + seed * 13.0));
			vec3 e_far = win * lit_far * night * mix(vec3(0.85, 0.9, 1.0), vec3(1.0, 0.82, 0.6), step(0.6, fract(seed * 2.9))) * 0.75;
			vec3 e_near = vec3(0.0);
			if (ik > 0.01 && win > 0.5) {
				float lit;
				vec3 rm = room(lpos, rd, ns, tg, cwm * 2.0, fh, rdepth, seed, 0.55, 1.0, lit);
				e_near = rm * mix(0.36, 0.015 + 0.85 * lit, night) * (1.0 - fres) * win * mix(vec3(1.0), vec3(1.0, 0.9, 0.75), night);
			}
			emit = mix(e_far, e_near, ik);
			// crown light and corner LEDs on some towers at night
			float crown = step(vsc.y - fh * 1.5, v) * step(0.5, fract(seed * 61.0)) * step(60.0, vsc.y);
			emit += crown * night * mix(vec3(0.3, 0.6, 1.0), vec3(1.0, 0.8, 0.4), step(0.5, fract(seed * 71.0))) * 1.6 * (1.0 - mull * 0.5);
		} else if (kind < 0.64) {
			// residential tower: small windows, air-conditioner boxes, balcony slots
			float wx = fract(u / 2.3);
			float wy = fract(v / 2.9);
			vec2 cell = floor(vec2(u / 2.3, v / 2.9)) + seed * 57.0;
			float win = step(0.2, wx) * step(wx, 0.8) * step(0.36, wy) * step(wy, 0.82) * step(6.0, v);
			col = mix(col, vec3(0.06, 0.07, 0.09) * mix(1.0, 0.3, ik), win * 0.85);
			if (ik > 0.01 && win > 0.5) {
				float lit3;
				vec3 rm = room(lpos, rd, ns, tg, 2.3, 2.9, clamp(rdepth, 3.0, 6.0), seed + 0.57, 0.45, 0.0, lit3);
				emit += rm * mix(0.32, 0.015 + 0.8 * lit3, night) * (1.0 - fres) * ik * mix(vec3(1.0), vec3(1.0, 0.85, 0.65), lit3 * night);
			}
			float ac = step(0.55, wx) * step(wx, 0.85) * step(0.18, wy) * step(wy, 0.33) * step(0.55, hash12(cell + 5.0)) * fine;
			col = mix(col, vec3(0.75, 0.75, 0.73), ac);
			float slot = step(0.92, fract(u / 9.2)) * fine;
			col *= 1.0 - 0.35 * slot;
			rough = mix(0.85, 0.2, win);
			emit += win * night * step(0.4, hash12(cell)) * mix(vec3(1.0, 0.78, 0.5), vec3(0.8, 0.9, 1.0), step(0.6, hash12(cell + 1.3))) * 1.4 * (1.0 - ik);
		} else if (kind < 0.73) {
			// concrete panel slab: panel joints, one window per panel, stacked loggias
			float px = fract(u / 3.6);
			float py = fract(v / 2.8);
			vec2 cell = floor(vec2(u / 3.6, v / 2.8)) + seed * 83.0;
			float joint = (step(px, 0.025) + step(py, 0.03)) * fine;
			col *= 1.0 - 0.25 * clamp(joint, 0.0, 1.0);
			float loggia = step(3.0, mod(floor(u / 3.6) + 40.0, 4.0)) * step(2.6, v);
			float win = step(0.25, px) * step(px, 0.75) * step(0.3, py) * step(py, 0.78) * step(2.6, v);
			col = mix(col, col * 0.55, loggia * step(py, 0.95) * 0.8);
			col = mix(col, vec3(0.06, 0.07, 0.09), win * 0.8);
			rough = mix(0.9, 0.2, win);
			emit = win * night * step(0.5, hash12(cell)) * mix(vec3(1.0, 0.74, 0.45), vec3(0.8, 0.88, 1.0), step(0.7, hash12(cell + 2.0))) * 1.3;
		} else if (kind < 0.83) {
			// shed: corrugated cladding, a strip of high windows, roller doors
			col *= 0.88 + 0.12 * mix(0.5, step(0.5, fract(u / 0.6)), fine);
			float strip = step(5.2, v) * step(v, 6.2);
			col = mix(col, vec3(0.5, 0.55, 0.58), strip * 0.6);
			float dx = fract(u / 18.0);
			float door = step(0.1, dx) * step(dx, 0.32) * step(v, 4.6);
			col = mix(col, vec3(0.35, 0.36, 0.37) * (0.9 + 0.1 * step(0.5, fract(v / 0.25))), door);
			rough = 0.6;
			metal = 0.3;
			emit = night * (1.0 - smoothstep(0.0, 0.5, length(vec2(fract(u / 18.0) - 0.21, (v - 5.0) * 0.3)))) * vec3(1.0, 0.85, 0.6) * 1.5;
		} else if (kind < 0.93) {
			// stucco: shuttered windows, shop openings on the ground floor
			float wx = fract(u / 3.0);
			float wy = fract(v / 3.0);
			vec2 cell = floor(vec2(u / 3.0, v / 3.0)) + seed * 67.0;
			float win = step(0.36, wx) * step(wx, 0.64) * step(0.25, wy) * step(wy, 0.78) * step(3.4, v);
			float shut = (step(0.24, wx) * step(wx, 0.36) + step(0.64, wx) * step(wx, 0.76)) * step(0.25, wy) * step(wy, 0.78) * step(3.4, v);
			vec3 shc = fract(seed * 3.7) < 0.4 ? vec3(0.08, 0.2, 0.1) : (fract(seed * 3.7) < 0.7 ? vec3(0.3, 0.16, 0.08) : vec3(0.12, 0.2, 0.32));
			col = mix(col, shc, shut * step(0.35, hash12(cell + 4.0)) * fine);
			col = mix(col, vec3(0.05, 0.06, 0.07), win * 0.85);
			float shop = step(v, 3.0) * step(0.5, v) * step(0.12, fract(u / 4.5)) * step(fract(u / 4.5), 0.88);
			col = mix(col, vec3(0.08, 0.08, 0.09), shop * 0.85);
			rough = mix(0.9, 0.2, win + shop);
			emit = (win * step(0.45, hash12(cell)) + shop * 0.7 * step(0.4, hash12(cell + 8.0))) * night * vec3(1.0, 0.76, 0.46) * 1.3;
		} else {
			// offices and flats: each building has its own window module, proportions and floor
			// height; some have continuous ribbon windows, some strong piers; rooms behind
			float mw = mix(2.4, 3.8, fract(seed * 11.3));
			float fh = mix(3.2, 4.0, fract(seed * 23.1));
			float wf = mix(0.5, 0.84, fract(seed * 31.7));
			float hf = mix(0.46, 0.64, fract(seed * 43.9));
			bool ribbon = fract(seed * 53.3) < 0.25;
			float wx = fract(u / mw);
			float wy = fract(v / fh);
			float wxin = ribbon ? 1.0 : step(0.5 - wf * 0.5, wx) * step(wx, 0.5 + wf * 0.5);
			float win = wxin * step(0.86 - hf, wy) * step(wy, 0.86) * step(4.2, v);
			vec2 cell = floor(vec2(u / mw, v / fh)) + seed * 113.0;
			float lit = step(0.52, hash12(cell));
			vec3 glass = mix(vec3(0.05, 0.07, 0.1), vec3(0.16, 0.2, 0.26), hash12(cell * 1.7));
			// piers a touch different from the spandrels
			col *= mix(1.0, 0.86 + 0.2 * fract(seed * 5.1), step(0.5, abs(wx - 0.5) * 2.0 - wf * 0.5 + 0.5) * (1.0 - win));
			col = mix(col, glass * mix(1.0, 0.28, ik), win);
			rough = mix(0.85, 0.15, win);
			metal = 0.1 * win;
			float warm = hash12(cell + 3.1);
			vec3 e_far = win * lit * night * mix(vec3(1.0, 0.75, 0.45), vec3(0.75, 0.85, 1.0), step(0.75, warm)) * 1.1;
			vec3 e_near = vec3(0.0);
			if (ik > 0.01 && win > 0.5) {
				float lit2;
				vec3 rm = room(lpos, rd, ns, tg, mw, fh, rdepth, seed + 0.31, 0.5, 1.0, lit2);
				e_near = rm * mix(0.34, 0.015 + 0.85 * lit2, night) * (1.0 - fres) * mix(vec3(1.0), vec3(1.0, 0.85, 0.65), night);
			}
			emit = mix(e_far, e_near, ik);
			float shop = step(v, 4.0) * step(0.6, v) * step(0.1, wx) * step(wx, 0.9);
			emit += shop * night * vec3(1.0, 0.85, 0.6) * 0.8 * step(0.4, hash12(cell + 9.0));
		}
		// a little grime toward the ground
		col *= 0.82 + 0.18 * smoothstep(0.0, 6.0, v);
		if (region == 1 && kind > 0.85 && v < 26.0) {
			// vertical signboards stacked up the facade and lit boards over the shops
			float slot = floor(u / 7.0);
			float sr = hash12(vec2(slot, seed * 19.0));
			float sx = fract(u / 7.0);
			float vert = step(0.42, sr) * step(0.08, sx) * step(sx, 0.2) * step(4.0, v) * step(v, 4.0 + 4.0 + 18.0 * sr);
			float board = step(3.1, v) * step(v, 4.3) * step(0.05, sx) * step(sx, 0.95);
			float glyph = step(0.45, hash12(floor(vec2(u / 0.45, v / 0.55)) + slot));
			vec3 sc2 = sign_col(fract(sr * 7.7));
			vec3 sc3 = sign_col(fract(sr * 3.3 + 0.5));
			col = mix(col, mix(sc2 * 0.6, vec3(0.95), glyph * 0.6), vert);
			col = mix(col, mix(sc3 * 0.5, vec3(0.92), glyph * 0.5), board * step(0.3, sr));
			emit += (vert * mix(sc2, vec3(1.0), glyph * 0.5) * 2.4 + board * step(0.3, sr) * sc3 * 1.4) * mix(0.15, 1.0, night);
		}
	} else if (onrm.y >= 0.5) {
		col = vec3(0.18, 0.18, 0.19) + facade * 0.15;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
