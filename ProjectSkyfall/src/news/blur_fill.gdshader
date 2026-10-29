shader_type canvas_item;
// Soft, darkened fill behind vertical phone footage (the classic TV treatment).
uniform float radius = 22.0;
uniform float darken = 0.42;

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * radius;
	vec3 acc = vec3(0.0);
	float wsum = 0.0;
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			vec2 o = vec2(float(x), float(y)) / 3.0;
			float w = exp(-dot(o, o) * 1.6);
			acc += texture(TEXTURE, UV + o * px).rgb * w;
			wsum += w;
		}
	}
	COLOR = vec4(acc / wsum * darken, 1.0);
}
