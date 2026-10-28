class_name UIStyle
extends RefCounted
## Shared look for every screen, modelled on a modern flight-simulator front end: dark frosted
## glass over the live world, thin hairline borders, one sky-blue accent, condensed bold
## uppercase titles and tracked small caps. Builds a Theme in code (no editor resources) and
## small helpers for common widgets.

const BG := Color(0.02, 0.03, 0.05, 0.86)
const PANEL := Color(0.035, 0.05, 0.072, 0.84)
const PANEL_LIGHT := Color(0.08, 0.11, 0.15, 0.95)
const ACCENT := Color(0.29, 0.74, 1.0)
const AMBER := Color(1.0, 0.72, 0.22)
const RED := Color(1.0, 0.33, 0.28)
const GREEN := Color(0.35, 0.9, 0.52)
const MAGENTA := Color(0.93, 0.45, 0.95)
const TEXT := Color(0.94, 0.96, 0.98)
const DIM := Color(0.62, 0.68, 0.75)
const GOLD := Color(1.0, 0.8, 0.2)
const INK := Color(0.04, 0.06, 0.09)
const LINE := Color(1, 1, 1, 0.12)
const GLASS := Color(0.025, 0.035, 0.05, 0.72)

static var _theme: Theme
static var _font: SystemFont
static var _font_bold: SystemFont
static var _mono: SystemFont
static var _variants := {}


static func font(bold: bool = false) -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Inter", "Roboto", "Noto Sans", "Segoe UI", "DejaVu Sans", "Arial", "Helvetica", "sans-serif"])
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		_font_bold = SystemFont.new()
		_font_bold.font_names = _font.font_names
		_font_bold.font_weight = 700
		_font_bold.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return _font_bold if bold else _font


static func mono() -> SystemFont:
	if _mono == null:
		_mono = SystemFont.new()
		_mono.font_names = PackedStringArray(["JetBrains Mono", "Roboto Mono", "DejaVu Sans Mono", "Consolas", "monospace"])
	return _mono


## A weight / width / tracking variant of the UI typeface (cached). squeeze < 1 condenses it.
static func face(weight: int = 400, squeeze: float = 1.0, tracking: int = 0) -> Font:
	var key := "%d_%.2f_%d" % [weight, squeeze, tracking]
	if _variants.has(key):
		return _variants[key]
	var base := SystemFont.new()
	base.font_names = font().font_names
	base.font_weight = weight
	base.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	var fv := FontVariation.new()
	fv.base_font = base
	if squeeze != 1.0:
		fv.variation_transform = Transform2D(Vector2(squeeze, 0), Vector2(0, 1), Vector2.ZERO)
	fv.spacing_glyph = tracking
	_variants[key] = fv
	return fv


## Condensed heavy face for titles.
static func title_font() -> Font:
	return face(800, 0.9, 0)


static func box(col: Color, radius: int = 10, border: Color = Color(0, 0, 0, 0), bw: int = 0, pad: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.7
	s.content_margin_bottom = pad * 0.7
	s.anti_aliasing = true
	return s


## Frosted glass panel style.
static func glass(radius: int = 6, alpha: float = 0.72, pad: int = 16, border_a: float = 0.1) -> StyleBoxFlat:
	var s := box(Color(GLASS.r, GLASS.g, GLASS.b, alpha), radius, Color(1, 1, 1, border_a), 1, pad)
	s.content_margin_top = pad * 0.8
	s.content_margin_bottom = pad * 0.8
	return s


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 16
	var semi := face(600)
	t.set_color("font_color", "Label", TEXT)
	t.set_font("font", "Button", semi)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", DIM * Color(1, 1, 1, 0.55))
	t.set_stylebox("normal", "Button", box(Color(1, 1, 1, 0.07), 4, Color(1, 1, 1, 0.16), 1, 14))
	t.set_stylebox("hover", "Button", box(Color(1, 1, 1, 0.16), 4, Color(1, 1, 1, 0.6), 1, 14))
	t.set_stylebox("pressed", "Button", box(Color(0.92, 0.95, 0.98, 0.96), 4, Color.WHITE, 1, 14))
	t.set_stylebox("hover_pressed", "Button", box(Color(0.92, 0.95, 0.98, 0.96), 4, Color.WHITE, 1, 14))
	t.set_stylebox("disabled", "Button", box(Color(1, 1, 1, 0.03), 4, Color(1, 1, 1, 0.05), 1, 14))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 4, Color(ACCENT, 0.95), 2, 14))
	t.set_stylebox("panel", "PanelContainer", glass(6, 0.78, 16))
	t.set_stylebox("panel", "Panel", glass(6, 0.78, 16))
	t.set_stylebox("normal", "LineEdit", box(Color(0, 0, 0, 0.35), 4, Color(1, 1, 1, 0.18), 1, 12))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0.45), 4, ACCENT, 1, 12))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(DIM, 0.6))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.1), 2, Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, 2, Color(0, 0, 0, 0), 0, 0))
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_stylebox("slider", "HSlider", box(Color(1, 1, 1, 0.14), 2, Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("grabber_area", "HSlider", box(Color(ACCENT, 0.85), 2, Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, 2, Color(0, 0, 0, 0), 0, 2))
	t.set_icon("grabber", "HSlider", _knob_icon(Color.WHITE))
	t.set_icon("grabber_highlight", "HSlider", _knob_icon(Color(0.85, 0.95, 1.0)))
	t.set_stylebox("panel", "TabContainer", glass(6, 0.78, 12))
	t.set_stylebox("tab_selected", "TabContainer", box(Color(0.92, 0.95, 0.98, 0.95), 3, Color.WHITE, 1, 12))
	t.set_stylebox("tab_unselected", "TabContainer", box(Color(1, 1, 1, 0.05), 3, Color(0, 0, 0, 0), 0, 12))
	t.set_stylebox("tab_hovered", "TabContainer", box(Color(1, 1, 1, 0.12), 3, Color(1, 1, 1, 0.3), 1, 12))
	t.set_color("font_selected_color", "TabContainer", INK)
	t.set_color("font_unselected_color", "TabContainer", DIM)
	t.set_stylebox("panel", "PopupMenu", box(Color(0.05, 0.07, 0.1, 0.98), 4, Color(1, 1, 1, 0.14), 1, 8))
	t.set_stylebox("hover", "PopupMenu", box(Color(1, 1, 1, 0.12), 2, Color(0, 0, 0, 0), 0, 6))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("normal", "OptionButton", box(Color(1, 1, 1, 0.07), 4, Color(1, 1, 1, 0.16), 1, 14))
	t.set_stylebox("hover", "OptionButton", box(Color(1, 1, 1, 0.16), 4, Color(1, 1, 1, 0.6), 1, 14))
	t.set_stylebox("pressed", "OptionButton", box(Color(1, 1, 1, 0.22), 4, ACCENT, 1, 14))
	t.set_stylebox("focus", "OptionButton", box(Color(0, 0, 0, 0), 4, Color(ACCENT, 0.95), 2, 14))
	t.set_color("font_pressed_color", "OptionButton", Color.WHITE)
	t.set_color("font_hover_pressed_color", "OptionButton", Color.WHITE)
	t.set_stylebox("normal", "SpinBox", box(Color(0, 0, 0, 0.35), 4, Color(1, 1, 1, 0.18), 1, 10))
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("scroll", "VScrollBar", box(Color(1, 1, 1, 0.04), 3, Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("grabber", "VScrollBar", box(Color(1, 1, 1, 0.22), 3, Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(1, 1, 1, 0.4), 3, Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(ACCENT, 3, Color(0, 0, 0, 0), 0, 0))
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", Color.WHITE)
	t.set_color("font_pressed_color", "CheckButton", TEXT)
	t.set_color("font_hover_pressed_color", "CheckButton", Color.WHITE)
	t.set_stylebox("hover", "CheckButton", box(Color(1, 1, 1, 0.06), 4, Color(0, 0, 0, 0), 0, 8))
	t.set_stylebox("normal", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("hover_pressed", "CheckButton", box(Color(1, 1, 1, 0.06), 4, Color(0, 0, 0, 0), 0, 8))
	t.set_stylebox("focus", "CheckButton", box(Color(0, 0, 0, 0), 4, Color(ACCENT, 0.9), 2, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.05, 0.07, 0.1, 0.96), 4, Color(1, 1, 1, 0.16), 1, 8))
	_theme = t
	return t


static func _knob_icon(col: Color) -> ImageTexture:
	var img := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	for y in 18:
		for x in 18:
			var d := Vector2(x - 8.5, y - 8.5).length()
			var a := clampf(7.5 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)


static func label(text: String, size: int = 16, col: Color = TEXT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if bold:
		l.add_theme_font_override("font", font(true))
	return l


## Tracked uppercase label (navigation, section headers, captions).
static func caps(text: String, size: int = 13, col: Color = DIM, weight: int = 600, tracking: int = 2) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_override("font", face(weight, 1.0, tracking))
	return l


## Condensed heavy uppercase title.
static func title(text: String, size: int = 30, col: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_override("font", title_font())
	return l


static func button(text: String, cb: Callable, min_w: float = 0.0, accent: Color = Color(0, 0, 0, 0)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 40)
	b.focus_mode = Control.FOCUS_NONE
	if accent.a > 0.0:
		b.add_theme_stylebox_override("normal", box(Color(accent.r * 0.42, accent.g * 0.42, accent.b * 0.42, 0.92), 4, Color(accent, 0.75), 1, 14))
		b.add_theme_stylebox_override("hover", box(Color(accent.r * 0.62, accent.g * 0.62, accent.b * 0.62, 0.98), 4, accent.lightened(0.3), 1, 14))
	b.pressed.connect(_click_sound)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


## The primary call to action: solid, bright, uppercase (FLY, START, CONTINUE).
static func primary(text: String, cb: Callable, min_w: float = 200.0, col: Color = GOLD) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.custom_minimum_size = Vector2(min_w, 48)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", face(800, 0.92, 2))
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_focus_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_stylebox_override("normal", box(col, 3, col.lightened(0.2), 1, 18))
	b.add_theme_stylebox_override("hover", box(col.lightened(0.18), 3, Color.WHITE, 2, 18))
	b.add_theme_stylebox_override("pressed", box(col.darkened(0.15), 3, Color.WHITE, 2, 18))
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), 3, Color.WHITE, 2, 18))
	b.add_theme_stylebox_override("disabled", box(Color(col, 0.25), 3, Color(0, 0, 0, 0), 0, 18))
	b.pressed.connect(_click_sound)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func _click_sound() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var audio := tree.root.get_node_or_null("Audio") if tree else null
	if audio:
		audio.call("click")


static func panel(min_size: Vector2 = Vector2.ZERO, col: Color = PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	if col != PANEL:
		p.add_theme_stylebox_override("panel", box(col, 6, Color(1, 1, 1, 0.08), 1, 16))
	return p


static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func spacer(expand: bool = true) -> Control:
	var c := Control.new()
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func rich(bbcode: String, size: int = 15) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = bbcode
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_override("bold_font", font(true))
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


## Small rounded tag (difficulty, conditions, status).
static func chip(text: String, col: Color = ACCENT, filled: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(col if filled else Color(col, 0.14), 3, Color(col, 0.55), 1, 8)
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	var l := caps(text, 11, INK if filled else col.lightened(0.25), 700, 1)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Thin horizontal rule.
static func rule(col: Color = LINE) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static var _frost_shader: Shader


## Frosted glass: the node's own stylebox is blended over a blurred copy of the screen behind
## it (the live world). Give it an opaque stylebox; `tint` is how much of the box colour shows.
static func frost(ci: CanvasItem, tint: float = 0.72, blur: float = 2.6) -> void:
	if Game.renderer == "gl_compatibility":
		return
	if _frost_shader == null:
		_frost_shader = Shader.new()
		_frost_shader.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float tint = 0.72;
uniform float blur = 2.6;
void fragment() {
	vec3 b = textureLod(screen_tex, SCREEN_UV, blur).rgb;
	b = mix(b, textureLod(screen_tex, SCREEN_UV, blur + 1.0).rgb, 0.5);
	COLOR = vec4(mix(b, COLOR.rgb, tint), COLOR.a);
}
"""
	var m := ShaderMaterial.new()
	m.shader = _frost_shader
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("blur", blur)
	ci.material = m


## A frosted glass PanelContainer (opaque box blended over the blurred world).
static func glass_panel(pad: int = 16, radius: int = 4, tint: float = 0.74) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(Color(0.03, 0.042, 0.06), radius, Color(0.32, 0.36, 0.42), 1, pad)
	sb.content_margin_top = pad * 0.85
	sb.content_margin_bottom = pad * 0.85
	if Game.renderer == "gl_compatibility":
		sb = glass(radius, 0.86, pad)
	p.add_theme_stylebox_override("panel", sb)
	frost(p, tint)
	return p


static func kind_color(kind: String) -> Color:
	match kind:
		"warning", "error", "crash":
			return RED
		"caution":
			return AMBER
		"good", "success":
			return GREEN
	return ACCENT
