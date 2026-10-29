class_name StoryGraphic
extends Control
## The key graphic of a story: a map of the region with the route and the crash site, the
## flight and a headline tag, in the outlet's colours. Rendered onto the studio video wall,
## used for over-the-shoulder boxes and for video thumbnails.

var program: Dictionary = {}
var outlet := "skyline"
var t := 0.0
var map_tex: Texture2D
var map_center := Vector2.ZERO
var map_half := 60000.0
var site := Vector2.INF
var dep := Vector2.INF
var arr := Vector2.INF
var dep_name := ""
var arr_name := ""
var tag := ""
var title := ""
var sub := ""
var kind := "crash"


func setup(prog: Dictionary) -> void:
	program = prog
	outlet = String(prog.get("outlet", "skyline"))
	var w: Dictionary = prog.get("world", {})
	var pk := String(prog.get("kind", ""))
	kind = "crash" if pk.begins_with("accident") or pk == "inv_report" else ("storm" if "weather" in pk or "storm" in pk else "travel")
	if String(w.get("mode", "")) == "incident":
		site = Vector2(float(w.get("x", 0.0)), float(w.get("z", 0.0)))
	var inc := News.incident(String(prog.get("incident", "")))
	var d_icao := String(inc.get("dep", w.get("dep", "")))
	var a_icao := String(inc.get("arr", w.get("arr", w.get("icao", ""))))
	if d_icao != "":
		var ap: Dictionary = Airports.get_ap(d_icao)
		dep = Vector2(float(ap.x), float(ap.z))
		dep_name = String(ap.short)
	if a_icao != "":
		var ap2: Dictionary = Airports.get_ap(a_icao)
		arr = Vector2(float(ap2.x), float(ap2.z))
		arr_name = String(ap2.short)
	var pts := []
	for p in [site, dep, arr]:
		if p != Vector2.INF:
			pts.append(p)
	if pts.is_empty():
		pts.append(Vector2(-40000.0, 0.0))
	var lo: Vector2 = pts[0]
	var hi: Vector2 = pts[0]
	for p2 in pts:
		lo = Vector2(minf(lo.x, p2.x), minf(lo.y, p2.y))
		hi = Vector2(maxf(hi.x, p2.x), maxf(hi.y, p2.y))
	map_center = (lo + hi) * 0.5
	map_half = clampf(maxf(hi.x - lo.x, hi.y - lo.y) * 0.62, 30000.0, 190000.0)
	if site != Vector2.INF:
		map_center = map_center.lerp(site, 0.35)
	var dark := NewsStyle.col(outlet, "secondary")
	map_tex = NewsMap.texture(map_center, map_half, 192, dark.lerp(Color(0.05, 0.12, 0.22), 0.6), Color(0.2, 0.26, 0.24), Color(0.5, 0.48, 0.42), Color(0.55, 0.75, 0.9))
	tag = {"crash": "PLANE CRASH", "storm": "STORM CHAOS", "travel": "TRAVEL"}.get(kind, "NEWS")
	if pk == "accident_prelim" or pk == "inv_report":
		tag = "INVESTIGATION"
	elif pk in ["accident_victims", "accident_memorial", "accident_anniversary"]:
		tag = "REMEMBERED"
	elif String(inc.get("id", "")) != "" and bool(inc.get("ditching", false)):
		tag = "DITCHING"
	title = String(prog.get("headline", ""))
	sub = String(prog.get("sub", ""))


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	var sz := size
	var prim := NewsStyle.col(outlet, "primary")
	var dark := NewsStyle.col(outlet, "secondary")
	var hi := NewsStyle.col(outlet, "hi")
	# background: deep gradient with slow light sweeps
	var steps := 24
	for i in steps:
		var f := float(i) / steps
		draw_rect(Rect2(0, sz.y * f, sz.x, sz.y / steps + 1.0), dark.lerp(dark.darkened(0.6), f))
	for k in 5:
		var x0 := fmod(t * (24.0 + k * 9.0) + k * 230.0, sz.x + 600.0) - 300.0
		var pts := PackedVector2Array([Vector2(x0, 0), Vector2(x0 + 60.0 + k * 14.0, 0), Vector2(x0 - 140.0 + k * 14.0, sz.y), Vector2(x0 - 200.0, sz.y)])
		draw_colored_polygon(pts, Color(prim, 0.06 + 0.02 * (k % 2)))
	# map panel
	var mr := Rect2(sz.x * 0.04, sz.y * 0.1, sz.y * 0.8, sz.y * 0.8)
	if map_tex:
		draw_texture_rect(map_tex, mr, false, Color(1, 1, 1, 0.95))
	draw_rect(mr, Color(prim, 0.9), false, maxf(sz.y * 0.006, 1.5))
	var fs := maxi(int(sz.y * 0.035), 10)
	var f_b := NewsStyle.font("sans", 800)
	var f_r := NewsStyle.font("sans", 500)
	# route and places
	if dep != Vector2.INF and arr != Vector2.INF:
		var a := NewsMap.to_px(dep, map_center, map_half, mr)
		var b := NewsMap.to_px(arr, map_center, map_half, mr)
		var n := 22
		for i2 in n:
			if i2 % 2 == 0:
				draw_line(a.lerp(b, float(i2) / n), a.lerp(b, float(i2 + 1) / n), Color(1, 1, 1, 0.75), maxf(sz.y * 0.004, 1.2))
	for pl in [[dep, dep_name], [arr, arr_name]]:
		if pl[0] == Vector2.INF:
			continue
		var p := NewsMap.to_px(pl[0], map_center, map_half, mr)
		if mr.has_point(p):
			draw_circle(p, sz.y * 0.012, Color.WHITE)
			draw_string(f_b, p + Vector2(sz.y * 0.02, -sz.y * 0.015), String(pl[1]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	if site != Vector2.INF:
		var s := NewsMap.to_px(site, map_center, map_half, mr)
		var pulse := fmod(t * 0.8, 1.0)
		draw_arc(s, sz.y * (0.02 + pulse * 0.07), 0, TAU, 32, Color(1, 0.2, 0.15, 1.0 - pulse), maxf(sz.y * 0.006, 1.5))
		draw_circle(s, sz.y * 0.018, Color(0.95, 0.12, 0.1))
		var k2 := sz.y * 0.012
		draw_line(s - Vector2(k2, k2), s + Vector2(k2, k2), Color.WHITE, maxf(sz.y * 0.005, 1.5))
		draw_line(s - Vector2(k2, -k2), s + Vector2(k2, -k2), Color.WHITE, maxf(sz.y * 0.005, 1.5))
	# headline block
	var tx := mr.end.x + sz.x * 0.04
	var tw := sz.x - tx - sz.x * 0.05
	var tag_fs := maxi(int(sz.y * 0.07), 12)
	var tag_w := f_b.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tag_fs).x + sz.y * 0.06
	draw_rect(Rect2(tx, sz.y * 0.16, tag_w, tag_fs * 1.45), prim)
	draw_string(f_b, Vector2(tx + sz.y * 0.03, sz.y * 0.16 + tag_fs * 1.12), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tag_fs, Color.WHITE)
	var hf := NewsStyle.head_font(outlet, 800)
	var hfs := maxi(int(sz.y * 0.085), 12)
	var y := sz.y * 0.16 + tag_fs * 1.45 + hfs * 1.3
	for ln in _wrap(title, hf, hfs, tw).slice(0, 3):
		draw_string(hf, Vector2(tx, y), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, hfs, Color.WHITE)
		y += hfs * 1.08
	draw_rect(Rect2(tx, y - hfs * 0.35, tw * 0.3, maxf(sz.y * 0.008, 2.0)), hi)
	var sfs := maxi(int(sz.y * 0.04), 10)
	y += sfs * 1.2
	for ln2 in _wrap(sub, f_r, sfs, tw).slice(0, 2):
		draw_string(f_r, Vector2(tx, y), ln2, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, Color(1, 1, 1, 0.85))
		y += sfs * 1.25
	# outlet signature
	var st := NewsStyle.get_style(outlet)
	draw_string(f_b, Vector2(tx, sz.y * 0.9), String(st.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, Color(prim.lightened(0.4), 0.9))


static func _wrap(text: String, f: Font, fs: int, width: float) -> Array:
	var out := []
	var cur := ""
	for w in text.split(" ", false):
		var tryl := w if cur == "" else cur + " " + w
		if f.get_string_size(tryl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width and cur != "":
			out.append(cur)
			cur = w
		else:
			cur = tryl
	if cur != "":
		out.append(cur)
	return out


## Top view of an airliner as a filled polygon (used by maps, trackers and thumbnails).
static func draw_plane(ci: CanvasItem, pos: Vector2, heading_rad: float, s: float, col: Color) -> void:
	var shape := [Vector2(0, -1.0), Vector2(0.09, -0.8), Vector2(0.1, -0.2), Vector2(0.95, 0.15), Vector2(0.95, 0.27), Vector2(0.1, 0.12),
		Vector2(0.08, 0.68), Vector2(0.38, 0.86), Vector2(0.38, 0.95), Vector2(0.0, 0.88), Vector2(-0.38, 0.95), Vector2(-0.38, 0.86),
		Vector2(-0.08, 0.68), Vector2(-0.1, 0.12), Vector2(-0.95, 0.27), Vector2(-0.95, 0.15), Vector2(-0.1, -0.2), Vector2(-0.09, -0.8)]
	var pts := PackedVector2Array()
	for p in shape:
		pts.append(pos + (p * s).rotated(heading_rad))
	ci.draw_colored_polygon(pts, col)
