shader_type spatial;
render_mode cull_back, depth_draw_opaque;
// Ground vehicles: one mesh, the material class is packed into vertex alpha
// (1 paint, 0.8 rubber, 0.55 bare metal, 0.3 matte plastic/fabric, 0.05 glass).

uniform float grime : hint_range(0.0, 1.0) = 0.35;
varying float v_cls;
varying float v_h;

void vertex() {
	v_cls = COLOR.a;
	v_h = VERTEX.y;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5);
}

void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	float rough = 0.32;
	float metal = 0.2;
	float spec = 0.55;
	if (v_cls < 0.15) {
		// glass: dark, glossy, picks up the sky
		c = c * 0.45;
		rough = 0.05;
		metal = 0.7;
		spec = 0.95;
	} else if (v_cls < 0.42) {
		rough = 0.76;
		metal = 0.0;
		spec = 0.35;
	} else if (v_cls < 0.68) {
		rough = 0.24;
		metal = 0.9;
	} else if (v_cls < 0.9) {
		rough = 0.9;
		metal = 0.0;
		spec = 0.25;
	}
	if (v_cls > 0.15) {
		// road grime builds up low on the body
		float g = (1.0 - smoothstep(0.15, 1.1, v_h)) * grime;
		float n = hash21(floor(UV * 24.0));
		c *= 1.0 - g * (0.35 + 0.15 * n);
		rough = mix(rough, 0.95, g * 0.6);
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
}
