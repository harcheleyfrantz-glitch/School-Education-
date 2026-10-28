extends ScreenBase
## HANGAR: every aircraft type in a live 3D hall - turn it around, zoom in, try each airline's
## livery - with its specifications, and a button to take it flying from the world map.

var viewer: HangarViewer
var type_id := "s320"
var airline := "SKF"
var _list := {}
var _specs: VBoxContainer
var _title: Label
var _maker: Label
var _liveries: HBoxContainer


func setup(params: Dictionary) -> void:
	type_id = String(params.get("type", "s320"))
	airline = String(params.get("airline", _default_airline(type_id)))
	viewer = HangarViewer.new()
	viewer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(viewer)
	page("profile", "clear")
	move_child(viewer, 0)
	if Game.main and Game.main.get("backdrop"):
		(Game.main.get("backdrop") as Node3D).visible = false
	var left := UIStyle.glass_panel(14, 4, 0.82)
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.offset_right = 262
	body.add_child(left)
	var lv := UIStyle.vbox(6)
	left.add_child(lv)
	lv.add_child(ScreenBase.section("Aircraft"))
	for t in AircraftTypes.ORDER:
		var b := _type_row(String(t))
		lv.add_child(b)
		_list[String(t)] = b
	var right := UIStyle.glass_panel(18, 4, 0.82)
	right.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_left = -300
	body.add_child(right)
	_specs = UIStyle.vbox(8)
	right.add_child(_specs)
	var top := UIStyle.vbox(0)
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.offset_left = -300
	top.offset_right = 300
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(top)
	_maker = UIStyle.caps("", 13, UIStyle.ACCENT, 800, 3)
	_maker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_maker)
	_title = UIStyle.title("", 40, Color.WHITE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_title.add_theme_constant_override("shadow_offset_y", 2)
	top.add_child(_title)
	var hint := UIStyle.caps("Drag to turn · scroll or pinch to zoom", 10, Color(1, 1, 1, 0.45), 700, 2)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(hint)
	var bottom_box := UIStyle.vbox(10)
	bottom_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom_box.offset_left = -250
	bottom_box.offset_right = 250
	bottom_box.offset_top = -112
	bottom_box.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(bottom_box)
	var lt := UIStyle.caps("Livery", 11, Color(1, 1, 1, 0.6), 700, 2)
	lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom_box.add_child(lt)
	_liveries = UIStyle.hbox(8)
	_liveries.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_box.add_child(_liveries)
	var fly := UIStyle.primary("Fly this aircraft", func(): Game.goto("world_map", {"type": type_id, "airline": airline}), 260)
	fly.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom_box.add_child(fly)
	_show(type_id, airline)


func _exit_tree() -> void:
	if Game.main and is_instance_valid(Game.main.get("backdrop")):
		(Game.main.get("backdrop") as Node3D).visible = true


static func _default_airline(t: String) -> String:
	for code in Airlines.ORDER:
		if Airlines.operates_type(code, t):
			return code
	return "SKF"


func _type_row(t: String) -> Button:
	var spec := AircraftTypes.get_type(t)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 54)
	b.add_theme_stylebox_override("normal", UIStyle.box(Color(0, 0, 0, 0), 3, Color(0, 0, 0, 0), 0, 10))
	b.add_theme_stylebox_override("hover", UIStyle.box(Color(1, 1, 1, 0.1), 3, Color(1, 1, 1, 0.3), 1, 10))
	b.add_theme_stylebox_override("pressed", UIStyle.box(Color(1, 1, 1, 0.16), 3, Color(1, 1, 1, 0.5), 1, 10))
	b.add_theme_stylebox_override("focus", UIStyle.box(Color(0, 0, 0, 0), 3, UIStyle.ACCENT, 2, 10))
	var v := UIStyle.vbox(0)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_right = -10
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_l := UIStyle.title(String(spec.name), 18, Color.WHITE)
	name_l.clip_text = true
	v.add_child(name_l)
	v.add_child(UIStyle.caps("%s · %s" % [AircraftTypes.category_label(String(spec.category)), String(spec.maker)], 10, UIStyle.DIM, 700, 1))
	b.add_child(v)
	b.set_meta("name", name_l)
	b.pressed.connect(func():
		UIStyle._click_sound()
		_show(t, _default_airline(t) if t != type_id else airline))
	b.focus_entered.connect(func():
		if t != type_id:
			_show(t, _default_airline(t)))
	return b


func _show(t: String, al: String) -> void:
	type_id = t
	airline = al
	viewer.show_aircraft(t, al)
	var spec := AircraftTypes.get_type(t)
	_maker.text = String(spec.maker).to_upper()
	_title.text = String(spec.name).to_upper()
	for k in _list.keys():
		var b: Button = _list[k]
		var on: bool = k == t
		b.add_theme_stylebox_override("normal", UIStyle.box(Color(0.92, 0.95, 0.98, 0.92) if on else Color(0, 0, 0, 0), 3, Color(0, 0, 0, 0), 0, 10))
		(b.get_meta("name") as Label).add_theme_color_override("font_color", UIStyle.INK if on else Color.WHITE)
		for c in b.get_child(0).get_children():
			if c is Label and c != b.get_meta("name"):
				(c as Label).add_theme_color_override("font_color", Color(0.25, 0.3, 0.36) if on else UIStyle.DIM)
	_fill_specs(spec)
	_fill_liveries()


func _fill_specs(spec: Dictionary) -> void:
	for c in _specs.get_children():
		c.queue_free()
	_specs.add_child(ScreenBase.section("Specifications"))
	var role := UIStyle.label(String(spec.role), 14, Color.WHITE, true)
	role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_specs.add_child(role)
	var bl := UIStyle.label(String(spec.blurb), 13, UIStyle.DIM)
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_specs.add_child(bl)
	_specs.add_child(UIStyle.rule())
	var seats := AircraftTypes.seat_count(String(type_id))
	var eng := "%d × %s" % [int(spec.engine_count), {"piston": "piston", "turboprop": "turboprop", "turbofan": "turbofan"}.get(String(spec.engine_type), String(spec.engine_type))]
	var rows := [
		["Length", "%.1f m" % float(spec.length)], ["Wingspan", "%.1f m" % float(spec.span)], ["Height", "%.1f m" % float(spec.height)],
		["Max take-off", ("%s kg" % U.fmt_int(int(spec.mtow))) if float(spec.mtow) < 10000.0 else ("%.1f t" % (float(spec.mtow) / 1000.0))],
		["Range", "%s NM" % U.fmt_int(int(spec.range_nm))],
		["Cruise", ("M %.2f" % (float(spec.cruise_tas) / 573.0)) if float(spec.mmo) > 0.7 else "%d kt" % int(spec.cruise_tas)],
		["Ceiling", "%s ft" % U.fmt_int(int(spec.ceiling))], ["Engines", eng],
		["Seats", str(seats) if seats > 0 else "Cargo"], ["Crew", "%d pilots%s" % [int(spec.pilots), (" · %d cabin" % int(spec.fa)) if int(spec.fa) > 0 else ""]],
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	_specs.add_child(grid)
	for r in rows:
		var l := UIStyle.caps(String(r[0]), 10, UIStyle.DIM, 700, 1)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(l)
		var vl := UIStyle.label(String(r[1]), 14, Color.WHITE, true)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(vl)
	if Game.has_character():
		var rated: bool = type_id in Game.player.get("ratings", [])
		_specs.add_child(UIStyle.rule())
		var hr := float(Game.player.get("hours_by_type", {}).get(type_id, 0.0))
		_specs.add_child(UIStyle.chip("Type rated · %.0f h" % hr if rated else "No type rating", UIStyle.GREEN if rated else UIStyle.AMBER))


func _fill_liveries() -> void:
	for c in _liveries.get_children():
		c.queue_free()
	for code in Airlines.ORDER:
		var lc := Airlines.livery_colors(String(code))
		var sw := Swatch.new()
		sw.a = lc.tail
		sw.b = lc.body
		sw.c = lc.stripe
		sw.selected = code == airline
		sw.operates = Airlines.operates_type(String(code), type_id)
		sw.custom_minimum_size = Vector2(38, 38)
		sw.tooltip_text = String(Airlines.get_al(String(code)).name)
		sw.focus_mode = Control.FOCUS_ALL
		var cc := String(code)
		sw.gui_input.connect(func(e):
			if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed) or e.is_action_pressed("ui_accept"):
				UIStyle._click_sound()
				_show(type_id, cc))
		_liveries.add_child(sw)
	var name_l := UIStyle.caps(String(Airlines.get_al(airline).name), 11, Color.WHITE, 800, 2)
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_liveries.add_child(name_l)


## A round livery swatch: tail colour, body and cheatline.
class Swatch extends Control:
	var a := Color.WHITE
	var b := Color.WHITE
	var c := Color.WHITE
	var selected := false
	var operates := true

	func _draw() -> void:
		var ctr := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 3.0
		draw_circle(ctr, r, b)
		var pts := PackedVector2Array([ctr])
		for i in 13:
			var ang := -PI * 0.5 + PI * i / 12.0
			pts.append(ctr + Vector2(cos(ang), sin(ang)) * r)
		draw_colored_polygon(pts, a)
		draw_line(ctr + Vector2(-r * 0.9, r * 0.25), ctr + Vector2(r * 0.9, r * 0.25), c, 3.0)
		draw_arc(ctr, r + 1.5, 0.0, TAU, 40, Color.WHITE if selected else Color(1, 1, 1, 0.35 if operates else 0.15), 2.5 if selected else 1.2, true)
		if not operates:
			draw_circle(ctr, r, Color(0, 0, 0, 0.35))
