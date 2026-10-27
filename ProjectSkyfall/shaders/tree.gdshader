shader_type spatial;
render_mode cull_back;

// Instanced trees. Vertex alpha marks canopy (tinted per instance), INSTANCE_CUSTOM.rgb = tint,
// INSTANCE_CUSTOM.a = sway phase.
uniform float wind = 0.35;

varying vec3 albedo;

void vertex() {
	vec3 tint = mix(vec3(1.0), INSTANCE_CUSTOM.rgb, COLOR.a);
	albedo = pow(COLOR.rgb * tint, vec3(2.2));
	float k = clamp(VERTEX.y / 9.0, 0.0, 1.0);
	float ph = INSTANCE_CUSTOM.a * 6.2831 + TIME * 1.1;
	VERTEX.x += sin(ph) * k * k * wind * 0.5;
	VERTEX.z += cos(ph * 0.73) * k * k * wind * 0.35;
	// darken the underside of the canopy for cheap ambient occlusion
	albedo *= mix(0.55, 1.0, clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0));
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
