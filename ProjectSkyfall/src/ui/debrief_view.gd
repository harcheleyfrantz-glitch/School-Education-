extends Control
## End-of-flight debrief: grade and category scores, remarks, pay; after an accident a compact
## facts card (the human toll, the probable cause, how responsibility is shared) and the
## investigation report itself as a video - the reconstructed flight with flight-data overlays,
## the cockpit voice transcript, narrated findings and recommendations. Normal flights can be
## replayed right here. Continue applies the result to the career (or, if the pilot died,
## closes the character's story for good).

var result: Dictionary = {}
var cons: Dictionary = {}
var player: BroadcastPlayer = null
var _replay_slot: VBoxContainer
var _replay_btn: Button
var _3d_was_disabled := false


func show_result(res: Dictionary) -> void:
	result = res
	cons = CareerRules.consequences(res)
	theme = UIStyle.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.04, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var p := UIStyle.panel(Vector2(900, 0))
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.anchor_top = 0.04
	p.anchor_bottom = 0.96
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.offset_left = -450
	p.offset_right = 450
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
	elif String(res.get("mode", "pilot")) == "passenger":
		_journey(v)
	else:
		_scores(v)
	_consequences(v)
	_replay_slot = UIStyle.vbox(6)
	v.add_child(_replay_slot)
	var row := UIStyle.hbox(10)
	row.add_child(UIStyle.spacer())
	if result.has("recorder") and not crashed and not result.get("recorder", {}).get("samples", []).is_empty():
		_replay_btn = UIStyle.button("▶  Watch replay", _toggle_replay, 0)
		row.add_child(_replay_btn)
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
	var titles := {"landed": "Welcome to %s" % Airports.get_ap(String(result.get("arr", ""))).get("city", "your destination") if String(result.get("mode", "")) == "passenger" else "Flight complete", "diverted": "Diverted landing", "crashed": "Accident", "ditched": "Ditching", "abandoned": "Flight abandoned"}
	c.add_child(UIStyle.label(String(titles.get(outcome, outcome.capitalize())), 28, UIStyle.TEXT, true))
	c.add_child(UIStyle.label("%s · %s %s · %s → %s" % [result.get("callsign", ""), AircraftTypes.get_type(String(result.get("type", "s320"))).name,
		result.get("reg", ""), result.get("dep", ""), result.get("arr", "")], 16, UIStyle.DIM))
	if not outcome in ["crashed", "ditched", "abandoned"]:
		if String(result.get("mode", "pilot")) == "passenger":
			c.add_child(UIStyle.label("Trip rating %d / 100   ·   %s in the air" % [int(result.get("score", 0.0)), U.fmt_duration(float(result.get("hours", 0.0)) * 3600.0)], 16, UIStyle.ACCENT))
		else:
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
		var l := UIStyle.label("ATC" if k == "atc" else String(k).capitalize(), 15, UIStyle.TEXT)
		l.custom_minimum_size = Vector2(130, 0)
		grid.add_child(l)
		var pb := ProgressBar.new()
		pb.value = float(cats.get(k, 0.0))
		pb.custom_minimum_size = Vector2(560, 16)
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


func _journey(v: VBoxContainer) -> void:
	## Passenger mode: the trip as experienced from the seat.
	var rt: Dictionary = result.get("ratings", {})
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	for k in ["smoothness", "landing", "punctuality", "cabin"]:
		var l := UIStyle.label({"smoothness": "Smoothness", "landing": "Landing", "punctuality": "Punctuality", "cabin": "Cabin mood"}[k], 15, UIStyle.TEXT)
		l.custom_minimum_size = Vector2(130, 0)
		grid.add_child(l)
		var pb := ProgressBar.new()
		pb.value = float(rt.get(k, 0.0))
		pb.custom_minimum_size = Vector2(560, 16)
		var col := UIStyle.GREEN if pb.value >= 80.0 else (UIStyle.AMBER if pb.value >= 55.0 else UIStyle.RED)
		pb.add_theme_stylebox_override("fill", UIStyle.box(col, 6, Color(0, 0, 0, 0), 0, 0))
		grid.add_child(pb)
	v.add_child(grid)
	var txt := ""
	for n in result.get("notes", []):
		txt += "• %s\n" % n
	if txt != "":
		v.add_child(UIStyle.rich(txt, 15))
	var reviews: Array = result.get("reviews", [])
	if not reviews.is_empty():
		v.add_child(UIStyle.label("Overheard in the aisle", 18, UIStyle.ACCENT, true))
		for rv in reviews:
			v.add_child(UIStyle.rich("[i]“%s”[/i]  [color=#9fb1c2]— %s, %d, %s[/color]" % [rv.text, rv.name, int(rv.age), rv.home], 15))


func _accident(v: VBoxContainer) -> void:
	## Facts card + the investigation report as a video.
	var af: Dictionary = result.get("aftermath", {})
	var c: Dictionary = af.get("counts", {})
	var inv: Dictionary = result.get("investigation", {})
	v.add_child(UIStyle.label("%s, %s" % [String(af.get("place", "")), U.fmt_datetime(float(result.get("clock", WorldSim.clock)))], 15, UIStyle.DIM))
	var chips := UIStyle.hbox(8)
	for it in [["on board", int(c.get("aboard", 0)), UIStyle.TEXT], ["killed", int(c.get("fatal", 0)), UIStyle.RED], ["critical", int(c.get("critical", 0)), UIStyle.AMBER],
			["serious", int(c.get("serious", 0)), Color(1.0, 0.85, 0.4)], ["minor", int(c.get("minor", 0)), UIStyle.ACCENT], ["unhurt", int(c.get("uninjured", 0)), UIStyle.GREEN]]:
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UIStyle.box(Color(1, 1, 1, 0.05), 10, Color(it[2], 0.5), 1, 10))
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := UIStyle.vbox(0)
		var n := UIStyle.label(U.fmt_int(int(it[1])), 26, it[2], true)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(n)
		var lb := UIStyle.label(String(it[0]), 12, UIStyle.DIM)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(lb)
		pc.add_child(cv)
		chips.add_child(pc)
	v.add_child(chips)
	if not inv.is_empty():
		v.add_child(UIStyle.rich("[b]Probable cause:[/b] %s" % inv.get("probable_cause", ""), 16))
		var bar := ShareBar.new()
		bar.shares = inv.get("shares", {})
		bar.custom_minimum_size = Vector2(0, 44)
		v.add_child(bar)
	var victims: Array = af.get("victims", [])
	if not victims.is_empty():
		var names := []
		for vi in victims.slice(0, 6):
			names.append("%s (%d)" % [vi.name, int(vi.age)])
		v.add_child(UIStyle.rich("[color=#9fb1c2]In memory of %s%s.[/color]" % [", ".join(names), (" and %d others" % (victims.size() - names.size())) if victims.size() > names.size() else ""], 13))
	var prog := NewsScript.for_result(result)
	if prog.is_empty():
		return
	var head := UIStyle.hbox(8)
	head.add_child(UIStyle.label("Investigation report", 20, UIStyle.AMBER, true))
	head.add_child(UIStyle.spacer())
	head.add_child(UIStyle.label("Calderra Transport Safety Board · %s" % BroadcastPlayer._mmss(float(prog.duration)), 13, UIStyle.DIM))
	v.add_child(head)
	_embed(v, prog, true)


func _embed(parent: Container, prog: Dictionary, autoplay: bool) -> void:
	player = BroadcastPlayer.new()
	player.custom_minimum_size = Vector2(860, 484)
	player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(player)
	player.open(prog, {"autoplay": autoplay, "closable": false})
	# the flight session's world behind the debrief no longer needs to be drawn
	var vp := get_viewport()
	if vp and not _3d_was_disabled:
		_3d_was_disabled = true
		vp.disable_3d = true


func _toggle_replay() -> void:
	if player and is_instance_valid(player):
		player.queue_free()
		player = null
		_replay_btn.text = "▶  Watch replay"
		_restore_3d()
		return
	var prog := NewsScript.for_result(result)
	if prog.is_empty():
		return
	_embed(_replay_slot, prog, true)
	_replay_btn.text = "Hide replay"


func _restore_3d() -> void:
	if _3d_was_disabled:
		_3d_was_disabled = false
		var vp := get_viewport()
		if vp:
			vp.disable_3d = false


func _exit_tree() -> void:
	_restore_3d()


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
	var place := String(result.get("aftermath", {}).get("place", ""))
	var life := "%d flight hours, %d flights." % [int(hrs), int(Game.player.get("flights", 0)) if Game.has_character() else 0]
	if String(result.get("mode", "pilot")) == "passenger":
		life = "A passenger on flight %s from %s." % [String(result.get("callsign", "")), Airports.get_ap(String(result.get("dep", ""))).get("city", "")]
	v.add_child(UIStyle.rich("[i]%s did not survive the accident %s.\n%s[/i]\n\nThis character's story has ended. Their record is kept in the archive, and the world will remember what happened." % [
		name, place, life], 16))


func _continue() -> void:
	if player and is_instance_valid(player):
		player.close()
	_restore_3d()
	if Game.has_character() and (String(result.get("mode", "pilot")) == "passenger" or not bool(result.get("free_flight", false))):
		CareerRules.apply_result(result)
	elif News.has_method("on_flight_result"):
		News.call("on_flight_result", result, cons)
	get_tree().paused = false
	Engine.time_scale = 1.0
	Game.goto("hub" if Game.has_character() else "menu", {"last_result": result})


## Stacked bar of how the investigation shares responsibility.
class ShareBar extends Control:
	var shares: Dictionary = {}
	const COLS := {"pilot": Color(1.0, 0.69, 0.0), "maintenance": Color(0.35, 0.65, 1.0), "weather": Color(0.55, 0.85, 0.95), "atc": Color(0.75, 0.5, 1.0), "manufacturer": Color(0.6, 0.9, 0.55)}
	const NAMES := {"pilot": "Flight crew", "maintenance": "Maintenance", "weather": "Weather", "atc": "ATC", "manufacturer": "Manufacturer"}

	func _draw() -> void:
		var x := 0.0
		var w := size.x
		var f := UIStyle.font(true)
		draw_rect(Rect2(0, 0, w, 16), Color(1, 1, 1, 0.08))
		for k in ["pilot", "maintenance", "weather", "atc", "manufacturer"]:
			var s := float(shares.get(k, 0.0))
			if s <= 0.01:
				continue
			var seg := w * s
			draw_rect(Rect2(x, 0, seg - 1.0, 16), COLS[k])
			if seg > 90.0:
				draw_string(f, Vector2(x, 36), "%s %d%%" % [NAMES[k], int(s * 100.0)], HORIZONTAL_ALIGNMENT_LEFT, seg, 13, Color(COLS[k], 0.95))
			x += seg
