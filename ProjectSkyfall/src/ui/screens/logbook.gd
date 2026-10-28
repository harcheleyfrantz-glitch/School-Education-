extends ScreenBase
## MY LOGBOOK: totals, every logged flight in a table (date, flight, route, aircraft, block
## time, grade and outcome) and hours by aircraft type.


func setup(_params: Dictionary) -> void:
	var p: Dictionary = Game.player
	if p.is_empty():
		Game.goto("profile")
		return
	frame("My Logbook", "%s · %s" % [p.get("name", ""), p.get("license", "")], "profile", 0.74)
	var log: Array = p.get("logbook", [])
	var tiles := UIStyle.hbox(12)
	content.add_child(tiles)
	var scores := log.map(func(e): return float(e.get("score", 0.0)))
	var avg := 0.0
	for s in scores:
		avg += float(s)
	avg = avg / maxf(scores.size(), 1)
	tiles.add_child(_tile("Total time", "%s h" % U.fmt_int(int(float(p.get("hours", 0.0))))))
	tiles.add_child(_tile("Flights", U.fmt_int(int(p.get("flights", 0)))))
	tiles.add_child(_tile("Landings", U.fmt_int(int(p.get("landings", 0)))))
	tiles.add_child(_tile("Average score", ("%d" % int(avg)) if not log.is_empty() else "—"))
	var c := card("Flights")
	if log.is_empty():
		c.add_child(UIStyle.label("No flights logged yet. Your first flight will appear here.", 14, UIStyle.DIM))
	else:
		var grid := GridContainer.new()
		grid.columns = 7
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 0)
		c.add_child(grid)
		for h in ["Date", "Flight", "Route", "Aircraft", "Block", "Grade", "Result"]:
			var hl := UIStyle.caps(h, 10, UIStyle.DIM, 800, 2)
			hl.custom_minimum_size = Vector2(0, 26)
			grid.add_child(hl)
		var shown := 0
		for i in range(log.size() - 1, -1, -1):
			if shown >= 80:
				break
			shown += 1
			var e: Dictionary = log[i]
			var bad := String(e.get("outcome", "")) in ["crashed", "ditched"]
			var col := UIStyle.RED if bad else Color.WHITE
			grid.add_child(_cell(U.fmt_date_short(float(e.get("t", 0.0))), UIStyle.DIM))
			grid.add_child(_cell(String(e.get("flight", "")), col, true))
			grid.add_child(_cell("%s → %s" % [e.get("from", ""), e.get("to", "")], col))
			grid.add_child(_cell("%s  %s" % [AircraftTypes.get_type(String(e.get("type", ""))).short, e.get("reg", "")], UIStyle.DIM))
			grid.add_child(_cell("%.1f h" % float(e.get("hours", 0.0)), col))
			var g := String(e.get("grade", ""))
			var gc := UIStyle.GREEN if g in ["A", "B"] else (UIStyle.AMBER if g == "C" else UIStyle.RED)
			var gw := CenterContainer.new()
			gw.custom_minimum_size = Vector2(0, 30)
			if g != "":
				gw.add_child(UIStyle.chip(g, gc, true))
			grid.add_child(gw)
			grid.add_child(_cell(String(e.get("outcome", "")).capitalize(), UIStyle.RED if bad else UIStyle.DIM))
	var hb: Dictionary = p.get("hours_by_type", {})
	if not hb.is_empty():
		var t := card("Hours by type")
		var most := 1.0
		for k in hb.keys():
			most = maxf(most, float(hb[k]))
		for k in hb.keys():
			var row := UIStyle.hbox(12)
			var l := UIStyle.label(String(AircraftTypes.get_type(String(k)).name), 14, Color.WHITE)
			l.custom_minimum_size = Vector2(200, 0)
			row.add_child(l)
			var pb := ProgressBar.new()
			pb.show_percentage = false
			pb.value = float(hb[k]) / most * 100.0
			pb.custom_minimum_size = Vector2(200, 6)
			pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(pb)
			var vl := UIStyle.label("%s h" % U.fmt_int(int(float(hb[k]))), 14, Color.WHITE, true)
			vl.custom_minimum_size = Vector2(80, 0)
			vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(vl)
			t.add_child(row)


func _tile(label_text: String, value: String) -> Control:
	var p := UIStyle.glass_panel(16)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UIStyle.vbox(0)
	p.add_child(v)
	v.add_child(UIStyle.caps(label_text, 10, UIStyle.DIM, 800, 2))
	v.add_child(UIStyle.title(value, 28, Color.WHITE))
	return p


static func _cell(text: String, col: Color, bold: bool = false) -> Label:
	var l := UIStyle.label(text, 14, col, bold)
	l.custom_minimum_size = Vector2(0, 30)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l
