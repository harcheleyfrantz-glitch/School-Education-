extends ScreenBase
## Settings: graphics quality, sound, assists, simulation realism, controls.

var _back := "menu"


func setup(params: Dictionary) -> void:
	_back = String(params.get("back", "menu"))
	frame("Settings", "Changes apply immediately", _back, 0.6)
	var g := card("Graphics")
	var q_keys: Array = Game.QUALITY.keys()
	var labels := []
	for k in q_keys:
		labels.append(Game.QUALITY[k].label)
	g.add_child(_row("Quality", option(labels, q_keys.find(String(Game.settings.quality)), func(i): Game.set_setting("quality", q_keys[i]))))
	g.add_child(_check("Show frame rate", "show_fps"))
	var hud_modes := ["full", "minimal", "off"]
	g.add_child(_row("Flight HUD", option(["Full", "Minimal", "Off"], hud_modes.find(String(Game.settings.hud_mode)), func(i): Game.set_setting("hud_mode", hud_modes[i]))))
	var s := card("Sound")
	for k in [["Master", "master_volume"], ["Effects", "sfx_volume"], ["Music", "music_volume"], ["Voices", "voice_volume"]]:
		s.add_child(_slider(k[0], k[1]))
	s.add_child(_check("Spoken ATC and announcements (text to speech)", "tts"))
	s.add_child(_check("Subtitles", "subtitles"))
	var f := card("Flying")
	var assists := ["assisted", "realistic"]
	f.add_child(_row("Flight controls", option(["Assisted (attitude hold, protections)", "Realistic (direct)"], assists.find(String(Game.settings.assist)), func(i): Game.set_setting("assist", assists[i]))))
	f.add_child(_check("Automatic rudder coordination", "auto_rudder"))
	f.add_child(_check("Automatic ATC replies", "auto_atc"))
	var rates := ["off", "realistic", "frequent"]
	f.add_child(_row("Unexpected events", option(["Off", "Realistic", "Frequent"], rates.find(String(Game.settings.event_rate)), func(i): Game.set_setting("event_rate", rates[i]))))
	f.add_child(_check("Realistic crash consequences (permanent death)", "crash_realism"))
	f.add_child(_check("Metric units", "units_metric"))
	var c2 := card("Controls")
	c2.add_child(_slider("Look sensitivity", "mouse_sens", 0.2, 3.0))
	c2.add_child(_check("Invert pitch", "invert_pitch"))
	c2.add_child(_check("Tilt the device to steer (phones and tablets)", "touch_tilt"))
	c2.add_child(_slider("Touch control size", "touch_scale", 0.7, 1.5))
	var danger := card("Saved world")
	danger.add_child(UIStyle.label("Erasing the world removes your character, the archive and every persistent person and event.", 14, UIStyle.DIM))
	danger.add_child(UIStyle.button("Erase world and start over", func():
		Game.wipe_world()
		Game.goto("menu"), 0, UIStyle.RED))


func _row(text: String, ctl: Control) -> HBoxContainer:
	var h := UIStyle.hbox(10)
	var l := UIStyle.label(text, 15)
	l.custom_minimum_size = Vector2(200, 0)
	h.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctl)
	return h


func _check(text: String, key: String) -> CheckButton:
	var cb := CheckButton.new()
	cb.text = text
	cb.button_pressed = bool(Game.settings.get(key, false))
	cb.toggled.connect(func(on): Game.set_setting(key, on))
	return cb


func _slider(text: String, key: String, lo: float = 0.0, hi: float = 1.0) -> HBoxContainer:
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 0.01
	sl.value = float(Game.settings.get(key, 1.0))
	sl.custom_minimum_size = Vector2(220, 28)
	sl.value_changed.connect(func(v): Game.set_setting(key, v))
	return _row(text, sl)
