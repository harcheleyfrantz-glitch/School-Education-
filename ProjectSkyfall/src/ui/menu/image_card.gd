class_name ImageCard
extends Control
## A big picture card in the style of a modern flight-simulator front end: an in-engine render
## (from the PhotoStudio) filling the card, a dark gradient, a chevron box and a bold uppercase
## title with a short subtitle, an optional NEW / FEATURED ribbon, a progress bar or a big count
## badge. Hover and focus zoom the picture, light the border and sweep a glint across it; press
## gives a little push. Works with mouse, touch, keyboard and gamepad.

signal activated

var title := ""
var subtitle := ""
var ribbon := ""
var ribbon_color := UIStyle.GOLD
var badge := ""                 ## big number in a top band (activity categories)
var progress := -1.0            ## 0..1 bar along the bottom
var progress_text := ""
var shot_id := ""
var icon_name := "plane"        ## placeholder icon while the picture renders
var title_size := 20
var top_band := false
var kenburns := false
var on_pressed: Callable

var _tex: Texture2D
var _clip: Control
var _img: TextureRect
var _shade: TextureRect
var _sweep: Sweep
var _ph: Placeholder
var _border: Panel
var _border_sb: StyleBoxFlat
var _chev: Panel
var _chev_sb: StyleBoxFlat
var _title_row: Control
var _hover := 0.0
var _hover_tw: Tween
var _hovered := false
var _focused := false
var _press_in := false


static func make(t: String, sub: String, shot: String, cb: Callable, opts: Dictionary = {}) -> ImageCard:
	var c := ImageCard.new()
	c.title = t
	c.subtitle = sub
	c.shot_id = shot
	c.on_pressed = cb
	for k in opts.keys():
		c.set(k, opts[k])
	return c


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = false
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_clip)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(bg)
	_ph = Placeholder.new()
	_ph.icon_name = icon_name
	_ph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_ph)
	_img = TextureRect.new()
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_img.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_img.modulate.a = 0.0
	_clip.add_child(_img)
	_shade = TextureRect.new()
	_shade.texture = _shade_tex(top_band)
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_shade)
	_sweep = Sweep.new()
	_sweep.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_sweep)
	if top_band:
		_clip.add_child(_build_band())
	_clip.add_child(_build_caption())
	if ribbon != "":
		add_child(_build_ribbon())
	_border = Panel.new()
	_border_sb = StyleBoxFlat.new()
	_border_sb.draw_center = false
	_border_sb.set_border_width_all(1)
	_border_sb.border_color = Color(1, 1, 1, 0.16)
	_border_sb.set_corner_radius_all(3)
	_border_sb.anti_aliasing = true
	_border.add_theme_stylebox_override("panel", _border_sb)
	_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_border)
	resized.connect(_on_resized)
	mouse_entered.connect(func():
		_hovered = true
		_set_hover(true))
	mouse_exited.connect(func():
		_hovered = false
		_press_in = false
		_set_hover(_focused))
	focus_entered.connect(func():
		_focused = true
		_set_hover(true))
	focus_exited.connect(func():
		_focused = false
		_set_hover(_hovered))
	if shot_id != "":
		set_shot(shot_id)


func set_shot(id: String) -> void:
	shot_id = id
	var t := PhotoStudio.get_shot(id, true)
	if t:
		_apply(t, false)
	else:
		var st := PhotoStudio.instance()
		if not st.shot_ready.is_connected(_on_shot):
			st.shot_ready.connect(_on_shot)


func set_texture(t: Texture2D) -> void:
	_apply(t, true)


func _on_shot(id: String, t: Texture2D) -> void:
	if id == shot_id and is_instance_valid(_img):
		_apply(t, true)


func _apply(t: Texture2D, fade: bool) -> void:
	_tex = t
	_img.texture = t
	if fade and is_inside_tree():
		create_tween().tween_property(_img, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)
	else:
		_img.modulate.a = 1.0
	_ph.loading = false
	if kenburns:
		_start_kenburns()


func _start_kenburns() -> void:
	var tw := create_tween().set_loops()
	tw.tween_property(_img, "scale", Vector2(1.07, 1.07), 16.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_img, "scale", Vector2(1.0, 1.0), 16.0).set_trans(Tween.TRANS_SINE)


func _on_resized() -> void:
	_img.pivot_offset = size * 0.5
	pivot_offset = size * 0.5


func _build_caption() -> Control:
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16 if side != "bottom" else (18 if progress < 0.0 else 22))
	m.add_theme_constant_override("margin_top", 12)
	var v := UIStyle.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_END
	m.add_child(v)
	var row := UIStyle.hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_row = row
	_chev = Panel.new()
	_chev.custom_minimum_size = Vector2(28, 28)
	_chev.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_chev_sb = StyleBoxFlat.new()
	_chev_sb.bg_color = Color(1, 1, 1, 0.0)
	_chev_sb.border_color = Color(1, 1, 1, 0.85)
	_chev_sb.set_border_width_all(2)
	_chev_sb.set_corner_radius_all(2)
	_chev.add_theme_stylebox_override("panel", _chev_sb)
	_chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ci := UIIcon.make("chevron2", 22, Color.WHITE, 2.0)
	ci.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ci.position = Vector2(3, 3)
	_chev.add_child(ci)
	if not top_band:
		row.add_child(_chev)
	var tv := UIStyle.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not top_band:
		var tl := UIStyle.title(title, title_size, Color.WHITE)
		tl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
		tl.add_theme_constant_override("shadow_offset_y", 1)
		tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tl.clip_text = true
		tv.add_child(tl)
	if subtitle != "":
		var sl := UIStyle.label(subtitle, 13, Color(0.88, 0.91, 0.95, 0.92))
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.max_lines_visible = 2
		sl.custom_minimum_size = Vector2(10, 18 if subtitle.length() < 34 else 34)
		sl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		sl.add_theme_constant_override("shadow_offset_y", 1)
		tv.add_child(sl)
	row.add_child(tv)
	v.add_child(row)
	if progress >= 0.0:
		var ph := UIStyle.hbox(10)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pb := ProgressBar.new()
		pb.show_percentage = false
		pb.value = progress * 100.0
		pb.custom_minimum_size = Vector2(0, 4)
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pb.add_theme_stylebox_override("background", UIStyle.box(Color(1, 1, 1, 0.18), 0, Color(0, 0, 0, 0), 0, 0))
		pb.add_theme_stylebox_override("fill", UIStyle.box(UIStyle.ACCENT, 0, Color(0, 0, 0, 0), 0, 0))
		ph.add_child(pb)
		if progress_text != "":
			ph.add_child(UIStyle.caps(progress_text, 11, Color(1, 1, 1, 0.85), 700, 1))
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(0, 10)
		v.add_child(pad)
		v.add_child(ph)
	return m


func _build_band() -> Control:
	## Top band for tall category cards: big count disc and the title.
	var band := PanelContainer.new()
	band.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	band.offset_bottom = 66
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.92, 0.95, 0.98, 0.2)
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.border_width_bottom = 1
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	band.add_theme_stylebox_override("panel", sb)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UIStyle.hbox(14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(h)
	if badge != "":
		var disc := CountDisc.new()
		disc.text = badge
		disc.custom_minimum_size = Vector2(42, 42)
		disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(disc)
	var tl := UIStyle.title(title, title_size, Color.WHITE)
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	tl.add_theme_constant_override("shadow_offset_y", 1)
	h.add_child(tl)
	return band


func _build_ribbon() -> Control:
	var p := PanelContainer.new()
	var sb := UIStyle.box(ribbon_color, 2, Color(0, 0, 0, 0), 0, 9)
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(UIStyle.caps(ribbon, 11, UIStyle.INK, 800, 2))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.anchor_left = 1.0
	p.anchor_right = 1.0
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.offset_right = -12
	p.offset_top = 12 if not top_band else 78
	return p


static var _shades := {}


static func _shade_tex(band: bool) -> GradientTexture2D:
	if _shades.has(band):
		return _shades[band]
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.32 if band else 0.0))
	g.set_color(1, Color(0.0, 0.01, 0.02, 0.9))
	g.add_point(0.22 if band else 0.4, Color(0, 0, 0, 0.0))
	g.add_point(0.72, Color(0.0, 0.01, 0.02, 0.45))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	t.width = 4
	t.height = 128
	_shades[band] = t
	return t


func _set_hover(on: bool) -> void:
	if _hover_tw and _hover_tw.is_valid():
		_hover_tw.kill()
	_hover_tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hover_tw.tween_method(_apply_hover, _hover, 1.0 if on else 0.0, 0.35)
	if on:
		_sweep.play()


func _apply_hover(v: float) -> void:
	_hover = v
	if not kenburns:
		_img.scale = Vector2.ONE * (1.0 + 0.055 * v)
	_border_sb.border_color = Color(1, 1, 1, 0.16).lerp(Color(1, 1, 1, 0.95), v)
	_border_sb.set_border_width_all(1 if v < 0.5 else 2)
	_chev_sb.bg_color = Color(UIStyle.ACCENT, 0.9 * v)
	_chev_sb.border_color = Color(1, 1, 1, 0.85).lerp(UIStyle.ACCENT.lightened(0.3), v)
	if _title_row:
		_title_row.position.x = 5.0 * v
	_border.queue_redraw()
	_chev.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_in = true
			_push(true)
		elif _press_in:
			_press_in = false
			_push(false)
			_activate()
		accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_press_in = true
			_push(true)
		elif _press_in:
			_press_in = false
			_push(false)
			_activate()
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		_push(true)
		_push(false)
		_activate()
		accept_event()


func _push(down: bool) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE * (0.975 if down else 1.0), 0.12 if down else 0.25)


func _activate() -> void:
	UIStyle._click_sound()
	activated.emit()
	if on_pressed.is_valid():
		on_pressed.call()


## The glint that sweeps across a card when it is hovered or focused.
class Sweep extends Control:
	var t := -1.0

	func play() -> void:
		var tw := create_tween()
		tw.tween_method(func(v: float):
			t = v
			queue_redraw(), 0.0, 1.0, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(func():
			t = -1.0
			queue_redraw())

	func _draw() -> void:
		if t < 0.0:
			return
		var w := size.x * 0.22
		var x := lerpf(-w * 2.0, size.x + w, t)
		var sl := size.y * 0.45
		var c0 := Color(1, 1, 1, 0.0)
		var c1 := Color(1, 1, 1, 0.16)
		draw_polygon(PackedVector2Array([Vector2(x, size.y), Vector2(x + sl, 0), Vector2(x + sl + w * 0.5, 0), Vector2(x + w * 0.5, size.y)]),
			PackedColorArray([c0, c0, c1, c1]))
		draw_polygon(PackedVector2Array([Vector2(x + w * 0.5, size.y), Vector2(x + sl + w * 0.5, 0), Vector2(x + sl + w, 0), Vector2(x + w, size.y)]),
			PackedColorArray([c1, c1, c0, c0]))


## Shown while the picture renders: a dark gradient with a slow shimmer and a faint icon.
class Placeholder extends Control:
	var loading := true
	var icon_name := "plane"
	var _t := 0.0

	func _process(delta: float) -> void:
		if not loading:
			set_process(false)
			return
		_t += delta
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.055, 0.075, 0.1))
		var g := fmod(_t * 0.45, 1.6) - 0.3
		var x := g * size.x
		var w := size.x * 0.35
		var c0 := Color(1, 1, 1, 0.0)
		var c1 := Color(1, 1, 1, 0.045)
		draw_polygon(PackedVector2Array([Vector2(x - w, size.y), Vector2(x, 0), Vector2(x + w * 0.5, 0), Vector2(x - w * 0.5, size.y)]),
			PackedColorArray([c0, c0, c1, c1]))
		draw_polygon(PackedVector2Array([Vector2(x - w * 0.5, size.y), Vector2(x + w * 0.5, 0), Vector2(x + w, 0), Vector2(x, size.y)]),
			PackedColorArray([c1, c1, c0, c0]))
		var s := minf(size.x, size.y) * 0.16
		UIIcon.draw(self, icon_name, Rect2(size * 0.5 - Vector2(s, s) * 0.5 - Vector2(0, size.y * 0.08), Vector2(s, s)), Color(1, 1, 1, 0.08), 2.0)


## Count badge for category cards (a ringed disc with a big number).
class CountDisc extends Control:
	var text := "5"

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color(0.02, 0.03, 0.05, 0.55))
		draw_arc(c, r - 1.5, 0.0, TAU, 40, Color(1, 1, 1, 0.85), 2.0, true)
		var f := UIStyle.title_font()
		var fs := int(r * 1.15)
		var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, c + Vector2(-ts.x * 0.5, ts.y * 0.32), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
