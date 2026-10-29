shader_type canvas_item;
// Phone camera look: punchy processing, sharpening halo, sensor noise, banding and the odd
// compression macroblock, plus a lens vignette. region = the atlas UV rectangle shown.
uniform float time = 0.0;
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	vec2 local = (uv - region.xy) / max(region.zw - region.xy, vec2(0.0001));
	vec2 bsz = TEXTURE_PIXEL_SIZE * 8.0;
	vec2 blk = floor(uv / bsz);
	float glitch = step(0.992, hash(blk * 0.37 + floor(time * 3.0)));
	vec2 buv = (blk + 0.5) * bsz;
	vec3 c = texture(TEXTURE, mix(uv, buv, glitch)).rgb;
	vec3 n = texture(TEXTURE, uv + vec2(TEXTURE_PIXEL_SIZE.x * 1.5, 0.0)).rgb + texture(TEXTURE, uv - vec2(TEXTURE_PIXEL_SIZE.x * 1.5, 0.0)).rgb
		+ texture(TEXTURE, uv + vec2(0.0, TEXTURE_PIXEL_SIZE.y * 1.5)).rgb + texture(TEXTURE, uv - vec2(0.0, TEXTURE_PIXEL_SIZE.y * 1.5)).rgb;
	c = c + (c - n * 0.25) * 0.45;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, 1.18);
	c = (c - 0.5) * 1.1 + 0.52;
	c *= vec3(1.03, 1.0, 0.95);
	float g = hash(local * vec2(406.0, 720.0) + fract(time * 7.13) * 91.0) - 0.5;
	c += g * 0.06;
	c = floor(c * 40.0 + 0.5) / 40.0;
	vec2 d = local * 2.0 - 1.0;
	c *= 1.0 - dot(d * vec2(0.6, 0.35), d * vec2(0.6, 0.35)) * 0.55;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
