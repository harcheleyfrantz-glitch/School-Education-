extends Node
func _ready() -> void:
	var icao: String = OS.get_cmdline_user_args()[0]
	var t0 := Time.get_ticks_msec()
	var L := AirportLayout.get_layout(icao)
	print("LAYOUT %s built in %d ms: stands %d buildings %d runways %d nodes %d edges %d" % [icao, Time.get_ticks_msec() - t0, L.stands.size(), L.buildings.size(), L.runways.size(), L.taxi_nodes.size(), L.taxi_edges.size()])
	var t1 := Time.get_ticks_msec()
	var sd: Dictionary = L.stands[3]
	var n := 0
	for rw in L.runways:
		for e in rw.ends:
			var hold := AirportLayout.hold_node_for(L, String(e.name))
			var path := AirportLayout.find_path(L, int(sd.lane_node), hold)
			print("   route to %s: %d nodes" % [e.name, path.size()])
			n += 1
	print("ROUTES %d in %d ms" % [n, Time.get_ticks_msec() - t1])
	get_tree().quit()
