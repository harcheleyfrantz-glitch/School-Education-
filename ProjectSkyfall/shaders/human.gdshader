shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Poses and dresses the shared HumanMesh per MultiMesh instance.
// INSTANCE_CUSTOM: x = pose + phase offset (fraction), y = animation rate (cycles/s),
//                  z = hair style (integer part) + appearance seed (fraction),
//                  w = flags + build fraction (0 masculine .. 1 feminine)
// flags: bag 1, phone 2, elderly 4, skirt 8, cap 16, soot 32, glasses 64, backpack 128, helmet 256, tie 512
// instance COLOR: rgb = top colour, a = outfit / 16
// mesh: UV2.x = part, UV2.y = colour slot, UV.x = variant (hair style)

global uniform float crowd_time;
instance uniform vec3 uniform_color = vec3(0.09, 0.13, 0.30);
instance uniform vec3 uniform_trim = vec3(0.75, 0.12, 0.14);

varying flat vec3 v_albedo;
varying flat vec3 v_top;
varying flat vec3 v_bottom;
varying flat vec3 v_trim;
varying flat float v_rough;
varying flat float v_emit;
varying flat float v_stripe;
varying flat float v_kind;
varying flat float v_slot;
varying flat float v_denim;
varying vec3 v_rest;

void rot(inout vec3 p, inout vec3 n, vec3 pivot, vec3 a) {
	// order: x (swing), then z (abduction), then y (twist)
	vec3 q = p - pivot;
	float c = cos(a.x), s = sin(a.x);
	q = vec3(q.x, c * q.y - s * q.z, s * q.y + c * q.z);
	n = vec3(n.x, c * n.y - s * n.z, s * n.y + c * n.z);
	c = cos(a.z); s = sin(a.z);
	q = vec3(c * q.x - s * q.y, s * q.x + c * q.y, q.z);
	n = vec3(c * n.x - s * n.y, s * n.x + c * n.y, n.z);
	c = cos(a.y); s = sin(a.y);
	q = vec3(c * q.x + s * q.z, q.y, -s * q.x + c * q.z);
	n = vec3(c * n.x + s * n.z, n.y, -s * n.x + c * n.z);
	p = q + pivot;
}

float h1(float x) { return fract(sin(x * 127.1 + 311.7) * 43758.5453); }

vec3 skin_tone(float s) {
	vec3 a[7] = vec3[7](vec3(0.86, 0.68, 0.57), vec3(0.80, 0.60, 0.47), vec3(0.71, 0.51, 0.37), vec3(0.60, 0.42, 0.29),
		vec3(0.47, 0.32, 0.21), vec3(0.36, 0.24, 0.16), vec3(0.26, 0.17, 0.12));
	return a[int(s * 6.999)];
}

vec3 hair_tone(float s, bool elderly) {
	if (elderly) return mix(vec3(0.58, 0.57, 0.55), vec3(0.88, 0.87, 0.85), s);
	vec3 a[7] = vec3[7](vec3(0.035, 0.03, 0.028), vec3(0.11, 0.07, 0.045), vec3(0.24, 0.15, 0.08),
		vec3(0.42, 0.28, 0.15), vec3(0.70, 0.56, 0.34), vec3(0.48, 0.18, 0.07), vec3(0.07, 0.055, 0.05));
	return a[int(s * 6.999)];
}

vec3 trouser_tone(float s) {
	vec3 a[7] = vec3[7](vec3(0.14, 0.21, 0.36), vec3(0.06, 0.06, 0.07), vec3(0.55, 0.48, 0.36),
		vec3(0.32, 0.33, 0.35), vec3(0.10, 0.12, 0.22), vec3(0.30, 0.22, 0.15), vec3(0.24, 0.33, 0.48));
	return a[int(s * 6.999)];
}

vec3 iris_tone(float s, float skin) {
	vec3 a[6] = vec3[6](vec3(0.12, 0.07, 0.04), vec3(0.22, 0.13, 0.06), vec3(0.32, 0.26, 0.12),
		vec3(0.22, 0.34, 0.2), vec3(0.22, 0.38, 0.6), vec3(0.4, 0.45, 0.5));
	int i = int(s * 5.999);
	if (skin > 0.45) i = min(i, 1);
	return a[i];
}

void vertex() {
	float cx = INSTANCE_CUSTOM.x;
	int pose = int(floor(cx));
	float ph0 = fract(cx);
	float rate = INSTANCE_CUSTOM.y;
	int style_sel = int(floor(INSTANCE_CUSTOM.z));
	float seed = fract(INSTANCE_CUSTOM.z);
	int flags = int(floor(INSTANCE_CUSTOM.w));
	float build = fract(INSTANCE_CUSTOM.w);
	int outfit = int(COLOR.a * 16.0 + 0.5);
	vec3 top = COLOR.rgb;
	int part = int(UV2.x + 0.5);
	int slot = int(UV2.y + 0.5);
	int variant = int(UV.x + 0.5);
	bool has_bag = (flags & 1) != 0;
	bool has_phone = (flags & 2) != 0;
	bool elderly = (flags & 4) != 0;
	bool skirt = (flags & 8) != 0;
	bool cap = (flags & 16) != 0;
	bool soot = (flags & 32) != 0;
	bool glasses = (flags & 64) != 0;
	bool backpack = (flags & 128) != 0;
	bool helmet = (flags & 256) != 0;
	bool tie = (flags & 512) != 0;
	float t = (ph0 + crowd_time * rate) * 6.2831853;
	float sh1 = h1(seed * 13.0);
	float sh2 = h1(seed * 29.0 + 1.0);
	float sh3 = h1(seed * 47.0 + 2.0);
	float sh4 = h1(seed * 71.0 + 3.0);
	float sh5 = h1(seed * 97.0 + 4.0);

	vec3 P = VERTEX;
	vec3 N = NORMAL;
	vec3 R = P;
	v_rest = R;

	// ---- body shape: feminine build narrows shoulders and waist, widens hips
	if (part == 0) {
		float hip = smoothstep(1.1, 0.92, P.y);
		float waist = exp(-pow((P.y - 1.05) / 0.06, 2.0));
		float shoulder = smoothstep(1.24, 1.42, P.y);
		float bust = exp(-pow((P.y - 1.25) / 0.07, 2.0)) * step(P.z, 0.0);
		float bulk = 1.0 + (sh3 - 0.5) * 0.2 + (elderly ? 0.05 : 0.0);
		P.x *= mix(1.0, 1.12, hip * build) * mix(1.0, 0.92, waist * build) * mix(1.0, 0.9, shoulder * build) * bulk;
		P.z *= bulk * (1.0 + bust * build * 0.16);
		P.z += waist * (bulk - 1.0) * -0.04;
	}
	// ---- hair: only the selected style is drawn
	bool hidden = false;
	if (part == 2 && variant != style_sel) hidden = true;
	if ((part == 11 && !has_bag) || (part == 12 && !has_phone && pose != 19) || (part == 15 && !cap)
		|| (part == 16 && !helmet) || (part == 17 && !skirt) || (part == 18 && !tie)
		|| (part == 19 && !backpack) || (part == 20 && !glasses)) hidden = true;
	if (part == 2 && (cap || helmet) && variant == style_sel) P += N * 0.002;   // squash under hats
	if (hidden) {
		P = vec3(0.0, 1.2, 0.02);
	}
	// mouth and blinking
	float mouth = 0.0;
	float blink = step(0.965, fract(crowd_time * 0.23 + sh2 * 7.0));

	// ---- pose parameters
	float hipLx = 0.0, hipLz = 0.0, kneeL = 0.0, hipRx = 0.0, hipRz = 0.0, kneeR = 0.0;
	float shLx = 0.0, shLz = -0.07, elL = 0.12, shRx = 0.0, shRz = 0.07, elR = 0.12;
	float torsoX = 0.0, torsoY = 0.0, headX = 0.0, headY = 0.0, headZ = 0.0;
	float rootY = 0.0, rootZ = 0.0, rootX = 0.0;
	bool seated = pose == 2 || pose == 3 || pose == 8 || pose == 9 || pose == 13 || pose == 15 || pose == 16 || pose == 17 || pose == 19;
	if (seated) {
		hipLx = 1.45; hipRx = 1.45; kneeL = -1.32; kneeR = -1.38; hipLz = -0.06; hipRz = 0.06;
		rootY = -0.43; rootZ = 0.04; torsoX = 0.10;
		shLx = 0.38; shRx = 0.38; elL = 1.05; elR = 1.05; shLz = -0.10; shRz = 0.10;
		headX = -0.05 + 0.05 * sin(t * 0.3 + sh1 * 6.0);
		headY = 0.3 * sin(t * 0.21 + sh2 * 5.0) * (sh3 > 0.5 ? 1.0 : 0.4);
	}
	if (pose == 0) {
		torsoX = 0.012 * sin(t * 0.5);
		headY = 0.28 * sin(t * 0.37 + sh1 * 6.0);
		headX = 0.04 * sin(t * 0.23);
		shLz = -0.09; shRz = 0.09;
		hipLz = -0.03; hipRz = 0.03;
		if (has_bag) { shRz = 0.3; elR = 0.05; }
	} else if (pose == 1 || pose == 4 || pose == 20) {
		bool run = pose == 4;
		float sw = sin(t);
		float amp = run ? 0.72 : 0.42;
		hipLx = amp * sw; hipRx = -amp * sw;
		float kb = run ? 1.5 : 0.85;
		kneeL = -(0.06 + kb * max(0.0, cos(t - 0.3)));
		kneeR = -(0.06 + kb * max(0.0, cos(t - 0.3 + 3.14159)));
		float aamp = run ? 0.7 : 0.34;
		shLx = -aamp * sw; shRx = aamp * sw;
		elL = run ? 1.3 : 0.28 + 0.12 * max(0.0, -sw); elR = run ? 1.3 : 0.28 + 0.12 * max(0.0, sw);
		rootY = -(run ? 0.05 : 0.022) * abs(sw) + (run ? 0.03 : 0.0);
		torsoX = run ? -0.2 : -0.04;
		torsoY = 0.07 * sw;
		headY = -0.05 * sw;
		if (pose == 20) {
			shLx = 1.0; shRx = 1.0; elL = 0.6; elR = 0.6; shLz = 0.05; shRz = -0.05; torsoX = -0.12;
		} else if (has_bag) {
			shRx = -0.28; shRz = 0.32; elR = 0.05;
		}
		if (run && has_phone) { shRx = 1.2; elR = 0.9; }
	} else if (pose == 3) {
		torsoX = -0.95; headX = -0.45;
		shLx = 2.4; shRx = 2.4; shLz = -0.35; shRz = 0.35; elL = 1.95; elR = 1.95;
		kneeL = -1.15; kneeR = -1.15;
	} else if (pose == 5) {
		rootX = 1.5708; rootY = 0.11; rootZ = -0.85;
		shLz = -0.35; shRz = 0.35; elL = 0.2; elR = 0.2; hipLz = -0.08; hipRz = 0.08;
		headY = 0.35 * (sh1 - 0.5);
		blink = 1.0;
	} else if (pose == 6) {
		int stage = int(floor(ph0 * 4.0));
		float w = sin(crowd_time * 2.2 + sh1 * 6.0);
		if (stage == 0) {
			shLx = 0.55; shRx = 0.55; elL = 1.25 + 0.15 * w; elR = 1.25 - 0.15 * w; shLz = 0.12; shRz = -0.12;
		} else if (stage == 1) {
			shLx = 2.7; shLz = -0.15; elL = 0.3;
			shRx = 1.6; shRz = 0.25; elR = 2.3 + 0.1 * w;
		} else if (stage == 2) {
			shLx = 0.7; shRx = 0.7; elL = 1.7; elR = 1.7; shLz = 0.25; shRz = -0.25;
			headX = -0.15;
		} else {
			shLz = -1.45 + 0.08 * w; shRz = 1.45 - 0.08 * w; shLx = 0.25 * w; shRx = 0.25 * w; elL = 0.05; elR = 0.05;
			headY = 0.5 * w;
		}
		mouth = 0.3 + 0.3 * sin(crowd_time * 9.0);
	} else if (pose == 7) {
		elL = 1.15 + 0.35 * sin(t * 1.3); elR = 1.0 + 0.4 * sin(t * 1.1 + 1.0);
		shLx = 0.3 + 0.15 * sin(t * 0.9); shRx = 0.35 + 0.2 * sin(t * 0.7 + 2.0);
		shLz = -0.15; shRz = 0.15;
		headX = 0.08 * sin(t * 2.1); headY = 0.15 * sin(t * 0.5);
		mouth = 0.5 + 0.5 * sin(crowd_time * 11.0 + sh1 * 9.0);
	} else if (pose == 8) {
		torsoX = -0.35 + 0.16 * sin(t * 2.0); headX = -0.35;
		shLx = 2.0; shRx = 2.0; shLz = -0.6; shRz = 0.6; elL = 2.25; elR = 2.25;
		mouth = 0.6;
	} else if (pose == 9) {
		torsoX = 0.16; headX = -0.38; headZ = 0.32 * (sh1 > 0.5 ? 1.0 : -1.0); headY = 0.0;
		shLx = 0.5; shRx = 0.5; elL = 1.6; elR = 1.6; shLz = 0.18; shRz = -0.18;
		blink = 1.0;
	} else if (pose == 10) {
		shLx = 2.8 + 0.12 * sin(t); shRx = 2.8 + 0.12 * sin(t + 0.5); elL = 0.35; elR = 0.35; shLz = -0.12; shRz = 0.12;
		headX = 0.32;
	} else if (pose == 11) {
		shRz = 2.55 + 0.28 * sin(crowd_time * 7.0 + sh1 * 5.0); elR = 0.35; shRx = 0.15;
		headY = 0.2;
	} else if (pose == 12) {
		rootY = -0.42; hipLx = 1.45; kneeL = -1.45; hipRx = 0.0; kneeR = -1.57;
		torsoX = -0.28; headX = -0.32; shLx = 0.95 + 0.1 * sin(t); shRx = 0.9; elL = 0.5; elR = 0.6;
	} else if (pose == 13 || pose == 14) {
		shRx = 1.35; shRz = 0.12; elR = 0.85;
		headX = -0.06;
		if (pose == 14) { shLz = -0.09; hipLz = -0.04; hipRz = 0.04; torsoX = 0.01 * sin(t); }
	} else if (pose == 15) {
		float side = sh1 > 0.5 ? 1.0 : -1.0;
		headY = 0.55 * side + 0.1 * sin(t * 0.8);
		elR = 1.1 + 0.4 * sin(t * 1.4); shRx = 0.5 + 0.2 * sin(t * 0.9);
		mouth = 0.5 + 0.5 * sin(crowd_time * 10.0 + sh2 * 9.0);
	} else if (pose == 16) {
		shLx = 0.75; shRx = 0.75; elL = 1.45; elR = 1.45; shLz = 0.12; shRz = -0.12; headX = -0.38;
	} else if (pose == 17) {
		float clap = sin(crowd_time * 13.0 + sh1 * 3.0);
		shLx = 0.95; shRx = 0.95; elL = 1.25; elR = 1.25;
		shLz = 0.28 + 0.14 * clap; shRz = -(0.28 + 0.14 * clap);
		headY = 0.1 * sin(t);
		mouth = 0.6;
	} else if (pose == 18) {
		headX = -0.45; torsoX = -0.08;
		shLx = 1.75; shRx = 1.75; elL = 2.2; elR = 2.2; shLz = 0.32; shRz = -0.32;
		blink = 1.0;
	} else if (pose == 19) {
		shRx = 1.55; shRz = 0.3; elR = 2.3; headX = -0.04;
		shLx = 0.4; elL = 1.0;
	}

	// ---- facial animation
	if (part == 14) P.y -= 0.006 * mouth;
	if (part == 21 && slot != 0) {
		float ey = 1.677;
		P.y = ey + (P.y - ey) * mix(1.0, 0.12, blink);
	}

	// ---- skeleton with soft joints
	float y0 = R.y;
	bool farmL = part == 4;
	bool farmR = part == 6 || part == 12;
	bool armL = part == 3 || farmL;
	bool armR = part == 5 || farmR;
	// elbows
	if (farmL) rot(P, N, vec3(-0.205, 1.145, 0.01), vec3(elL * mix(0.5, 1.0, smoothstep(1.165, 1.10, y0)), 0.0, 0.0));
	if (farmR) rot(P, N, vec3(0.205, 1.145, 0.01), vec3(elR * mix(0.5, 1.0, smoothstep(1.165, 1.10, y0)), 0.0, 0.0));
	if (part == 3) rot(P, N, vec3(-0.205, 1.145, 0.01), vec3(elL * 0.5 * smoothstep(1.21, 1.145, y0), 0.0, 0.0));
	if (part == 5) rot(P, N, vec3(0.205, 1.145, 0.01), vec3(elR * 0.5 * smoothstep(1.21, 1.145, y0), 0.0, 0.0));
	// shoulders (deltoids blend into the torso)
	float wsL = part == 3 ? mix(0.6, 1.0, smoothstep(1.44, 1.34, y0)) : 1.0;
	float wsR = part == 5 ? mix(0.6, 1.0, smoothstep(1.44, 1.34, y0)) : 1.0;
	if (armL) rot(P, N, vec3(-0.192, 1.415, 0.0), vec3(shLx, 0.0, shLz) * wsL);
	if (armR) rot(P, N, vec3(0.192, 1.415, 0.0), vec3(shRx, 0.0, shRz) * wsR);
	if (part == 0 && y0 > 1.28) {
		float wl = 0.28 * smoothstep(0.12, 0.19, -R.x) * smoothstep(1.28, 1.40, y0);
		float wr = 0.28 * smoothstep(0.12, 0.19, R.x) * smoothstep(1.28, 1.40, y0);
		if (wl > 0.0) rot(P, N, vec3(-0.192, 1.415, 0.0), vec3(shLx, 0.0, shLz) * wl);
		if (wr > 0.0) rot(P, N, vec3(0.192, 1.415, 0.0), vec3(shRx, 0.0, shRz) * wr);
	}
	// knees
	if (part == 8) rot(P, N, vec3(-0.095, 0.50, -0.01), vec3(kneeL * mix(0.5, 1.0, smoothstep(0.52, 0.45, y0)), 0.0, 0.0));
	if (part == 10) rot(P, N, vec3(0.095, 0.50, -0.01), vec3(kneeR * mix(0.5, 1.0, smoothstep(0.52, 0.45, y0)), 0.0, 0.0));
	if (part == 7) rot(P, N, vec3(-0.095, 0.50, -0.01), vec3(kneeL * 0.5 * smoothstep(0.58, 0.49, y0), 0.0, 0.0));
	if (part == 9) rot(P, N, vec3(0.095, 0.50, -0.01), vec3(kneeR * 0.5 * smoothstep(0.58, 0.49, y0), 0.0, 0.0));
	// hips
	float wh = (part == 7 || part == 9) ? mix(0.55, 1.0, smoothstep(0.97, 0.84, y0)) : 1.0;
	if (part == 7 || part == 8) rot(P, N, vec3(-0.092, 0.93, 0.0), vec3(hipLx, 0.0, hipLz) * wh);
	if (part == 9 || part == 10) rot(P, N, vec3(0.092, 0.93, 0.0), vec3(hipRx, 0.0, hipRz) * wh);
	if (part == 0 && y0 < 0.95) {
		float base = 0.5 * smoothstep(0.95, 0.84, y0);
		float wl2 = base * smoothstep(0.0, 0.07, -R.x);
		float wr2 = base * smoothstep(0.0, 0.07, R.x);
		if (wl2 > 0.0) rot(P, N, vec3(-0.092, 0.93, 0.0), vec3(hipLx, 0.0, hipLz) * wl2);
		if (wr2 > 0.0) rot(P, N, vec3(0.092, 0.93, 0.0), vec3(hipRx, 0.0, hipRz) * wr2);
	}
	if (part == 17) {
		// skirt drapes over the thighs when they swing
		float front = R.z < 0.0 ? 1.0 : 0.35;
		float wsk = smoothstep(0.98, 0.62, y0) * front * 0.92;
		if (R.x < 0.0) rot(P, N, vec3(-0.092, 0.93, 0.0), vec3(hipLx * wsk, 0.0, 0.0));
		else rot(P, N, vec3(0.092, 0.93, 0.0), vec3(hipRx * wsk, 0.0, 0.0));
	}
	// head and neck
	bool head = part == 1 || part == 2 || part == 13 || part == 14 || part == 15 || part == 16 || part == 20 || part == 21;
	if (head) {
		float wn = part == 1 ? smoothstep(1.43, 1.56, y0) : 1.0;
		rot(P, N, vec3(0.0, 1.50, 0.0), vec3(headX, headY, headZ) * wn);
	}
	// upper body lean around the pelvis
	bool upper = part == 0 || head || armL || armR || part == 18 || part == 19;
	if (upper) {
		float wp = part == 0 ? smoothstep(0.86, 1.02, y0) : 1.0;
		rot(P, N, vec3(0.0, 0.93, 0.0), vec3(torsoX, torsoY, 0.0) * wp);
	}
	if (rootX != 0.0) rot(P, N, vec3(0.0), vec3(rootX, 0.0, 0.0));
	P.y += rootY;
	P.z += rootZ;
	VERTEX = P;
	NORMAL = normalize(N);

	// ---- clothing and colour
	vec3 skin = skin_tone(sh1);
	vec3 bottom = trouser_tone(sh2);
	v_denim = (outfit == 0 && (int(sh2 * 6.999) == 0 || int(sh2 * 6.999) == 6)) ? 1.0 : 0.0;
	bool sneakers = sh3 > 0.72;
	vec3 shoes = sneakers ? vec3(0.86, 0.86, 0.85) : (sh3 > 0.35 ? vec3(0.05) : vec3(0.24, 0.14, 0.07));
	vec3 hatc = vec3(0.08);
	bool long_sleeve = sh4 > 0.45;
	bool formal = false;
	float rough = 0.85;
	v_stripe = 0.0;
	if (outfit == 1) {          // business suit
		bottom = top * 0.85; long_sleeve = true; shoes = vec3(0.04); formal = true; v_denim = 0.0; sneakers = false;
	} else if (outfit == 2) {   // cabin crew
		top = uniform_color; bottom = uniform_color * 0.9; long_sleeve = true; shoes = vec3(0.03); formal = true; sneakers = false;
	} else if (outfit == 3) {   // flight crew
		top = vec3(0.93, 0.94, 0.96); bottom = vec3(0.04, 0.045, 0.06); long_sleeve = false; shoes = vec3(0.02);
		hatc = vec3(0.03, 0.04, 0.07); formal = true; sneakers = false;
	} else if (outfit == 4) {   // ground crew hi-vis
		top = vec3(1.0, 0.45, 0.05); bottom = vec3(0.12, 0.13, 0.15); long_sleeve = true; v_stripe = 1.0; shoes = vec3(0.05);
		hatc = vec3(0.95, 0.85, 0.1); sneakers = false;
	} else if (outfit == 5) {   // firefighter
		top = vec3(0.55, 0.47, 0.30); bottom = top; long_sleeve = true; v_stripe = 1.0; hatc = vec3(0.95, 0.80, 0.08); sneakers = false;
	} else if (outfit == 6) {   // paramedic
		top = vec3(0.15, 0.42, 0.22); bottom = vec3(0.12, 0.30, 0.18); long_sleeve = true; v_stripe = 1.0; hatc = vec3(0.1);
	} else if (outfit == 7) {   // police / security
		top = vec3(0.07, 0.10, 0.20); bottom = top; long_sleeve = sh4 > 0.3; hatc = vec3(0.05, 0.07, 0.15);
	} else if (outfit == 8) {   // investigator / official in vest
		bottom = vec3(0.10, 0.11, 0.14); long_sleeve = true; v_stripe = 2.0;
	}
	vec3 c = top;
	v_kind = 0.0;
	if (slot == 0) { c = skin; rough = 0.58; }
	else if (slot == 1) { v_kind = outfit == 2 ? 2.0 : (formal ? 3.0 : 1.0); }
	else if (slot == 2) { c = bottom; }
	else if (slot == 3) { c = shoes; rough = sneakers ? 0.7 : 0.3; }
	else if (slot == 4) { c = hair_tone(sh2 * 0.7 + sh4 * 0.3, elderly); rough = 0.62; }
	else if (slot == 5) { vec3 bags[4] = vec3[4](vec3(0.05), vec3(0.08, 0.10, 0.22), vec3(0.55, 0.08, 0.08), vec3(0.62, 0.64, 0.66)); c = bags[int(sh3 * 3.999)]; rough = 0.4; }
	else if (slot == 6) { c = vec3(0.04, 0.035, 0.035); }
	else if (slot == 7) { c = pose == 19 ? vec3(0.95, 0.80, 0.10) : vec3(0.03); rough = 0.25; }
	else if (slot == 8) { c = hatc; rough = 0.45; }
	else if (slot == 10) { c = long_sleeve ? top : skin; if (!long_sleeve) rough = 0.58; }
	else if (slot == 11) { c = skirt ? skin * 0.92 : bottom; }
	else if (slot == 12) { c = sneakers ? vec3(0.92) : vec3(0.06); rough = 0.7; }
	else if (slot == 13) { c = (build > 0.5 && sh5 > 0.72) ? mix(skin * vec3(0.8, 0.5, 0.5), vec3(0.55, 0.16, 0.2), 0.6) : skin * vec3(0.88, 0.7, 0.68); rough = 0.4; }
	else if (slot == 14) { c = vec3(0.93, 0.91, 0.89); rough = 0.2; }
	else if (slot == 15) { c = iris_tone(sh5, sh1); rough = 0.1; }
	else if (slot == 16) { c = formal ? vec3(0.95) : top; }
	else if (slot == 17) { c = outfit == 3 ? vec3(0.03) : (outfit == 2 ? uniform_trim : mix(vec3(0.5, 0.1, 0.12), vec3(0.1, 0.15, 0.4), sh5)); rough = 0.5; }
	else if (slot == 18) { c = sh5 > 0.6 ? vec3(0.62, 0.52, 0.28) : vec3(0.05); rough = 0.3; }
	if (soot) { c *= 0.45; top *= 0.45; bottom *= 0.45; skin *= 0.6; }
	v_albedo = c;
	v_top = top;
	v_bottom = bottom;
	v_trim = outfit == 2 ? uniform_trim : vec3(0.08, 0.1, 0.25);
	v_slot = float(slot);
	v_rough = rough;
	v_emit = (slot == 7 && has_phone && pose != 19) ? 1.0 : 0.0;
}

float hash3(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	vec3 c = v_albedo;
	vec3 rp = v_rest;
	float y = rp.y;
	float rough = v_rough;
	if (v_kind > 0.5) {
		c = y < 1.0 ? v_bottom : v_top;
		if (abs(y - 1.0) < 0.012) c = vec3(0.04);                   // belt
		float vneck = 0.022 + (y - 1.32) * 0.62;
		if (v_kind > 1.5 && y > 1.32 && abs(rp.x) < vneck && rp.z < 0.0) {
			// cabin crew scarf; suits and flight crew show the shirt (the tie is geometry)
			c = v_kind < 2.5 ? v_trim : vec3(0.94);
		}
		// lapel edges and buttons on formal jackets
		if (v_kind > 2.5 && y > 1.0 && y < 1.3 && rp.z < 0.0 && abs(abs(rp.x) - (0.03 + (1.3 - y) * 0.06)) < 0.004) c *= 0.7;
		if (v_kind > 1.5 && rp.z < 0.0 && abs(rp.x) < 0.006 && y > 1.02 && y < 1.3 && fract(y * 12.5) < 0.18) c = mix(c, vec3(0.75), 0.6);
	}
	// fabric texture
	if ((v_slot > 0.5 && v_slot < 3.5) || (v_slot > 9.5 && v_slot < 11.5)) {
		float fab = vnoise(rp * 180.0) * 0.5 + vnoise(rp * 40.0) * 0.5;
		c *= 0.93 + fab * 0.1;
		if (v_denim > 0.5 && y < 1.0) {
			float tw = sin((rp.x + rp.y) * 900.0) * 0.5 + 0.5;
			c *= 0.92 + tw * 0.12;
		}
	}
	// pupils
	if (abs(v_slot - 15.0) < 0.5) {
		float d = length(vec2(abs(rp.x) - 0.03, rp.y - 1.677));
		c = mix(vec3(0.01), c, smoothstep(0.0022, 0.003, d));
	}
	// hair strands
	if (abs(v_slot - 4.0) < 0.5) {
		float strands = vnoise(vec3(rp.x * 220.0, rp.y * 12.0, rp.z * 220.0));
		c *= 0.78 + strands * 0.4;
		rough = 0.5 + strands * 0.2;
	}
	// skin: warmer cheeks, nose and lips region
	if (v_slot < 0.5 && y > 1.58 && y < 1.75 && rp.z < -0.05) {
		float blush = exp(-pow((abs(rp.x) - 0.045) / 0.02, 2.0) - pow((y - 1.64) / 0.025, 2.0));
		c = mix(c, c * vec3(1.06, 0.88, 0.86), blush * 0.6);
	}
	if (v_stripe > 0.5 && v_stripe < 1.5) {
		float band = step(abs(y - 1.10), 0.022) + step(abs(y - 1.22), 0.022) + step(abs(y - 0.62), 0.02);
		c = mix(c, vec3(0.85, 0.87, 0.85), clamp(band, 0.0, 1.0));
	} else if (v_stripe > 1.5 && y > 1.0 && y < 1.46 && (abs(v_slot - 1.0) < 0.5)) {
		c = mix(c, vec3(0.95, 0.75, 0.05), 0.85);
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = (abs(v_slot - 14.0) < 0.5 || abs(v_slot - 15.0) < 0.5) ? 0.8 : 0.32;
	RIM = v_slot < 0.5 ? 0.25 : 0.1;
	RIM_TINT = 0.6;
	EMISSION = vec3(0.35, 0.45, 0.6) * v_emit * 1.5;
}
