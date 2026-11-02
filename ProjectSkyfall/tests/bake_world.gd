extends Node
## Bakes the real-world region's macro heightfield into res://data (shipped with the game),
## then reports land/water at every real airport, city and landmark.

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var g := Geo.bake_world()
	print("baked %d cells in %d ms" % [g.size(), Time.get_ticks_msec() - t0])
	var f := FileAccess.open("res://data/geo_world_v%d.bin" % Geo.WORLD_VERSION, FileAccess.WRITE)
	f.store_buffer(g.to_byte_array())
	f.close()
	Geo.macro_world = g
	var land := 0
	for v in g:
		if v > 0.0:
			land += 1
	print("land %.1f%%" % (100.0 * land / g.size()))
	for icao in Airports.ORDER:
		var a: Dictionary = Airports.get_ap(icao)
		if String(a.get("region", "")) != "world":
			continue
		var h := Geo.height(a.x, a.z)
		var ct := Airports.city_center(icao)
		var wet := 0
		var r := float(a.city_info.radius)
		for k in 36:
			var ang := TAU * k / 36.0
			for rr in [0.25, 0.55, 0.85]:
				if Geo.is_water(ct.x + cos(ang) * r * rr, ct.y + sin(ang) * r * rr):
					wet += 1
		var hi := -INF
		for k2 in 24:
			var ang2 := TAU * k2 / 24.0
			for d in [6000.0, 12000.0, 18000.0]:
				hi = maxf(hi, Geo.height(a.x + cos(ang2) * d, a.z + sin(ang2) * d))
		print("%s %-22s ground %6.1f (elev %5.0f)  city %s water %2d%%  max terrain 18km %5.0f  %s" % [icao, a.short, h, float(a.elev),
			"WET " if Geo.is_water(ct.x, ct.y) else "dry ", wet * 100 / 108, hi, Geo.place_name(a.x, a.z)])
	for lm in RealWorld.LANDMARKS:
		print("   %-26s %s  h %6.1f" % [lm.name, "WATER" if Geo.is_water(lm.x, lm.z) else "land ", Geo.height(lm.x, lm.z)])
	get_tree().quit()
