extends Node
## Stand conflicts at the real airports: pairs of stands where the largest aircraft each one
## takes would overlap if both were occupied. Traffic avoids such pairs at run time; this shows
## how common they are. Usage: -- all | ICAO,ICAO  [detail stand name]
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var list: Array = RealAirports.OUTLINE.keys() if a.is_empty() or a[0] == "all" else Array(a[0].split(","))
	var detail := a[1] if a.size() > 1 else ""
	var total_pairs := 0
	var total_stands := 0
	for icao in list:
		var L := AirportLayout.get_layout(String(icao))
		var fps := []
		for s in L.stands:
			fps.append(AirportLayout.parked_footprint(s, AircraftTypes.get_type(_design_type(float(s.max_span)))))
		var n := 0
		var ex := []
		for i in L.stands.size():
			var si: Dictionary = L.stands[i]
			for j in range(i + 1, L.stands.size()):
				var sj: Dictionary = L.stands[j]
				if (si.stop as Vector2).distance_to(sj.stop) > 160.0:
					continue
				if AirportLayout.footprints_clash(fps[i], fps[j]):
					n += 1
					if ex.size() < 4:
						ex.append("%s/%s %.0fm" % [si.name, sj.name, (si.stop as Vector2).distance_to(sj.stop)])
				if detail != "" and (String(si.name) == detail or String(sj.name) == detail) and (si.stop as Vector2).distance_to(sj.stop) < 90.0:
					print("  %s(span %.0f hdg %.0f) - %s(span %.0f hdg %.0f): %.1f m apart, clash %s" % [si.name, float(si.max_span), float(si.hdg), sj.name,
						float(sj.max_span), float(sj.hdg), (si.stop as Vector2).distance_to(sj.stop), AirportLayout.footprints_clash(fps[i], fps[j])])
		total_pairs += n
		total_stands += L.stands.size()
		print("CLASH %s stands %d clashing pairs %d %s" % [icao, L.stands.size(), n, ", ".join(ex)])
	print("CLASH TOTAL stands %d clashing pairs %d" % [total_stands, total_pairs])
	get_tree().quit()


static func _design_type(max_span: float) -> String:
	var best := "rj90"
	var best_span := 0.0
	for t in AircraftTypes.ORDER:
		var s := AircraftTypes.get_type(t)
		if String(s.category) in ["trainer", "fighter"]:
			continue
		if float(s.span) <= max_span and float(s.span) > best_span:
			best = t
			best_span = float(s.span)
	return best
