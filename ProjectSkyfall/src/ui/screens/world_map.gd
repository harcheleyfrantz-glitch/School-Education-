extends ScreenBase
## WORLD MAP (free flight): pick departure and arrival on the map, the aircraft and livery,
## where to start, the time of day and the weather, then fly. Nothing here touches the career.

const WEATHER := [["live", "Live", "globe"], ["clear", "Clear", "sun"], ["few", "Few", "cloud"], ["scattered", "Scattered", "cloud"],
	["overcast", "Overcast", "cloud"], ["rain", "Rain", "rain"], ["storm", "Storm", "storm"], ["fog", "Fog", "fog"], ["snow", "Snow", "snow"],
	["crosswind", "Crosswind", "wind"]]

var cfg := {"type": "s320", "airline": "SKF", "dep": "SKPC", "arr": "SKRV", "start": "gate", "hour": 18.5, "weather": "live", "events": "realistic"}
var map: WorldMapView
var _panel: VBoxContainer
var _popup: PanelContainer
var _summary: Label
var _summary_sub: Label


func setup(params: Dictionary) -> void:
	if Game.has_character():
		cfg.dep = String(Game.player.get("location", "SKPC"))
		cfg.arr = "SKRV" if cfg.dep != "SKRV" else "SKPC"
	for k in ["type", "airline", "dep", "arr", "start", "weather"]:
		if params.has(k):
			cfg[k] = params[k]
	if not params.has("airline") or not Airlines.operates_type(String(cfg.airline), String(cfg.type)):
		cfg.airline = _airlines_for(String(cfg.type))[0]
	cfg.events = String(Game.settings.get("event_rate", "realistic"))
	map = WorldMapView.new()
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.dep = String(cfg.dep)
	map.arr = String(cfg.arr)
	add_child(map)
	map.airport_clicked.connect(_on_airport)
	page("menu", "clear")
	move_child(map, 0)
	if Game.main and Game.main.get("backdrop"):
		(Game.main.get("backdrop") as Node3D).visible = false
	var left := UIStyle.glass_panel(16, 4, 0.84)
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.offset_right = 356
	body.add_child(left)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(sc)
	_panel = UIStyle.vbox(10)
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_panel)
	var fly_box := UIStyle.glass_panel(16, 4, 0.84)
	fly_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	fly_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	fly_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	body.add_child(fly_box)
	var fh := UIStyle.hbox(18)
	fly_box.add_child(fh)
	var sv := UIStyle.vbox(0)
	_summary = UIStyle.title("", 22, Color.WHITE)
	sv.add_child(_summary)
	_summary_sub = UIStyle.caps("", 11, UIStyle.DIM, 700, 1)
	sv.add_child(_summary_sub)
	fh.add_child(sv)
	fh.add_child(UIStyle.primary("Fly now", _fly, 190))
	var legend := UIStyle.caps("Click an airport to plan · drag to pan · scroll to zoom", 10, Color(1, 1, 1, 0.5), 700, 2)
	legend.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	legend.offset_left = 0
	legend.offset_right = 520
	legend.offset_top = 0
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(legend)
	_rebuild()


func _exit_tree() -> void:
	if Game.main and is_instance_valid(Game.main.get("backdrop")):
		(Game.main.get("backdrop") as Node3D).visible = true


static func _airlines_for(t: String) -> Array:
	var out := []
	for code in Airlines.ORDER:
		if Airlines.operates_type(code, t):
			out.append(code)
	if out.is_empty():
		out = ["SKF"]
	return out


func _rebuild() -> void:
	for c in _panel.get_children():
		c.queue_free()
	_panel.add_child(UIStyle.caps("Free flight", 12, UIStyle.ACCENT, 800, 3))
	_panel.add_child(UIStyle.title("Flight plan", 28, Color.WHITE))
	_panel.add_child(_airport_card("Departure", String(cfg.dep), UIStyle.GREEN))
	var swap := UIStyle.button("Swap departure and arrival", func():
		var d: String = cfg.dep
		cfg.dep = cfg.arr
		cfg.arr = d
		_sync(), 0)
	swap.custom_minimum_size = Vector2(0, 30)
	swap.add_theme_font_size_override("font_size", 13)
	_panel.add_child(swap)
	_panel.add_child(_airport_card("Arrival", String(cfg.arr), UIStyle.GOLD))
	_panel.add_child(UIStyle.rule())
	# aircraft
	_panel.add_child(ScreenBase.section("Aircraft"))
	var spec := AircraftTypes.get_type(String(cfg.type))
	var ah := UIStyle.hbox(6)
	ah.add_child(_arrow("chevron_left", -1))
	var av := UIStyle.vbox(0)
	av.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var an := UIStyle.title(String(spec.name), 20, Color.WHITE)
	an.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av.add_child(an)
	var ac := UIStyle.caps("%s · %s" % [AircraftTypes.category_label(String(spec.category)), String(spec.maker)], 10, UIStyle.DIM, 700, 1)
	ac.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av.add_child(ac)
	ah.add_child(av)
	ah.add_child(_arrow("chevron", 1))
	_panel.add_child(ah)
	var liv := HFlowContainer.new()
	liv.add_theme_constant_override("h_separation", 6)
	liv.add_theme_constant_override("v_separation", 6)
	for code in _airlines_for(String(cfg.type)):
		var cc := String(code)
		liv.add_child(_seg_button(String(Airlines.get_al(cc).name), cc == String(cfg.airline), func():
			cfg.airline = cc
			_rebuild()))
	_panel.add_child(liv)
	# start
	_panel.add_child(ScreenBase.section("Start"))
	_panel.add_child(_segmented([["gate", "Gate"], ["runway", "Runway"], ["air", "Final"]], "start"))
	# time of day
	_panel.add_child(ScreenBase.section("Time of day"))
	var th := UIStyle.hbox(8)
	var tl := UIStyle.title(_hour_text(float(cfg.hour)), 18, Color.WHITE)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(tl)
	var tp := UIStyle.caps(_daypart(float(cfg.hour)), 11, UIStyle.ACCENT, 800, 2)
	tp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	th.add_child(tp)
	_panel.add_child(th)
	var bar := SkyBar.new()
	bar.custom_minimum_size = Vector2(0, 14)
	bar.hour = float(cfg.hour)
	_panel.add_child(bar)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 23.75
	sl.step = 0.25
	sl.value = float(cfg.hour)
	sl.custom_minimum_size = Vector2(0, 24)
	sl.value_changed.connect(func(v):
		cfg.hour = v
		tl.text = _hour_text(v)
		tp.text = _daypart(v).to_upper()
		bar.hour = v
		bar.queue_redraw())
	_panel.add_child(sl)
	# weather
	_panel.add_child(ScreenBase.section("Weather"))
	var wf := HFlowContainer.new()
	wf.add_theme_constant_override("h_separation", 6)
	wf.add_theme_constant_override("v_separation", 6)
	for w in WEATHER:
		var key := String(w[0])
		wf.add_child(_seg_button(String(w[1]), key == String(cfg.weather), func():
			cfg.weather = key
			_rebuild(), String(w[2])))
	_panel.add_child(wf)
	_panel.add_child(ScreenBase.section("Unexpected events"))
	_panel.add_child(_segmented([["off", "Off"], ["realistic", "Realistic"], ["frequent", "Frequent"]], "events"))
	_sync(false)


func _sync(refresh_cards: bool = true) -> void:
	map.dep = String(cfg.dep)
	map.arr = String(cfg.arr)
	map._redraw()
	var spec := AircraftTypes.get_type(String(cfg.type))
	var nm := Airports.distance_nm(String(cfg.dep), String(cfg.arr))
	var ete := nm / maxf(float(spec.cruise_tas), 60.0) * 60.0 + (12.0 if nm > 1.0 else 0.0)
	_summary.text = ("%s → %s" % [cfg.dep, cfg.arr]) if cfg.dep != cfg.arr else "%s local flight" % cfg.dep
	_summary_sub.text = ("%d NM · about %s · %s" % [int(nm), U.fmt_duration(ete * 60.0), String(spec.short)]).to_upper()
	if refresh_cards and _panel.get_child_count() > 4:
		# refresh the airport cards in place
		var dep_card := _airport_card("Departure", String(cfg.dep), UIStyle.GREEN)
		var arr_card := _airport_card("Arrival", String(cfg.arr), UIStyle.GOLD)
		var old_dep := _panel.get_child(2)
		var old_arr := _panel.get_child(4)
		_panel.add_child(dep_card)
		_panel.move_child(dep_card, 2)
		_panel.add_child(arr_card)
		_panel.move_child(arr_card, 5)
		old_dep.queue_free()
		old_arr.queue_free()


func _airport_card(role: String, icao: String, col: Color) -> Control:
	var ap: Dictionary = Airports.get_ap(icao)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIStyle.box(Color(1, 1, 1, 0.05), 3, Color(col, 0.55), 1, 10))
	var h := UIStyle.hbox(10)
	p.add_child(h)
	var bar := ColorRect.new()
	bar.color = col
	bar.custom_minimum_size = Vector2(3, 0)
	h.add_child(bar)
	var v := UIStyle.vbox(1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UIStyle.caps(role, 10, col, 800, 2))
	var nl := UIStyle.label(String(ap.get("name", icao)), 15, Color.WHITE, true)
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.clip_text = true
	v.add_child(nl)
	var rws: Array = ap.get("runways", [])
	var longest := Airports.longest_runway(icao)
	v.add_child(UIStyle.caps("%s · %s · %d rwy · %s m · elev %d ft" % [icao, ap.get("iata", ""), rws.size(), U.fmt_int(int(longest)),
		int(float(ap.get("elev", 0.0)) / U.FT)], 10, UIStyle.DIM, 600, 0))
	h.add_child(v)
	return p


func _arrow(icon_kind: String, step: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(34, 40)
	b.focus_mode = Control.FOCUS_ALL
	var ic := UIIcon.make(icon_kind, 18, Color.WHITE, 2.2)
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 8
	ic.offset_right = -8
	ic.offset_top = 11
	ic.offset_bottom = -11
	b.add_child(ic)
	b.pressed.connect(func():
		UIStyle._click_sound()
		var order: Array = AircraftTypes.ORDER
		var i := order.find(String(cfg.type))
		cfg.type = order[wrapi(i + step, 0, order.size())]
		cfg.airline = _airlines_for(String(cfg.type))[0]
		_rebuild())
	return b


func _seg_button(text: String, on: bool, cb: Callable, icon_kind: String = "") -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.text = text.to_upper()
	b.add_theme_font_override("font", UIStyle.face(700, 1.0, 1))
	b.add_theme_font_size_override("font_size", 11)
	b.custom_minimum_size = Vector2(0, 30)
	if on:
		b.add_theme_stylebox_override("normal", UIStyle.box(Color(0.93, 0.95, 0.98, 0.95), 3, Color.WHITE, 1, 10))
		b.add_theme_stylebox_override("hover", UIStyle.box(Color.WHITE, 3, Color.WHITE, 1, 10))
		b.add_theme_color_override("font_color", UIStyle.INK)
		b.add_theme_color_override("font_hover_color", UIStyle.INK)
		b.add_theme_color_override("font_focus_color", UIStyle.INK)
	else:
		b.add_theme_stylebox_override("normal", UIStyle.box(Color(1, 1, 1, 0.06), 3, Color(1, 1, 1, 0.14), 1, 10))
	if icon_kind != "":
		b.icon = _icon_tex(icon_kind, UIStyle.INK if on else Color.WHITE)
		b.add_theme_constant_override("h_separation", 6)
	b.pressed.connect(func():
		UIStyle._click_sound()
		cb.call())
	return b


func _segmented(opts: Array, key: String) -> Control:
	var h := UIStyle.hbox(6)
	for o in opts:
		var val := String(o[0])
		var b := _seg_button(String(o[1]), String(cfg[key]) == val, func():
			cfg[key] = val
			_rebuild())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(b)
	return h


static var _icon_cache := {}


## Small icon textures for buttons, drawn once into a viewport-free image.
static func _icon_tex(kind: String, col: Color) -> Texture2D:
	var key := kind + col.to_html()
	if _icon_cache.has(key):
		return _icon_cache[key]
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# rasterise the icon's shape coarsely: sample UIIcon geometry with simple primitives
	var c := Vector2(n, n) * 0.5
	match kind:
		"sun":
			_disc(img, c, 6.0, col)
			for k in 8:
				var a := TAU * k / 8.0
				_disc(img, c + Vector2(cos(a), sin(a)) * 11.0, 1.8, col)
		"cloud", "rain", "storm", "snow":
			_disc(img, c + Vector2(-5, 1), 5.5, col)
			_disc(img, c + Vector2(2, -3), 7.0, col)
			_disc(img, c + Vector2(8, 2), 4.5, col)
			for x in range(5, 27):
				for y in range(16, 21):
					img.set_pixel(x, y, col)
			if kind == "rain" or kind == "storm":
				for k2 in 3:
					_disc(img, Vector2(10 + k2 * 6, 26), 1.6, col)
		"fog":
			for k3 in 4:
				for x2 in range(4 + (k3 % 2) * 3, 28 - (k3 % 2) * 3):
					for y2 in range(7 + k3 * 6, 9 + k3 * 6):
						img.set_pixel(x2, y2, col)
		"wind":
			for k4 in 3:
				for x3 in range(4, 26 - k4 * 5):
					for y3 in range(9 + k4 * 6, 11 + k4 * 6):
						img.set_pixel(x3, y3, col)
		_:
			_disc(img, c, 9.0, col)
			_disc(img, c, 6.5, Color(0, 0, 0, 0))
	img.resize(16, 16, Image.INTERPOLATE_LANCZOS)
	var t := ImageTexture.create_from_image(img)
	_icon_cache[key] = t
	return t


static func _disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	for y in range(int(c.y - r - 1), int(c.y + r + 2)):
		for x in range(int(c.x - r - 1), int(c.x + r + 2)):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			if Vector2(x + 0.5, y + 0.5).distance_to(c) <= r:
				img.set_pixel(x, y, col)


func _on_airport(icao: String, at: Vector2) -> void:
	if _popup and is_instance_valid(_popup):
		_popup.queue_free()
	var ap: Dictionary = Airports.get_ap(icao)
	_popup = UIStyle.glass_panel(14, 4, 0.9)
	var v := UIStyle.vbox(6)
	_popup.add_child(v)
	v.add_child(UIStyle.caps("%s · %s" % [icao, ap.get("iata", "")], 11, UIStyle.ACCENT, 800, 2))
	v.add_child(UIStyle.title(String(ap.get("name", icao)), 20, Color.WHITE))
	var d := UIStyle.label(String(ap.get("desc", "")), 12, UIStyle.DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(260, 0)
	v.add_child(d)
	var h := UIStyle.hbox(8)
	h.add_child(UIStyle.button("Depart here", func():
		cfg.dep = icao
		_popup.queue_free()
		_sync(), 0, UIStyle.GREEN))
	h.add_child(UIStyle.button("Arrive here", func():
		cfg.arr = icao
		_popup.queue_free()
		_sync(), 0, UIStyle.GOLD))
	v.add_child(h)
	add_child(_popup)
	_popup.position = Vector2(clampf(at.x + 18.0, 380.0, size.x - 320.0), clampf(at.y - 60.0, NavBar.HEIGHT + 10.0, size.y - 260.0))
	_popup.modulate.a = 0.0
	create_tween().tween_property(_popup, "modulate:a", 1.0, 0.18)


func _fly() -> void:
	var al := Airlines.get_al(String(cfg.airline))
	var params := {"mode": "pilot", "free_flight": true, "type": cfg.type, "airline": cfg.airline,
		"reg": "%sFF%d" % [String(al.get("reg_prefix", "CR-")), randi() % 9], "dep": cfg.dep, "arr": cfg.arr,
		"callsign": "%s %d" % [String(al.get("callsign", "SKYFALL")).capitalize(), randi_range(100, 999)],
		"flight_id": "FREE-%d" % Time.get_ticks_msec(), "clock": Activities.next_clock(float(cfg.hour)), "start": cfg.start}
	if String(cfg.weather) != "live":
		params.weather = cfg.weather
	WeatherModel.override_dir = -1.0
	Game.set_setting("event_rate", cfg.events)
	var spec := AircraftTypes.get_type(String(cfg.type))
	launch_with_loading("%s → %s" % [Airports.get_ap(String(cfg.dep)).short, Airports.get_ap(String(cfg.arr)).short],
		"%s · %s · %s" % [spec.name, al.name, _hour_text(float(cfg.hour))], "ap:" + String(cfg.dep), func(): Game.goto("flight", params))


static func _hour_text(h: float) -> String:
	return "%02d:%02d local" % [int(h), int(fmod(h, 1.0) * 60.0)]


static func _daypart(h: float) -> String:
	if h < 5.0 or h >= 21.5:
		return "Night"
	if h < 7.5:
		return "Dawn"
	if h < 17.5:
		return "Day"
	if h < 19.6:
		return "Golden hour"
	return "Dusk"


## A strip showing the sky over the day with a marker at the chosen hour.
class SkyBar extends Control:
	var hour := 12.0

	func _draw() -> void:
		var stops := [[0.0, Color(0.02, 0.03, 0.08)], [5.0, Color(0.05, 0.07, 0.16)], [6.3, Color(0.85, 0.45, 0.3)], [8.0, Color(0.45, 0.65, 0.9)],
			[13.0, Color(0.32, 0.58, 0.92)], [18.0, Color(0.55, 0.62, 0.8)], [19.2, Color(0.95, 0.55, 0.28)], [20.3, Color(0.35, 0.2, 0.35)],
			[21.5, Color(0.05, 0.06, 0.14)], [24.0, Color(0.02, 0.03, 0.08)]]
		var n := 96
		for i in n:
			var h0 := 24.0 * i / n
			var col: Color = stops[0][1]
			for k in stops.size() - 1:
				var a: Array = stops[k]
				var b: Array = stops[k + 1]
				if h0 >= float(a[0]) and h0 <= float(b[0]):
					col = (a[1] as Color).lerp(b[1], (h0 - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001))
			draw_rect(Rect2(Vector2(size.x * i / n, 2.0), Vector2(size.x / n + 1.0, size.y - 4.0)), col)
		var x := size.x * hour / 24.0
		draw_rect(Rect2(Vector2(x - 1.5, 0.0), Vector2(3.0, size.y)), Color.WHITE)
