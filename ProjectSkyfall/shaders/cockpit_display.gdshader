shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
// Avionics screen: samples the display atlas, adds a faint glass sheen and a dark bezel edge.

uniform sampler2D screen : source_color, filter_linear_mipmap, repeat_disable;
uniform float brightness = 1.0;
uniform float powered = 1.0;

void fragment() {
	vec3 c = texture(screen, UV).rgb;
	// glass: a little view-dependent sheen so screens read as glass, not stickers
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 off = vec3(0.012, 0.014, 0.016);
	ALBEDO = mix(off, c * brightness, powered) + vec3(0.25, 0.28, 0.32) * fres * 0.35;
}
