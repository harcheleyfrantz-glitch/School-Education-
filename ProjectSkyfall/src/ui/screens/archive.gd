extends ScreenBase
## Past characters and the accident record of this world.


func setup(_params: Dictionary) -> void:
	frame("Archive", "Careers that ended, and the accidents this world remembers", "menu", 0.62)
	var c := card("Former pilots")
	if Game.archive.is_empty():
		c.add_child(UIStyle.label("No careers have ended yet.", 14, UIStyle.DIM))
	for rec in Game.archive:
		var reason := String(rec.get("end_reason", ""))
		var col := "#ff6b60" if reason == "deceased" else "#c8d3dc"
		var det: Dictionary = rec.get("end_details", {})
		c.add_child(UIStyle.rich("[b]%s[/b] — %s, %d hours. [color=%s]%s[/color] %s" % [rec.get("name", ""), rec.get("rank", ""), int(float(rec.get("hours", 0.0))),
			col, {"deceased": "Died", "abandoned": "Retired", "retired": "Retired"}.get(reason, reason.capitalize()),
			("(%s, %s)" % [U.fmt_date(float(rec.get("ended", 0.0))), String(det.get("place", ""))]) if not det.is_empty() else ""], 15))
		if String(det.get("cause", "")) != "":
			c.add_child(UIStyle.label("Probable cause: " + String(det.cause), 13, UIStyle.DIM))
	var a := card("Accidents and serious incidents")
	if News.incidents.is_empty():
		a.add_child(UIStyle.label("No accidents recorded.", 14, UIStyle.DIM))
	for inc in News.incidents:
		a.add_child(UIStyle.rich("[b]%s[/b] %s — %s" % [U.fmt_date(float(inc.get("clock", 0.0))), inc.get("title", ""), inc.get("summary", "")], 14))
