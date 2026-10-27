shader_type spatial;
render_mode cull_back;
// Annunciator / push-button light. lit: 0 off, 1 on; colour per instance.

instance uniform float lit = 0.0;
instance uniform vec3 light_color = vec3(1.0, 0.7, 0.1);
uniform float night = 0.0;

void fragment() {
	vec3 off = light_color * 0.08 + vec3(0.02);
	ALBEDO = mix(off, light_color * 0.3, lit);
	ROUGHNESS = 0.35;
	EMISSION = light_color * lit * mix(2.2, 1.2, night);
}
