class_name NavBar
extends Control
## Top navigation of the front end: logo, the main tabs (the active one in a solid white plate
## that slides over from the previously active tab), the world clock and the pilot badge.

const HEIGHT := 58.0
const TABS := [
	["home", "HOME", "home"], ["career", "CAREER", "plane"], ["activities", "ACTIVITIES", "trophy"],
	["world_map", "WORLD MAP", "globe"], ["news", "NEWS", "news"], ["profile", "PROFILE", "user"], ["options", "OPTIONS", "gear"],
]
## Screen name -> tab.
const SCREEN_TAB := {
	"menu": "home", "passenger": "home", "hub": "career", "create": "career", "briefing": "career", "jobs": "career",
	"activities": "activities", "activity": "activities", "world_map": "world_map", "free": "world_map", "news": "news",
	"archive": "news", "profile": "profile", "hangar": "profile", "logbook": "profile", "settings": "options",
}

static var _last_tab := ""

var active := "home"
var _buttons := {}
var _plate: Panel
var _row: HBoxContainer
var _clock: Label


static func tab_target(tab: String) -> String:
	match tab:
		"home": return "menu"
		"career": return "hub" if Game.has_character() else "create"
		"options": return "settings"
	return tab


static func tab_for_screen(screen: String) -> String:
	return String(SCREEN_TAB.get(screen, "home"))


func build(active_tab: String) -> void:
	active = active_tab
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	offset_bottom = HEIGHT
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.022, 0.035, 0.82)
	sb.border_color = Color(1, 1, 1, 0.09)
	sb.border_width_bottom = 1
	bg.add_theme_stylebox_override("panel", sb)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_plate = Panel.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.94, 0.96, 0.98, 0.97)
	ps.set_corner_radius_all(2)
	_plate.add_theme_stylebox_override("panel", ps)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.visible = false
	add_child(_plate)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 22)
	m.add_theme_constant_override("margin_right", 18)
	add_child(m)
	_row = UIStyle.hbox(0)
	m.add_child(_row)
	_row.add_child(_logo())
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(26, 0)
	_row.add_child(gap)
	for t in TABS:
		var b := _tab_button(String(t[0]), String(t[1]), String(t[2]))
		_row.add_child(b)
		_buttons[String(t[0])] = b
	_row.add_child(UIStyle.spacer())
	_row.add_child(_status())
	_row.add_child(_badge())
	_row.sort_children.connect(_place_plate)
	resized.connect(_place_plate.bind(false))


func _logo() -> Control:
	var h := UIStyle.hbox(9)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mark := LogoMark.new()
	mark.custom_minimum_size = Vector2(30, 30)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(mark)
	var t := UIStyle.title("SKYFALL", 21, UIStyle.TEXT)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(t)
	return h


func _tab_button(key: String, text: String, icon_name: String) -> Control:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.text = ""
	b.custom_minimum_size = Vector2(0, HEIGHT)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var inner := UIStyle.hbox(7)
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var is_active := key == active
	var col := UIStyle.INK if is_active else Color(0.86, 0.9, 0.94)
	if key == "home":
		var ic := UIIcon.make("home", 15, col, 1.6)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inner.add_child(ic)
	var l := UIStyle.caps(text, 13, col, 700, 2)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inner.add_child(l)
	b.add_child(inner)
	b.custom_minimum_size.x = l.get_minimum_size().x + (40.0 if key == "home" else 30.0)
	var bar := ColorRect.new()
	bar.color = Color(UIStyle.ACCENT, 0.0 if is_active else 0.55)
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = 6
	bar.offset_right = -6
	bar.offset_top = -9
	bar.offset_bottom = -6
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(bar)
	b.set_meta("label", l)
	b.set_meta("bar", bar)
	b.mouse_entered.connect(func(): _hover(b, true))
	b.mouse_exited.connect(func(): _hover(b, false))
	b.focus_entered.connect(func(): _hover(b, true))
	b.focus_exited.connect(func(): _hover(b, false))
	b.pressed.connect(func():
		UIStyle._click_sound()
		if key != active or key == "career":
			Game.goto(tab_target(key)))
	return b


func _hover(b: Button, on: bool) -> void:
	var key := ""
	for k in _buttons.keys():
		if _buttons[k] == b:
			key = k
	if key == active:
		return
	var bar: ColorRect = b.get_meta("bar")
	var l: Label = b.get_meta("label")
	var tw := create_tween().set_parallel(true)
	tw.tween_property(bar, "color", Color(1, 1, 1, 0.95) if on else Color(UIStyle.ACCENT, 0.55), 0.15)
	tw.tween_property(l, "modulate", Color(1.15, 1.15, 1.15) if on else Color.WHITE, 0.15)


func _place_plate(animate: bool = true) -> void:
	if not _buttons.has(active) or not is_inside_tree():
		return
	var b: Control = _buttons[active]
	var target := Rect2(b.global_position - global_position + Vector2(0, 8), Vector2(b.size.x, HEIGHT - 16))
	if target.size.x <= 1.0:
		return
	var from_key := _last_tab
	_last_tab = active
	_plate.visible = true
	if animate and from_key != "" and from_key != active and _buttons.has(from_key):
		var fb: Control = _buttons[from_key]
		_plate.position = fb.global_position - global_position + Vector2(0, 8)
		_plate.size = Vector2(fb.size.x, HEIGHT - 16)
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_parallel(true)
		tw.tween_property(_plate, "position", target.position, 0.32)
		tw.tween_property(_plate, "size", target.size, 0.32)
	else:
		_plate.position = target.position
		_plate.size = target.size


func _status() -> Control:
	var v := UIStyle.vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dt := U.clock_to_date(WorldSim.clock)
	_clock = UIStyle.caps("%s %d %s  %02d:%02d" % [U.DAY_NAMES[dt.weekday].substr(0, 3), dt.day, U.MONTH_SHORT[dt.month - 1], dt.hour, dt.minute], 12, UIStyle.DIM, 600, 1)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_clock)
	if Game.has_character():
		var money := float(Game.player.get("money", 0.0))
		var ml := UIStyle.caps(U.fmt_money(money), 12, UIStyle.GREEN if money >= 0.0 else UIStyle.RED, 700, 1)
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.add_child(ml)
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_right", 16)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(v)
	return wrap


func _badge() -> Control:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(0, HEIGHT)
	var h := UIStyle.hbox(10)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.alignment = BoxContainer.ALIGNMENT_END
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var has := Game.has_character()
	var v := UIStyle.vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_text := String(Game.player.get("name", "")) if has else "NO ACTIVE PILOT"
	var nl := UIStyle.caps(name_text, 13, UIStyle.TEXT, 800, 1)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(nl)
	var lv := PilotLevel.compute()
	var sub := UIStyle.caps(("LEVEL %d · %s" % [int(lv.level), String(Game.player.get("rank", ""))]) if has else "CREATE YOUR PILOT", 11,
		UIStyle.ACCENT, 700, 1)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(sub)
	h.add_child(v)
	var av := Avatar.new()
	av.custom_minimum_size = Vector2(40, 40)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	av.level = int(lv.level) if has else 0
	h.add_child(av)
	if has:
		av.set_shot(PhotoStudio.pilot_id())
	b.add_child(h)
	b.custom_minimum_size.x = maxf(nl.get_minimum_size().x, sub.get_minimum_size().x) + 56.0
	b.pressed.connect(func():
		UIStyle._click_sound()
		Game.goto("profile" if has else "create"))
	return b


## The game's mark: a swept delta wing over a horizon line.
class LogoMark extends Control:
	func _draw() -> void:
		var s := minf(size.x, size.y)
		var o := (size - Vector2(s, s)) * 0.5
		var pts := PackedVector2Array([o + Vector2(0.5, 0.08) * s, o + Vector2(0.95, 0.72) * s, o + Vector2(0.62, 0.6) * s,
			o + Vector2(0.5, 0.86) * s, o + Vector2(0.38, 0.6) * s, o + Vector2(0.05, 0.72) * s])
		draw_colored_polygon(pts, UIStyle.ACCENT)
		draw_colored_polygon(PackedVector2Array([o + Vector2(0.5, 0.08) * s, o + Vector2(0.62, 0.6) * s, o + Vector2(0.5, 0.86) * s]), Color(1, 1, 1, 0.9))
		draw_line(o + Vector2(0.0, 0.96) * s, o + Vector2(1.0, 0.96) * s, Color(1, 1, 1, 0.5), 1.5)


## Round pilot portrait with a level ring.
class Avatar extends Control:
	var tex: Texture2D = null
	var level := 0
	var _id := ""

	func set_shot(id: String) -> void:
		_id = id
		tex = PhotoStudio.get_shot(id)
		if tex == null:
			PhotoStudio.instance().shot_ready.connect(_on_shot)

	func _on_shot(id: String, t: Texture2D) -> void:
		if id == _id:
			tex = t
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		draw_circle(c, r + 2.0, Color(0, 0, 0, 0.5))
		if tex:
			var pts := PackedVector2Array()
			var uvs := PackedVector2Array()
			for i in 40:
				var a := TAU * i / 40.0
				var d := Vector2(cos(a), sin(a))
				pts.append(c + d * r)
				uvs.append(Vector2(0.5, 0.5) + d * 0.5)
			draw_colored_polygon(pts, Color.WHITE, uvs, tex)
		else:
			draw_circle(c, r, Color(0.12, 0.16, 0.22))
			UIIcon.draw(self, "user", Rect2(c - Vector2(r, r) * 0.7, Vector2(r, r) * 1.4), UIStyle.DIM, 1.6)
		draw_arc(c, r + 1.0, 0.0, TAU, 48, UIStyle.ACCENT if level > 0 else Color(1, 1, 1, 0.3), 2.0, true)
