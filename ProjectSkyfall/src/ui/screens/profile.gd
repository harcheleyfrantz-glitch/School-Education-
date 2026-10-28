extends ScreenBase
## PROFILE: the tall pilot card (name, hours, rank insignia, level and progress to the next,
## career statistics and medals) beside the MY HANGAR, CAREER and MY LOGBOOK cards.


func setup(_params: Dictionary) -> void:
	page("menu", "soft")
	var h := UIStyle.hbox(16)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(h)
	var pc := _pilot_card()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.size_flags_stretch_ratio = 0.5
	h.add_child(pc)
	var right := UIStyle.vbox(16)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(right)
	var types := AircraftTypes.ORDER.size()
	var hangar := ImageCard.make("My Hangar", "%d aircraft · every livery · walk around them in 3D" % types, "prof_hangar",
		func(): Game.goto("hangar"), {"icon_name": "hangar", "title_size": 24})
	hangar.size_flags_stretch_ratio = 1.15
	right.add_child(hangar)
	var row := UIStyle.hbox(16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(row)
	var has := Game.has_character()
	var p: Dictionary = Game.player
	row.add_child(ImageCard.make("Career", ("%s · %s" % [p.get("rank", ""), Airlines.get_al(String(p.get("airline", ""))).name if String(p.get("airline", "")) != "" else "Unemployed"]) if has
		else "Create your pilot and start a career", PhotoStudio.pilot_id("career"), func(): Game.goto("hub" if has else "create"), {"icon_name": "plane"}))
	var log: Array = p.get("logbook", []) if has else []
	row.add_child(ImageCard.make("My Logbook", ("%d entries · last %s → %s" % [log.size(), log[-1].get("from", ""), log[-1].get("to", "")]) if not log.is_empty()
		else "Every flight you fly is recorded here", "prof_logbook", func(): Game.goto("logbook" if has else "create"), {"icon_name": "logbook"}))


func _pilot_card() -> Control:
	var has := Game.has_character()
	var p: Dictionary = Game.player
	var lv := PilotLevel.compute()
	var card := UIStyle.glass_panel(22, 4, 0.8)
	card.custom_minimum_size = Vector2(320, 0)
	var v := UIStyle.vbox(10)
	card.add_child(v)
	v.add_child(UIStyle.caps("Pilot", 12, UIStyle.ACCENT, 800, 3))
	var nm := UIStyle.title(String(p.get("name", "No active pilot")) if has else "No active pilot", 30, Color.WHITE)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(nm)
	var hrs := UIStyle.hbox(6)
	var hl := UIStyle.title(U.fmt_int(int(float(lv.hours))), 46, Color.WHITE)
	hrs.add_child(hl)
	var hu := UIStyle.title("HRS", 22, UIStyle.DIM)
	hu.size_flags_vertical = Control.SIZE_SHRINK_END
	hrs.add_child(hu)
	v.add_child(hrs)
	var em := RankEmblem.new()
	em.rank = String(p.get("rank", "")) if has else ""
	em.level = int(lv.level)
	em.custom_minimum_size = Vector2(0, 170)
	em.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(em)
	var rk := UIStyle.caps(String(p.get("rank", "Guest")) if has else "Guest pilot", 14, Color.WHITE, 800, 2)
	rk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(rk)
	var al := Airlines.get_al(String(p.get("airline", ""))) if has and String(p.get("airline", "")) != "" else {}
	var sub := UIStyle.label(("%s · based at %s" % [al.get("name", "Unemployed"), Airports.get_ap(String(p.get("base", ""))).get("short", p.get("base", ""))]) if has
		else "Activities still count toward your level.", 13, UIStyle.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sub)
	# level progress
	var nl := UIStyle.hbox(8)
	var nlt := UIStyle.caps("Next level", 11, UIStyle.DIM, 700, 2)
	nlt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.add_child(nlt)
	nl.add_child(UIStyle.caps("Level %d" % (int(lv.level) + 1), 11, Color.WHITE, 800, 2))
	v.add_child(nl)
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 6)
	pb.value = 0.0
	v.add_child(pb)
	create_tween().tween_property(pb, "value", float(lv.progress) * 100.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.25)
	v.add_child(UIStyle.caps("%s / %s XP" % [U.fmt_int(int(float(lv.xp))), U.fmt_int(int(float(lv.to)))], 11, UIStyle.DIM, 600, 1))
	v.add_child(UIStyle.rule())
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	var medals: Dictionary = lv.medals
	grid.add_child(_stat("Flights", U.fmt_int(int(p.get("flights", 0))) if has else "—"))
	grid.add_child(_stat("Landings", U.fmt_int(int(p.get("landings", 0))) if has else "—"))
	grid.add_child(_stat("Activities", "%d/%d" % [int(lv.activities), Activities.SCENARIOS.size()]))
	grid.add_child(_stat("Reputation", ("%d" % int(float(p.get("reputation", 0.0)))) if has else "—"))
	grid.add_child(_stat("Safety", ("%d" % int(float(p.get("safety", 0.0)))) if has else "—"))
	grid.add_child(_stat("Medals", "%d · %d · %d" % [int(medals.gold), int(medals.silver), int(medals.bronze)]))
	if not has:
		v.add_child(UIStyle.primary("Create your pilot", func(): Game.goto("create"), 0, UIStyle.ACCENT))
	return card


func _stat(label_text: String, value: String) -> Control:
	var v := UIStyle.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UIStyle.caps(label_text, 10, UIStyle.DIM, 700, 1))
	v.add_child(UIStyle.title(value, 20, Color.WHITE))
	return v
