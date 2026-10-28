extends ScreenBase
## ACTIVITIES: three tall category cards (discovery flights, landing challenges, bush trips)
## over the live world, with the player's medal tally.


func setup(params: Dictionary) -> void:
	var act := Activities.consume(params)
	if not act.is_empty():
		Game.goto("activity", {"category": act.category, "focus": act.id, "result": act})
		return
	page("menu", "soft")
	var v := UIStyle.vbox(18)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(v)
	v.add_child(_header())
	var row := UIStyle.hbox(18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	for cat in Activities.ORDER:
		var info: Dictionary = Activities.CATEGORIES[cat]
		var list := Activities.by_category(cat)
		var done := Activities.completed_count(cat)
		var c := ImageCard.make(String(info.title), String(info.blurb), String(info.shot), func(): Game.goto("activity", {"category": cat}),
			{"top_band": true, "badge": str(list.size()), "title_size": 22, "progress": float(done) / float(maxi(list.size(), 1)),
				"progress_text": "%d/%d complete" % [done, list.size()], "icon_name": "trophy"})
		c.custom_minimum_size = Vector2(260, 0)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(c)
	resized.connect(_fit.bind(row))
	_fit.call_deferred(row)


func _fit(row: HBoxContainer) -> void:
	## Keep the cards a tall portrait shape, centred, on wide screens.
	if not is_instance_valid(row):
		return
	var h := row.size.y
	var w := minf(h * 0.78, (body.size.x - 36.0) / 3.0)
	for c in row.get_children():
		(c as Control).custom_minimum_size.x = w
		(c as Control).size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _header() -> Control:
	var h := UIStyle.hbox(18)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tv := UIStyle.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UIStyle.caps("New in Project Skyfall", 12, UIStyle.ACCENT, 800, 3))
	tv.add_child(UIStyle.title("Activities", 40, Color.WHITE))
	h.add_child(tv)
	var lv := PilotLevel.compute()
	var medals: Dictionary = lv.medals
	for m in ["gold", "silver", "bronze"]:
		var mh := UIStyle.hbox(6)
		mh.size_flags_vertical = Control.SIZE_SHRINK_END
		mh.add_child(UIIcon.make("medal", 24, Activities.MEDAL_COLORS[m], 1.6))
		var n := UIStyle.title(str(int(medals.get(m, 0))), 24, Color.WHITE)
		mh.add_child(n)
		h.add_child(mh)
	var tot := UIStyle.vbox(0)
	tot.size_flags_vertical = Control.SIZE_SHRINK_END
	tot.add_child(UIStyle.caps("Completed", 11, UIStyle.DIM, 700, 2))
	tot.add_child(UIStyle.title("%d / %d" % [Activities.completed_count(), Activities.SCENARIOS.size()], 24, Color.WHITE))
	h.add_child(tot)
	return h
