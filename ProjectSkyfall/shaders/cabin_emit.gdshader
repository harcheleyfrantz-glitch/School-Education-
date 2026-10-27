shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
// Cabin light sources grouped by vertex alpha:
// ~1.0 exit signs (battery backed), ~0.75 ceiling/cove wash, ~0.5 seat belt & no smoking signs,
// ~0.3 floor path lighting, ~0.1 auxiliary (lavatory occupied, reading lights, screens)

uniform float exit_e = 1.0;
uniform float wash_e = 1.0;
uniform float belt_e = 0.0;
uniform float path_e = 0.0;
uniform float aux_e = 0.6;
uniform vec3 wash_tint : source_color = vec3(1.0, 0.95, 0.86);
uniform float flicker = 0.0;

void fragment() {
	float g = COLOR.a;
	float e = g > 0.9 ? exit_e : (g > 0.65 ? wash_e : (g > 0.4 ? belt_e : (g > 0.2 ? path_e : aux_e)));
	vec3 c = COLOR.rgb;
	if (g > 0.65 && g <= 0.9) {
		c *= wash_tint;
	}
	if (flicker > 0.0) {
		e *= 1.0 - flicker * step(0.7, fract(sin(floor(TIME * 13.0) * 12.9898) * 43758.5453));
	}
	float lit = clamp(e, 0.0, 2.0);
	ALBEDO = c * mix(0.08, 1.0, min(lit, 1.0)) * (1.0 + max(lit - 1.0, 0.0) * 1.5);
}
