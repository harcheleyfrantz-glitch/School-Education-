shader_type sky;

// Procedural atmosphere: day/night gradient, sunset glow, sun & moon, stars, high cirrus,
// overcast greying and lightning flashes. The directional light is the sun.
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float cover : hint_range(0.0, 1.0) = 0.2;
uniform float storm : hint_range(0.0, 1.0) = 0.0;
uniform float cirrus : hint_range(0.0, 1.0) = 0.35;
uniform vec2 cirrus_offset = vec2(0.0);
uniform float flash = 0.0;
uniform float haze = 0.0;
uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 sky_color(vec3 d, vec3 sd) {
	float sun_h = sd.y;
	float day = smoothstep(-0.14, 0.18, sun_h);
	float twilight = smoothstep(-0.22, -0.02, sun_h) * (1.0 - smoothstep(0.02, 0.32, sun_h));
	float up = clamp(d.y, 0.0, 1.0);
	float hor = pow(1.0 - up, 5.0);
	vec3 zen_day = vec3(0.10, 0.27, 0.62);
	vec3 hor_day = vec3(0.55, 0.69, 0.85);
	vec3 zen_night = vec3(0.006, 0.011, 0.03);
	vec3 hor_night = vec3(0.028, 0.042, 0.075);
	vec3 col = mix(mix(zen_night, hor_night, hor), mix(zen_day, hor_day, hor), day);
	vec2 dxz = d.xz;
	vec2 sxz = sd.xz;
	float toward = 0.5;
	if (length(dxz) > 0.001 && length(sxz) > 0.001) {
		toward = dot(normalize(dxz), normalize(sxz)) * 0.5 + 0.5;
	}
	vec3 sunset = mix(vec3(0.95, 0.32, 0.1), vec3(1.0, 0.62, 0.3), up);
	col += sunset * twilight * pow(1.0 - up, 3.0) * (0.15 + 1.1 * pow(toward, 4.0));
	col += vec3(0.25, 0.12, 0.3) * twilight * (1.0 - toward) * hor * 0.35;
	float c = max(dot(d, sd), 0.0);
	float mie = pow(c, 10.0) * 0.25 + pow(c, 120.0) * 0.7;
	col += mix(vec3(1.0, 0.55, 0.25), vec3(1.0, 0.9, 0.7), day) * mie * (day * 0.7 + twilight * 1.5) * (1.0 - cover * 0.7);
	return col;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 sd = normalize(sun_dir);
	vec3 col = sky_color(d, sd);
	float day = smoothstep(-0.14, 0.18, sd.y);
	float c = dot(d, sd);
	// sun disc
	float disc = smoothstep(0.99975, 0.99992, c) * step(-0.03, sd.y);
	col += vec3(1.0, 0.92, 0.8) * disc * 40.0 * (1.0 - cover * 0.95);
	// moon
	float mc = dot(d, normalize(moon_dir));
	float moon = smoothstep(0.99955, 0.99968, mc) * step(0.0, moon_dir.y);
	col += vec3(0.85, 0.88, 0.95) * moon * 2.5 * (1.0 - day) * (1.0 - cover * 0.9);
	col += vec3(0.25, 0.3, 0.45) * pow(max(mc, 0.0), 300.0) * (1.0 - day) * 0.4 * (1.0 - cover);
	if (!AT_CUBEMAP_PASS) {
		// stars
		vec3 sp = d * 420.0;
		vec3 cell = floor(sp);
		float h = hash13(cell);
		float star = 0.0;
		if (h > 0.9965) {
			vec3 cpos = cell + 0.5 + (vec3(hash13(cell + 1.3), hash13(cell + 7.1), hash13(cell + 3.7)) - 0.5) * 0.6;
			float dist = length(sp - cpos);
			star = smoothstep(0.32, 0.0, dist) * (h - 0.9965) / 0.0035;
			star *= 0.6 + 0.4 * fract(h * 7919.0);
		}
		col += vec3(0.9, 0.92, 1.0) * star * 2.2 * (1.0 - day) * (1.0 - cover) * smoothstep(0.0, 0.15, d.y);
	}
	// high cirrus layer
	if (d.y > 0.0) {
		vec2 cuv = d.xz / (d.y + 0.08) * 0.35 + cirrus_offset;
		float ci = texture(cloud_tex, cuv).r;
		float ci2 = texture(cloud_tex, cuv * 2.7 + vec2(0.3, 0.1)).g;
		float amount = smoothstep(0.5, 0.85, ci * 0.8 + ci2 * 0.35) * cirrus * smoothstep(0.0, 0.25, d.y);
		vec3 lit = mix(vec3(1.0, 0.55, 0.35), vec3(1.0), day) * (0.25 + day * 0.85);
		col = mix(col, lit, amount * 0.55);
	}
	// overcast & storms grey the sky out
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	vec3 grey = vec3(lum) * vec3(0.95, 0.97, 1.0) * (1.0 - storm * 0.55);
	col = mix(col, grey, clamp(cover * 0.85 + storm * 0.2, 0.0, 0.95));
	col = mix(col, vec3(lum) * 1.1, haze * 0.5);
	// below horizon
	if (d.y < 0.0) {
		vec3 hz = sky_color(normalize(vec3(d.x, 0.0, d.z)), sd);
		hz = mix(hz, vec3(dot(hz, vec3(0.3, 0.59, 0.11))), clamp(cover * 0.85, 0.0, 0.95));
		col = mix(col, hz * 0.75, smoothstep(0.0, -0.08, d.y));
	}
	COLOR = col + vec3(0.8, 0.85, 1.0) * flash;
}
