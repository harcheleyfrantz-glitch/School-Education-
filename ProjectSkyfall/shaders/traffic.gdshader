shader_type spatial;
render_mode cull_back;

// Street and motorway traffic (CarMeshes, one MultiMesh per vehicle type and chunk). Each instance
// sits at the middle of its lane piece facing the direction of travel and slides along it:
// INSTANCE_CUSTOM.r = lane length (m), .g = speed (m/s, 0 = parked), .b = phase (0..1),
// .a = palette (integer part) + colour seed (fraction). Vehicles shrink in and out at the ends
// of a lane, where they turn off at the junctions. Vertex colour r = part (see CarMeshes).
uniform float night = 0.0;

varying float v_part;
varying vec3 v_paint;
varying vec3 v_paint2;

float h1(float x) { return fract(sin(x * 127.1 + 311.7) * 43758.5453); }

vec3 paint(float pal, float s) {
	float r = h1(s * 91.7);
	vec3 c;
	if (pal > 2.5 && r < 0.35) {
		c = vec3(0.95, 0.72, 0.05);                       // New York cabs
	} else if (pal > 1.5 && pal < 2.5) {
		c = r < 0.55 ? vec3(0.93) : (r < 0.7 ? vec3(0.82, 0.78, 0.68) : (r < 0.85 ? vec3(0.04) : vec3(0.62, 0.64, 0.66)));
	} else if (pal > 0.5 && pal < 1.5) {
		c = r < 0.38 ? vec3(0.94) : (r < 0.6 ? vec3(0.7, 0.71, 0.73) : (r < 0.78 ? vec3(0.05) : (r < 0.88 ? vec3(0.42, 0.44, 0.47) : vec3(0.2, 0.3, 0.55))));
	} else {
		c = r < 0.2 ? vec3(0.92) : (r < 0.36 ? vec3(0.04) : (r < 0.52 ? vec3(0.66, 0.68, 0.7) : (r < 0.62 ? vec3(0.38, 0.4, 0.43)
			: (r < 0.72 ? vec3(0.55, 0.06, 0.06) : (r < 0.82 ? vec3(0.08, 0.16, 0.42) : (r < 0.88 ? vec3(0.12, 0.3, 0.2)
			: (r < 0.93 ? vec3(0.75, 0.6, 0.4) : vec3(0.9, 0.5, 0.1))))))));
	}
	return pow(c, vec3(2.2));
}

void vertex() {
	float len = max(INSTANCE_CUSTOM.r, 1.0);
	float spd = INSTANCE_CUSTOM.g;
	float t = fract(TIME * spd / len + INSTANCE_CUSTOM.b);
	float along = (t - 0.5) * len;
	float k = 1.0;
	if (spd > 0.01) {
		k = smoothstep(0.0, 6.0, min(t, 1.0 - t) * len);
	}
	VERTEX *= k;
	VERTEX.x += along;
	v_part = COLOR.r;
	float pal = floor(INSTANCE_CUSTOM.a);
	float sd = fract(INSTANCE_CUSTOM.a);
	v_paint = paint(pal, sd);
	// second paint: bus liveries and lorry trailers
	float r2 = h1(sd * 13.1 + 2.0);
	v_paint2 = pow(r2 < 0.5 ? vec3(0.93, 0.93, 0.9) : (r2 < 0.7 ? vec3(0.85, 0.12, 0.08) : (r2 < 0.85 ? vec3(0.1, 0.3, 0.6) : vec3(0.95, 0.8, 0.15))), vec3(2.2));
}

void fragment() {
	vec3 c = v_paint;
	float rough = 0.3;
	float metal = 0.55;
	vec3 e = vec3(0.0);
	if (v_part < 0.4) {
		c = vec3(0.025);
		rough = 0.8;
		metal = 0.0;
	} else if (v_part < 0.66) {
		c = vec3(0.02, 0.025, 0.03);
		rough = 0.05;
		metal = 0.6;
	} else if (v_part < 0.78) {
		c = v_paint2;
		rough = 0.45;
		metal = 0.2;
	} else if (v_part < 0.9) {
		c = vec3(0.9, 0.9, 0.86);
		rough = 0.1;
		e = vec3(1.0, 0.95, 0.82) * night * 6.0;
	} else if (v_part < 0.99) {
		c = vec3(0.45, 0.02, 0.02);
		rough = 0.2;
		e = vec3(1.0, 0.04, 0.02) * (0.3 + night * 3.5);
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = e;
}
