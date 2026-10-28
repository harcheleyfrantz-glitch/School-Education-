class_name RankEmblem
extends Control
## Procedural rank insignia: a hexagonal badge in the rank's colour with spread wings, gold
## rank stripes (one for a student up to four for a captain), stars for senior ranks and the
## pilot level on a tab below. A slow glint passes over it.

const TIERS := {
	"": [Color(0.32, 0.36, 0.42), 0, 0],
	"Student Pilot": [Color(0.16, 0.62, 0.66), 1, 0], "Private Pilot": [Color(0.22, 0.66, 0.42), 1, 1],
	"Commercial Pilot": [Color(0.2, 0.5, 0.86), 2, 0], "Flight Instructor": [Color(0.3, 0.42, 0.9), 2, 1],
	"First Officer": [Color(0.14, 0.36, 0.78), 3, 0], "Senior First Officer": [Color(0.18, 0.3, 0.7), 3, 1],
	"Captain": [Color(0.86, 0.5, 0.12), 4, 0], "Senior Captain": [Color(0.86, 0.36, 0.12), 4, 1], "Training Captain": [Color(0.78, 0.18, 0.16), 4, 2],
}

var rank := ""
var level := 1
var _glint := -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween().set_loops()
	tw.tween_interval(2.5)
	tw.tween_method(func(v: float):
		_glint = v
		queue_redraw(), -0.3, 1.3, 1.4).set_trans(Tween.TRANS_SINE)


func _hex(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := -PI * 0.5 + TAU * i / 6.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


func _draw() -> void:
	var t: Array = TIERS.get(rank, TIERS[""])
	var col: Color = t[0]
	var stripes := int(t[1])
	var stars := int(t[2])
	var s := minf(size.x, size.y * 0.9)
	var c := Vector2(size.x * 0.5, s * 0.47)
	var r := s * 0.4
	# shadow and outer bevel
	draw_colored_polygon(_hex(c + Vector2(0, 4), r * 1.04), Color(0, 0, 0, 0.35))
	var outer := _hex(c, r)
	var cols := PackedColorArray()
	for i in 6:
		cols.append(col.lightened(0.25) if i in [0, 1, 5] else col.darkened(0.2))
	draw_polygon(outer, cols)
	draw_colored_polygon(_hex(c, r * 0.84), Color(0.03, 0.05, 0.08, 0.9))
	draw_polyline(_close(_hex(c, r * 0.84)), col.lightened(0.35), 2.0, true)
	draw_polyline(_close(outer), Color(1, 1, 1, 0.55), 1.5, true)
	# wings
	var wc := c + Vector2(0, -r * 0.18)
	for side in [-1.0, 1.0]:
		for k in 4:
			var span := r * (0.62 - k * 0.1)
			var y := float(k) * r * 0.075
			var pts := PackedVector2Array([wc + Vector2(side * r * 0.09, y - r * 0.02), wc + Vector2(side * span, y - r * 0.16 + k * r * 0.03),
				wc + Vector2(side * span * 0.92, y - r * 0.08 + k * r * 0.03), wc + Vector2(side * r * 0.09, y + r * 0.06)])
			draw_colored_polygon(pts, Color(1, 1, 1, 0.92 - k * 0.12))
	draw_circle(wc + Vector2(0, r * 0.02), r * 0.11, col.lightened(0.15))
	draw_arc(wc + Vector2(0, r * 0.02), r * 0.11, 0.0, TAU, 20, Color(1, 1, 1, 0.9), 1.5, true)
	# rank stripes
	var gold := Color(1.0, 0.8, 0.28)
	for i in stripes:
		var y2 := c.y + r * 0.2 + i * r * 0.11
		var w := r * 0.62
		draw_rect(Rect2(Vector2(c.x - w * 0.5, y2), Vector2(w, r * 0.065)), gold)
	for j in stars:
		var sc := c + Vector2((float(j) - (stars - 1) * 0.5) * r * 0.3, -r * 0.6)
		UIIcon.draw(self, "star", Rect2(sc - Vector2(r * 0.12, r * 0.12), Vector2(r * 0.24, r * 0.24)), gold)
	# glint
	if _glint > -0.25 and _glint < 1.25:
		var gx := c.x - r + _glint * r * 2.0
		var band := PackedVector2Array()
		var bc := PackedColorArray()
		for p in outer:
			band.append(p)
			var d := absf(p.x + (p.y - c.y) * 0.5 - gx)
			bc.append(Color(1, 1, 1, clampf(0.28 - d / r * 0.5, 0.0, 0.28)))
		draw_polygon(band, bc)
	# level tab
	var tab := Rect2(Vector2(c.x - r * 0.42, c.y + r * 0.86), Vector2(r * 0.84, r * 0.3))
	draw_rect(tab, Color(0.94, 0.96, 0.98))
	var f := UIStyle.title_font()
	var fs := int(r * 0.22)
	var txt := "LV %d" % level
	var ts := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(f, Vector2(tab.get_center().x - ts.x * 0.5, tab.get_center().y + ts.y * 0.3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIStyle.INK)


func _close(p: PackedVector2Array) -> PackedVector2Array:
	var q := p.duplicate()
	q.append(p[0])
	return q
