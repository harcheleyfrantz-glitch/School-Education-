extends ScreenBase
## The pilot's logbook.


func setup(_params: Dictionary) -> void:
	var p: Dictionary = Game.player
	frame("Logbook", "%s · %s hours" % [p.name, U.fmt_int(int(float(p.hours)))], "hub", 0.66)
	var c := card("")
	var log: Array = p.get("logbook", [])
	if log.is_empty():
		c.add_child(UIStyle.label("No flights logged yet.", 14, UIStyle.DIM))
	for i in range(log.size() - 1, maxi(log.size() - 60, 0) - 1, -1):
		var e: Dictionary = log[i]
		var col := "#ff6b60" if String(e.outcome) in ["crashed", "ditched"] else "#c8d3dc"
		c.add_child(UIStyle.rich("%s  [b]%s[/b]  %s → %s  %s %s  %.1f h  [color=%s]%s %s[/color]" % [U.fmt_date_short(float(e.t)), e.flight, e.from, e.to,
			AircraftTypes.get_type(String(e.type)).short, e.reg, float(e.hours), col, e.outcome, e.get("grade", "")], 14))
	var hb: Dictionary = p.get("hours_by_type", {})
	if not hb.is_empty():
		var t := card("Hours by type")
		for k in hb.keys():
			stat_row(t, AircraftTypes.get_type(String(k)).name, "%.1f h" % float(hb[k]))
