extends Control
## End-of-flight debrief: grade and category scores, remarks, pay; after an accident the human
## toll, the investigation report and what happens to the pilot. Continue applies the result to
## the career (or, if the pilot died, closes the character's story for good).

var result: Dictionary = {}
var cons: Dictionary = {}


func show_result(res: Dictionary) -> void:
	result = res
	cons = CareerRules.consequences(res)
	theme = UIStyle.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.04, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var p := UIStyle.panel(Vector2(860, 0))
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.anchor_top = 0.05
	p.anchor_bottom = 0.95
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.offset_left = -430
	p.offset_right = 430
	p.offset_top = 0
	p.offset_bottom = 0
	add_child(p)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(sc)
	var v := UIStyle.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var outcome := String(res.get("outcome", "landed"))
	var crashed := outcome in ["crashed", "ditched"]
	if bool(cons.dead):
		_memorial(v)
	else:
		_header(v, outcome)
	if crashed:
		_accident(v)
	else:
		_scores(v)
	_consequences(v)
	var row := UIStyle.hbox(10)
	row.add_child(UIStyle.spacer())
	if result.has("recorder") and not crashed:
		row.add_child(UIStyle.button("Watch replay", func(): Game.goto("replay", {"result": result})))
	row.add_child(UIStyle.button("Continue", _continue, 180, UIStyle.ACCENT))
	v.add_child(row)


func _header(v: VBoxContainer, outcome: String) -> void:
	var h := UIStyle.hbox(16)
	var grade := String(result.get("grade", "-"))
	var gcol := UIStyle.GREEN if grade in ["A", "B"] else (UIStyle.AMBER if grade == "C" else UIStyle.RED)
	if outcome in ["crashed", "ditched"]:
		gcol = UIStyle.RED
	var g := UIStyle.label(grade if not outcome in ["crashed", "ditched"] else "!", 64, gcol, true)
	g.custom_minimum_size = Vector2(90, 0)
	h.add_child(g)
	var c := UIStyle.vbox(4)
	var titles := {"landed": "Flight complete", "diverted": "Diverted landing", "crashed": "Accident", "ditched": "Ditching", "abandoned": "Flight abandoned"}
	c.add_child(UIStyle.label(String(titles.get(outcome, outcome.capitalize())), 28, UIStyle.TEXT, true))
	c.add_child(UIStyle.label("%s · %s %s · %s → %s" % [result.get("callsign", ""), AircraftTypes.get_type(String(result.get("type", "s320"))).name,
		result.get("reg", ""), result.get("dep", ""), result.get("arr", "")], 16, UIStyle.DIM))
	if not outcome in ["crashed", "ditched", "abandoned"]:
		c.add_child(UIStyle.label("Score %d / 100   ·   %.1f block hours" % [int(result.get("score", 0.0)), float(result.get("hours", 0.0))], 16, UIStyle.ACCENT))
	h.add_child(c)
	v.add_child(h)


func _scores(v: VBoxContainer) -> void:
	var cats: Dictionary = result.get("categories", {})
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	for k in ["landing", "approach", "procedures", "atc", "comfort", "efficiency", "safety"]:
		var l := UIStyle.label(String(k).capitalize(), 15, UIStyle.TEXT)
		l.custom_minimum_size = Vector2(130, 0)
		grid.add_child(l)
		var pb := ProgressBar.new()
		pb.value = float(cats.get(k, 0.0))
		pb.custom_minimum_size = Vector2(520, 16)
		pb.show_percentage = true
		var col := UIStyle.GREEN if pb.value >= 80.0 else (UIStyle.AMBER if pb.value >= 55.0 else UIStyle.RED)
		pb.add_theme_stylebox_override("fill", UIStyle.box(col, 6, Color(0, 0, 0, 0), 0, 0))
		grid.add_child(pb)
	v.add_child(grid)
	var td: Dictionary = result.get("touchdown", {})
	if not td.is_empty():
		v.add_child(UIStyle.label("Touchdown %d ft/min · %.1f m from centreline · %d m past the threshold · %.2f g" % [int(absf(float(td.get("vs_fpm", 0.0)))),
			absf(float(td.get("centerline", 0.0))), int(td.get("dist_from_thr", 0.0)), float(td.get("g", 1.0))], 15, UIStyle.DIM))
	var notes: Array = result.get("notes", [])
	if not notes.is_empty():
		var txt := ""
		for n in notes:
			txt += "• %s\n" % n
		v.add_child(UIStyle.rich(txt, 15))
	var pay := float(result.get("pay", 0.0)) + float(result.get("bonus", 0.0))
	if pay != 0.0:
		v.add_child(UIStyle.label("Pay %s%s" % [U.fmt_money(pay), "  (incl. bonus %s)" % U.fmt_money(float(result.bonus)) if float(result.get("bonus", 0.0)) > 0.0 else ""], 16, UIStyle.GREEN))


func _accident(v: VBoxContainer) -> void:
	var af: Dictionary = result.get("aftermath", {})
	var c: Dictionary = af.get("counts", {})
	var inv: Dictionary = result.get("investigation", {})
	v.add_child(UIStyle.label("%s, %s" % [String(af.get("place", "")), U.fmt_datetime(float(result.get("clock", WorldSim.clock)))], 15, UIStyle.DIM))
	var toll := "[b]%d[/b] on board · [color=#ff6b60][b]%d killed[/b][/color] · %d critically injured · %d seriously injured · %d minor injuries · %d unhurt" % [
		int(c.get("aboard", 0)), int(c.get("fatal", 0)), int(c.get("critical", 0)), int(c.get("serious", 0)), int(c.get("minor", 0)), int(c.get("uninjured", 0))]
	v.add_child(UIStyle.rich(toll, 16))
	var victims: Array = af.get("victims", [])
	if not victims.is_empty():
		var names := []
		for vi in victims.slice(0, 12):
			names.append("%s (%d), %s" % [vi.name, int(vi.age), vi.home])
		var more := victims.size() - names.size()
		v.add_child(UIStyle.rich("[color=#9fb1c2]Among the victims: %s%s[/color]" % [", ".join(names), (" and %d others" % more) if more > 0 else ""], 14))
	if inv.is_empty():
		return
	v.add_child(UIStyle.label("Preliminary investigation report", 20, UIStyle.AMBER, true))
	v.add_child(UIStyle.rich("[b]Probable cause:[/b] %s" % inv.get("probable_cause", ""), 16))
	var txt := ""
	for f in inv.get("findings", []):
		txt += "• %s\n" % f
	if txt != "":
		v.add_child(UIStyle.rich("[b]Findings[/b]\n" + txt, 15))
	txt = ""
	for f2 in inv.get("factors", []):
		txt += "• %s\n" % f2
	if txt != "":
		v.add_child(UIStyle.rich("[b]Contributing factors[/b]\n" + txt, 15))
	var sh: Dictionary = inv.get("shares", {})
	var parts := []
	for k in ["pilot", "maintenance", "weather", "atc", "manufacturer"]:
		if float(sh.get(k, 0.0)) > 0.04:
			parts.append("%s %d%%" % [k, int(float(sh[k]) * 100.0)])
	v.add_child(UIStyle.label("Responsibility: " + ", ".join(parts), 15, UIStyle.DIM))
	txt = ""
	for r in inv.get("recommendations", []):
		txt += "• %s\n" % r
	v.add_child(UIStyle.rich("[b]Safety recommendations[/b]\n" + txt, 14))


func _consequences(v: VBoxContainer) -> void:
	var msgs: Array = cons.get("messages", [])
	if msgs.is_empty() and float(cons.get("reputation", 0.0)) == 0.0:
		return
	v.add_child(UIStyle.label("For your career", 18, UIStyle.ACCENT, true))
	var txt := ""
	for m in msgs:
		txt += "• %s\n" % m
	var rep := float(cons.get("reputation", 0.0))
	if absf(rep) >= 0.5:
		txt += "• Reputation %+d\n" % int(round(rep))
	if int(cons.get("medical_days", 0)) > 0:
		txt += "• Medical leave: %d days\n" % int(cons.medical_days)
	v.add_child(UIStyle.rich(txt, 15))


func _memorial(v: VBoxContainer) -> void:
	var name := String(Game.player.get("name", "The pilot")) if Game.has_character() else "The pilot"
	v.add_child(UIStyle.label("In memoriam", 30, UIStyle.TEXT, true))
	var hrs := float(Game.player.get("hours", 0.0)) if Game.has_character() else 0.0
	v.add_child(UIStyle.rich("[i]%s did not survive the accident at %s.\n%d flight hours, %d flights.[/i]\n\nThis character's story has ended. Their record is kept in the archive, and the world will remember what happened." % [
		name, String(result.get("aftermath", {}).get("place", "")), int(hrs), int(Game.player.get("flights", 0)) if Game.has_character() else 0], 16))


func _continue() -> void:
	if Game.has_character() and String(result.get("mode", "pilot")) == "pilot" and not bool(result.get("free_flight", false)):
		CareerRules.apply_result(result)
	elif News.has_method("on_flight_result"):
		News.call("on_flight_result", result, cons)
	get_tree().paused = false
	Engine.time_scale = 1.0
	Game.goto("hub" if Game.has_character() else "menu", {"last_result": result})
