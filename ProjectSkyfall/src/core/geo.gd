class_name Geo
## World geography. A shape-defined macro heightfield (coastlines, mountain ranges, plateaus)
## is baked once into a grid, then detail noise, rivers, lakes and airport platforms are layered
## on top. Every system (terrain meshes, collision, crash logic, AI) samples the same function.

const MAP_HALF := 512000.0
const GRID := 128
const CELL := 8000.0
const CACHE_VERSION := 3
const SEA_LEVEL := 0.0

static var ready := false
static var macro := PackedFloat32Array()
static var airports_flat := []      # [x, z, elev, r_in, r_out]
static var cities := []             # {x, z, r, tall, name, icao}
static var lakes := []              # {x, z, rx, rz, level}
static var rivers := []             # {pts: PackedVector2Array, levels: PackedFloat32Array, width: float}
static var river_grid := {}         # Vector2i -> Array of [river, seg]
static var runway_rects := []       # {cx, cz, dx, dz, half_len, half_wid, elev, icao, surface}
static var corridors := []          # approach/departure valleys: [thr_x, thr_z, out_x, out_z, elev]
static var main_sampler: Sampler = null
static var snowline := 2700.0       # metres; set from the season by WorldSim

# ------------------------------------------------------------------ shape definition (km)
const MAINLAND := [
	Vector2(-20, -430), Vector2(60, -445), Vector2(150, -430), Vector2(250, -460), Vector2(380, -440),
	Vector2(530, -450), Vector2(530, 300), Vector2(420, 290), Vector2(330, 272), Vector2(262, 286),
	Vector2(205, 266), Vector2(178, 244), Vector2(152, 230), Vector2(132, 236), Vector2(126, 258),
	Vector2(108, 270), Vector2(60, 256), Vector2(22, 228), Vector2(-8, 192), Vector2(-30, 150),
	Vector2(-46, 110), Vector2(-58, 62), Vector2(-56, 32), Vector2(-60, 8), Vector2(-54, -14),
	Vector2(-50, -42), Vector2(-46, -80), Vector2(-49, -104), Vector2(-45, -116), Vector2(-53, -133),
	Vector2(-50, -162), Vector2(-41, -202), Vector2(-37, -262), Vector2(-31, -322), Vector2(-35, -382),
]
const WESTMARK := [
	Vector2(-512, -240), Vector2(-440, -266), Vector2(-380, -241), Vector2(-345, -181), Vector2(-332, -110),
	Vector2(-336, -40), Vector2(-352, 16), Vector2(-388, 72), Vector2(-425, 108), Vector2(-470, 118),
	Vector2(-492, 96), Vector2(-486, 70), Vector2(-497, 41), Vector2(-505, -20), Vector2(-512, -120),
]
const ISLANDS := [
	[Vector2(-18, 252), Vector2(11, 8.5)],
	[Vector2(40, 330), Vector2(9, 6)],
	[Vector2(75, 346), Vector2(6, 5)],
	[Vector2(21, 366), Vector2(5, 4)],
	[Vector2(180, -492), Vector2(12, 6)],
	[Vector2(-200, 40), Vector2(5, 3)],
	[Vector2(-250, -150), Vector2(7, 4)],
]
# [center, radii, peak metres]  (ellipse bumps)
const RISES := [
	[Vector2(90, -20), Vector2(70, 60), 430.0],
	[Vector2(380, 120), Vector2(140, 150), 360.0],
	[Vector2(200, 72), Vector2(60, 50), 150.0],
	[Vector2(262, 196), Vector2(50, 40), 620.0],
	[Vector2(-430, -190), Vector2(60, 50), 720.0],
	[Vector2(-470, 20), Vector2(30, 50), 340.0],
	[Vector2(-11, 257), Vector2(5, 4), 380.0],
	[Vector2(420, -320), Vector2(90, 80), 900.0],
]
# [a, b, radius, peak]  (capsule ranges)
const RANGES := [
	[Vector2(120, -330), Vector2(330, -90), 75.0, 2300.0],
	[Vector2(330, -90), Vector2(440, -30), 45.0, 1500.0],
]
const LAKES := [
	{"x": 215000.0, "z": 62000.0, "rx": 14000.0, "rz": 9000.0, "level": 205.0, "name": "Lake Oren"},
	{"x": -460000.0, "z": -10000.0, "rx": 6000.0, "rz": 4500.0, "level": 38.0, "name": "Lough Varra"},
	{"x": 252000.0, "z": -150000.0, "rx": 3800.0, "rz": 2600.0, "level": 1240.0, "name": "Lake Silvane"},
]
const RIVERS := [
	{"name": "Calder", "w": 260.0, "pts": [Vector2(150, -140), Vector2(110, -118), Vector2(70, -112), Vector2(30, -122), Vector2(0, -126), Vector2(-20, -128), Vector2(-36, -128), Vector2(-56, -131)]},
	{"name": "Oren", "w": 200.0, "pts": [Vector2(203, 73), Vector2(185, 110), Vector2(166, 150), Vector2(160, 190), Vector2(150, 220), Vector2(140, 240)]},
	{"name": "Aldwater", "w": 220.0, "pts": [Vector2(-450, -150), Vector2(-425, -120), Vector2(-408, -95), Vector2(-390, -70), Vector2(-365, -45), Vector2(-334, -30)]},
	{"name": "Calder Creek", "w": 110.0, "pts": [Vector2(40, 40), Vector2(10, 30), Vector2(-20, 22), Vector2(-42, 16), Vector2(-63, 12)]},
]


# ------------------------------------------------------------------ init
static func init_world() -> void:
	if ready:
		return
	_build_airports()
	if not _load_cache():
		_bake_macro()
		_save_cache()
	main_sampler = Sampler.new()
	_build_lakes()
	_build_rivers()
	ready = true


static func _build_airports() -> void:
	airports_flat.clear()
	cities.clear()
	runway_rects.clear()
	corridors.clear()
	for icao in Airports.ORDER:
		var a: Dictionary = Airports.DATA[icao]
		var r_in := 1800.0
		for e in Airports.runway_ends(icao):
			r_in = maxf(r_in, U.dist2d(a.x, a.z, e.thr_x, e.thr_z) + 900.0)
		airports_flat.append([float(a.x), float(a.z), float(a.elev), r_in, r_in + 2600.0])
		var ci: Dictionary = a.city_info
		cities.append({"x": a.x + ci.dx, "z": a.z + ci.dz, "r": float(ci.radius), "tall": float(ci.tall),
			"name": a.city, "icao": icao, "pop": int(ci.pop), "coastal": bool(ci.coastal)})
		for e in Airports.runway_ends(icao):
			if e.surface != "asphalt":
				continue
			# corridor extends outward from the threshold, opposite to the landing direction
			var out := Vector2(-sin(deg_to_rad(e.hdg)), cos(deg_to_rad(e.hdg)))
			corridors.append([float(e.thr_x), float(e.thr_z), out.x, out.y, float(a.elev)])
		var idx := 0
		for rw in a.runways:
			var ends := Airports.runway_ends(icao)
			var e0: Dictionary = ends[idx * 2]
			var cx = (e0.thr_x + e0.end_x) * 0.5
			var cz = (e0.thr_z + e0.end_z) * 0.5
			var d := Vector2(e0.end_x - e0.thr_x, e0.end_z - e0.thr_z).normalized()
			runway_rects.append({"cx": cx, "cz": cz, "dx": d.x, "dz": d.y, "half_len": rw.len * 0.5 + 60.0,
				"half_wid": rw.wid * 0.5 + 8.0, "elev": float(a.elev), "icao": icao, "surface": rw.surface})
			idx += 1


static func _cache_path() -> String:
	return "user://geo_cache_v%d.bin" % CACHE_VERSION


static func _load_cache() -> bool:
	if not FileAccess.file_exists(_cache_path()):
		return false
	var f := FileAccess.open(_cache_path(), FileAccess.READ)
	if f == null:
		return false
	var data := f.get_buffer(GRID * GRID * 4)
	f.close()
	if data.size() != GRID * GRID * 4:
		return false
	macro = data.to_float32_array()
	return macro.size() == GRID * GRID


static func _save_cache() -> void:
	var f := FileAccess.open(_cache_path(), FileAccess.WRITE)
	if f:
		f.store_buffer(macro.to_byte_array())
		f.close()


static func _bake_macro() -> void:
	macro.resize(GRID * GRID)
	var polys := [MAINLAND, WESTMARK]
	for j in GRID:
		for i in GRID:
			var p := Vector2((-MAP_HALF + (i + 0.5) * CELL) / 1000.0, (-MAP_HALF + (j + 0.5) * CELL) / 1000.0)
			macro[j * GRID + i] = _macro_at_km(p, polys)


static func _macro_at_km(p: Vector2, polys: Array) -> float:
	var inside := false
	var dcoast := INF
	for poly in polys:
		if _point_in_poly(p, poly):
			inside = true
		dcoast = minf(dcoast, _dist_to_poly(p, poly))
	for isl in ISLANDS:
		var c: Vector2 = isl[0]
		var rr: Vector2 = isl[1]
		var q := (p - c) / rr
		var l := q.length()
		var approx_d := (l - 1.0) * minf(rr.x, rr.y)
		if l < 1.0:
			inside = true
		dcoast = minf(dcoast, absf(approx_d))
	if not inside:
		return -30.0 - 870.0 * U.smooth01(dcoast / 60.0)
	var h := 6.0 + 54.0 * U.smooth01(dcoast / 25.0)
	for rise in RISES:
		var q2: Vector2 = (p - rise[0]) / rise[1]
		var t := q2.length()
		if t < 1.0:
			h += float(rise[2]) * (1.0 - U.smooth01(t)) * U.smooth01(dcoast / 12.0)
	for rg in RANGES:
		var d := _dist_seg(p, rg[0], rg[1])
		var t2 := d / float(rg[2])
		if t2 < 1.0:
			h += float(rg[3]) * (1.0 - U.smooth01(t2)) * U.smooth01(dcoast / 20.0)
	return h


static func _point_in_poly(p: Vector2, poly: Array) -> bool:
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[j]
		if ((a.y > p.y) != (b.y > p.y)) and (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x):
			inside = not inside
		j = i
	return inside


static func _dist_to_poly(p: Vector2, poly: Array) -> float:
	var best := INF
	var n := poly.size()
	for i in n:
		best = minf(best, _dist_seg(p, poly[i], poly[(i + 1) % n]))
	return best


static func _dist_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _build_lakes() -> void:
	# Lake surfaces sit just below the lowest point of their shoreline so water never floats.
	lakes = []
	for lk in LAKES:
		var l: Dictionary = lk.duplicate(true)
		var lowest := INF
		for i in 36:
			var ang := TAU * i / 36.0
			var sx: float = l.x + cos(ang) * l.rx * 1.25
			var sz: float = l.z + sin(ang) * l.rz * 1.25
			lowest = minf(lowest, main_sampler.base_height(sx, sz, false))
		l.level = minf(float(l.level), lowest - 2.0)
		lakes.append(l)


static func _build_rivers() -> void:
	rivers.clear()
	river_grid.clear()
	var ri := 0
	for rd in RIVERS:
		var pts := PackedVector2Array()
		for p in rd.pts:
			pts.append(Vector2(p.x * 1000.0, p.y * 1000.0))
		# densify so the water level can follow the valley
		var dense := PackedVector2Array()
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var steps := maxi(1, int(a.distance_to(b) / 2500.0))
			for s in steps:
				dense.append(a.lerp(b, float(s) / steps))
		dense.append(pts[pts.size() - 1])
		var levels := PackedFloat32Array()
		levels.resize(dense.size())
		var prev := INF
		for i in dense.size():
			var h := main_sampler.base_height(dense[i].x, dense[i].y, false) - 6.0
			h = minf(h, prev - 0.5)
			levels[i] = h
			prev = h
		# mouth sits at sea level
		var n := dense.size()
		for i in n:
			var t := float(i) / float(n - 1)
			var target := lerpf(levels[0], -1.5, pow(t, 0.7))
			levels[i] = maxf(minf(levels[i], target), -1.5) if i < n - 1 else -1.5
		for i in range(1, n):
			levels[i] = minf(levels[i], levels[i - 1])
		rivers.append({"name": rd.name, "pts": dense, "levels": levels, "width": float(rd.w)})
		for s in dense.size() - 1:
			var a2 := dense[s]
			var b2 := dense[s + 1]
			var reach := float(rd.w) * 0.5 + 1800.0
			var mn := Vector2(minf(a2.x, b2.x) - reach, minf(a2.y, b2.y) - reach)
			var mx := Vector2(maxf(a2.x, b2.x) + reach, maxf(a2.y, b2.y) + reach)
			for gx in range(int(floor(mn.x / 4000.0)), int(floor(mx.x / 4000.0)) + 1):
				for gz in range(int(floor(mn.y / 4000.0)), int(floor(mx.y / 4000.0)) + 1):
					var key := Vector2i(gx, gz)
					if not river_grid.has(key):
						river_grid[key] = []
					river_grid[key].append([ri, s])
		ri += 1


# ------------------------------------------------------------------ convenience (main thread)
static func height(x: float, z: float) -> float:
	return main_sampler.height(x, z)


static func set_season(doy: int) -> void:
	## Snowline: ~1100 m in midwinter, ~3000 m in late summer.
	snowline = 2050.0 - 950.0 * cos((float(doy) - 20.0) / 365.0 * TAU)


static func ground_height(x: float, z: float) -> float:
	## Height of the surface an aircraft would touch (water counts as sea level/lake level).
	var h := main_sampler.height(x, z)
	var wl := water_level(x, z)
	return maxf(h, wl)


static func water_level(x: float, z: float) -> float:
	for lk in lakes:
		var q := Vector2((x - lk.x) / lk.rx, (z - lk.z) / lk.rz)
		if q.length_squared() < 1.3:
			return float(lk.level)
	var key := Vector2i(int(floor(x / 4000.0)), int(floor(z / 4000.0)))
	if river_grid.has(key):
		for rs in river_grid[key]:
			var rv: Dictionary = rivers[rs[0]]
			var a: Vector2 = rv.pts[rs[1]]
			var b: Vector2 = rv.pts[rs[1] + 1]
			var ab := b - a
			var t := clampf((Vector2(x, z) - a).dot(ab) / maxf(ab.length_squared(), 1.0), 0.0, 1.0)
			if Vector2(x, z).distance_to(a + ab * t) < rv.width:
				return lerpf(rv.levels[rs[1]], rv.levels[rs[1] + 1], t)
	return SEA_LEVEL


static func is_water(x: float, z: float) -> bool:
	return main_sampler.height(x, z) < water_level(x, z) - 0.3


static func runway_at(x: float, z: float) -> Dictionary:
	for r in runway_rects:
		var rx: float = x - r.cx
		var rz: float = z - r.cz
		var along: float = rx * r.dx + rz * r.dz
		var across: float = -rx * r.dz + rz * r.dx
		if absf(along) <= r.half_len and absf(across) <= r.half_wid:
			return r
	return {}


static func surface_at(x: float, z: float) -> String:
	var rw := runway_at(x, z)
	if not rw.is_empty():
		return "runway" if rw.surface == "asphalt" else "grass_strip"
	if is_water(x, z):
		return "water"
	var lu := main_sampler.landuse(x, z)
	if lu.urban > 0.5:
		return "urban"
	if lu.forest > 0.5:
		return "forest"
	var h := main_sampler.height(x, z)
	if h > 1900.0:
		return "mountain"
	if lu.farm > 0.4:
		return "farmland"
	return "grass"


## Motorways between neighbouring cities: [ax, az, bx, bz, seed], each city joined to its two
## nearest neighbours. The terrain shader draws them; scatter keeps trees and buildings off them.
static var _highways: Array = []

static func highways() -> Array:
	if not _highways.is_empty() or cities.size() < 2:
		return _highways
	var seen := {}
	for i in cities.size():
		var a: Dictionary = cities[i]
		var order := []
		for j in cities.size():
			if j != i:
				order.append([U.dist2d(a.x, a.z, cities[j].x, cities[j].z), j])
		order.sort_custom(func(p, q): return float(p[0]) < float(q[0]))
		for k in mini(2, order.size()):
			var j2: int = order[k][1]
			var key := "%d-%d" % [mini(i, j2), maxi(i, j2)]
			if seen.has(key) or float(order[k][0]) > 260000.0:
				continue
			seen[key] = true
			var b: Dictionary = cities[j2]
			_highways.append([float(a.x), float(a.z), float(b.x), float(b.z), float(U.hash_str(key) % 1000) / 1000.0 * 6.28])
	return _highways


## Sideways meander of a motorway (m) at distance s along a segment of length len (same
## formula as shaders/terrain.gdshader).
static func highway_offset(s: float, len: float, seed_v: float) -> float:
	return 140.0 * sin(s / 2200.0 + seed_v) * sin(PI * clampf(s / maxf(len, 1.0), 0.0, 1.0))


## Distance (m) from a point to the nearest motorway centreline.
static func highway_distance(x: float, z: float, list: Array = []) -> float:
	var best := INF
	for h in (list if not list.is_empty() else highways()):
		var a := Vector2(h[0], h[1])
		var b := Vector2(h[2], h[3])
		var ab := b - a
		var L := ab.length()
		if L < 1.0:
			continue
		var dirv := ab / L
		var rel := Vector2(x, z) - a
		var sa := clampf(rel.dot(dirv), 0.0, L)
		var perp := dirv.x * rel.y - dirv.y * rel.x
		var d := absf(perp - highway_offset(sa, L, float(h[4])))
		if rel.dot(dirv) < -200.0 or rel.dot(dirv) > L + 200.0:
			d = maxf(d, minf(rel.length(), (Vector2(x, z) - b).length()))
		best = minf(best, d)
	return best


static func nearest_city(x: float, z: float) -> Dictionary:
	var best := {}
	var bd := INF
	for c in cities:
		var d := U.dist2d(x, z, c.x, c.z)
		if d < bd:
			bd = d
			best = c
	if not best.is_empty():
		best = best.duplicate()
		best["dist"] = bd
	return best


static func place_name(x: float, z: float) -> String:
	## Human readable location ("12 km east of Oren Falls", "over the Western Sea").
	var c := nearest_city(x, z)
	var d: float = c.get("dist", INF)
	var on_water := is_water(x, z)
	if d < float(c.get("r", 0.0)) * 0.8:
		return "in " + String(c.name)
	if d < 60000.0:
		var brg := U.bearing_deg(c.x, c.z, x, z)
		var dirs := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
		var dn: String = dirs[int(round(brg / 45.0)) % 8]
		var where := "in the sea " if on_water else ""
		return "%s%d km %s of %s" % [where, int(round(d / 1000.0)), dn, c.name]
	if on_water:
		if x < -60000.0:
			return "over the Western Sea"
		return "over the Southern Sea" if z > 0 else "over the Northern Sea"
	if x > 100000.0 and z < -60000.0:
		return "in the Varn Mountains"
	return "in rural " + ("Westmark" if x < -330000.0 else "Calderra")


static func region_country(x: float, _z: float) -> String:
	if x < -300000.0:
		return "Westmark"
	if x < -70000.0:
		return "Oceanic"
	return "Calderra"


# ====================================================================== Sampler
class Sampler:
	## Thread-local terrain sampler (own noise objects, read-only shared data).
	var n_hills := FastNoiseLite.new()
	var n_ridge := FastNoiseLite.new()
	var n_warp := FastNoiseLite.new()
	var n_moist := FastNoiseLite.new()
	var n_fine := FastNoiseLite.new()
	var n_farm := FastNoiseLite.new()

	func _init() -> void:
		n_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n_hills.seed = 1337
		n_hills.frequency = 1.0 / 7000.0
		n_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
		n_hills.fractal_octaves = 5
		n_hills.fractal_gain = 0.48
		n_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n_ridge.seed = 4242
		n_ridge.frequency = 1.0 / 16000.0
		n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		n_ridge.fractal_octaves = 6
		n_ridge.fractal_gain = 0.52
		n_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX
		n_warp.seed = 99
		n_warp.frequency = 1.0 / 26000.0
		n_warp.fractal_type = FastNoiseLite.FRACTAL_FBM
		n_warp.fractal_octaves = 3
		n_moist.noise_type = FastNoiseLite.TYPE_SIMPLEX
		n_moist.seed = 7
		n_moist.frequency = 1.0 / 9000.0
		n_moist.fractal_type = FastNoiseLite.FRACTAL_FBM
		n_moist.fractal_octaves = 3
		n_fine.noise_type = FastNoiseLite.TYPE_SIMPLEX
		n_fine.seed = 31
		n_fine.frequency = 1.0 / 2600.0
		n_fine.fractal_type = FastNoiseLite.FRACTAL_FBM
		n_fine.fractal_octaves = 3
		n_farm.noise_type = FastNoiseLite.TYPE_SIMPLEX
		n_farm.seed = 555
		n_farm.frequency = 1.0 / 30000.0
		n_farm.fractal_octaves = 2

	func macro_at(x: float, z: float) -> float:
		# Uniform cubic B-spline over the baked grid (smooth, never overshoots).
		var gx := (x + MAP_HALF) / CELL - 0.5
		var gz := (z + MAP_HALF) / CELL - 0.5
		var ix := int(floor(gx))
		var iz := int(floor(gz))
		if ix < 1 or iz < 1 or ix > GRID - 3 or iz > GRID - 3:
			return -900.0
		var fx := gx - ix
		var fz := gz - iz
		var fx2 := fx * fx
		var fx3 := fx2 * fx
		var fz2 := fz * fz
		var fz3 := fz2 * fz
		var ax0 := (1.0 - 3.0 * fx + 3.0 * fx2 - fx3) / 6.0
		var ax1 := (4.0 - 6.0 * fx2 + 3.0 * fx3) / 6.0
		var ax2 := (1.0 + 3.0 * fx + 3.0 * fx2 - 3.0 * fx3) / 6.0
		var ax3 := fx3 / 6.0
		var az0 := (1.0 - 3.0 * fz + 3.0 * fz2 - fz3) / 6.0
		var az1 := (4.0 - 6.0 * fz2 + 3.0 * fz3) / 6.0
		var az2 := (1.0 + 3.0 * fz + 3.0 * fz2 - 3.0 * fz3) / 6.0
		var az3 := fz3 / 6.0
		var m := Geo.macro
		var base := (iz - 1) * GRID + ix - 1
		var r0 := m[base] * ax0 + m[base + 1] * ax1 + m[base + 2] * ax2 + m[base + 3] * ax3
		base += GRID
		var r1 := m[base] * ax0 + m[base + 1] * ax1 + m[base + 2] * ax2 + m[base + 3] * ax3
		base += GRID
		var r2 := m[base] * ax0 + m[base + 1] * ax1 + m[base + 2] * ax2 + m[base + 3] * ax3
		base += GRID
		var r3 := m[base] * ax0 + m[base + 1] * ax1 + m[base + 2] * ax2 + m[base + 3] * ax3
		return r0 * az0 + r1 * az1 + r2 * az2 + r3 * az3

	func base_height(x: float, z: float, with_water: bool = true) -> float:
		var wx := n_warp.get_noise_2d(x, z) * 5500.0
		var wz := n_warp.get_noise_2d(z + 9100.0, x - 3700.0) * 5500.0
		var m := macro_at(x + wx, z + wz)
		var h := m
		if m > -80.0 and m < 90.0:
			h += n_fine.get_noise_2d(x, z) * 34.0 * (1.0 - absf(m - 5.0) / 95.0)
		if m > 0.0:
			var rough := clampf(m / 500.0, 0.05, 1.0)
			h += (n_hills.get_noise_2d(x, z) * 0.5 + 0.18) * 260.0 * rough
			var mt := clampf((m - 550.0) / 1100.0, 0.0, 1.0)
			if mt > 0.0:
				var r := n_ridge.get_noise_2d(x, z)
				h += (r * 0.5 + 0.5) * 1500.0 * mt - 300.0 * mt
		if with_water:
			h = _carve_water(x, z, h)
		return h

	func _carve_water(x: float, z: float, h: float) -> float:
		for lk in Geo.lakes:
			var q := Vector2((x - lk.x) / lk.rx, (z - lk.z) / lk.rz)
			var l := q.length()
			if l < 1.6:
				var bed: float = float(lk.level) - 14.0 * (1.0 - U.smooth01(l))
				if l < 1.0:
					h = minf(h, bed - 2.0)
				else:
					var t := U.smooth01((l - 1.0) / 0.6)
					h = minf(h, lerpf(float(lk.level) - 1.5, maxf(h, float(lk.level) + 3.0), t))
		var key := Vector2i(int(floor(x / 4000.0)), int(floor(z / 4000.0)))
		if Geo.river_grid.has(key):
			var p := Vector2(x, z)
			for rs in Geo.river_grid[key]:
				var rv: Dictionary = Geo.rivers[rs[0]]
				var a: Vector2 = rv.pts[rs[1]]
				var b: Vector2 = rv.pts[rs[1] + 1]
				var ab := b - a
				var t2 := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1.0), 0.0, 1.0)
				var d := p.distance_to(a + ab * t2)
				var level: float = lerpf(rv.levels[rs[1]], rv.levels[rs[1] + 1], t2)
				var half: float = rv.width * 0.5
				if d < half:
					h = minf(h, level - 3.5 * (1.0 - d / half) - 0.8)
				elif d < half + 1600.0:
					var bank := level + (d - half) * 0.045 + 0.6
					h = minf(h, bank)
		return h

	func height(x: float, z: float) -> float:
		var h := base_height(x, z, true)
		# approach and climb-out valleys keep instrument procedures clear of terrain
		if h > 60.0:
			for c in Geo.corridors:
				var dx0: float = x - c[0]
				var dz0: float = z - c[1]
				var along: float = dx0 * c[2] + dz0 * c[3]
				if along < -3000.0 or along > 24000.0:
					continue
				var lat := absf(-dx0 * c[3] + dz0 * c[2])
				var wob := n_warp.get_noise_2d(x * 3.0, z * 3.0)
				var half_w := (900.0 + maxf(along, 0.0) * 0.2) * (1.0 + wob * 0.35)
				if lat > half_w * 2.6:
					continue
				var cap: float = c[4] + maxf(along, 0.0) * 0.045 - 60.0 * U.smooth01(along / 2500.0)
				cap += n_fine.get_noise_2d(x, z) * 35.0 * U.smooth01(along / 3000.0)
				if h > cap:
					var t := U.smooth01((lat - half_w) / (half_w * 1.6))
					t = t * t * (3.0 - 2.0 * t)
					h = lerpf(cap, h, t)
		# airport platforms
		for ap in Geo.airports_flat:
			var dx: float = x - ap[0]
			var dz: float = z - ap[1]
			var d2 := dx * dx + dz * dz
			var ro: float = ap[4]
			if d2 < ro * ro:
				var d := sqrt(d2)
				var t := 1.0 - U.smooth01((d - ap[3]) / (ro - ap[3]))
				h = lerpf(h, ap[2], t)
		return h

	func landuse(x: float, z: float) -> Dictionary:
		return landuse_h(x, z, height(x, z))

	func landuse_h(x: float, z: float, h: float) -> Dictionary:
		var moist := n_moist.get_noise_2d(x, z)
		var urban := 0.0
		for c in Geo.cities:
			var d := U.dist2d(x, z, c.x, c.z)
			if d < c.r * 1.4:
				var edge = n_fine.get_noise_2d(x * 1.7, z * 1.7) * c.r * 0.28
				urban = maxf(urban, 1.0 - U.smooth01((d + edge - c.r * 0.55) / (c.r * 0.6)))
		var near_ap := 0.0
		for ap in Geo.airports_flat:
			var d2 := U.dist2d(x, z, ap[0], ap[1])
			near_ap = maxf(near_ap, 1.0 - U.smooth01((d2 - ap[3]) / 1500.0))
		var forest := U.smooth01((moist - 0.02) / 0.3) * (1.0 - urban) * (1.0 - near_ap)
		forest *= 1.0 - U.smooth01((h - 1650.0) / 250.0)
		if h < 2.0:
			forest = 0.0
		var farm_region := n_farm.get_noise_2d(x, z) * 0.5 + 0.5
		var farm := U.smooth01((farm_region - 0.35) / 0.2) * (1.0 - forest) * (1.0 - urban) * (1.0 - near_ap)
		farm *= 1.0 - U.smooth01((h - 450.0) / 200.0)
		if h < 3.0:
			farm = 0.0
		return {"h": h, "moist": moist, "urban": urban, "forest": forest, "farm": farm, "airport": near_ap}
