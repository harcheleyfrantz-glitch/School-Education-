class_name ScreenBase
extends Control
## Common frame for menu screens: full-screen layer with a soft gradient over the 3D backdrop,
## a header (title, subtitle, back button) and a content area.

var content: VBoxContainer
var header_title: Label
var header_sub: Label


func setup(_params: Dictionary) -> void:
	pass


func frame(title: String, subtitle: String = "", back_to: String = "menu", width: float = 0.62) -> VBoxContainer:
	theme = UIStyle.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := TextureRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.texture = _gradient()
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var margin := MarginContainer.new()
	margin.anchor_right = width
	margin.anchor_bottom = 1.0
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28 if side != "right" else 12)
	add_child(margin)
	var v := UIStyle.vbox(14)
	margin.add_child(v)
	var head := UIStyle.hbox(12)
	if back_to != "":
		var b := UIStyle.button("‹ Back", func(): Game.goto(back_to), 90)
		head.add_child(b)
	var tv := UIStyle.vbox(0)
	header_title = UIStyle.label(title, 30, UIStyle.TEXT, true)
	tv.add_child(header_title)
	header_sub = UIStyle.label(subtitle, 15, UIStyle.DIM)
	header_sub.visible = subtitle != ""
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


static var _grad_tex: GradientTexture2D


static func _gradient() -> GradientTexture2D:
	if _grad_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.01, 0.02, 0.04, 0.92))
		g.set_color(1, Color(0.01, 0.02, 0.04, 0.0))
		g.add_point(0.55, Color(0.01, 0.02, 0.04, 0.78))
		_grad_tex = GradientTexture2D.new()
		_grad_tex.gradient = g
		_grad_tex.fill_from = Vector2(0, 0)
		_grad_tex.fill_to = Vector2(1, 0)
		_grad_tex.width = 256
		_grad_tex.height = 4
	return _grad_tex


func card(title: String = "", min_w: float = 0.0) -> VBoxContainer:
	var p := UIStyle.panel(Vector2(min_w, 0))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(p)
	var v := UIStyle.vbox(8)
	p.add_child(v)
	if title != "":
		v.add_child(UIStyle.label(title, 18, UIStyle.ACCENT, true))
	return v


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
	pb.custom_minimum_size = Vector2(220, 14)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.show_percentage = false
	pb.add_theme_stylebox_override("fill", UIStyle.box(col, 6, Color(0, 0, 0, 0), 0, 0))
	h.add_child(pb)
	h.add_child(UIStyle.label("%d" % int(value), 14, UIStyle.TEXT, true))
	parent.add_child(h)


static func option(items: Array, selected: int, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(String(it))
	o.selected = clampi(selected, 0, maxi(items.size() - 1, 0))
	o.custom_minimum_size = Vector2(0, 38)
	o.item_selected.connect(cb)
	return o
