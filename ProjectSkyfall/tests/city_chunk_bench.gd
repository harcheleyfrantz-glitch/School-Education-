extends Node
## City chunk cost: build time and instance counts (buildings, cars) for 2 km detail chunks across
## a metro, from downtown out to the suburbs. Usage: -- City quality
const CityStyles := preload("res://src/data/city_styles.gd")
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var name := a[0] if a.size() > 0 else "Tokyo"
	var props := {"potato": 0.0, "low": 0.25, "medium": 0.6, "high": 1.0, "ultra": 1.6}.get(a[1] if a.size() > 1 else "medium", 0.6)
	if Geo.cities.is_empty():
		Geo.init_world()
	TerrainManager._ensure_meshes()
	CityStyles.prepare(Geo.cities)
	var city := {}
	for c in Geo.cities:
		if String(c.name) == name:
			city = c
	var size := 2048.0
	var dirs := [Vector2(1, 0.3), Vector2(-1, 0), Vector2(0, -1), Vector2(0.7, -0.7)]
	for k in 16:
		var dv: Vector2 = dirs[k / 4].normalized()
		var d := float(k % 4) * 9000.0 + 4000.0
		var cx := float(city.x) + dv.x * d
		var cz := float(city.z) + dv.y * d
		var job := {"key": Vector3i(12, k, 0), "size": size, "cx": cx, "cz": cz, "res": 32, "detail": true, "trees": 0.55, "buildings": 0.7,
			"cars": props, "gen": 0, "roads": []}
		for h in Geo.highways():
			var ha := Vector2(h[0], h[1])
			var hb := Vector2(h[2], h[3])
			var lo := Vector2(minf(ha.x, hb.x), minf(ha.y, hb.y)) - Vector2.ONE * (size + 400.0)
			var hi := Vector2(maxf(ha.x, hb.x), maxf(ha.y, hb.y)) + Vector2.ONE * (size + 400.0)
			if cx > lo.x and cx < hi.x and cz > lo.y and cz < hi.y:
				job.roads.append(h)
		var t0 := Time.get_ticks_usec()
		var r := TerrainManager.build_chunk(job)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var bld := 0
		var cars := 0
		for mm in r.multimeshes:
			if mm.kind == "building":
				bld += int(mm.count)
			elif mm.kind == "car":
				cars += int(mm.count)
		var u: float = Geo.main_sampler.landuse(cx, cz).urban
		var h := Geo.main_sampler.height(cx, cz)
		print("CHUNK %s dir %d %4.1f km out: urban %.2f h %5.1f build %6.1f ms  buildings %5d  cars %5d" % [name, k / 4, d / 1000.0, u, h, ms, bld, cars])
	get_tree().quit()
