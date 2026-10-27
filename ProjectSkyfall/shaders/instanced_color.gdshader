shader_type spatial;
render_mode cull_back;

// Generic instanced props (cars, containers, ground equipment): vertex colour alpha marks
// tintable parts, INSTANCE_CUSTOM.rgb is the per-instance paint colour.
varying vec3 albedo;

void vertex() {
	vec3 tint = mix(vec3(1.0), INSTANCE_CUSTOM.rgb, COLOR.a);
	albedo = pow(COLOR.rgb * tint, vec3(2.2));
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = 0.45;
	METALLIC = 0.25;
}
