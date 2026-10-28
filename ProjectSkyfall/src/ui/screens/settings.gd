extends ScreenBase
## OPTIONS: categories on the left, option rows on the right (graphics, sound, flying,
## controls, saved world). Every change applies and saves immediately.

const CATS := [["graphics", "Graphics", "Quality preset, frame rate and the flight HUD"], ["sound", "Sound", "Volumes, voices and subtitles"],
	["flying", "Flying", "Assists, realism and air traffic control"], ["controls", "Controls", "Mouse, touch and tilt"],
	["data", "Saved world", "Your persistent world and characters"]]

var _back := "menu"
var _cat := "graphics"
var _rows: VBoxContainer
var _cat_buttons := {}
var _title: Label
var _sub: Label


func setup(params: Dictionary) -> void:
	_back = String(params.get("back", "menu"))
	_cat = String(params.get("cat", "graphics"))
	page(_back, "dark")
	var h := UIStyle.hbox(22)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(h)
	var left := UIStyle.vbox(6)
	left.custom_minimum_size = Vector2(250, 0)
	h.add_child(left)
	var head := UIStyle.hbox(12)
	head.add_child(back_button(_back))
	head.add_child(UIStyle.title("Options", 34, Color.WHITE))
	left.add_child(head)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	left.add_child(gap)
	for c in CATS:
		var key := String(c[0])
		var b := Button.new()
		b.text = String(c[1]).to_upper()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(0, 46)
		b.add_theme_font_override("font", UIStyle.face(800, 1.0, 2))
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func():
			UIStyle._click_sound()
			_show(key))
		b.focus_entered.connect(func(): _show(key))
		left.add_child(b)
		_cat_buttons[key] = b
	var right := UIStyle.glass_panel(24, 4, 0.82)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	var rv := UIStyle.vbox(4)
	right.add_child(rv)
	_title = UIStyle.title("", 26, Color.WHITE)
	rv.add_child(_title)
	_sub = UIStyle.label("", 13, UIStyle.DIM)
	rv.add_child(_sub)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 8)
	rv.add_child(gap2)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(sc)
	_rows = UIStyle.vbox(0)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_rows)
	_show(_cat)


func _show(key: String) -> void:
	if key == _cat and _rows.get_child_count() > 0:
		return
	_cat = key
	for k in _cat_buttons.keys():
		var b: Button = _cat_buttons[k]
		var on: bool = k == key
		b.add_theme_stylebox_override("normal", UIStyle.box(Color(0.93, 0.95, 0.98, 0.95) if on else Color(0, 0, 0, 0.25), 3,
			Color(0, 0, 0, 0) if on else Color(1, 1, 1, 0.08), 0 if on else 1, 16))
		b.add_theme_stylebox_override("hover", UIStyle.box(Color.WHITE if on else Color(1, 1, 1, 0.12), 3, Color(1, 1, 1, 0.5), 1, 16))
		b.add_theme_color_override("font_color", UIStyle.INK if on else Color(0.9, 0.93, 0.96))
		b.add_theme_color_override("font_hover_color", UIStyle.INK if on else Color.WHITE)
		b.add_theme_color_override("font_focus_color", UIStyle.INK if on else Color.WHITE)
	for c in _rows.get_children():
		c.queue_free()
	for c2 in CATS:
		if String(c2[0]) == key:
			_title.text = String(c2[1]).to_upper()
			_sub.text = String(c2[2])
	match key:
		"graphics":
			var q_keys: Array = Game.QUALITY.keys()
			var labels := q_keys.map(func(k): return String(Game.QUALITY[k].label))
			_row("Quality preset", "Rendering scale, shadows, clouds, trees and view distance", option(labels, q_keys.find(String(Game.settings.quality)),
				func(i): Game.set_setting("quality", q_keys[i])))
			_check("Show frame rate", "", "show_fps")
			var hud_modes := ["full", "minimal", "off"]
			_row("Flight HUD", "Instrument overlay while flying", option(["Full", "Minimal", "Off"], hud_modes.find(String(Game.settings.hud_mode)),
				func(i): Game.set_setting("hud_mode", hud_modes[i])))
		"sound":
			for k in [["Master volume", "master_volume"], ["Effects", "sfx_volume"], ["Music", "music_volume"], ["Voices", "voice_volume"]]:
				_slider(String(k[0]), String(k[1]))
			_check("Spoken ATC and announcements", "Text to speech for controllers, crew and the captain", "tts")
			_check("Subtitles", "", "subtitles")
		"flying":
			var assists := ["assisted", "realistic"]
			_row("Flight controls", "Assisted holds attitude and protects the envelope", option(["Assisted", "Realistic (direct)"],
				assists.find(String(Game.settings.assist)), func(i): Game.set_setting("assist", assists[i])))
			_check("Automatic rudder coordination", "", "auto_rudder")
			_check("Automatic ATC replies", "Read-backs are made for you", "auto_atc")
			var rates := ["off", "realistic", "frequent"]
			_row("Unexpected events", "Failures, weather and people during a flight", option(["Off", "Realistic", "Frequent"],
				rates.find(String(Game.settings.event_rate)), func(i): Game.set_setting("event_rate", rates[i])))
			_check("Realistic crash consequences", "A fatal accident ends the character's story for good", "crash_realism")
			_check("Metric units", "", "units_metric")
		"controls":
			_slider("Look sensitivity", "mouse_sens", 0.2, 3.0)
			_check("Invert pitch", "", "invert_pitch")
			_check("Tilt the device to steer", "Phones and tablets", "touch_tilt")
			_slider("Touch control size", "touch_scale", 0.7, 1.5)
		"data":
			var r := _row("Erase world and start over", "Removes your character, the archive and every persistent person and event",
				UIStyle.button("Erase world", func():
					Game.wipe_world()
					Game.goto("menu"), 180, UIStyle.RED))
			r.modulate = Color(1, 0.92, 0.9)


func _row(text: String, desc: String, ctl: Control) -> Control:
	var p := PanelContainer.new()
	var sb := UIStyle.box(Color(1, 1, 1, 0.035 if _rows.get_child_count() % 2 == 0 else 0.0), 2, Color(0, 0, 0, 0), 0, 14)
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	var h := UIStyle.hbox(16)
	p.add_child(h)
	var v := UIStyle.vbox(1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UIStyle.label(text, 15, Color.WHITE, true))
	if desc != "":
		var d := UIStyle.label(desc, 12, UIStyle.DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)
	h.add_child(v)
	ctl.custom_minimum_size.x = maxf(ctl.custom_minimum_size.x, 260.0)
	ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ctl)
	_rows.add_child(p)
	return p


func _check(text: String, desc: String, key: String) -> void:
	var cb := CheckButton.new()
	cb.button_pressed = bool(Game.settings.get(key, false))
	cb.text = "On" if cb.button_pressed else "Off"
	cb.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cb.toggled.connect(func(on):
		cb.text = "On" if on else "Off"
		Game.set_setting(key, on))
	_row(text, desc, cb)


func _slider(text: String, key: String, lo: float = 0.0, hi: float = 1.0) -> void:
	var h := UIStyle.hbox(10)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 0.01
	sl.value = float(Game.settings.get(key, 1.0))
	sl.custom_minimum_size = Vector2(200, 24)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vl := UIStyle.label("", 14, Color.WHITE, true)
	vl.custom_minimum_size = Vector2(46, 0)
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var fmt := func(v: float) -> String: return ("%d%%" % int(round(v * 100.0))) if hi <= 1.0 else ("%.2f×" % v)
	vl.text = fmt.call(sl.value)
	sl.value_changed.connect(func(v):
		vl.text = fmt.call(v)
		Game.set_setting(key, v))
	h.add_child(sl)
	h.add_child(vl)
	_row(text, "", h)
