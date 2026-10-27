extends SceneTree
## Prints terrain under each ILS approach path versus a 3 degree glide path (headless).
func _init() -> void:
	Geo.init_world()
	var worst := INF
	for icao in Airports.ORDER:
		for e in Airports.runway_ends(icao):
			if e.surface != "asphalt":
				continue
			var out := Vector2(-sin(deg_to_rad(e.hdg)), cos(deg_to_rad(e.hdg)))
			var min_clear := INF
			for k in range(1, 40):
				var d := k * 500.0
				var x: float = e.thr_x + out.x * d
				var z: float = e.thr_z + out.y * d
				var gp: float = e.elev + 15.0 + d * tan(deg_to_rad(3.0))
				var g := Geo.ground_height(x, z)
				min_clear = minf(min_clear, gp - g)
			worst = minf(worst, min_clear)
			print("%s %s: min clearance below 3deg path over 19.5 km = %d m" % [icao, e.name, int(min_clear)])
	print("WORST: ", int(worst))
	quit()
