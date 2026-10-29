class_name NewsMap
extends RefCounted
## Stylised maps for broadcast graphics (story walls, flight trackers, report cards), drawn
## from the same macro heightfield the world is built from, so coastlines match the game.

static var _cache := {}


static func macro_height(x: float, z: float) -> float:
	if Geo.macro.is_empty():
		return 10.0
	var fi := (x + Geo.MAP_HALF) / Geo.CELL - 0.5
	var fj := (z + Geo.MAP_HALF) / Geo.CELL - 0.5
	var i0 := clampi(int(floor(fi)), 0, Geo.GRID - 2)
	var j0 := clampi(int(floor(fj)), 0, Geo.GRID - 2)
	var u := clampf(fi - i0, 0.0, 1.0)
	var v := clampf(fj - j0, 0.0, 1.0)
	var a := Geo.macro[j0 * Geo.GRID + i0]
	var b := Geo.macro[j0 * Geo.GRID + i0 + 1]
	var c := Geo.macro[(j0 + 1) * Geo.GRID + i0]
	var d := Geo.macro[(j0 + 1) * Geo.GRID + i0 + 1]
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


## Map image centred on a world position (x, z), half_m metres to each side.
static func texture(center: Vector2, half_m: float, size: int, sea: Color, land: Color, high: Color, coast: Color) -> ImageTexture:
	var key := "%d|%d|%d|%d|%s|%s|%s" % [int(center.x / 500.0), int(center.y / 500.0), int(half_m / 500.0), size, sea.to_html(), land.to_html(), high.to_html()]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var hs := PackedFloat32Array()
	hs.resize(size * size)
	for j in size:
		for i in size:
			var wx := center.x + (float(i) / float(size - 1) * 2.0 - 1.0) * half_m
			var wz := center.y + (float(j) / float(size - 1) * 2.0 - 1.0) * half_m
			hs[j * size + i] = macro_height(wx, wz)
	for j2 in size:
		for i2 in size:
			var h := hs[j2 * size + i2]
			var col: Color
			if h <= 0.0:
				col = sea.darkened(clampf(-h / 1800.0, 0.0, 0.35))
			else:
				col = land.lerp(high, clampf(h / 1600.0, 0.0, 1.0))
				# simple hill shading from the north-west
				var hx := hs[j2 * size + mini(i2 + 1, size - 1)] - h
				var hz := hs[mini(j2 + 1, size - 1) * size + i2] - h
				col = col.lightened(clampf(-(hx + hz) / 400.0, -0.25, 0.25)) if hx + hz < 0.0 else col.darkened(clampf((hx + hz) / 400.0, 0.0, 0.25))
			# coastline
			var nb := 0
			for o in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var ii := clampi(i2 + int(o[0]), 0, size - 1)
				var jj := clampi(j2 + int(o[1]), 0, size - 1)
				if (hs[jj * size + ii] > 0.0) != (h > 0.0):
					nb += 1
			if nb > 0:
				col = col.lerp(coast, 0.75)
			img.set_pixel(i2, j2, col)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## World (x, z) to a point in a rectangle showing the map centred on `center`.
static func to_px(w: Vector2, center: Vector2, half_m: float, rect: Rect2) -> Vector2:
	var u := (w.x - center.x) / (2.0 * half_m) + 0.5
	var v := (w.y - center.y) / (2.0 * half_m) + 0.5
	return rect.position + Vector2(u, v) * rect.size


## Airports and cities that fall inside a map window: [{name, pos(world), kind}].
static func places_in(center: Vector2, half_m: float) -> Array:
	var out := []
	for icao in Airports.ORDER:
		var ap: Dictionary = Airports.get_ap(icao)
		var p := Vector2(float(ap.x), float(ap.z))
		if absf(p.x - center.x) < half_m * 0.95 and absf(p.y - center.y) < half_m * 0.95:
			out.append({"name": String(ap.short), "pos": p, "kind": "airport", "icao": icao})
	return out
