class_name UIStyle
extends RefCounted
## Shared look for every screen: dark glass panels, rounded corners, one accent colour, clear
## type. Builds a Theme in code (no editor resources) and small helpers for common widgets.

const BG := Color(0.03, 0.05, 0.08, 0.86)
const PANEL := Color(0.06, 0.09, 0.13, 0.92)
const PANEL_LIGHT := Color(0.1, 0.14, 0.19, 0.95)
const ACCENT := Color(0.29, 0.74, 1.0)
const AMBER := Color(1.0, 0.72, 0.22)
const RED := Color(1.0, 0.33, 0.28)
const GREEN := Color(0.35, 0.9, 0.52)
const MAGENTA := Color(0.93, 0.45, 0.95)
const TEXT := Color(0.92, 0.95, 0.98)
const DIM := Color(0.6, 0.67, 0.74)

static var _theme: Theme
static var _font: SystemFont
static var _font_bold: SystemFont
static var _mono: SystemFont


static func font(bold: bool = false) -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Inter", "Noto Sans", "DejaVu Sans", "Arial", "Helvetica", "sans-serif"])
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		_font_bold = SystemFont.new()
		_font_bold.font_names = _font.font_names
		_font_bold.font_weight = 700
	return _font_bold if bold else _font


static func mono() -> SystemFont:
	if _mono == null:
		_mono = SystemFont.new()
		_mono.font_names = PackedStringArray(["JetBrains Mono", "DejaVu Sans Mono", "Consolas", "monospace"])
	return _mono


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


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 16
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", DIM * Color(1, 1, 1, 0.6))
	t.set_stylebox("normal", "Button", box(Color(0.12, 0.17, 0.23, 0.95), 9, Color(ACCENT, 0.25), 1, 12))
	t.set_stylebox("hover", "Button", box(Color(0.16, 0.24, 0.32, 0.98), 9, Color(ACCENT, 0.6), 1, 12))
	t.set_stylebox("pressed", "Button", box(Color(0.1, 0.36, 0.52, 1.0), 9, ACCENT, 1, 12))
	t.set_stylebox("disabled", "Button", box(Color(0.08, 0.1, 0.13, 0.8), 9, Color(1, 1, 1, 0.05), 1, 12))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 9, Color(ACCENT, 0.9), 2, 12))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 14, Color(1, 1, 1, 0.06), 1, 14))
	t.set_stylebox("panel", "Panel", box(PANEL, 14, Color(1, 1, 1, 0.06), 1, 14))
	t.set_stylebox("normal", "LineEdit", box(Color(0.04, 0.06, 0.09, 1), 8, Color(ACCENT, 0.3), 1, 10))
	t.set_stylebox("focus", "LineEdit", box(Color(0.04, 0.06, 0.09, 1), 8, ACCENT, 1, 10))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.08), 6, Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, 6, Color(0, 0, 0, 0), 0, 0))
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_stylebox("slider", "HSlider", box(Color(1, 1, 1, 0.12), 4, Color(0, 0, 0, 0), 0, 3))
	t.set_stylebox("grabber_area", "HSlider", box(Color(ACCENT, 0.7), 4, Color(0, 0, 0, 0), 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, 4, Color(0, 0, 0, 0), 0, 3))
	t.set_stylebox("panel", "TabContainer", box(PANEL, 12, Color(1, 1, 1, 0.06), 1, 12))
	t.set_stylebox("tab_selected", "TabContainer", box(Color(0.12, 0.2, 0.28, 1), 8, Color(ACCENT, 0.7), 1, 12))
	t.set_stylebox("tab_unselected", "TabContainer", box(Color(0.07, 0.1, 0.14, 1), 8, Color(0, 0, 0, 0), 0, 12))
	t.set_stylebox("tab_hovered", "TabContainer", box(Color(0.1, 0.15, 0.2, 1), 8, Color(ACCENT, 0.3), 1, 12))
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", "TabContainer", DIM)
	t.set_stylebox("panel", "PopupMenu", box(PANEL_LIGHT, 10, Color(ACCENT, 0.2), 1, 8))
	t.set_stylebox("normal", "OptionButton", box(Color(0.12, 0.17, 0.23, 0.95), 9, Color(ACCENT, 0.25), 1, 12))
	t.set_stylebox("hover", "OptionButton", box(Color(0.16, 0.24, 0.32, 0.98), 9, Color(ACCENT, 0.6), 1, 12))
	t.set_stylebox("pressed", "OptionButton", box(Color(0.1, 0.36, 0.52, 1.0), 9, ACCENT, 1, 12))
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", TEXT)
	_theme = t
	return t


static func label(text: String, size: int = 16, col: Color = TEXT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if bold:
		l.add_theme_font_override("font", font(true))
	return l


static func button(text: String, cb: Callable, min_w: float = 0.0, accent: Color = Color(0, 0, 0, 0)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 40)
	b.focus_mode = Control.FOCUS_NONE
	if accent.a > 0.0:
		b.add_theme_stylebox_override("normal", box(Color(accent.r * 0.35, accent.g * 0.35, accent.b * 0.35, 0.95), 9, Color(accent, 0.6), 1, 12))
		b.add_theme_stylebox_override("hover", box(Color(accent.r * 0.5, accent.g * 0.5, accent.b * 0.5, 0.98), 9, accent, 1, 12))
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
		p.add_theme_stylebox_override("panel", box(col, 14, Color(1, 1, 1, 0.06), 1, 14))
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


static func kind_color(kind: String) -> Color:
	match kind:
		"warning", "error", "crash":
			return RED
		"caution":
			return AMBER
		"good", "success":
			return GREEN
	return ACCENT
