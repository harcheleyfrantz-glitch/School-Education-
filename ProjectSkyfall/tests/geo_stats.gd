extends SceneTree
## Prints land-use statistics around a few points (headless).
func _init() -> void:
	Geo.init_world()
	var s := Geo.main_sampler
	for c in [[-30000.0, 9000.0], [60000.0, -40000.0], [205000.0, -150000.0], [230000.0, -170000.0], [-49000.0, 11000.0]]:
		var forest := 0.0
		var farm := 0.0
		var urban := 0.0
		var water := 0
		var hmin := INF
		var hmax := -INF
		var n := 0
		var t0 := Time.get_ticks_usec()
		for j in 20:
			for i in 20:
				var x: float = c[0] + (i - 10) * 500.0
				var z: float = c[1] + (j - 10) * 500.0
				var h := s.height(x, z)
				var lu := s.landuse_h(x, z, h)
				forest += lu.forest
				farm += lu.farm
				urban += lu.urban
				if h < 0.0:
					water += 1
				hmin = minf(hmin, h)
				hmax = maxf(hmax, h)
				n += 1
		var us := (Time.get_ticks_usec() - t0) / float(n)
		print("%s: forest=%.2f farm=%.2f urban=%.2f water=%d h=[%d..%d] %.1f us/sample  %s" % [str(c), forest / n, farm / n, urban / n, water, hmin, hmax, us, Geo.place_name(c[0], c[1])])
	quit()
