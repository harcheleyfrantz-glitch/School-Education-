class_name TexGen
## Procedurally generated textures (cached). Nothing is loaded from disk.

static var _cache := {}


static func noise_tex(size: int = 256, freq: float = 0.02, octaves: int = 4, seed_value: int = 1, kind: int = FastNoiseLite.TYPE_SIMPLEX) -> ImageTexture:
	var key := "noise_%d_%f_%d_%d_%d" % [size, freq, octaves, seed_value, kind]
	if _cache.has(key):
		return _cache[key]
	var n := FastNoiseLite.new()
	n.noise_type = kind
	n.seed = seed_value
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	var img := n.get_seamless_image(size, size, false, false, 0.15, true)
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func normal_tex(size: int = 256, freq: float = 0.03, seed_value: int = 3, strength: float = 4.0) -> ImageTexture:
	var key := "normal_%d_%f_%d_%f" % [size, freq, seed_value, strength]
	if _cache.has(key):
		return _cache[key]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = seed_value
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	var img := n.get_seamless_image(size, size, false, false, 0.15, true)
	img.convert(Image.FORMAT_RGBA8)
	img.bump_map_to_normal_map(strength)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func cloud_tex(size: int = 256) -> ImageTexture:
	## RG: large-scale coverage noise (R) and erosion detail (G), seamless.
	var key := "cloud_%d" % size
	if _cache.has(key):
		return _cache[key]
	var a := FastNoiseLite.new()
	a.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	a.seed = 71
	a.frequency = 4.0 / size
	a.fractal_type = FastNoiseLite.FRACTAL_FBM
	a.fractal_octaves = 5
	a.fractal_gain = 0.55
	var b := FastNoiseLite.new()
	b.noise_type = FastNoiseLite.TYPE_CELLULAR
	b.seed = 72
	b.frequency = 16.0 / size
	b.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	b.fractal_type = FastNoiseLite.FRACTAL_FBM
	b.fractal_octaves = 3
	var c := FastNoiseLite.new()
	c.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	c.seed = 73
	c.frequency = 1.0 / size
	c.fractal_type = FastNoiseLite.FRACTAL_FBM
	c.fractal_octaves = 2
	var ia := a.get_seamless_image(size, size, false, false, 0.2, true)
	var ib := b.get_seamless_image(size, size, false, false, 0.2, true)
	var ic := c.get_seamless_image(size, size, false, false, 0.2, true)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var va := ia.get_pixel(x, y).r
			var vb := 1.0 - ib.get_pixel(x, y).r
			var vc := ic.get_pixel(x, y).r
			img.set_pixel(x, y, Color(va, vb, vc, 1.0))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func radial_tex(size: int = 64, hardness: float = 2.0) -> ImageTexture:
	var key := "radial_%d_%f" % [size, hardness]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - size * 0.5, y + 0.5 - size * 0.5).length() / (size * 0.5)
			var v := pow(clampf(1.0 - d, 0.0, 1.0), hardness)
			img.set_pixel(x, y, Color(1, 1, 1, v))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func macro_depth_tex() -> ImageTexture:
	## The baked macro heightfield as a float texture (for water shallowness).
	if _cache.has("macro"):
		return _cache["macro"]
	var img := Image.create_from_data(Geo.GRID, Geo.GRID, false, Image.FORMAT_RF, Geo.macro.to_byte_array())
	var tex := ImageTexture.create_from_image(img)
	_cache["macro"] = tex
	return tex


static func smoke_tex(size: int = 64) -> ImageTexture:
	var key := "smoke_%d" % size
	if _cache.has(key):
		return _cache[key]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.seed = 9
	n.frequency = 6.0 / size
	n.fractal_octaves = 3
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - size * 0.5, y + 0.5 - size * 0.5).length() / (size * 0.5)
			var v := clampf(1.0 - d, 0.0, 1.0)
			var nn := n.get_noise_2d(x, y) * 0.5 + 0.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(v * v * (0.55 + nn * 0.9), 0.0, 1.0)))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
