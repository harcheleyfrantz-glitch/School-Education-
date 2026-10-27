extends Control
## In-flight interface: top bar, flight data strip, toasts, ATC transcript with selectable
## readbacks and requests, checklists, PA announcements, route/FMS, event decisions, map,
## walking prompts and conversations, passenger-mode bar, touch flight controls, pause menu,
## cockpit clicking (mouse and touch) and camera control.

var session: FlightSession
var ac: Aircraft
var top_info: Label
var top_clock: Label
var rate_label: Label
var toast_box: VBoxContainer
var strip: PanelContainer
var strip_labels := {}
var fma_label: Label
var prompt_label: Label
var panels := {}                 # name -> Control
var atc_log: RichTextLabel
var atc_opts: VBoxContainer
var atc_station: Label
var cl_title: Label
var cl_items: VBoxContainer
var fms_box: VBoxContainer
var map_view: Control
var modal_root: Control
var pax_bar: PanelContainer
var pax_progress: ProgressBar
var pax_label: Label
var touch_root: Control
var pause_menu: Control
var crash_flash: ColorRect
var debrief_root: Control
var _cl_timer := 0.0
var _strip_timer := 0.0
var _looking := false
var _touch_look := {}
var _last_click_feedback := ""
var _sim_rates := [1.0, 2.0, 4.0, 8.0]
var _rate_i := 0
var _log_lines: Array = []


func setup(sess: Node) -> void:
	session = sess
	ac = session.ac
	theme = UIStyle.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_toasts()
	_build_strip()
	_build_prompt()
	_build_atc_panel()
	_build_checklist_panel()
	_build_pa_panel()
	_build_fms_panel()
	_build_map_panel()
	_build_passenger_bar()
	_build_touch_controls()
	_build_pause_menu()
	modal_root = Control.new()
	modal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modal_root)
	crash_flash = ColorRect.new()
	crash_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crash_flash.color = Color(1, 1, 1, 0)
	crash_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(crash_flash)
	session.toast.connect(show_toast)
	session.phase_changed.connect(func(p): _refresh_top())
	session.finished.connect(_on_finished)
	if session.atc:
		session.atc.transmission.connect(_on_transmission)
		session.atc.options_changed.connect(_on_options)
	if session.events:
		session.events.decision_needed.connect(_on_decision)
	if session.walker:
		session.walker.prompt_changed.connect(func(t): prompt_label.text = t)
		session.walker.interacted.connect(_on_walker_interact)
		session.walker.inspected.connect(_on_inspected)
	toggle_panel("atc", session.mode == "pilot")
	toggle_panel("checklist", false)
	_refresh_top()


# ================================================================== layout builders
func _anchor(c: Control, preset: int, offset: Vector2 = Vector2.ZERO) -> void:
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	c.position += offset


func _build_top_bar() -> void:
	var bar := UIStyle.panel(Vector2(0, 46), Color(0.03, 0.05, 0.08, 0.78))
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 46
	add_child(bar)
	var h := UIStyle.hbox(10)
	bar.add_child(h)
	top_info = UIStyle.label("", 16, UIStyle.TEXT, true)
	top_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(top_info)
	h.add_child(UIStyle.spacer())
	rate_label = UIStyle.label("", 15, UIStyle.AMBER, true)
	h.add_child(rate_label)
	top_clock = UIStyle.label("", 15, UIStyle.DIM)
	h.add_child(top_clock)
	for spec in [["ATC", "atc"], ["Checklist", "checklist"], ["PA", "pa"], ["Route", "fms"], ["Map", "map"]]:
		var key: String = spec[1]
		var b := UIStyle.button(spec[0], func(): toggle_panel(key))
		b.custom_minimum_size = Vector2(0, 32)
		h.add_child(b)
	var cam := UIStyle.button("View", func(): session.rig.cycle(1))
	cam.custom_minimum_size = Vector2(0, 32)
	h.add_child(cam)
	if session.mode == "passenger" or true:
		var walk := UIStyle.button("Walk", func(): session.toggle_walk())
		walk.custom_minimum_size = Vector2(0, 32)
		h.add_child(walk)
	var menu := UIStyle.button("II", func(): _toggle_pause())
	menu.custom_minimum_size = Vector2(40, 32)
	h.add_child(menu)


func _build_toasts() -> void:
	toast_box = UIStyle.vbox(6)
	toast_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast_box.position = Vector2(-260, 56)
	toast_box.custom_minimum_size = Vector2(520, 0)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_box)


func _build_strip() -> void:
	strip = UIStyle.panel(Vector2(0, 0), Color(0.02, 0.04, 0.06, 0.72))
	strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	strip.position.y -= 12
	add_child(strip)
	var v := UIStyle.vbox(2)
	strip.add_child(v)
	var h := UIStyle.hbox(18)
	v.add_child(h)
	for k in ["IAS", "ALT", "V/S", "HDG", "GS", "THR", "FLAPS", "GEAR"]:
		var col := UIStyle.vbox(0)
		var t := UIStyle.label(k, 11, UIStyle.DIM)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var val := UIStyle.label("--", 20, UIStyle.GREEN, true)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.custom_minimum_size = Vector2(64, 0)
		col.add_child(t)
		col.add_child(val)
		h.add_child(col)
		strip_labels[k] = val
	fma_label = UIStyle.label("", 13, UIStyle.ACCENT)
	fma_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(fma_label)


func _build_prompt() -> void:
	prompt_label = UIStyle.label("", 17, UIStyle.TEXT, true)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.position = Vector2(-300, -150)
	prompt_label.custom_minimum_size = Vector2(600, 30)
	prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	prompt_label.add_theme_constant_override("outline_size", 6)
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(prompt_label)


func _side_panel(name: String, left: bool, width: float, title: String) -> VBoxContainer:
	var p := UIStyle.panel(Vector2(width, 0))
	p.anchor_left = 0.0 if left else 1.0
	p.anchor_right = 0.0 if left else 1.0
	p.anchor_top = 0.0
	p.anchor_bottom = 1.0
	p.offset_left = 10.0 if left else -width - 10.0
	p.offset_right = width + 10.0 if left else -10.0
	p.offset_top = 56.0
	p.offset_bottom = -110.0
	add_child(p)
	var v := UIStyle.vbox(8)
	p.add_child(v)
	var head := UIStyle.hbox(6)
	head.add_child(UIStyle.label(title, 17, UIStyle.ACCENT, true))
	head.add_child(UIStyle.spacer())
	var x := UIStyle.button("x", func(): toggle_panel(name, false))
	x.custom_minimum_size = Vector2(30, 28)
	head.add_child(x)
	v.add_child(head)
	panels[name] = p
	p.visible = false
	return v


func _build_atc_panel() -> void:
	var v := _side_panel("atc", false, 380.0, "Radio")
	atc_station = UIStyle.label("", 14, UIStyle.AMBER, true)
	v.add_child(atc_station)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	atc_log = UIStyle.rich("", 14)
	atc_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(atc_log)
	sc.set_meta("follow", true)
	v.add_child(UIStyle.label("Your reply", 13, UIStyle.DIM))
	atc_opts = UIStyle.vbox(6)
	v.add_child(atc_opts)


func _build_checklist_panel() -> void:
	var v := _side_panel("checklist", true, 330.0, "Checklist")
	var nav := UIStyle.hbox(6)
	nav.add_child(UIStyle.button("<", func(): _cl_step(-1), 36))
	cl_title = UIStyle.label("", 15, UIStyle.TEXT, true)
	cl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav.add_child(cl_title)
	nav.add_child(UIStyle.button(">", func(): _cl_step(1), 36))
	v.add_child(nav)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	cl_items = UIStyle.vbox(4)
	cl_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(cl_items)


func _build_pa_panel() -> void:
	var v := _side_panel("pa", true, 300.0, "Cabin & PA")
	var items := [["Welcome aboard", "welcome"], ["Turbulence - seats", "turbulence"], ["Crew: prepare for landing", "crew_seats"],
		["Brace for impact", "brace"], ["Evacuate", "evacuate"]]
	for it in items:
		var kind: String = it[1]
		var col := UIStyle.RED if kind in ["brace", "evacuate"] else Color(0, 0, 0, 0)
		v.add_child(UIStyle.button(it[0], func(): session.pa_announcement(kind), 0.0, col))
	v.add_child(UIStyle.button("Call the purser", func(): session.call_cabin()))
	v.add_child(UIStyle.button("Seat belt signs", func():
		ac.sys.lights.seatbelt = not bool(ac.sys.lights.get("seatbelt", false))
		session.on_seatbelt_sign(ac.sys.lights.seatbelt)
		show_toast("Seat belt signs " + ("ON" if ac.sys.lights.seatbelt else "OFF"), "info")))


func _build_fms_panel() -> void:
	var v := _side_panel("fms", false, 360.0, "Route & autopilot")
	fms_box = UIStyle.vbox(6)
	v.add_child(fms_box)


func _build_map_panel() -> void:
	var p := UIStyle.panel(Vector2(560, 420))
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(p)
	map_view = Control.new()
	map_view.custom_minimum_size = Vector2(540, 400)
	map_view.draw.connect(_draw_map)
	p.add_child(map_view)
	panels["map"] = p
	p.visible = false
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			toggle_panel("map", false))


func _build_passenger_bar() -> void:
	pax_bar = UIStyle.panel(Vector2(620, 0), Color(0.03, 0.05, 0.08, 0.8))
	pax_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	pax_bar.position.y -= 12
	add_child(pax_bar)
	var v := UIStyle.vbox(6)
	pax_bar.add_child(v)
	pax_label = UIStyle.label("", 15, UIStyle.TEXT, true)
	v.add_child(pax_label)
	pax_progress = ProgressBar.new()
	pax_progress.custom_minimum_size = Vector2(580, 10)
	pax_progress.show_percentage = false
	v.add_child(pax_progress)
	var h := UIStyle.hbox(8)
	v.add_child(h)
	h.add_child(UIStyle.button("Window", func(): session.passenger_window()))
	h.add_child(UIStyle.button("Walk", func(): session.toggle_walk()))
	h.add_child(UIStyle.button("Call attendant", func(): _crew_dialog({})))
	h.add_child(UIStyle.button("Flight map", func(): toggle_panel("map")))
	h.add_child(UIStyle.button("Outside view", func(): session.rig.set_mode("chase")))
	pax_bar.visible = session.mode == "passenger"


func _build_touch_controls() -> void:
	touch_root = Control.new()
	touch_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	touch_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(touch_root)
	var show := (Game.has_touch or Game.is_mobile) and session.mode == "pilot"
	touch_root.visible = show
	PilotInput.touch_active = show
	if not show:
		return
	var stick_script: GDScript = load("res://src/ui/touch_stick.gd")
	var stick: Control = stick_script.new()
	stick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	stick.position = Vector2(30, -250)
	stick.custom_minimum_size = Vector2(220, 220)
	stick.size = Vector2(220, 220)
	touch_root.add_child(stick)
	var thr := VSlider.new()
	thr.min_value = 0.0
	thr.max_value = 1.0
	thr.step = 0.01
	thr.custom_minimum_size = Vector2(60, 230)
	thr.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	thr.position = Vector2(-90, -260)
	thr.value_changed.connect(func(val): PilotInput.throttle = val)
	touch_root.add_child(thr)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	grid.position = Vector2(-330, -200)
	touch_root.add_child(grid)
	var acts := [["GEAR", func(): ac.toggle_gear()], ["FLAP+", func(): ac.set_flaps(ac.sys.flap_lever + 1)], ["FLAP-", func(): ac.set_flaps(ac.sys.flap_lever - 1)],
		["AP", func(): ac.toggle_autopilot()], ["SPLR", func(): ac.cycle_spoilers()], ["REV", func(): ac.sys.reverse_cmd = not ac.sys.reverse_cmd]]
	for a in acts:
		var b := UIStyle.button(a[0], a[1], 70)
		b.custom_minimum_size = Vector2(70, 52)
		grid.add_child(b)
	var brake := UIStyle.button("BRAKE", Callable(), 0)
	brake.custom_minimum_size = Vector2(110, 60)
	brake.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	brake.position = Vector2(270, -90)
	brake.button_down.connect(func(): PilotInput.brake = 1.0)
	brake.button_up.connect(func(): PilotInput.brake = 0.0)
	touch_root.add_child(brake)
	for side in [-1.0, 1.0]:
		var rb := UIStyle.button("<" if side < 0.0 else ">", Callable(), 0)
		rb.custom_minimum_size = Vector2(56, 56)
		rb.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		rb.position = Vector2(270 + (0 if side < 0.0 else 120), -160)
		rb.button_down.connect(func(): PilotInput.pedal = side)
		rb.button_up.connect(func(): PilotInput.pedal = 0.0)
		touch_root.add_child(rb)


func _build_pause_menu() -> void:
	pause_menu = ColorRect.new()
	(pause_menu as ColorRect).color = Color(0, 0, 0, 0.55)
	pause_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu.visible = false
	pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_menu)
	var p := UIStyle.panel(Vector2(380, 0))
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pause_menu.add_child(p)
	var v := UIStyle.vbox(10)
	p.add_child(v)
	v.add_child(UIStyle.label("Paused", 24, UIStyle.TEXT, true))
	v.add_child(UIStyle.button("Resume", func(): _toggle_pause()))
	var auto := CheckButton.new()
	auto.text = "Automatic ATC replies"
	auto.button_pressed = session.atc.auto_atc if session.atc else false
	auto.toggled.connect(func(on):
		if session.atc:
			session.atc.auto_atc = on
		Game.set_setting("auto_atc", on))
	v.add_child(auto)
	var hudm := OptionButton.new()
	for m in ["full", "minimal", "off"]:
		hudm.add_item("HUD: " + m)
	hudm.selected = ["full", "minimal", "off"].find(String(Game.settings.get("hud_mode", "full")))
	hudm.item_selected.connect(func(i): Game.set_setting("hud_mode", ["full", "minimal", "off"][i]))
	v.add_child(hudm)
	v.add_child(UIStyle.rich("[color=#9fb1c2]Mouse: right-drag to look, wheel to zoom or turn knobs, click switches.\nKeys: 1-8 views, C cycle, Tab radio, K checklist, M map, J PA, Z autopilot, T autothrust, G gear, F/V flaps, B brakes, P parking brake, X spoilers, R reverse, = / - time.[/color]", 13))
	v.add_child(UIStyle.button("Abandon flight", func():
		_toggle_pause()
		session.finish_flight("abandoned"), 0.0, UIStyle.RED))


# ================================================================== panels
func toggle_panel(name: String, force = null) -> void:
	if not panels.has(name):
		return
	var p: Control = panels[name]
	var on: bool = (not p.visible) if force == null else bool(force)
	# left and right columns hold one panel each
	if on:
		for other in panels.keys():
			if other != name and other != "map" and name != "map":
				var o: Control = panels[other]
				if o.anchor_left == p.anchor_left:
					o.visible = false
	p.visible = on
	if name == "checklist" and on:
		_refresh_checklist()
	if name == "fms" and on:
		_refresh_fms()
	if name == "map" and on:
		map_view.queue_redraw()


func open_pa() -> void:
	toggle_panel("pa", true)


func show_toast(text: String, kind: String = "info") -> void:
	if text == "":
		return
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIStyle.box(Color(0.04, 0.07, 0.1, 0.9), 10, Color(UIStyle.kind_color(kind), 0.8), 1, 12))
	var l := UIStyle.label(text, 15, UIStyle.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_child(p)
	while toast_box.get_child_count() > 4:
		toast_box.get_child(0).queue_free()
	var tw := create_tween()
	tw.tween_interval(5.0 if kind in ["info", "good"] else 8.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


func _on_transmission(station: String, who: String, text: String) -> void:
	var col := "#7fd3ff" if who == "atc" or who == "ATC" else ("#9ff0b0" if who == "pilot" else "#c8d3dc")
	var tag := station if who != "pilot" else "You"
	_log_lines.append("[color=%s][b]%s[/b][/color] %s" % [col, tag, text])
	if _log_lines.size() > 40:
		_log_lines.pop_front()
	atc_log.text = "\n".join(_log_lines)
	if session.atc:
		atc_station.text = "%s  %s" % [session.atc.station_name(session.atc.station), session.atc.station_freq(session.atc.station)]
	# subtitles for transmissions while the radio panel is closed
	if not panels.atc.visible and Game.settings.get("subtitles", true) and who != "pilot":
		show_toast("%s: %s" % [station, text], "info")


func _on_options(options: Array) -> void:
	for c in atc_opts.get_children():
		c.queue_free()
	var i := 1
	for o in options:
		var id := String(o.id)
		var b := UIStyle.button("%d. %s" % [i, String(o.label)], func(): session.atc.choose(id))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = String(o.get("text", ""))
		b.clip_text = true
		if id.begins_with("mayday") or id.begins_with("pan"):
			b.add_theme_color_override("font_color", UIStyle.RED)
		atc_opts.add_child(b)
		i += 1


func _cl_step(d: int) -> void:
	var cl := session.checklists
	if cl.abnormal_id != "":
		cl.abnormal_id = ""
	else:
		cl.select(cl.index + d)
	_refresh_checklist()


func _refresh_checklist() -> void:
	var cl := session.checklists
	if cl == null:
		return
	var cur := cl.current()
	cl_title.text = String(cur[0])
	cl_title.add_theme_color_override("font_color", UIStyle.RED if cl.abnormal_id != "" else UIStyle.TEXT)
	for c in cl_items.get_children():
		c.queue_free()
	var rows := cl.evaluate(ac, session)
	for i in rows.size():
		var r: Array = rows[i]
		var h := UIStyle.hbox(6)
		var state := String(r[2])
		var mark := UIStyle.label("✓" if state == "done" else ("○" if state == "open" else "?"), 16,
			UIStyle.GREEN if state == "done" else (UIStyle.AMBER if state == "manual" else UIStyle.DIM), true)
		mark.custom_minimum_size = Vector2(20, 0)
		h.add_child(mark)
		var item := UIStyle.label(String(r[0]), 14, UIStyle.TEXT if state != "done" else UIStyle.DIM)
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_child(item)
		var val := UIStyle.label(String(r[1]), 13, UIStyle.ACCENT if state != "done" else UIStyle.DIM)
		h.add_child(val)
		if state == "manual":
			var idx := i
			var b := UIStyle.button("Check", func():
				cl.confirm(idx)
				_refresh_checklist())
			b.custom_minimum_size = Vector2(60, 28)
			h.add_child(b)
		cl_items.add_child(h)


func _refresh_fms() -> void:
	for c in fms_box.get_children():
		c.queue_free()
	var ap := ac.ap
	var n := ac.nav_state()
	fms_box.add_child(UIStyle.label("%s  →  %s   runway %s" % [session.dep_icao, session.arr_icao, String(session.arr_end.get("name", "--"))], 15, UIStyle.TEXT, true))
	var dist := U.dist2d(n.x, n.z, float(session.arr_end.get("thr_x", 0.0)), float(session.arr_end.get("thr_z", 0.0))) / U.NM
	var gs_kt := maxf(float(n.gs) / U.KT, 120.0)
	fms_box.add_child(UIStyle.label("%.0f NM to go · ETA %s · fuel %.1f t" % [dist, U.fmt_clock(WorldSim.clock + dist / gs_kt * 3600.0), ac.sys.fuel_total() / 1000.0], 14, UIStyle.DIM))
	for i in ap.plan.size():
		var w: Dictionary = ap.plan[i]
		var active := i == ap.leg
		var d := U.dist2d(n.x, n.z, float(w.x), float(w.z)) / U.NM
		var l := UIStyle.label("%s %-8s %6.1f NM" % ["▶" if active else " ", String(w.name), d], 14, UIStyle.MAGENTA if active else UIStyle.TEXT)
		l.add_theme_font_override("font", UIStyle.mono())
		fms_box.add_child(l)
	var row := UIStyle.hbox(6)
	row.add_child(UIStyle.button("LNAV", func(): show_toast(CockpitActions.apply(ac, session, "lnav"), "info")))
	row.add_child(UIStyle.button("APPR", func(): show_toast(CockpitActions.apply(ac, session, "appr"), "info")))
	row.add_child(UIStyle.button("AP", func(): show_toast(CockpitActions.apply(ac, session, "ap"), "info")))
	row.add_child(UIStyle.button("A/THR", func(): show_toast(CockpitActions.apply(ac, session, "athr"), "info")))
	fms_box.add_child(row)
	var sel := UIStyle.hbox(6)
	for spec in [["SPD", "spd_knob"], ["HDG", "hdg_knob"], ["ALT", "alt_knob"], ["V/S", "vs_wheel"]]:
		var id: String = spec[1]
		var col := UIStyle.vbox(2)
		col.add_child(UIStyle.button("+", func():
			show_toast(CockpitActions.apply(ac, session, id, 1), "info")
			_refresh_fms(), 44))
		col.add_child(UIStyle.label(spec[0], 12, UIStyle.DIM))
		col.add_child(UIStyle.button("-", func():
			show_toast(CockpitActions.apply(ac, session, id, -1), "info")
			_refresh_fms(), 44))
		sel.add_child(col)
	fms_box.add_child(sel)
	fms_box.add_child(UIStyle.label("Selected: %d kt · HDG %03d · %d ft" % [int(ap.spd_sel), int(ap.hdg_sel), int(round(ap.alt_sel / U.FT / 100.0) * 100.0)], 13, UIStyle.ACCENT))
	fms_box.add_child(UIStyle.label("Divert to", 13, UIStyle.DIM))
	var dv := UIStyle.hbox(6)
	var near := []
	for icao in Airports.all_icao():
		if icao != session.arr_icao:
			near.append([U.dist2d(n.x, n.z, Airports.get_ap(icao).x, Airports.get_ap(icao).z), icao])
	near.sort()
	for k in mini(3, near.size()):
		var ic: String = near[k][1]
		dv.add_child(UIStyle.button("%s %.0fNM" % [ic, near[k][0] / U.NM], func():
			session.divert_to(ic, "crew decision")
			_refresh_fms()))
	fms_box.add_child(dv)


func _draw_map() -> void:
	var sz := map_view.size
	map_view.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.05, 0.08, 1.0))
	var n := ac.nav_state()
	var pts := [Vector2(float(Airports.get_ap(session.dep_icao).x), float(Airports.get_ap(session.dep_icao).z)),
		Vector2(float(Airports.get_ap(session.arr_icao).x), float(Airports.get_ap(session.arr_icao).z)), Vector2(n.x, n.z)]
	var lo = pts[0]
	var hi = pts[0]
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var span := maxf(maxf(hi.x - lo.x, hi.y - lo.y), 30000.0) * 1.4
	var c = (lo + hi) * 0.5
	var k := minf(sz.x, sz.y) / span
	var tf := func(p: Vector2) -> Vector2: return sz * 0.5 + (p - c) * k
	# coastlines are expensive; show airports and the route
	for icao in Airports.all_icao():
		var ap: Dictionary = Airports.get_ap(icao)
		var sp: Vector2 = tf.call(Vector2(float(ap.x), float(ap.z)))
		if Rect2(Vector2.ZERO, sz).has_point(sp):
			map_view.draw_circle(sp, 4.0, UIStyle.DIM)
			map_view.draw_string(UIStyle.font(), sp + Vector2(6, -4), icao, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIStyle.DIM)
	var plan: Array = ac.ap.plan
	for i in plan.size() - 1:
		map_view.draw_line(tf.call(Vector2(plan[i].x, plan[i].z)), tf.call(Vector2(plan[i + 1].x, plan[i + 1].z)), UIStyle.MAGENTA, 2.0)
	var me: Vector2 = tf.call(Vector2(n.x, n.z))
	var h := deg_to_rad(float(n.hdg))
	var fwd := Vector2(sin(h), -cos(h))
	var rt := Vector2(-fwd.y, fwd.x)
	map_view.draw_colored_polygon(PackedVector2Array([me + fwd * 12.0, me - fwd * 7.0 + rt * 7.0, me - fwd * 4.0, me - fwd * 7.0 - rt * 7.0]), UIStyle.AMBER)
	map_view.draw_string(UIStyle.font(true), Vector2(14, 24), "%s → %s" % [session.dep_icao, session.arr_icao], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIStyle.TEXT)


# ================================================================== decisions, dialogue, inspection
func _modal(title: String, body: String, buttons: Array) -> void:
	for c in modal_root.get_children():
		c.queue_free()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_root.add_child(shade)
	var p := UIStyle.panel(Vector2(520, 0))
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	modal_root.add_child(p)
	var v := UIStyle.vbox(10)
	p.add_child(v)
	v.add_child(UIStyle.label(title, 20, UIStyle.AMBER, true))
	var b := UIStyle.rich(body, 15)
	b.custom_minimum_size = Vector2(480, 0)
	v.add_child(b)
	for bt in buttons:
		var cb: Callable = bt[1]
		v.add_child(UIStyle.button(String(bt[0]), func():
			_close_modal()
			if cb.is_valid():
				cb.call()))
	modal_root.mouse_filter = Control.MOUSE_FILTER_STOP


func _close_modal() -> void:
	for c in modal_root.get_children():
		c.queue_free()
	modal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_decision(ev: Dictionary, choices: Array) -> void:
	var btns := []
	for ch in choices:
		var cid := String(ch.id)
		btns.append([String(ch.label), func(): session.events.resolve(ev, cid)])
	_modal(String(ev.get("label", "Decision")), String(ev.get("detail", ev.get("label", ""))), btns)


func _on_walker_interact(kind: String, data: Dictionary) -> void:
	match kind:
		"talk":
			_talk_dialog(data.person)
		"crew":
			_crew_dialog(data.person)
		"lav":
			show_toast("You spend a few minutes in the lavatory.", "info")
		"flight_deck":
			session.end_walk("cockpit")
		"exit":
			session.walk_to_apron()
		"board":
			session.end_walk("cockpit")


func _talk_dialog(p: Dictionary) -> void:
	var ctx := session.dialogue_context()
	var line := Dialogue.ambient(p, ctx)
	var who := "%s, %d · %s from %s" % [String(p.get("name", "Passenger")), int(p.get("age", 30)), String(p.get("job", "")), String(p.get("home", ""))]
	var btns := []
	for t in [["Where are you headed?", "trip"], ["What do you do?", "job"], ["Where are you from?", "home"], ["How's the flight?", "flight"], ["Reassure them", "reassure"]]:
		var topic: String = t[1]
		btns.append([t[0], func(): _modal(String(p.get("first", "")), "[i]%s[/i]" % Dialogue.answer(p, topic, ctx), [["Continue", func(): _talk_dialog(p)], ["Goodbye", Callable()]])])
	btns.append(["Goodbye", Callable()])
	_modal(who, "[i]\"%s\"[/i]" % line, btns)


func _crew_dialog(fa: Dictionary) -> void:
	var ctx := session.dialogue_context()
	if fa.is_empty() and session.people and not session.people.crew.is_empty():
		fa = session.people.crew[0]
	var name := String(fa.get("first", "Cabin crew"))
	var btns := []
	for t in [["Could I have a drink?", "drink"], ["How long until we land?", "status"], ["I'm nervous about flying", "nervous"]]:
		var req: String = t[1]
		btns.append([t[0], func(): _modal(name, "[i]\"%s\"[/i]" % Dialogue.crew(fa, req, ctx), [["Thanks", Callable()]])])
	btns.append(["Never mind", Callable()])
	_modal(name, "[i]\"Hello! How can I help?\"[/i]", btns)


func _on_inspected(point: Dictionary, finding: Dictionary) -> void:
	var ok := bool(finding.get("ok", true))
	show_toast("%s: %s" % [String(point.label).capitalize(), String(finding.text)], "good" if ok else ("warning" if int(finding.get("severity", 1)) >= 2 else "caution"))
	if not ok and int(finding.get("severity", 0)) >= 2:
		_modal("Walkaround finding", "[b]%s[/b]\n%s\n\nYou can call maintenance (delay ~25 min) or accept the aircraft and note it in the tech log." % [String(point.label).capitalize(), String(finding.text)],
			[["Call maintenance", func(): session.call_maintenance(finding)], ["Accept and continue", func(): session.accept_defect(finding)]])


# ================================================================== crash / end
func on_crash(info: Dictionary) -> void:
	crash_flash.color = Color(1, 1, 1, 0.95)
	var tw := create_tween()
	tw.tween_property(crash_flash, "color", Color(0, 0, 0, 0.0), 1.6)
	for k in panels.keys():
		panels[k].visible = false
	strip.visible = false
	touch_root.visible = false


func _on_finished(res: Dictionary) -> void:
	Engine.time_scale = 1.0
	for k in panels.keys():
		panels[k].visible = false
	strip.visible = false
	pax_bar.visible = false
	touch_root.visible = false
	PilotInput.touch_active = false
	PilotInput.reset()
	var debrief_script: GDScript = load("res://src/ui/debrief_view.gd")
	debrief_root = debrief_script.new()
	add_child(debrief_root)
	debrief_root.call("show_result", res)


# ================================================================== per frame
func _process(delta: float) -> void:
	if ac == null:
		return
	_strip_timer -= delta
	if _strip_timer <= 0.0:
		_strip_timer = 0.15
		_update_strip()
		_refresh_top()
		if pax_bar.visible:
			_update_pax_bar()
	_cl_timer -= delta
	if _cl_timer <= 0.0:
		_cl_timer = 0.6
		if panels.checklist.visible:
			_refresh_checklist()
		if panels.map.visible:
			map_view.queue_redraw()
	# keep the sim rate sane close to the ground and in emergencies
	if Engine.time_scale > 1.0 and (ac.ra < 900.0 or session.emergency != "" or ac.fdm.on_ground) and not session.has_meta("test_fast"):
		_rate_i = 0
		Engine.time_scale = 1.0
	var mode := String(Game.settings.get("hud_mode", "full"))
	var inside := session.rig and session.rig.mode in ["cockpit", "walk"]
	strip.visible = mode == "full" and session.mode == "pilot" and not inside and not session.ended
	prompt_label.visible = session.rig and session.rig.mode == "walk"


func _refresh_top() -> void:
	if top_info == null:
		return
	top_info.text = "%s   %s → %s   ·   %s" % [session.callsign, session.dep_icao, session.arr_icao, session.phase.replace("_", " ").to_upper()]
	top_clock.text = "%s  ·  %s" % [U.fmt_clock(WorldSim.clock), U.fmt_zulu(WorldSim.clock)]
	rate_label.text = "" if Engine.time_scale <= 1.0 else "×%d" % int(Engine.time_scale)


func _update_strip() -> void:
	var n := ac.nav_state()
	strip_labels["IAS"].text = "%d" % int(n.ias_kt)
	strip_labels["ALT"].text = "%d" % int(round(float(n.alt) / U.FT / 10.0) * 10.0)
	strip_labels["V/S"].text = "%+d" % int(round(float(n.vs) / U.FPM / 50.0) * 50.0)
	strip_labels["HDG"].text = "%03d" % int(n.hdg)
	strip_labels["GS"].text = "%d" % int(float(n.gs) / U.KT)
	strip_labels["THR"].text = "%d%%" % int(ac.throttle_lever * 100.0)
	strip_labels["FLAPS"].text = ac.flap_label()
	strip_labels["GEAR"].text = ac.gear_state_text()
	strip_labels["GEAR"].add_theme_color_override("font_color", UIStyle.GREEN if ac.sys.gear_down_cmd else UIStyle.DIM)
	var stall := ac.sys.stall_warning
	strip_labels["IAS"].add_theme_color_override("font_color", UIStyle.RED if stall or ac.sys.overspeed else UIStyle.GREEN)
	fma_label.text = ac.ap.fma()


func _update_pax_bar() -> void:
	var total := Airports.distance_m(session.dep_icao, session.arr_icao)
	var n := ac.nav_state()
	var left := U.dist2d(n.x, n.z, float(session.arr_end.get("thr_x", 0.0)), float(session.arr_end.get("thr_z", 0.0)))
	pax_progress.value = clampf(1.0 - left / maxf(total, 1.0), 0.0, 1.0) * 100.0
	var mins := int(left / maxf(float(n.gs), 60.0) / 60.0)
	pax_label.text = "Seat %s  ·  %s → %s  ·  %s  ·  %s" % [session.pax_seat, Airports.get_ap(session.dep_icao).short, Airports.get_ap(session.arr_icao).short,
		session.phase.replace("_", " "), ("%d min to go" % mins) if not ac.fdm.on_ground or session.phase == "taxi_out" else ""]


# ================================================================== input
func _toggle_pause() -> void:
	var p := not get_tree().paused
	get_tree().paused = p
	pause_menu.visible = p
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if session == null or session.ended:
		return
	var rig: CameraRig = session.rig
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).physical_keycode
		if panels.atc.visible and kc >= KEY_1 and kc <= KEY_9:
			var i := kc - KEY_1
			if i < atc_opts.get_child_count():
				(atc_opts.get_child(i) as Button).pressed.emit()
				get_viewport().set_input_as_handled()
				return
	if event.is_action_pressed("pause"):
		_toggle_pause()
	elif event.is_action_pressed("atc"):
		toggle_panel("atc")
	elif event.is_action_pressed("checklist"):
		toggle_panel("checklist")
	elif event.is_action_pressed("map"):
		toggle_panel("map")
	elif event.is_action_pressed("pa"):
		toggle_panel("pa")
	elif event.is_action_pressed("hud"):
		var modes := ["full", "minimal", "off"]
		Game.set_setting("hud_mode", modes[(modes.find(String(Game.settings.get("hud_mode", "full"))) + 1) % 3])
	elif event.is_action_pressed("camera_next"):
		rig.cycle(1)
	elif event.is_action_pressed("cam_cockpit"):
		session.set_view("cockpit")
	elif event.is_action_pressed("cam_external"):
		session.set_view("orbit")
	elif event.is_action_pressed("cam_chase"):
		session.set_view("chase")
	elif event.is_action_pressed("cam_tower"):
		session.set_view("tower")
	elif event.is_action_pressed("cam_flyby"):
		session.set_view("flyby")
	elif event.is_action_pressed("cam_cabin"):
		session.set_view("cabin")
	elif event.is_action_pressed("cam_wing"):
		session.set_view("wing")
	elif event.is_action_pressed("simrate_up"):
		if not ac.fdm.on_ground and ac.ra > 900.0 and session.emergency == "":
			_rate_i = mini(_rate_i + 1, _sim_rates.size() - 1)
			Engine.time_scale = _sim_rates[_rate_i]
	elif event.is_action_pressed("simrate_down"):
		_rate_i = maxi(_rate_i - 1, 0)
		Engine.time_scale = _sim_rates[_rate_i]
	elif event.is_action_pressed("seatbelt"):
		show_toast(CockpitActions.apply(ac, session, "seatbelt"), "info")
	elif event.is_action_pressed("crew"):
		session.call_cabin()
	elif event.is_action_pressed("look_back"):
		rig.look_yaw = 180.0 if absf(rig.look_yaw) < 90.0 else 0.0
	# mouse look and zoom
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_looking = mb.pressed
			if not mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and not _did_drag:
				_cockpit_click(mb.position, -1)
			_did_drag = false
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_cockpit_click(mb.position, 1)
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var d := 1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			if not _cockpit_click(mb.position, d, true):
				rig.zoom_by(0.9 if d > 0 else 1.1)
	elif event is InputEventMouseMotion and _looking:
		var mm := event as InputEventMouseMotion
		_did_drag = true
		var sens := float(Game.settings.get("mouse_sens", 1.0)) * 0.18
		if rig.mode == "walk" and session.walker:
			session.walker.look(mm.relative.x * sens, -mm.relative.y * sens)
		else:
			rig.look(mm.relative.x * sens, -mm.relative.y * sens)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if PilotInput.touch_active and sd.position.x < get_viewport_rect().size.x * 0.35:
			return
		var s2 := float(Game.settings.get("mouse_sens", 1.0)) * 0.22
		if rig.mode == "walk" and session.walker:
			session.walker.look(sd.relative.x * s2, -sd.relative.y * s2)
		else:
			rig.look(sd.relative.x * s2, -sd.relative.y * s2)


var _did_drag := false


func _cockpit_click(screen_pos: Vector2, dir: int, wheel: bool = false) -> bool:
	## Clicks a flight-deck control under the cursor. Returns true when one was hit.
	var rig: CameraRig = session.rig
	if rig.mode != "cockpit" or session.cockpit == null or session.mode != "pilot":
		return false
	var cam := rig.cam
	var origin := cam.project_ray_origin(screen_pos)
	var normal := cam.project_ray_normal(screen_pos)
	var inv := session.cockpit.global_transform.affine_inverse()
	var hit: Dictionary = session.cockpit.hit_test(inv * origin, (inv.basis * normal).normalized())
	if hit.is_empty():
		return false
	if wheel and not String(hit.get("kind", "")) in ["knob", "wheel", "lever"]:
		return false
	var fb := CockpitActions.apply(ac, session, String(hit.id), dir)
	if fb != "" and fb != _last_click_feedback:
		show_toast(fb, "info")
	_last_click_feedback = fb
	get_viewport().set_input_as_handled()
	return true
