shader_type spatial;
render_mode unshaded, cull_back;
// Vehicle lamps. Vertex alpha selects behaviour: 1 steady, 0.75 rotating beacon,
// 0.5 double-flash strobe, 0.25 head/tail lights (bright only when lights_on).
// UV.x holds a per-lamp phase so beacons on one vehicle do not pulse together.

instance uniform float active = 1.0;
instance uniform float lights_on = 0.0;

void fragment() {
	float a = COLOR.a;
	float k = 1.0;
	if (a > 0.9) {
		k = 1.0;
	} else if (a > 0.6) {
		float s = sin(TIME * 7.5 + UV.x * 6.2832);
		k = mix(0.12, 0.2 + 3.0 * pow(max(s, 0.0), 5.0), active);
	} else if (a > 0.4) {
		float t = fract(TIME * 1.15 + UV.x);
		float f = (t < 0.05 || (t > 0.12 && t < 0.17)) ? 3.5 : 0.06;
		k = mix(0.06, f, active);
	} else {
		k = mix(0.18, 1.8, lights_on);
	}
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * k;
}
