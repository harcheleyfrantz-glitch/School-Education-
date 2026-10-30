shader_type canvas_item;
// Security camera look: washed-out monochrome, low resolution, heavy noise, rolling interlace
// lines, a slight fisheye and a frame that only updates a few times a second.
uniform float time = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	vec2 uv = UV + d * dot(d, d) * 0.035;
	vec2 px = vec2(480.0, 270.0);
	uv = (floor(uv * px) + 0.5) / px;
	vec3 c = texture(TEXTURE, uv).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	l = pow(clamp(l, 0.0, 1.0), 0.85) * 0.9 + 0.06;
	float ft = floor(time * 6.0);
	l += (hash(floor(UV * px) + ft * 13.1) - 0.5) * 0.14;
	l *= 0.93 + 0.07 * sin(UV.y * 540.0 + ft * 2.0);
	float roll = fract(time * 0.13);
	l += smoothstep(0.02, 0.0, abs(UV.y - roll)) * 0.06;
	l *= 1.0 - dot(d, d) * 0.22;
	COLOR = vec4(vec3(clamp(l, 0.0, 1.0)) * vec3(0.96, 1.0, 0.97), 1.0);
}
