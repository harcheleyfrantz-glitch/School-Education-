shader_type spatial;
render_mode cull_back;

// Instanced trees. Vertex alpha marks foliage (tinted per instance), INSTANCE_CUSTOM.rgb = tint,
// INSTANCE_CUSTOM.a = sway phase. Foliage lets light through (backlight) and darkens toward
// the inside and underside of the crown.
uniform float wind = 0.35;

varying vec3 albedo;
varying float leaf;

void vertex() {
	vec3 tint = mix(vec3(1.0), INSTANCE_CUSTOM.rgb, COLOR.a);
	albedo = pow(COLOR.rgb * tint, vec3(2.2));
	leaf = COLOR.a;
	float k = clamp(VERTEX.y / 9.0, 0.0, 1.0);
	float ph = INSTANCE_CUSTOM.a * 6.2831 + TIME * 1.1;
	VERTEX.x += sin(ph) * k * k * wind * 0.5;
	VERTEX.z += cos(ph * 0.73) * k * k * wind * 0.35;
	// cheap crown occlusion: undersides and the lower crown are darker
	float under = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
	albedo *= mix(0.5, 1.0, under) * mix(0.78, 1.0, k);
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = 0.9;
	SPECULAR = 0.18;
	BACKLIGHT = albedo * 0.55 * leaf;
}
