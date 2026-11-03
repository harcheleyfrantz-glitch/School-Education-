extends Node
## Compares each real-world airport's elevation with the surrounding terrain (ring outside the
## flattened area) so airports sit level with the land around them.
func _ready() -> void:
	for icao in Airports.ORDER:
		var a: Dictionary = Airports.get_ap(icao)
		if String(a.get("region", "")) != "world":
			continue
		var r_in := 0.0
		for f in Geo.airports_flat:
			if absf(float(f[0]) - float(a.x)) < 1.0 and absf(float(f[1]) - float(a.z)) < 1.0:
				r_in = float(f[4])
		var hs := []
		for k in 24:
			var ang := TAU * k / 24.0
			var h := Geo.height(float(a.x) + cos(ang) * (r_in + 1500.0), float(a.z) + sin(ang) * (r_in + 1500.0))
			if not Geo.is_water(float(a.x) + cos(ang) * (r_in + 1500.0), float(a.z) + sin(ang) * (r_in + 1500.0)):
				hs.append(h)
		hs.sort()
		var med: float = hs[hs.size() / 2] if not hs.is_empty() else 0.0
		print("ELEV %s elev=%.0f ring_med=%.0f min=%.0f max=%.0f r=%.0f" % [icao, float(a.elev), med, hs[0] if not hs.is_empty() else 0.0, hs[hs.size() - 1] if not hs.is_empty() else 0.0, r_in])
	get_tree().quit()
