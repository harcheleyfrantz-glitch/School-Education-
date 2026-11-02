extends Node
## Every airport layout: stands, terminals, a taxi route from a gate to each runway end, and no
## runway running through a terminal building.

func _ready() -> void:
	var bad := 0
	for icao in Airports.ORDER:
		var L := AirportLayout.get_layout(icao)
		var msg := []
		if L.stands.is_empty():
			msg.append("no stands")
		var sd: Dictionary = L.stands[mini(3, L.stands.size() - 1)] if not L.stands.is_empty() else {}
		for rw in L.runways:
			if String(rw.surface) != "asphalt":
				continue
			for e in rw.ends:
				var hold := AirportLayout.hold_node_for(L, String(e.name))
				if hold < 0:
					msg.append("no hold for %s" % e.name)
					continue
				if not sd.is_empty() and AirportLayout.find_path(L, int(sd.lane_node), hold).is_empty():
					msg.append("no taxi route to %s" % e.name)
			# runway vs terminal overlap
			for b in L.buildings:
				var c: Vector2 = b.center
				var ax: Vector2 = (b.axis as Vector2).normalized()
				for k in 41:
					var p: Vector2 = (rw.center as Vector2) + (rw.dir as Vector2) * (float(k) / 40.0 - 0.5) * float(rw.len)
					var rel := p - c
					if absf(rel.dot(ax)) < float(b.len) * 0.5 + 40.0 and absf(rel.dot(Vector2(-ax.y, ax.x))) < float(b.depth) * 0.5 + 40.0:
						msg.append("runway %s crosses the %s" % [rw.id, b.kind])
						break
		print("%s %-26s stands %2d buildings %d runways %d %s" % [icao, Airports.get_ap(icao).short, L.stands.size(), L.buildings.size(), L.runways.size(), "OK" if msg.is_empty() else str(msg)])
		if not msg.is_empty():
			bad += 1
	print("LAYOUT CHECK: %d airports with problems" % bad)
	get_tree().quit()
