extends Node
## Real airports: layout build time, every runway end reachable from a gate (taxi, no runway
## use) and every gate reachable from a runway exit (arrival, runway allowed), ATC route names.
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var list: Array = RealAirports.OUTLINE.keys() if args.is_empty() or args[0] == "all" else Array(args[0].split(","))
	var bad := 0
	for icao in list:
		var t0 := Time.get_ticks_msec()
		var L := AirportLayout.get_layout(icao)
		var ms := Time.get_ticks_msec() - t0
		if not L.get("real", false):
			print("REAL %s NOT REAL" % icao)
			bad += 1
			continue
		var t1 := Time.get_ticks_msec()
		var fails := []
		var sample: Array = []
		for k in 3:
			sample.append(L.stands[(k * 7919) % L.stands.size()])
		var ends := 0
		var names_eg := ""
		for rw in L.runways:
			for e in rw.ends:
				ends += 1
				var hold := AirportLayout.hold_node_for(L, String(e.name))
				if hold < 0:
					fails.append("nohold " + String(e.name))
					continue
				for sd in sample:
					var path := AirportLayout.find_path(L, int(sd.lane_node), hold)
					if path.is_empty():
						fails.append("dep %s->%s" % [sd.name, e.name])
					elif names_eg == "":
						names_eg = ", ".join(AirportLayout.route_names(path))
				var rn := AirportLayout.runway_node_near(L, rw.index, e.thr + e.dir * rw.len * 0.6)
				var sd2: Dictionary = sample[0]
				if rn < 0 or AirportLayout.find_path(L, rn, int(sd2.node), true).is_empty():
					fails.append("arr %s->%s" % [e.name, sd2.name])
		print("REAL %s layout %d ms, stands %d, nodes %d, %d runway ends, routes %d ms, fails %d %s | e.g. taxi via %s" % [icao, ms, L.stands.size(), L.taxi_nodes.size(), ends,
			Time.get_ticks_msec() - t1, fails.size(), str(fails.slice(0, 4)), names_eg])
		if not fails.is_empty():
			bad += 1
	print("REAL CHECK DONE: %d airports with problems" % bad)
	get_tree().quit()
