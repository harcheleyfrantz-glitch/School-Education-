extends Node
## Elevation of each airport against the terrain ring just outside its flattened area.
## Usage: -- ICAO,ICAO,...
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var list := (a[0] if a.size() > 0 else "").split(",")
	Geo.init_world()
	for icao in list:
		var ap: Dictionary = Airports.get_ap(icao)
		var r_in := 0.0
		for f in Geo.airports_flat:
			if absf(float(f[0]) - float(ap.x)) < 1.0 and absf(float(f[1]) - float(ap.z)) < 1.0:
				r_in = float(f[4])
		var hs := []
		for k in 24:
			var ang := TAU * k / 24.0
			var x := float(ap.x) + cos(ang) * (r_in + 1500.0)
			var z := float(ap.z) + sin(ang) * (r_in + 1500.0)
			if not Geo.is_water(x, z):
				hs.append(Geo.height(x, z))
		hs.sort()
		var med: float = hs[hs.size() / 2] if not hs.is_empty() else 0.0
		var lo: float = hs[0] if not hs.is_empty() else 0.0
		var hi: float = hs[hs.size() - 1] if not hs.is_empty() else 0.0
		print("ELEV %s elev=%.0f ring_med=%.0f min=%.0f max=%.0f land=%d" % [icao, float(ap.elev), med, lo, hi, hs.size()])
	get_tree().quit()
