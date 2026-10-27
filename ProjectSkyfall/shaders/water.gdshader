shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Ocean, lakes and rivers. Opaque for mobile friendliness; shallowness comes from the baked
// macro heightfield, reflections from the sky radiance.
uniform vec3 world_origin = vec3(0.0);
uniform vec3 deep_color : source_color = vec3(0.02, 0.09, 0.15);
uniform vec3 shallow_color : source_color = vec3(0.05, 0.32, 0.36);
uniform float use_macro = 1.0;
uniform float flat_shallow = 0.0;
uniform float roughness_boost = 0.0;
uniform float wave_scale = 1.0;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_tex : filter_linear, repeat_disable;
uniform float map_half = 512000.0;

varying vec3 wpos;
varying float vdist;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wpos = w + vec3(world_origin.x, 0.0, world_origin.z);
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec2 uv = wpos.xz;
	float t = TIME;
	vec3 n1 = texture(normal_tex, uv / (61.0 * wave_scale) + vec2(t * 0.011, t * 0.007)).xyz;
	vec3 n2 = texture(normal_tex, uv / (23.0 * wave_scale) - vec2(t * 0.017, -t * 0.012)).xyz;
	vec3 n3 = texture(normal_tex, uv / (310.0 * wave_scale) + vec2(t * 0.004, t * 0.003)).xyz;
	vec3 nm = normalize(n1 + n2 + n3 * 1.3 - 1.65);
	float far = clamp(vdist / 9000.0, 0.0, 1.0);
	NORMAL_MAP = mix(nm * 0.5 + 0.5, vec3(0.5, 0.5, 1.0), far * 0.8);
	NORMAL_MAP_DEPTH = 1.0;
	float depth = 50.0;
	if (use_macro > 0.5) {
		vec2 muv = (wpos.xz + map_half) / (2.0 * map_half);
		float m = texture(macro_tex, muv).r;
		depth = clamp(-m, 0.0, 900.0);
	}
	float shallow = max(1.0 - smoothstep(10.0, 140.0, depth), flat_shallow);
	ALBEDO = mix(deep_color, shallow_color, shallow);
	ROUGHNESS = clamp(0.035 + far * 0.12 + roughness_boost, 0.0, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.55;
}
