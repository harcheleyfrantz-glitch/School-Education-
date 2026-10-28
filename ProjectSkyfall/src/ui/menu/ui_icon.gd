class_name UIIcon
extends Control
## Crisp vector icons drawn in code (no image assets): navigation, conditions, medals.

var icon := "chevron"
var color := Color.WHITE
var weight := 2.0


static func make(kind: String, px: float = 20.0, col: Color = Color.WHITE, w: float = 2.0) -> UIIcon:
	var i := UIIcon.new()
	i.icon = kind
	i.color = col
	i.weight = w
	i.custom_minimum_size = Vector2(px, px)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func set_icon(kind: String, col: Color = color) -> void:
	icon = kind
	color = col
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	draw(self, icon, Rect2(o, Vector2(s, s)), color, weight)


## Draws an icon into any CanvasItem inside rect r.
static func draw(ci: CanvasItem, kind: String, r: Rect2, col: Color, w: float = 2.0) -> void:
	var c := r.get_center()
	var s := r.size.x
	var p := func(x: float, y: float) -> Vector2: return r.position + Vector2(x, y) * s
	match kind:
		"chevron":
			ci.draw_polyline(PackedVector2Array([p.call(0.36, 0.2), p.call(0.66, 0.5), p.call(0.36, 0.8)]), col, w, true)
		"chevron_left":
			ci.draw_polyline(PackedVector2Array([p.call(0.64, 0.2), p.call(0.34, 0.5), p.call(0.64, 0.8)]), col, w, true)
		"chevron2":
			ci.draw_polyline(PackedVector2Array([p.call(0.22, 0.22), p.call(0.48, 0.5), p.call(0.22, 0.78)]), col, w, true)
			ci.draw_polyline(PackedVector2Array([p.call(0.52, 0.22), p.call(0.78, 0.5), p.call(0.52, 0.78)]), col, w, true)
		"home":
			ci.draw_polyline(PackedVector2Array([p.call(0.12, 0.5), p.call(0.5, 0.16), p.call(0.88, 0.5)]), col, w, true)
			ci.draw_polyline(PackedVector2Array([p.call(0.24, 0.42), p.call(0.24, 0.86), p.call(0.76, 0.86), p.call(0.76, 0.42)]), col, w, true)
			ci.draw_rect(Rect2(p.call(0.42, 0.6), Vector2(0.16, 0.26) * s), col)
		"plane":
			var pts := PackedVector2Array()
			for v in [[0.5, 0.06], [0.56, 0.14], [0.56, 0.38], [0.94, 0.58], [0.94, 0.66], [0.56, 0.54], [0.56, 0.78], [0.68, 0.88], [0.68, 0.94],
					[0.5, 0.89], [0.32, 0.94], [0.32, 0.88], [0.44, 0.78], [0.44, 0.54], [0.06, 0.66], [0.06, 0.58], [0.44, 0.38], [0.44, 0.14]]:
				pts.append(p.call(v[0], v[1]))
			ci.draw_colored_polygon(pts, col)
		"globe":
			ci.draw_arc(c, s * 0.4, 0.0, TAU, 32, col, w, true)
			ci.draw_line(p.call(0.1, 0.5), p.call(0.9, 0.5), col, w * 0.8, true)
			var pts2 := PackedVector2Array()
			for k in 17:
				var a := -PI * 0.5 + PI * k / 16.0
				pts2.append(c + Vector2(cos(a) * s * 0.17, sin(a) * s * 0.4))
			ci.draw_polyline(pts2, col, w * 0.8, true)
			var pts3 := PackedVector2Array()
			for k in 17:
				var a2 := PI * 0.5 + PI * k / 16.0
				pts3.append(c + Vector2(cos(a2) * s * 0.17, sin(a2) * s * 0.4))
			ci.draw_polyline(pts3, col, w * 0.8, true)
		"user":
			ci.draw_arc(p.call(0.5, 0.34), s * 0.17, 0.0, TAU, 24, col, w, true)
			ci.draw_arc(p.call(0.5, 0.98), s * 0.36, PI * 1.08, PI * 1.92, 20, col, w, true)
		"gear":
			ci.draw_arc(c, s * 0.15, 0.0, TAU, 20, col, w, true)
			for k in 8:
				var a3 := TAU * k / 8.0
				ci.draw_line(c + Vector2(cos(a3), sin(a3)) * s * 0.26, c + Vector2(cos(a3), sin(a3)) * s * 0.42, col, w * 1.6, true)
			ci.draw_arc(c, s * 0.28, 0.0, TAU, 24, col, w, true)
		"news":
			ci.draw_rect(Rect2(p.call(0.14, 0.18), Vector2(0.72, 0.64) * s), col, false, w)
			ci.draw_rect(Rect2(p.call(0.24, 0.3), Vector2(0.22, 0.18) * s), col)
			for k2 in 3:
				ci.draw_line(p.call(0.54, 0.32 + k2 * 0.08), p.call(0.76, 0.32 + k2 * 0.08), col, w * 0.7)
			ci.draw_line(p.call(0.24, 0.6), p.call(0.76, 0.6), col, w * 0.7)
			ci.draw_line(p.call(0.24, 0.7), p.call(0.66, 0.7), col, w * 0.7)
		"trophy":
			ci.draw_polyline(PackedVector2Array([p.call(0.3, 0.16), p.call(0.7, 0.16), p.call(0.66, 0.46), p.call(0.5, 0.58), p.call(0.34, 0.46), p.call(0.3, 0.16)]), col, w, true)
			ci.draw_arc(p.call(0.3, 0.3), s * 0.11, PI * 0.5, PI * 1.5, 10, col, w * 0.8, true)
			ci.draw_arc(p.call(0.7, 0.3), s * 0.11, -PI * 0.5, PI * 0.5, 10, col, w * 0.8, true)
			ci.draw_line(p.call(0.5, 0.58), p.call(0.5, 0.74), col, w)
			ci.draw_line(p.call(0.32, 0.82), p.call(0.68, 0.82), col, w * 1.4)
		"star":
			var st := PackedVector2Array()
			for k3 in 10:
				var a4 := -PI * 0.5 + TAU * k3 / 10.0
				var rr := s * (0.44 if k3 % 2 == 0 else 0.19)
				st.append(c + Vector2(cos(a4), sin(a4)) * rr)
			ci.draw_colored_polygon(st, col)
		"clock":
			ci.draw_arc(c, s * 0.38, 0.0, TAU, 28, col, w, true)
			ci.draw_line(c, p.call(0.5, 0.26), col, w, true)
			ci.draw_line(c, p.call(0.66, 0.6), col, w, true)
		"wind":
			ci.draw_polyline(PackedVector2Array([p.call(0.1, 0.38), p.call(0.66, 0.38)]), col, w, true)
			ci.draw_arc(p.call(0.66, 0.28), s * 0.1, PI * 0.5, PI * 2.2, 12, col, w, true)
			ci.draw_polyline(PackedVector2Array([p.call(0.1, 0.58), p.call(0.8, 0.58)]), col, w, true)
			ci.draw_arc(p.call(0.8, 0.68), s * 0.1, -PI * 0.5, PI * 0.9, 12, col, w, true)
			ci.draw_line(p.call(0.18, 0.76), p.call(0.5, 0.76), col, w, true)
		"sun":
			ci.draw_circle(c, s * 0.18, col)
			for k4 in 8:
				var a5 := TAU * k4 / 8.0
				ci.draw_line(c + Vector2(cos(a5), sin(a5)) * s * 0.28, c + Vector2(cos(a5), sin(a5)) * s * 0.42, col, w, true)
		"moon":
			var mp := PackedVector2Array()
			for k5 in 25:
				var a6 := PI * 0.35 + (TAU - PI * 0.7) * k5 / 24.0
				mp.append(c + Vector2(cos(a6), sin(a6)) * s * 0.38)
			for k6 in 25:
				var a7 := PI * 2.0 - PI * 0.42 - (TAU - PI * 0.84) * k6 / 24.0
				mp.append(c + Vector2(s * 0.16, -s * 0.06) + Vector2(cos(a7), sin(a7)) * s * 0.3)
			ci.draw_colored_polygon(mp, col)
		"cloud":
			ci.draw_circle(p.call(0.36, 0.56), s * 0.16, col)
			ci.draw_circle(p.call(0.56, 0.46), s * 0.2, col)
			ci.draw_circle(p.call(0.72, 0.6), s * 0.13, col)
			ci.draw_rect(Rect2(p.call(0.22, 0.6), Vector2(0.56, 0.13) * s), col)
		"fog":
			for k7 in 4:
				ci.draw_line(p.call(0.14 + (k7 % 2) * 0.08, 0.28 + k7 * 0.15), p.call(0.86 - (k7 % 2) * 0.08, 0.28 + k7 * 0.15), col, w, true)
		"rain":
			UIIcon.draw(ci, "cloud", Rect2(r.position - Vector2(0, s * 0.12), r.size), col, w)
			for k8 in 3:
				ci.draw_line(p.call(0.34 + k8 * 0.16, 0.74), p.call(0.28 + k8 * 0.16, 0.9), col, w, true)
		"storm":
			UIIcon.draw(ci, "cloud", Rect2(r.position - Vector2(0, s * 0.14), r.size), col, w)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.54, 0.64), p.call(0.4, 0.82), p.call(0.5, 0.82), p.call(0.44, 0.98), p.call(0.62, 0.76), p.call(0.52, 0.76), p.call(0.6, 0.64)]), col)
		"snow":
			for k9 in 3:
				var a8 := PI * k9 / 3.0
				ci.draw_line(c - Vector2(cos(a8), sin(a8)) * s * 0.38, c + Vector2(cos(a8), sin(a8)) * s * 0.38, col, w, true)
		"pin":
			ci.draw_circle(p.call(0.5, 0.38), s * 0.24, col)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.3, 0.48), p.call(0.7, 0.48), p.call(0.5, 0.92)]), col)
			ci.draw_circle(p.call(0.5, 0.38), s * 0.09, Color(0, 0, 0, 0.6))
		"play":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.3, 0.18), p.call(0.82, 0.5), p.call(0.3, 0.82)]), col)
		"lock":
			ci.draw_rect(Rect2(p.call(0.24, 0.46), Vector2(0.52, 0.4) * s), col)
			ci.draw_arc(p.call(0.5, 0.46), s * 0.17, PI, TAU, 12, col, w * 1.2, true)
		"check":
			ci.draw_polyline(PackedVector2Array([p.call(0.18, 0.52), p.call(0.42, 0.74), p.call(0.84, 0.28)]), col, w * 1.2, true)
		"close":
			ci.draw_line(p.call(0.24, 0.24), p.call(0.76, 0.76), col, w, true)
			ci.draw_line(p.call(0.76, 0.24), p.call(0.24, 0.76), col, w, true)
		"medal":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.3, 0.06), p.call(0.44, 0.06), p.call(0.56, 0.42), p.call(0.42, 0.42)]), col.darkened(0.25))
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.56, 0.06), p.call(0.7, 0.06), p.call(0.58, 0.42), p.call(0.44, 0.42)]), col.darkened(0.1))
			ci.draw_circle(p.call(0.5, 0.64), s * 0.27, col)
			ci.draw_arc(p.call(0.5, 0.64), s * 0.19, 0.0, TAU, 20, col.darkened(0.3), w * 0.7, true)
		"route":
			ci.draw_circle(p.call(0.2, 0.78), s * 0.09, col)
			ci.draw_circle(p.call(0.8, 0.22), s * 0.09, col)
			var rp := PackedVector2Array()
			for k10 in 13:
				var tt := k10 / 12.0
				rp.append(p.call(0.2, 0.78).lerp(p.call(0.8, 0.22), tt) + Vector2(-0.18, -0.18) * s * sin(tt * PI))
			ci.draw_polyline(rp, col, w * 0.8, true)
		"logbook":
			ci.draw_rect(Rect2(p.call(0.2, 0.12), Vector2(0.6, 0.76) * s), col, false, w)
			ci.draw_line(p.call(0.32, 0.12), p.call(0.32, 0.88), col, w)
			for k11 in 3:
				ci.draw_line(p.call(0.42, 0.32 + k11 * 0.16), p.call(0.7, 0.32 + k11 * 0.16), col, w * 0.7)
		"hangar":
			ci.draw_polyline(PackedVector2Array([p.call(0.08, 0.86), p.call(0.08, 0.44), p.call(0.5, 0.16), p.call(0.92, 0.44), p.call(0.92, 0.86)]), col, w, true)
			ci.draw_line(p.call(0.08, 0.86), p.call(0.92, 0.86), col, w)
			UIIcon.draw(ci, "plane", Rect2(r.position + Vector2(s * 0.28, s * 0.42), r.size * 0.44), col, w)
		"bell":
			ci.draw_arc(p.call(0.5, 0.5), s * 0.26, PI, TAU, 14, col, w, true)
			ci.draw_polyline(PackedVector2Array([p.call(0.24, 0.5), p.call(0.2, 0.72), p.call(0.8, 0.72), p.call(0.76, 0.5)]), col, w, true)
			ci.draw_circle(p.call(0.5, 0.82), s * 0.07, col)
		_:
			ci.draw_circle(c, s * 0.2, col)
