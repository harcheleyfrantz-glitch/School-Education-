class_name BottomBar
extends Control
## Bottom strip of the front end: clickable key hints on the left (Esc back or quit, Q/E tabs,
## and any hints a screen adds) and the build/location status on the right.

const HEIGHT := 38.0

var _hints: HBoxContainer
var _status: Label


func build(screen: Control, back_to: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -HEIGHT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.01, 0.016, 0.026, 0.78)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.border_width_top = 1
	bg.add_theme_stylebox_override("panel", sb)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 22)
	m.add_theme_constant_override("margin_right", 22)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	var row := UIStyle.hbox(22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	_hints = UIStyle.hbox(22)
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_hints)
	var is_home := screen.has_method("screen_name") and String(screen.call("screen_name")) == "menu"
	if is_home:
		if not Game.is_mobile:
			add_hint("ESC", "Quit to desktop", func():
				if Game.has_character():
					Game.save_game()
				get_tree().quit())
	elif back_to != "":
		add_hint("ESC", "Back", func(): Game.goto(back_to))
	if not Game.is_mobile:
		add_hint("Q  E", "Switch tab", Callable())
	row.add_child(UIStyle.spacer())
	var ap: Dictionary = Airports.get_ap("SKPC")
	_status = UIStyle.caps("%s  ·  %s local  ·  Project Skyfall v%s" % [String(ap.get("name", "")), U.fmt_clock(WorldSim.clock),
		String(ProjectSettings.get_setting("application/config/version", "1.0"))], 11, Color(1, 1, 1, 0.42), 600, 1)
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_status)


func add_hint(key: String, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var h := UIStyle.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := PanelContainer.new()
	var sb := UIStyle.box(Color(0.9, 0.92, 0.95, 0.92), 3, Color(0, 0, 0, 0), 0, 6)
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	cap.add_theme_stylebox_override("panel", sb)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.add_child(UIStyle.caps(key, 10, UIStyle.INK, 800, 1))
	h.add_child(cap)
	var l := UIStyle.caps(text, 11, Color(1, 1, 1, 0.8), 700, 1)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	b.add_child(h)
	b.custom_minimum_size = Vector2(cap.get_minimum_size().x + l.get_minimum_size().x + 10.0, HEIGHT)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if cb.is_valid():
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.mouse_entered.connect(func(): l.add_theme_color_override("font_color", Color.WHITE))
		b.mouse_exited.connect(func(): l.add_theme_color_override("font_color", Color(1, 1, 1, 0.8)))
		b.pressed.connect(func():
			UIStyle._click_sound()
			cb.call())
	else:
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints.add_child(b)
