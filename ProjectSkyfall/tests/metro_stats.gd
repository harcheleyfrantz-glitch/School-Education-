extends Node
## Metro sizes: how far each big city's built-up area reaches, and the flying time across it.
func _ready() -> void:
	if Geo.cities.is_empty():
		Geo.init_world()
	var rows := []
	for c in Geo.cities:
		if int(c.pop) < 1500000:
			continue
		# walk out from the centre along 8 bearings until the urban weight falls below 0.3
		var reach := 0.0
		for k in 8:
			var a := TAU * k / 8.0
			var d := 0.0
			while d < 90000.0:
				var lu := Geo.main_sampler.landuse(float(c.x) + cos(a) * d, float(c.z) + sin(a) * d)
				if float(lu.urban) < 0.3 and d > 2000.0:
					break
				d += 1000.0
			reach += d
		reach /= 8.0
		rows.append([String(c.name), float(c.r_core), float(c.r), reach])
	rows.sort_custom(func(a, b): return a[3] > b[3])
	for r in rows.slice(0, 20):
		print("METRO %-16s core %5.1f km  metro radius %5.1f km  built-up across %5.1f km  = %4.1f min at 160 kt, %4.1f min at 250 kt" % [r[0], r[1] / 1000.0, r[2] / 1000.0, r[3] * 2.0 / 1000.0, r[3] * 2.0 / 82.3 / 60.0, r[3] * 2.0 / 128.6 / 60.0])
	get_tree().quit()
