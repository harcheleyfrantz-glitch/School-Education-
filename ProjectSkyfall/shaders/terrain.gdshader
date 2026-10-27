shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Terrain: vertex colour carries the natural biome colour, alpha = forest weight,
// UV2 = (farmland weight, urban weight). Fields, streets and city lights are drawn here.

uniform vec3 world_origin = vec3(0.0);
uniform float night = 0.0;
uniform float wetness = 0.0;
uniform float snow_cover = 0.0;
uniform float detail = 1.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;
varying vec2 landuse;
varying float forest;
varying float vdist;
varying float wup;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wpos = w + vec3(world_origin.x, 0.0, world_origin.z);
	landuse = UV2;
	forest = COLOR.a;
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	wup = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}

vec3 field_color(vec2 cell) {
	float h = hash12(cell);
	if (h < 0.2) return vec3(0.33, 0.29, 0.13);       // ripe wheat
	if (h < 0.42) return vec3(0.12, 0.19, 0.06);      // green crops
	if (h < 0.54) return vec3(0.17, 0.12, 0.07);      // ploughed soil
	if (h < 0.6) return vec3(0.42, 0.38, 0.08);       // rapeseed
	if (h < 0.84) return vec3(0.16, 0.24, 0.08);      // pasture
	return vec3(0.25, 0.22, 0.12);                    // stubble
}

void fragment() {
	vec3 base = COLOR.rgb;
	float n1 = texture(noise_tex, wpos.xz / 1700.0).r;
	float n2 = texture(noise_tex, wpos.xz / 230.0).r;
	float fade_near = clamp(1.0 - vdist / 2500.0, 0.0, 1.0);
	float n3 = texture(noise_tex, wpos.xz / 29.0).r;
	float close = clamp(1.0 - vdist / 350.0, 0.0, 1.0) * detail;
	float n4 = texture(noise_tex, wpos.xz / 3.7).r;
	float n5 = texture(noise_tex, wpos.xz / 0.9).r;
	base *= 0.80 + 0.32 * n1 + (n2 - 0.5) * 0.18 + (n3 - 0.5) * 0.14 * fade_near * detail;
	base *= 1.0 + ((n4 - 0.5) * 0.35 + (n5 - 0.5) * 0.25) * close;

	// farmland patchwork: each 1.6 km "farm" picks its own orientation and field size
	if (landuse.x > 0.02) {
		vec2 farm = floor(wpos.xz / 1600.0);
		float fh = hash12(farm + 3.7);
		float ang = fh * 1.2 - 0.3;
		mat2 rot = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang)));
		vec2 q = rot * wpos.xz;
		vec2 fsize = vec2(mix(170.0, 480.0, hash12(farm + 9.1)), mix(120.0, 320.0, hash12(farm + 1.3)));
		vec2 row = floor(q / fsize);
		q.x += hash12(vec2(row.y, fh * 31.0)) * fsize.x;
		vec2 cell = floor(q / fsize);
		vec2 f = fract(q / fsize);
		vec3 fc = field_color(cell + farm * 17.0);
		float stripes = 0.93 + 0.07 * sin((q.x * (0.8 + fh) + q.y * 0.15) * 1.1);
		fc *= mix(1.0, stripes, fade_near);
		float edge = smoothstep(0.0, 0.02, f.x) * smoothstep(1.0, 0.98, f.x) * smoothstep(0.0, 0.03, f.y) * smoothstep(1.0, 0.97, f.y);
		float hedge = step(0.55, hash12(cell + 5.0));
		fc = mix(mix(fc * 0.8, vec3(0.13, 0.19, 0.09), hedge), fc, mix(1.0, edge, clamp(1.0 - vdist / 7000.0, 0.0, 1.0)));
		fc *= 0.86 + 0.28 * n2;
		fc = mix(fc, base, 0.25);
		base = mix(base, fc, clamp(landuse.x * 1.3, 0.0, 1.0));
	}

	// forest canopy
	vec3 canopy = mix(vec3(0.025, 0.06, 0.02), vec3(0.06, 0.1, 0.03), n2) * (0.7 + 0.6 * n3 * fade_near + 0.3 * n1);
	base = mix(base, canopy, clamp(forest * 1.35, 0.0, 1.0));

	// urban fabric: block grid, roofs, streets (anti-aliased with screen-space derivatives)
	float lights = 0.0;
	if (landuse.y > 0.02) {
		vec2 b = wpos.xz / 95.0;
		float px = max(fwidth(b.x), fwidth(b.y));
		float far_mix = smoothstep(0.06, 0.45, px);
		vec2 bc = floor(b);
		vec2 bf = fract(b);
		float sw = 0.085;
		float street = 1.0 - smoothstep(0.0, sw, bf.x) * smoothstep(1.0, 1.0 - sw, bf.x) * smoothstep(0.0, sw, bf.y) * smoothstep(1.0, 1.0 - sw, bf.y);
		street = mix(street, 0.3, far_mix);
		float hb = hash12(bc);
		vec3 roof = mix(vec3(0.20, 0.19, 0.18), vec3(0.30, 0.15, 0.11), step(0.62, hb));
		roof = mix(roof, vec3(0.10, 0.16, 0.07), step(0.9, hb));
		roof = mix(roof, vec3(0.2, 0.19, 0.17), far_mix);
		vec3 urb = mix(roof * (0.8 + 0.3 * n3), vec3(0.09, 0.09, 0.095), street);
		base = mix(base, urb, clamp(landuse.y * 1.3, 0.0, 1.0));
		// night: lamps along streets, arterials every 6 blocks, lit windows in blocks
		vec2 lamp = fract(wpos.xz / 31.6);
		float lamp_dot = smoothstep(0.35, 0.0, min(abs(lamp.x - 0.5), abs(lamp.y - 0.5)) * 2.0);
		float near_street = 1.0 - smoothstep(0.0, sw * 0.6, min(min(bf.x, 1.0 - bf.x), min(bf.y, 1.0 - bf.y)));
		vec2 art = abs(fract(b / 6.0 + 0.5) - 0.5) * 6.0;
		float arterial = 1.0 - smoothstep(0.0, 0.12, min(art.x, art.y));
		float detailed = near_street * (0.3 + 0.7 * lamp_dot) * 0.8 + step(0.8, hash12(bc + 4.0)) * (1.0 - near_street) * 0.22;
		float averaged = 0.16 + 0.1 * hb;
		float hood = hash12(floor(b / 3.0) + 11.0);
		float hood_k = mix(0.25, 1.0, smoothstep(0.15, 0.6, hood));
		// arterials stay crisp further away than local streets
		float apx = px / 6.0;
		float art_far = smoothstep(0.08, 0.5, apx);
		float art_line = mix(arterial, 0.12, art_far);
		lights = (mix(detailed, averaged, far_mix) * hood_k + art_line * 1.1) * landuse.y;
	}

	// scattered rural settlements and road lights at night
	if (night > 0.05 && landuse.y < 0.3) {
		vec2 vc = floor(wpos.xz / 2300.0);
		float hv = hash12(vc + 21.0);
		if (hv > 0.6) {
			vec2 vcen = (vc + 0.3 + 0.4 * vec2(hash12(vc + 2.0), hash12(vc + 5.0))) * 2300.0;
			vec2 dvv = wpos.xz - vcen;
			float ang = atan(dvv.y, dvv.x);
			float vr = (160.0 + 240.0 * hash12(vc + 8.0)) * (0.65 + 0.35 * sin(ang * 3.0 + hv * 20.0) + 0.25 * sin(ang * 7.0 + hv * 9.0));
			float dv = length(dvv);
			vec2 lp2 = wpos.xz / 21.0;
			float dots2 = smoothstep(0.3, 0.0, length(fract(lp2) - 0.5)) * step(0.62, hash12(floor(lp2)));
			float vpx = max(fwidth(lp2.x), fwidth(lp2.y));
			dots2 = mix(dots2, 0.05, smoothstep(0.2, 0.8, vpx));
			// a road of lamps running out of the village
			float road = smoothstep(9.0, 0.0, abs(dot(dvv, vec2(-sin(hv * 6.28), cos(hv * 6.28))))) * step(0.5, fract(dot(dvv, vec2(cos(hv * 6.28), sin(hv * 6.28))) / 40.0)) * smoothstep(1400.0, 300.0, dv);
			lights += (dots2 * smoothstep(vr, vr * 0.3, dv) + road * 0.35 * mix(1.0, 0.25, smoothstep(0.2, 0.8, vpx))) * (1.0 - forest) * 0.85;
		}
	}

	// wet and snowy ground
	float snowy = snow_cover * smoothstep(0.55, 0.85, wup);
	base = mix(base, vec3(0.9, 0.92, 0.95), snowy * (1.0 - landuse.y * 0.5));
	base *= 1.0 - wetness * 0.25;

	ALBEDO = base;
	ROUGHNESS = mix(0.93, 0.35, wetness * (1.0 - forest));
	SPECULAR = 0.25;
	EMISSION = vec3(1.0, 0.6, 0.28) * lights * night * 1.25;
}
