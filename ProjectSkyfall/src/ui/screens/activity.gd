extends ScreenBase
## One activity category: the scenario list (picture, place, difficulty, medal and best score)
## and the selected scenario's briefing - picture, story, conditions, aircraft, objective, legs
## for bush trips, best score - with FLY to launch it. After a flight it opens with the result.

var category := "landing"
var selected := ""
var _rows := {}
var _detail: VBoxContainer
var _result: Dictionary = {}


func setup(params: Dictionary) -> void:
	category = String(params.get("category", "landing"))
	if not Activities.CATEGORIES.has(category):
		category = "landing"
	_result = params.get("result", {})
	var list := Activities.by_category(category)
	selected = String(params.get("focus", String(list[0].id) if not list.is_empty() else ""))
	page("activities", "dark")
	var h := UIStyle.hbox(22)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(h)
	var left_panel := UIStyle.glass_panel(16, 4, 0.8)
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 0.8
	h.add_child(left_panel)
	var left := UIStyle.vbox(12)
	left_panel.add_child(left)
	var info: Dictionary = Activities.CATEGORIES[category]
	var head := UIStyle.hbox(14)
	head.add_child(back_button("activities"))
	var tv := UIStyle.vbox(0)
	tv.add_child(UIStyle.caps("Activities", 12, info.accent, 800, 3))
	tv.add_child(UIStyle.title(String(info.title), 32, Color.WHITE))
	head.add_child(tv)
	left.add_child(head)
	var blurb := UIStyle.label(String(info.blurb), 14, UIStyle.DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(blurb)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(sc)
	var rows := UIStyle.vbox(6)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(rows)
	for s in list:
		var r := _row(s)
		rows.add_child(r)
		_rows[String(s.id)] = r
	var right := UIStyle.glass_panel(0, 4, 0.8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	_detail = UIStyle.vbox(0)
	right.add_child(_detail)
	_select(selected, false)


func _row(s: Dictionary) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 82)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("normal", UIStyle.box(Color(0.02, 0.03, 0.045, 0.55), 3, Color(1, 1, 1, 0.07), 1, 8))
	b.add_theme_stylebox_override("hover", UIStyle.box(Color(1, 1, 1, 0.1), 3, Color(1, 1, 1, 0.35), 1, 8))
	b.add_theme_stylebox_override("pressed", UIStyle.box(Color(1, 1, 1, 0.14), 3, Color(1, 1, 1, 0.5), 1, 8))
	b.add_theme_stylebox_override("focus", UIStyle.box(Color(0, 0, 0, 0), 3, UIStyle.ACCENT, 2, 8))
	var h := UIStyle.hbox(12)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8
	h.offset_right = -12
	h.offset_top = 8
	h.offset_bottom = -8
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var thumb := ShotRect.make("scn:" + String(s.id), Vector2(118, 66))
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(thumb)
	var v := UIStyle.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := UIStyle.label(String(s.title), 16, Color.WHITE, true)
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.clip_text = true
	v.add_child(t)
	var pl := UIStyle.label(String(s.place), 13, UIStyle.DIM)
	pl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pl.clip_text = true
	v.add_child(pl)
	v.add_child(Difficulty.make(int(s.difficulty)))
	h.add_child(v)
	var rec := Activities.record(String(s.id))
	var right := UIStyle.vbox(2)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var medal := String(rec.get("medal", ""))
	if int(rec.get("done", 0)) > 0:
		var mi := UIIcon.make("medal", 26, Activities.MEDAL_COLORS[medal], 1.6)
		mi.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		right.add_child(mi)
		var sl := UIStyle.caps("%d" % int(round(float(rec.get("best", 0.0)))), 13, Color.WHITE, 800, 1)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		right.add_child(sl)
	elif Activities.legs(s).size() > 1 and int(rec.get("leg", 0)) > 0:
		right.add_child(UIStyle.caps("Leg %d/%d" % [int(rec.leg) + 1, Activities.legs(s).size()], 11, UIStyle.ACCENT, 800, 1))
	else:
		var ni := UIIcon.make("medal", 26, Color(1, 1, 1, 0.14), 1.6)
		right.add_child(ni)
	h.add_child(right)
	var id := String(s.id)
	b.pressed.connect(func():
		UIStyle._click_sound()
		if selected == id:
			_launch(s)
		else:
			_select(id, true))
	b.focus_entered.connect(func():
		if selected != id:
			_select(id, true))
	return b


func _select(id: String, animate: bool) -> void:
	selected = id
	for k in _rows.keys():
		var r: Button = _rows[k]
		var on: bool = k == id
		r.add_theme_stylebox_override("normal", UIStyle.box(Color(0.92, 0.95, 0.98, 0.16) if on else Color(0.02, 0.03, 0.045, 0.55), 3,
			Color(1, 1, 1, 0.7) if on else Color(1, 1, 1, 0.07), 1, 8))
	var s := Activities.get_scenario(id)
	if s.is_empty():
		return
	for c in _detail.get_children():
		c.queue_free()
	_build_detail(s)
	if animate:
		_detail.modulate.a = 0.0
		create_tween().tween_property(_detail, "modulate:a", 1.0, 0.25)


func _build_detail(s: Dictionary) -> void:
	var info: Dictionary = Activities.CATEGORIES[String(s.category)]
	var hero := Control.new()
	hero.custom_minimum_size = Vector2(0, 250)
	hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero.size_flags_stretch_ratio = 1.15
	hero.clip_contents = true
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(hero)
	var img := ShotRect.make("scn:" + String(s.id), Vector2.ZERO, true)
	img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hero.add_child(img)
	var sh := TextureRect.new()
	sh.texture = ImageCard._shade_tex(false)
	sh.stretch_mode = TextureRect.STRETCH_SCALE
	sh.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(sh)
	var cap := UIStyle.vbox(6)
	cap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	cap.offset_left = 22
	cap.offset_right = -22
	cap.offset_bottom = -16
	cap.offset_top = -110
	cap.alignment = BoxContainer.ALIGNMENT_END
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(cap)
	var chips := UIStyle.hbox(6)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_child(UIStyle.chip(String(Activities.CATEGORIES[String(s.category)].title).trim_suffix("s"), info.accent, true))
	for tg in s.get("tags", []):
		chips.add_child(UIStyle.chip(String(tg), Color(0.9, 0.93, 0.97)))
	cap.add_child(chips)
	var tl := UIStyle.title(String(s.title), 34, Color.WHITE)
	tl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	tl.add_theme_constant_override("shadow_offset_y", 2)
	cap.add_child(tl)
	var m := MarginContainer.new()
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 22)
	m.add_theme_constant_override("margin_top", 14)
	m.add_theme_constant_override("margin_bottom", 18)
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_child(m)
	var v := UIStyle.vbox(12)
	m.add_child(v)
	if not _result.is_empty() and String(_result.get("id", "")) == String(s.id):
		v.add_child(_result_banner(s))
	var d := UIStyle.label(String(s.desc), 15, Color(0.88, 0.91, 0.95))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	var spec := AircraftTypes.get_type(String(s.type))
	var lg := Activities.legs(s)
	grid.add_child(_fact("plane", "Aircraft", "%s" % spec.name, Airlines.get_al(String(s.airline)).name))
	grid.add_child(_fact(_time_icon(float(s.hour)), "Local time", "%02d:%02d" % [int(s.hour), int(fmod(float(s.hour), 1.0) * 60.0)], _daypart(float(s.hour))))
	var wx := _weather_text(s)
	grid.add_child(_fact(_wx_icon(String(s.weather), float(s.hour)), "Weather", wx[0], wx[1]))
	grid.add_child(_fact("pin", "Start", _start_text(s), Airports.get_ap(String(lg[0][0])).name if String(s.get("start", "")) != "air" else Airports.get_ap(String(lg[0][1])).name))
	grid.add_child(_fact("route", "Route", "%s → %s" % [lg[0][0], lg[lg.size() - 1][1]], "%d leg%s · %d NM" % [lg.size(), "s" if lg.size() > 1 else "", int(_route_nm(lg))]))
	grid.add_child(_fact("trophy", "Objective", String(s.objective), ""))
	if lg.size() > 1:
		v.add_child(_legs(s))
	v.add_child(UIStyle.spacer())
	var bottom_row := UIStyle.hbox(16)
	var rec := Activities.record(String(s.id))
	var bs := UIStyle.vbox(0)
	bs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bs.add_child(UIStyle.caps("Personal best", 11, UIStyle.DIM, 700, 2))
	var bh := UIStyle.hbox(10)
	if int(rec.get("done", 0)) > 0:
		var medal := String(rec.get("medal", ""))
		bh.add_child(UIIcon.make("medal", 30, Activities.MEDAL_COLORS[medal], 1.8))
		bh.add_child(UIStyle.title("%d" % int(round(float(rec.get("best", 0.0)))), 30, Color.WHITE))
		var ml := UIStyle.caps(medal if medal != "" else "completed", 12, Activities.MEDAL_COLORS[medal], 800, 2)
		ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bh.add_child(ml)
	else:
		bh.add_child(UIStyle.title("—", 30, UIStyle.DIM))
		var hint := UIStyle.label("Gold %d · Silver %d · Bronze %d" % [int(Activities.MEDALS[0][1]), int(Activities.MEDALS[1][1]), int(Activities.MEDALS[2][1])], 13, UIStyle.DIM)
		hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bh.add_child(hint)
	bs.add_child(bh)
	bottom_row.add_child(bs)
	var leg := Activities.next_leg(s)
	var fly_text := "Fly leg %d" % (leg + 1) if lg.size() > 1 else "Fly"
	var fly := UIStyle.primary(fly_text, func(): _launch(s), 220)
	fly.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom_row.add_child(fly)
	v.add_child(bottom_row)


func _fact(icon_kind: String, label_text: String, value: String, sub: String) -> Control:
	var h := UIStyle.hbox(10)
	h.custom_minimum_size = Vector2(150, 0)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ic := UIIcon.make(icon_kind, 22, UIStyle.ACCENT, 1.6)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	var v := UIStyle.vbox(1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UIStyle.caps(label_text, 10, UIStyle.DIM, 700, 2))
	var vl := UIStyle.label(value, 14, Color.WHITE, true)
	vl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(vl)
	if sub != "":
		var sl := UIStyle.label(sub, 12, UIStyle.DIM)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(sl)
	h.add_child(v)
	return h


func _legs(s: Dictionary) -> Control:
	var rec := Activities.record(String(s.id))
	var scores: Array = rec.get("leg_scores", [])
	var nxt := Activities.next_leg(s)
	var v := UIStyle.vbox(6)
	v.add_child(ScreenBase.section("Legs"))
	var lg := Activities.legs(s)
	for i in lg.size():
		var pair: Array = lg[i]
		var h := UIStyle.hbox(10)
		var done := i < scores.size() and float(scores[i]) >= 0.0
		var col := UIStyle.GREEN if done else (UIStyle.ACCENT if i == nxt else UIStyle.DIM)
		h.add_child(UIIcon.make("check" if done else ("play" if i == nxt else "pin"), 16, col, 2.0))
		var t := UIStyle.label("%d.  %s → %s" % [i + 1, Airports.get_ap(String(pair[0])).short, Airports.get_ap(String(pair[1])).short], 14,
			Color.WHITE if i == nxt or done else UIStyle.DIM, i == nxt)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(t)
		h.add_child(UIStyle.label("%d NM" % int(Airports.distance_nm(String(pair[0]), String(pair[1]))), 13, UIStyle.DIM))
		if done:
			h.add_child(UIStyle.caps("%d" % int(round(float(scores[i]))), 12, UIStyle.GREEN, 800, 1))
		v.add_child(h)
	return v


func _result_banner(s: Dictionary) -> Control:
	var r := _result
	var ok := bool(r.get("complete", false)) or bool(r.get("leg_ok", false))
	var medal := String(r.get("medal", ""))
	var col: Color = Activities.MEDAL_COLORS[medal] if medal != "" else (UIStyle.GREEN if ok else UIStyle.RED)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIStyle.box(Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 0.9), 3, col, 1, 14))
	var h := UIStyle.hbox(14)
	p.add_child(h)
	h.add_child(UIIcon.make("medal" if medal != "" else ("check" if ok else "close"), 34, col, 2.0))
	var v := UIStyle.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := ""
	var sub := ""
	var legs := int(r.get("legs", 1))
	if legs > 1 and not bool(r.get("complete", false)):
		if bool(r.get("leg_ok", false)):
			head = "Leg %d of %d complete · %d" % [int(r.leg) + 1, legs, int(round(float(r.leg_score)))]
			var lg := Activities.legs(s)
			var n := mini(int(r.leg) + 1, lg.size() - 1)
			sub = "Next: %s → %s" % [Airports.get_ap(String(lg[n][0])).short, Airports.get_ap(String(lg[n][1])).short]
		else:
			head = "Leg not completed"
			sub = "Land at the destination to continue the trip."
	elif ok:
		head = "%s · %d" % ["Trip complete" if legs > 1 else ("Landing scored" if String(s.category) == "landing" else "Flight complete"), int(round(float(r.score)))]
		sub = ("%s medal" % medal.capitalize() if medal != "" else "No medal this time") + ("  ·  NEW PERSONAL BEST" if bool(r.get("new_best", false)) else "  ·  best %d" % int(round(float(r.get("best", 0.0)))))
		var td: Dictionary = r.get("touchdown", {})
		if not td.is_empty():
			sub += "\nTouchdown %d ft/min · %.1f m from the centreline · %d m past the threshold" % [int(absf(float(td.get("vs_fpm", 0.0)))),
				absf(float(td.get("centerline", 0.0))), int(td.get("dist_from_thr", 0.0))]
	else:
		head = "Not scored"
		sub = "The flight ended %s." % ("in an accident" if String(r.get("outcome", "")) in ["crashed", "ditched"] else "before a landing at the destination")
	v.add_child(UIStyle.title(head, 22, Color.WHITE))
	var sl := UIStyle.label(sub, 13, Color(0.9, 0.93, 0.96))
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sl)
	h.add_child(v)
	p.modulate.a = 0.0
	p.scale = Vector2(0.96, 0.96)
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 1.0, 0.4).set_delay(0.3)
	tw.tween_property(p, "scale", Vector2.ONE, 0.5).set_delay(0.3)
	return p


func _launch(s: Dictionary) -> void:
	var lg := Activities.legs(s)
	var leg := Activities.next_leg(s)
	var sub := "%s · %s" % [String(s.place) if lg.size() == 1 else "Leg %d: %s → %s" % [leg + 1, Airports.get_ap(String(lg[leg][0])).short,
		Airports.get_ap(String(lg[leg][1])).short], AircraftTypes.get_type(String(s.type)).name]
	launch_with_loading(String(s.title), sub, "scn:" + String(s.id), func(): Activities.launch(s, leg))


static func _route_nm(lg: Array) -> float:
	var t := 0.0
	for pair in lg:
		t += Airports.distance_nm(String(pair[0]), String(pair[1]))
	return t


static func _start_text(s: Dictionary) -> String:
	match String(s.get("start", "runway")):
		"air":
			return "Final, %d km from %s" % [int(s.get("dist_km", 10.0)), "runway " + String(s.get("arr_rwy", "")) if s.has("arr_rwy") else "the runway"]
		"gate":
			return "At the gate"
	return "Lined up, runway %s" % String(s.get("dep_rwy", "")) if s.has("dep_rwy") else "Lined up on the runway"


static func _weather_text(s: Dictionary) -> Array:
	var key := String(s.get("weather", "few"))
	var p: Dictionary = WeatherModel.PRESETS.get(key, WeatherModel.PRESETS["few"])
	var dir := float(s.get("wind", p.dir))
	var wind := "%03d° %d kt" % [int(dir), int(p.wind)]
	if key == "crosswind":
		wind = "%03d° %dG%d kt" % [int(dir), int(p.wind), int(p.wind) + 12]
	var names := {"clear": "Clear skies", "few": "Few clouds", "scattered": "Scattered clouds", "overcast": "Overcast", "rain": "Heavy rain",
		"storm": "Thunderstorms", "fog": "Fog · %d m" % int(p.vis), "snow": "Snow", "crosswind": "Strong crosswind"}
	return [String(names.get(key, key.capitalize())), "Wind " + wind]


static func _time_icon(hour: float) -> String:
	return "moon" if hour >= 20.5 or hour < 5.5 else "sun"


static func _daypart(hour: float) -> String:
	if hour < 5.5 or hour >= 21.0:
		return "Night"
	if hour < 8.0:
		return "Sunrise"
	if hour < 17.5:
		return "Day"
	return "Golden hour" if hour < 19.6 else "Dusk"


static func _wx_icon(key: String, hour: float) -> String:
	match key:
		"clear":
			return _time_icon(hour)
		"few", "scattered", "overcast":
			return "cloud"
		"rain":
			return "rain"
		"storm":
			return "storm"
		"fog":
			return "fog"
		"snow":
			return "snow"
		"crosswind":
			return "wind"
	return "cloud"


## Five little bars, filled up to the difficulty.
class Difficulty extends Control:
	var level := 1

	static func make(n: int) -> Difficulty:
		var d := Difficulty.new()
		d.level = n
		d.custom_minimum_size = Vector2(80, 10)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return d

	func _draw() -> void:
		for i in 5:
			var on := i < level
			var col := Color(1.0, 0.72, 0.22) if on and level >= 4 else (UIStyle.ACCENT if on else Color(1, 1, 1, 0.16))
			draw_rect(Rect2(Vector2(i * 15.0, 2.0), Vector2(11.0, 5.0)), col)
