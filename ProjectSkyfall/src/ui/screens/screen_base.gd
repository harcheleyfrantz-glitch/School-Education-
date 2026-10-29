class_name ScreenBase
extends Control
## Common frame for menu screens over the live 3D backdrop: a shade over the world, the top
## navigation bar, the bottom hint bar, an entrance animation and keyboard/gamepad navigation
## (Esc/B back, Q/E or the shoulder buttons switch tabs). page() gives new screens an empty
## body to lay out; frame() keeps the classic layout (header + scrolling column of glass cards)
## used by the career screens.

const MARGIN := 28.0

var content: VBoxContainer
var header_title: Label
var header_sub: Label
var nav: NavBar
var bottom: BottomBar
var body: Control
var back_target := "menu"

## Last input came from keys or a gamepad (then the first card takes focus).
static var nav_mode := false


func setup(_params: Dictionary) -> void:
	pass


func screen_name() -> String:
	var s: Script = get_script()
	return s.resource_path.get_file().get_basename() if s else "menu"


## New-style page: returns the body (the area between the bars, inside the page margins).
func page(back_to: String = "menu", shade: String = "soft") -> Control:
	back_target = back_to
	theme = UIStyle.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade(shade))
	body = Control.new()
	body.name = "Body"
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = MARGIN
	body.offset_right = -MARGIN
	body.offset_top = NavBar.HEIGHT + 22.0
	body.offset_bottom = -(BottomBar.HEIGHT + 18.0)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	nav = NavBar.new()
	nav.name = "Nav"
	add_child(nav)
	nav.build(NavBar.tab_for_screen(screen_name()))
	bottom = BottomBar.new()
	bottom.name = "Bottom"
	add_child(bottom)
	bottom.build(self, back_to)
	_intro()
	return body


func _intro() -> void:
	body.modulate.a = 0.0
	body.position.y += 16.0
	var y := body.position.y - 16.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(body, "modulate:a", 1.0, 0.32)
	tw.tween_property(body, "position:y", y, 0.4)
	if nav_mode:
		_focus_first.call_deferred()


func _focus_first() -> void:
	if not is_inside_tree():
		return
	var f := _find_focusable(body)
	if f:
		f.grab_focus()


func _find_focusable(n: Node) -> Control:
	for c in n.get_children():
		if c is Control and (c as Control).visible:
			if (c as Control).focus_mode == Control.FOCUS_ALL:
				return c
			var r := _find_focusable(c)
			if r:
				return r
	return null


func _shade(kind: String) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var flat := ColorRect.new()
	flat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flat.color = Color(0.01, 0.015, 0.025, {"soft": 0.28, "dark": 0.6, "left": 0.1, "clear": 0.0}.get(kind, 0.28))
	flat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flat)
	if kind == "left":
		var side := TextureRect.new()
		side.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		side.texture = _gradient()
		side.stretch_mode = TextureRect.STRETCH_SCALE
		side.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		side.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(side)
	var vig := TextureRect.new()
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.texture = _vignette()
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vig)
	return root


static var _grad_tex: GradientTexture2D
static var _vig_tex: GradientTexture2D


static func _gradient() -> GradientTexture2D:
	if _grad_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.01, 0.015, 0.03, 0.9))
		g.set_color(1, Color(0.01, 0.015, 0.03, 0.0))
		g.add_point(0.5, Color(0.01, 0.015, 0.03, 0.7))
		_grad_tex = GradientTexture2D.new()
		_grad_tex.gradient = g
		_grad_tex.fill_from = Vector2(0, 0)
		_grad_tex.fill_to = Vector2(1, 0)
		_grad_tex.width = 256
		_grad_tex.height = 4
	return _grad_tex


static func _vignette() -> GradientTexture2D:
	if _vig_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.0))
		g.set_color(1, Color(0.0, 0.005, 0.015, 0.62))
		g.add_point(0.55, Color(0, 0, 0, 0.08))
		_vig_tex = GradientTexture2D.new()
		_vig_tex.gradient = g
		_vig_tex.fill = GradientTexture2D.FILL_RADIAL
		_vig_tex.fill_from = Vector2(0.5, 0.45)
		_vig_tex.fill_to = Vector2(1.08, 1.08)
		_vig_tex.width = 256
		_vig_tex.height = 256
	return _vig_tex


## Classic layout used by the career screens: header with a back chevron, title and subtitle,
## and a scrolling column of glass cards `width` of the screen wide.
func frame(title: String, subtitle: String = "", back_to: String = "menu", width: float = 0.62) -> VBoxContainer:
	page(back_to, "left")
	var col := Control.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.anchor_right = clampf(width, 0.4, 1.0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(col)
	var v := UIStyle.vbox(14)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_child(v)
	var head := UIStyle.hbox(14)
	if back_to != "":
		head.add_child(back_button(back_to))
	var tv := UIStyle.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_title = UIStyle.title(title, 32, UIStyle.TEXT)
	header_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(header_title)
	header_sub = UIStyle.label(subtitle, 15, UIStyle.DIM)
	header_sub.visible = subtitle != ""
	header_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(header_sub)
	head.add_child(tv)
	v.add_child(head)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	content = UIStyle.vbox(12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	return content


## Square chevron back button.
func back_button(to: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(42, 42)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = "Back"
	var ic := UIIcon.make("chevron_left", 22, Color.WHITE, 2.4)
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 10
	ic.offset_top = 10
	ic.offset_right = -10
	ic.offset_bottom = -10
	b.add_child(ic)
	b.pressed.connect(func():
		UIStyle._click_sound()
		Game.goto(to))
	return b


## Section title in tracked caps with an accent tick.
static func section(text: String, col: Color = UIStyle.TEXT) -> Control:
	var h := UIStyle.hbox(10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tick := ColorRect.new()
	tick.color = UIStyle.ACCENT
	tick.custom_minimum_size = Vector2(3, 16)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tick)
	h.add_child(UIStyle.caps(text, 13, col, 800, 2))
	return h


func card(title: String = "", min_w: float = 0.0) -> VBoxContainer:
	var p := UIStyle.glass_panel(18)
	p.custom_minimum_size = Vector2(min_w, 0)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(p)
	var v := UIStyle.vbox(8)
	p.add_child(v)
	if title != "":
		v.add_child(section(title))
	return v


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventJoypadButton:
		nav_mode = true
	elif event is InputEventMouseMotion or event is InputEventScreenTouch:
		nav_mode = false
	if event.is_action_pressed("ui_cancel"):
		if back_target != "" and screen_name() != "menu":
			get_viewport().set_input_as_handled()
			UIStyle._click_sound()
			Game.goto(back_target)
		return
	var step := 0
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Q:
			step = -1
		elif event.physical_keycode == KEY_E:
			step = 1
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			step = -1
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			step = 1
	if step != 0 and nav:
		var keys: Array = NavBar.TABS.map(func(t): return String(t[0]))
		var i := keys.find(nav.active)
		var next := String(keys[wrapi(i + step, 0, keys.size())])
		get_viewport().set_input_as_handled()
		UIStyle._click_sound()
		Game.goto(NavBar.tab_target(next))


## Shows a full-screen "preparing" card for a moment, then runs `go` (flight start is heavy and
## would otherwise freeze the menu without feedback).
func launch_with_loading(title_text: String, sub: String, shot: String, go: Callable) -> void:
	var o := Control.new()
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(o)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.015, 0.025, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.add_child(bg)
	var img := TextureRect.new()
	img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.texture = PhotoStudio.get_shot(shot) if shot != "" else null
	img.modulate = Color(0.75, 0.75, 0.75)
	o.add_child(img)
	var sh := TextureRect.new()
	sh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sh.texture = ImageCard._shade_tex(false)
	sh.stretch_mode = TextureRect.STRETCH_SCALE
	sh.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	o.add_child(sh)
	var v := UIStyle.vbox(6)
	v.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	v.offset_left = 56
	v.offset_bottom = -64
	v.offset_top = -190
	v.offset_right = 900
	v.alignment = BoxContainer.ALIGNMENT_END
	o.add_child(v)
	v.add_child(UIStyle.caps("Preparing your flight", 13, UIStyle.ACCENT, 800, 3))
	v.add_child(UIStyle.title(title_text, 44, Color.WHITE))
	var sl := UIStyle.label(sub, 16, Color(0.9, 0.93, 0.96))
	v.add_child(sl)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(420, 3)
	bar.value = 0.0
	v.add_child(bar)
	o.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(o, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(bar, "value", 35.0, 0.3)
	await tw.finished
	await get_tree().process_frame
	await get_tree().process_frame
	go.call()


static func stat_row(parent: Control, label_text: String, value: String, col: Color = UIStyle.TEXT) -> void:
	var h := UIStyle.hbox(8)
	var l := UIStyle.label(label_text, 14, UIStyle.DIM)
	l.custom_minimum_size = Vector2(150, 0)
	h.add_child(l)
	var v := UIStyle.label(value, 15, col, true)
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.custom_minimum_size = Vector2(180, 0)
	h.add_child(v)
	parent.add_child(h)


static func meter(parent: Control, label_text: String, value: float, col: Color = UIStyle.ACCENT) -> void:
	var h := UIStyle.hbox(8)
	var l := UIStyle.label(label_text, 14, UIStyle.DIM)
	l.custom_minimum_size = Vector2(120, 0)
	h.add_child(l)
	var pb := ProgressBar.new()
	pb.value = value
	pb.custom_minimum_size = Vector2(220, 6)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.show_percentage = false
	pb.add_theme_stylebox_override("fill", UIStyle.box(col, 2, Color(0, 0, 0, 0), 0, 0))
	h.add_child(pb)
	var n := UIStyle.label("%d" % int(value), 14, UIStyle.TEXT, true)
	n.custom_minimum_size = Vector2(30, 0)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(n)
	parent.add_child(h)


static func option(items: Array, selected: int, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(String(it))
	o.selected = clampi(selected, 0, maxi(items.size() - 1, 0))
	o.custom_minimum_size = Vector2(0, 40)
	o.item_selected.connect(cb)
	return o
