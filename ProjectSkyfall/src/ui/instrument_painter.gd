class_name InstrumentPainter
extends RefCounted
## Draws glass-cockpit displays and analogue gauges onto any CanvasItem. Used by the 3D cockpit
## display atlas (SubViewport) and by the 2D HUD, so both always show identical information.

const GREEN := Color(0.25, 1.0, 0.35)
const CYAN := Color(0.25, 0.9, 1.0)
const MAGENTA := Color(1.0, 0.35, 1.0)
const AMBER := Color(1.0, 0.68, 0.1)
const RED := Color(1.0, 0.18, 0.15)
const WHITE := Color(0.95, 0.96, 0.97)
const GREY := Color(0.45, 0.47, 0.5)
const SKY := Color(0.12, 0.42, 0.85)
const GROUND := Color(0.48, 0.3, 0.14)
const BG := Color(0.02, 0.025, 0.03)

static var _font: Font
static var _mono: Font


static func font() -> Font:
	if _font == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Roboto Condensed", "Arial Narrow", "DejaVu Sans Condensed", "Helvetica", "sans-serif"])
		_font = sf
	return _font


static func mono() -> Font:
	if _mono == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["DejaVu Sans Mono", "Consolas", "Menlo", "Roboto Mono", "monospace"])
		_mono = sf
	return _mono


static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, w: float = -1.0, f: Font = null) -> void:
	var fo := f if f else font()
	var width := w
	var p := pos
	if align != HORIZONTAL_ALIGNMENT_LEFT and w <= 0.0:
		width = 400.0
		if align == HORIZONTAL_ALIGNMENT_CENTER:
			p.x -= width * 0.5
		else:
			p.x -= width
	ci.draw_string(fo, p + Vector2(0, size * 0.36), s, align, width, size, col)


static func _clip_line(ci: CanvasItem, a: Vector2, b: Vector2, clip: PackedVector2Array, col: Color, w: float) -> void:
	var parts := Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), clip)
	for p in parts:
		if p.size() >= 2:
			ci.draw_line(p[0], p[p.size() - 1], col, w, true)


static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


# =============================================================================== PFD
static func pfd(ci: CanvasItem, r: Rect2, ac: Aircraft, show_fma: bool = true) -> void:
	var n := ac.nav_state()
	var w := r.size.x
	var h := r.size.y
	var fs := int(clampf(h * 0.052, 9.0, 40.0))
	ci.draw_rect(r, BG)
	var att := Rect2(r.position + Vector2(w * 0.22, h * 0.14), Vector2(w * 0.56, h * 0.62))
	_attitude(ci, att, ac, n, fs)
	_speed_tape(ci, Rect2(r.position + Vector2(w * 0.02, h * 0.14), Vector2(w * 0.16, h * 0.62)), ac, n, fs)
	_alt_tape(ci, Rect2(r.position + Vector2(w * 0.81, h * 0.14), Vector2(w * 0.13, h * 0.62)), ac, n, fs)
	_vsi(ci, Rect2(r.position + Vector2(w * 0.945, h * 0.2), Vector2(w * 0.05, h * 0.5)), n, fs)
	_heading_tape(ci, Rect2(r.position + Vector2(w * 0.22, h * 0.83), Vector2(w * 0.56, h * 0.15)), ac, n, fs)
	if show_fma:
		_fma(ci, Rect2(r.position, Vector2(w, h * 0.12)), ac, fs)
	# airspeed source / baro readouts
	var baro := "STD" if n.alt > 5500.0 else "QNH %d" % int(round(float(ac.weather.get("qnh", 1013.0))))
	text(ci, r.position + Vector2(w * 0.875, h * 0.8), baro, int(fs * 0.85), CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	if n.mach > 0.4:
		text(ci, r.position + Vector2(w * 0.1, h * 0.8), ".%03d" % int(n.mach * 1000.0), int(fs * 0.9), GREEN, HORIZONTAL_ALIGNMENT_CENTER)
	# big warnings
	var warn := ""
	var wcol := RED
	if ac.sys.stall_warning:
		warn = "STALL"
	elif ac.get_meta("gpws", "") != "":
		warn = String(ac.get_meta("gpws", ""))
		wcol = RED if warn in ["PULL UP", "TERRAIN", "WINDSHEAR"] else AMBER
	elif ac.sys.overspeed:
		warn = "OVERSPEED"
	if warn != "":
		var blink := int(Time.get_ticks_msec() / 400) % 2 == 0
		if blink:
			text(ci, att.position + Vector2(att.size.x * 0.5, att.size.y * 0.7), warn, int(fs * 1.4), wcol, HORIZONTAL_ALIGNMENT_CENTER)


static func _attitude(ci: CanvasItem, att: Rect2, ac: Aircraft, n: Dictionary, fs: int) -> void:
	var c := att.get_center()
	var ppd := att.size.y / 36.0
	var bank := deg_to_rad(float(n.bank))
	var pitch := float(n.pitch)
	var clip := _rect_poly(att)
	# rotate a world-pitch coordinate into screen space
	var cs := cos(-bank)
	var sn := sin(-bank)
	var to_s := func(v: Vector2) -> Vector2:
		return c + Vector2(v.x * cs - v.y * sn, v.x * sn + v.y * cs)
	var hz := pitch * ppd
	var big := att.size.length() * 2.0
	var sky := PackedVector2Array([to_s.call(Vector2(-big, hz)), to_s.call(Vector2(big, hz)), to_s.call(Vector2(big, hz - big)), to_s.call(Vector2(-big, hz - big))])
	var gnd := PackedVector2Array([to_s.call(Vector2(-big, hz)), to_s.call(Vector2(big, hz)), to_s.call(Vector2(big, hz + big)), to_s.call(Vector2(-big, hz + big))])
	for poly in Geometry2D.intersect_polygons(clip, sky):
		ci.draw_colored_polygon(poly, SKY)
	for poly2 in Geometry2D.intersect_polygons(clip, gnd):
		ci.draw_colored_polygon(poly2, GROUND)
	_clip_line(ci, to_s.call(Vector2(-big, hz)), to_s.call(Vector2(big, hz)), clip, WHITE, 2.0)
	# pitch ladder
	var lw := att.size.x
	for k in range(-8, 9):
		if k == 0:
			continue
		var deg := k * 5.0
		var y := hz - deg * ppd
		var half := lw * (0.12 if k % 2 == 0 else 0.06)
		_clip_line(ci, to_s.call(Vector2(-half, y)), to_s.call(Vector2(half, y)), clip, WHITE, 1.5)
		if k % 2 == 0 and absf(deg - pitch) < 16.0:
			var lp: Vector2 = to_s.call(Vector2(-half - fs * 1.1, y))
			text(ci, lp, str(absi(int(deg))), int(fs * 0.75), WHITE, HORIZONTAL_ALIGNMENT_CENTER)
			lp = to_s.call(Vector2(half + fs * 1.1, y))
			text(ci, lp, str(absi(int(deg))), int(fs * 0.75), WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	for k2 in range(-6, 7):
		var y2 := hz - (k2 * 5.0 + 2.5) * ppd
		_clip_line(ci, to_s.call(Vector2(-lw * 0.035, y2)), to_s.call(Vector2(lw * 0.035, y2)), clip, WHITE, 1.0)
	# bank scale
	var rad := att.size.y * 0.42
	var top := Vector2(c.x, att.position.y + att.size.y * 0.06)
	var arc_c := Vector2(c.x, top.y + rad)
	ci.draw_arc(arc_c, rad, deg_to_rad(-150.0), deg_to_rad(-30.0), 32, WHITE, 1.5, true)
	for bdeg in [-60, -45, -30, -20, -10, 10, 20, 30, 45, 60]:
		var a := deg_to_rad(-90.0 + bdeg)
		var l := rad * (0.09 if absi(bdeg) in [30, 60] else 0.05)
		ci.draw_line(arc_c + Vector2(cos(a), sin(a)) * rad, arc_c + Vector2(cos(a), sin(a)) * (rad - l), WHITE, 1.5, true)
	ci.draw_colored_polygon(PackedVector2Array([top + Vector2(0, 0), top + Vector2(-fs * 0.35, -fs * 0.5), top + Vector2(fs * 0.35, -fs * 0.5)]), WHITE)
	var pa := deg_to_rad(-90.0) - bank
	var pt := arc_c + Vector2(cos(pa), sin(pa)) * rad
	var pcol := AMBER if absf(float(n.bank)) > 35.0 else WHITE
	var dirv := (arc_c - pt).normalized()
	var perp := Vector2(-dirv.y, dirv.x)
	ci.draw_colored_polygon(PackedVector2Array([pt, pt + dirv * fs * 0.6 + perp * fs * 0.35, pt + dirv * fs * 0.6 - perp * fs * 0.35]), pcol)
	# flight director
	if ac.ap.fd_on and (ac.ap.engaged or ac.get_meta("fd_active", false)):
		var fdp := (float(ac.ap.out_pitch) - pitch) * ppd
		var fdb := (float(ac.ap.out_bank) - float(n.bank)) * ppd * 0.6
		fdp = clampf(fdp, -att.size.y * 0.4, att.size.y * 0.4)
		fdb = clampf(fdb, -att.size.x * 0.4, att.size.x * 0.4)
		ci.draw_line(c + Vector2(-lw * 0.2, -fdp), c + Vector2(lw * 0.2, -fdp), GREEN, 2.0, true)
		ci.draw_line(c + Vector2(fdb, -att.size.y * 0.25), c + Vector2(fdb, att.size.y * 0.25), GREEN, 2.0, true)
	# aircraft symbol
	var yellow := Color(1.0, 0.85, 0.1)
	ci.draw_rect(Rect2(c - Vector2(lw * 0.3, 2), Vector2(lw * 0.12, 5)), Color.BLACK)
	ci.draw_rect(Rect2(c - Vector2(lw * 0.3, 2), Vector2(lw * 0.12, 5)), yellow, false, 2.0)
	ci.draw_rect(Rect2(c + Vector2(lw * 0.18, -2), Vector2(lw * 0.12, 5)), Color.BLACK)
	ci.draw_rect(Rect2(c + Vector2(lw * 0.18, -2), Vector2(lw * 0.12, 5)), yellow, false, 2.0)
	ci.draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), yellow)
	# ILS deviation scales
	if ac.ap.loc_valid or ac.ap.gs_valid:
		var gx := att.end.x + 4.0
		for k3 in [-2, -1, 1, 2]:
			ci.draw_circle(Vector2(gx + 4, c.y + k3 * att.size.y * 0.16), 2.5, WHITE)
			ci.draw_circle(Vector2(c.x + k3 * att.size.x * 0.16, att.end.y - 6), 2.5, WHITE)
		if ac.ap.gs_valid:
			var gy := clampf(float(ac.ap.gs_dev) / 0.7 * att.size.y * 0.32, -att.size.y * 0.36, att.size.y * 0.36)
			var d := Vector2(gx + 4, c.y + gy)
			ci.draw_colored_polygon(PackedVector2Array([d + Vector2(0, -7), d + Vector2(5, 0), d + Vector2(0, 7), d + Vector2(-5, 0)]), MAGENTA)
		if ac.ap.loc_valid:
			var lx := clampf(-float(ac.ap.loc_dev) / 2.5 * att.size.x * 0.32, -att.size.x * 0.36, att.size.x * 0.36)
			var d2 := Vector2(c.x + lx, att.end.y - 6)
			ci.draw_colored_polygon(PackedVector2Array([d2 + Vector2(-7, 0), d2 + Vector2(0, -5), d2 + Vector2(7, 0), d2 + Vector2(0, 5)]), MAGENTA)
	# radio altitude
	var ra_ft := float(ac.ra) / U.FT
	if ra_ft < 2500.0 and not ac.fdm.on_ground:
		var col := AMBER if ra_ft < 200.0 else GREEN
		text(ci, Vector2(c.x, att.end.y - att.size.y * 0.13), str(int(ra_ft / 10.0) * 10 if ra_ft > 50.0 else int(ra_ft)), int(fs * 1.1), col, HORIZONTAL_ALIGNMENT_CENTER)


static func _speed_tape(ci: CanvasItem, r: Rect2, ac: Aircraft, n: Dictionary, fs: int) -> void:
	ci.draw_rect(r, Color(0.18, 0.2, 0.22))
	var ias: float = n.ias_kt
	var c := r.get_center()
	var ppk := r.size.y / 80.0      # pixels per knot
	var spec := ac.spec
	# overspeed / stall bands
	var vmo := float(spec.vmo)
	var mmo := float(spec.mmo)
	if mmo > 0.0 and n.mach > 0.3:
		vmo = minf(vmo, ias * mmo / maxf(float(n.mach), 0.01))
	var vs := AircraftTypes.stall_speed_kt(spec, ac.total_mass(), ac.sys.flap_lever)
	for band in [[vmo, vmo + 200.0, RED], [-50.0, vs, RED], [vs, vs * 1.1, AMBER]]:
		var y0 := c.y - (float(band[1]) - ias) * ppk
		var y1 := c.y - (float(band[0]) - ias) * ppk
		y0 = clampf(y0, r.position.y, r.end.y)
		y1 = clampf(y1, r.position.y, r.end.y)
		if y1 > y0:
			ci.draw_rect(Rect2(Vector2(r.end.x - 6, y0), Vector2(6, y1 - y0)), band[2])
	var base := int(ias / 10.0) * 10
	for k in range(-5, 6):
		var v := base + k * 10
		if v < 0:
			continue
		var y := c.y - (v - ias) * ppk
		if y < r.position.y + 4 or y > r.end.y - 4:
			continue
		ci.draw_line(Vector2(r.end.x - 12, y), Vector2(r.end.x - 1, y), WHITE, 1.5)
		if v % 20 == 0:
			text(ci, Vector2(r.end.x - 15, y), str(v), int(fs * 0.85), WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	# speed bugs
	var sel := float(ac.ap.spd_sel)
	if ac.ap.use_mach and n.mach > 0.1:
		sel = float(ac.ap.mach_sel) / maxf(float(n.mach), 0.01) * ias
	var sy := clampf(c.y - (sel - ias) * ppk, r.position.y, r.end.y)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(r.end.x, sy), Vector2(r.end.x + 8, sy - 6), Vector2(r.end.x + 8, sy + 6)]), MAGENTA)
	if ac.fdm.on_ground or float(ac.ra) < 300.0:
		for vb in [["1", float(spec.v1 if spec.has("v1") else spec.vr) - 3.0], ["R", float(spec.vr)], ["2", float(spec.v2)], ["REF", float(spec.vref)]]:
			var vy := c.y - (float(vb[1]) - ias) * ppk
			if vy > r.position.y and vy < r.end.y:
				text(ci, Vector2(r.end.x + 2, vy), String(vb[0]), int(fs * 0.6), CYAN)
	# trend vector (10 s)
	var acc := float(ac.get_meta("ias_trend", 0.0))
	if absf(acc) > 0.3:
		var ty := c.y - acc * 10.0 * ppk
		ci.draw_line(Vector2(r.end.x - 4, c.y), Vector2(r.end.x - 4, ty), GREEN, 2.0)
	# readout box
	var bh := fs * 1.5
	var box := Rect2(Vector2(r.position.x, c.y - bh * 0.5), Vector2(r.size.x - 6, bh))
	ci.draw_rect(box, Color.BLACK)
	ci.draw_rect(box, WHITE, false, 1.5)
	text(ci, Vector2(box.end.x - 4, c.y), str(int(round(ias))), int(fs * 1.15), WHITE, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, mono())
	text(ci, Vector2(r.get_center().x, r.position.y - fs * 0.7), str(int(sel)) if not ac.ap.use_mach else ".%02d" % int(ac.ap.mach_sel * 100.0), int(fs * 0.9), MAGENTA, HORIZONTAL_ALIGNMENT_CENTER)


static func _alt_tape(ci: CanvasItem, r: Rect2, ac: Aircraft, n: Dictionary, fs: int) -> void:
	ci.draw_rect(r, Color(0.18, 0.2, 0.22))
	var alt_ft := float(n.alt) / U.FT
	var c := r.get_center()
	var ppf := r.size.y / 900.0
	var base := int(alt_ft / 100.0) * 100
	for k in range(-6, 7):
		var a := base + k * 100
		var y := c.y - (a - alt_ft) * ppf
		if y < r.position.y + 4 or y > r.end.y - 4:
			continue
		ci.draw_line(Vector2(r.position.x, y), Vector2(r.position.x + (12 if a % 500 == 0 else 6), y), WHITE, 1.5)
		if a % 200 == 0:
			text(ci, Vector2(r.position.x + 14, y), str(a), int(fs * 0.75), WHITE)
	# ground reference
	var gy := c.y - (float(ac.ground_elev) / U.FT - alt_ft) * ppf
	if gy < r.end.y:
		ci.draw_rect(Rect2(Vector2(r.position.x, maxf(gy, r.position.y)), Vector2(r.size.x, r.end.y - maxf(gy, r.position.y))), Color(0.5, 0.3, 0.1, 0.6))
	var sel_ft := float(ac.ap.alt_sel) / U.FT
	var sy := clampf(c.y - (sel_ft - alt_ft) * ppf, r.position.y, r.end.y)
	ci.draw_rect(Rect2(Vector2(r.position.x - 3, sy - 6), Vector2(8, 12)), MAGENTA, false, 2.0)
	text(ci, Vector2(r.get_center().x, r.position.y - fs * 0.7), str(int(round(sel_ft / 100.0)) * 100), int(fs * 0.9), CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	var bh := fs * 1.5
	var box := Rect2(Vector2(r.position.x, c.y - bh * 0.5), Vector2(r.size.x, bh))
	ci.draw_rect(box, Color.BLACK)
	ci.draw_rect(box, WHITE, false, 1.5)
	text(ci, Vector2(box.end.x - 3, c.y), str(int(round(alt_ft / 10.0)) * 10), int(fs * 1.0), WHITE, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, mono())


static func _vsi(ci: CanvasItem, r: Rect2, n: Dictionary, fs: int) -> void:
	ci.draw_rect(r, Color(0.12, 0.13, 0.15))
	var c := r.get_center()
	var vs_fpm := float(n.vs) / U.FPM
	var f := signf(vs_fpm) * sqrt(minf(absf(vs_fpm), 6000.0) / 6000.0)
	var y := c.y - f * r.size.y * 0.48
	for mark in [-6000, -2000, -1000, 0, 1000, 2000, 6000]:
		var fm := signf(mark) * sqrt(absf(mark) / 6000.0)
		var my := c.y - fm * r.size.y * 0.48
		ci.draw_line(Vector2(r.position.x, my), Vector2(r.position.x + 5, my), GREY, 1.0)
	var col := AMBER if absf(vs_fpm) > 6000.0 else GREEN
	ci.draw_line(Vector2(r.end.x + 6, c.y), Vector2(r.position.x + 2, y), col, 2.5, true)
	if absf(vs_fpm) > 400.0:
		text(ci, Vector2(c.x, y + (-fs if vs_fpm > 0 else fs) * 0.8), str(int(absf(vs_fpm) / 100.0)), int(fs * 0.7), col, HORIZONTAL_ALIGNMENT_CENTER)


static func _heading_tape(ci: CanvasItem, r: Rect2, ac: Aircraft, n: Dictionary, fs: int) -> void:
	ci.draw_rect(r, Color(0.18, 0.2, 0.22))
	var hdg := float(n.hdg)
	var c := r.get_center()
	var ppd := r.size.x / 60.0
	var base := int(hdg / 5.0) * 5
	for k in range(-7, 8):
		var d := base + k * 5
		var x := c.x + U.angle_diff_deg(float(d), hdg) * ppd
		if x < r.position.x + 3 or x > r.end.x - 3:
			continue
		var dd := posmod(d, 360)
		ci.draw_line(Vector2(x, r.position.y), Vector2(x, r.position.y + (10 if dd % 10 == 0 else 5)), WHITE, 1.5)
		if dd % 10 == 0:
			text(ci, Vector2(x, r.position.y + fs * 1.2), str(dd / 10), int(fs * 0.8), WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var sx := clampf(c.x + U.angle_diff_deg(float(ac.ap.hdg_sel), hdg) * ppd, r.position.x, r.end.x)
	ci.draw_rect(Rect2(Vector2(sx - 5, r.position.y), Vector2(10, 6)), CYAN, false, 2.0)
	var tx := clampf(c.x + U.angle_diff_deg(float(n.track), hdg) * ppd, r.position.x, r.end.x)
	ci.draw_circle(Vector2(tx, r.position.y + 14), 3.0, GREEN)
	ci.draw_line(Vector2(c.x, r.position.y - 6), Vector2(c.x, r.position.y + 12), Color(1, 0.85, 0.1), 2.5)
	text(ci, Vector2(c.x, r.end.y - fs * 0.45), "%03d" % int(posmod(int(round(hdg)), 360)), int(fs * 0.9), WHITE, HORIZONTAL_ALIGNMENT_CENTER, -1.0, mono())


static func _fma(ci: CanvasItem, r: Rect2, ac: Aircraft, fs: int) -> void:
	ci.draw_rect(r, Color.BLACK)
	var ap := ac.ap
	var cols := 5
	var cw := r.size.x / cols
	for i in range(1, cols):
		ci.draw_line(r.position + Vector2(cw * i, 2), r.position + Vector2(cw * i, r.size.y - 2), GREY, 1.0)
	var thr := ap.thr_mode if ap.at_engaged else ""
	var lat := ap.lat_mode if (ap.engaged or ap.fd_on) else ""
	var ver := ap.vert_mode if (ap.engaged or ap.fd_on) else ""
	if ver == "FLCH":
		ver = "OP CLB" if ap.alt_sel > float(ac.nav_state().alt) else "OP DES"
	var y := r.position.y + r.size.y * 0.35
	var fsz := int(fs * 0.85)
	text(ci, Vector2(r.position.x + cw * 0.5, y), thr, fsz, GREEN, HORIZONTAL_ALIGNMENT_CENTER)
	text(ci, Vector2(r.position.x + cw * 1.5, y), ver, fsz, GREEN, HORIZONTAL_ALIGNMENT_CENTER)
	text(ci, Vector2(r.position.x + cw * 2.5, y), lat, fsz, GREEN, HORIZONTAL_ALIGNMENT_CENTER)
	var armed_v := "G/S" if ap.arm_gs and ap.vert_mode != "GS" else ("ALT" if ap.vert_mode in ["VS", "FLCH"] else "")
	var armed_l := "LOC" if ap.arm_loc and ap.lat_mode != "LOC" else ""
	text(ci, Vector2(r.position.x + cw * 1.5, y + fs * 0.95), armed_v, int(fs * 0.75), CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	text(ci, Vector2(r.position.x + cw * 2.5, y + fs * 0.95), armed_l, int(fs * 0.75), CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	var cat := "CAT 3\nDUAL" if ap.vert_mode in ["GS", "FLARE"] and bool(ac.spec.autoland) else ""
	text(ci, Vector2(r.position.x + cw * 3.5, y), cat.split("\n")[0] if cat != "" else "", fsz, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var apt := "AP1" if ap.engaged else ""
	text(ci, Vector2(r.position.x + cw * 4.5, y), apt, fsz, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	text(ci, Vector2(r.position.x + cw * 4.5, y + fs * 0.95), "A/THR" if ap.at_engaged else "", int(fs * 0.75), WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	if ac.sys.master_warning:
		ci.draw_rect(Rect2(r.position + Vector2(cw * 3.0, 2), Vector2(cw - 4, r.size.y - 4)), Color(0.6, 0.0, 0.0, 0.0 if int(Time.get_ticks_msec() / 350) % 2 else 0.8))


# =============================================================================== ND
static func nd(ci: CanvasItem, r: Rect2, ac: Aircraft, range_nm: float = 40.0, traffic: Array = [], show_wx: bool = true) -> void:
	var n := ac.nav_state()
	ci.draw_rect(r, BG)
	var w := r.size.x
	var h := r.size.y
	var fs := int(clampf(h * 0.048, 8.0, 34.0))
	var c := r.position + Vector2(w * 0.5, h * 0.82)
	var rad := h * 0.7
	var hdg := float(n.hdg)
	var px_per_m := rad / (range_nm * U.NM)
	var clip_poly := _rect_poly(Rect2(r.position + Vector2(2, h * 0.08), r.size - Vector2(4, h * 0.08)))
	var to_s := func(wx: float, wz: float) -> Vector2:
		var dx := wx - float(n.x)
		var dz := wz - float(n.z)
		var brg := atan2(dx, -dz) - deg_to_rad(hdg)
		var dist := sqrt(dx * dx + dz * dz) * px_per_m
		return c + Vector2(sin(brg), -cos(brg)) * dist
	# weather radar returns
	if show_wx and ac.world:
		for cell in ac.world.storm_cells:
			var p: Vector2 = to_s.call(float(cell.x), float(cell.z))
			var rr: float = float(cell.r) * px_per_m
			if p.distance_to(c) - rr > rad * 1.1:
				continue
			ci.draw_circle(p, rr, Color(0.1, 0.7, 0.2, 0.55))
			ci.draw_circle(p, rr * 0.62, Color(0.95, 0.85, 0.1, 0.65))
			ci.draw_circle(p, rr * 0.3, Color(0.95, 0.1, 0.1, 0.75))
	# compass arc
	ci.draw_arc(c, rad, deg_to_rad(-90 - 50), deg_to_rad(-90 + 50), 48, WHITE, 1.5, true)
	ci.draw_arc(c, rad * 0.5, deg_to_rad(-90 - 50), deg_to_rad(-90 + 50), 32, GREY, 1.0, true)
	text(ci, c + Vector2(-rad * 0.5 * 0.8, -rad * 0.5 * 0.55), str(int(range_nm / 2.0)), int(fs * 0.7), GREY, HORIZONTAL_ALIGNMENT_CENTER)
	for d in range(0, 360, 5):
		var rel := U.angle_diff_deg(float(d), hdg)
		if absf(rel) > 52.0:
			continue
		var a := deg_to_rad(-90.0 + rel)
		var dirv := Vector2(cos(a), sin(a))
		var l := 12.0 if d % 10 == 0 else 6.0
		ci.draw_line(c + dirv * rad, c + dirv * (rad - l), WHITE, 1.5, true)
		if d % 30 == 0:
			text(ci, c + dirv * (rad - l - fs * 0.9), str(d / 10), int(fs * 0.85), WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	# selected heading bug
	var hs := deg_to_rad(-90.0 + U.angle_diff_deg(float(ac.ap.hdg_sel), hdg))
	ci.draw_circle(c + Vector2(cos(hs), sin(hs)) * rad, 4.0, CYAN)
	# airports and runways
	for icao in Airports.ORDER:
		var ap: Dictionary = Airports.get_ap(icao)
		var p2: Vector2 = to_s.call(float(ap.x), float(ap.z))
		if p2.distance_to(c) > rad * 1.05 or p2.y > c.y + 10:
			continue
		ci.draw_arc(p2, 6.0, 0, TAU, 12, CYAN, 1.5, true)
		text(ci, p2 + Vector2(8, -2), icao, int(fs * 0.75), CYAN)
		if range_nm <= 40.0:
			for e in Airports.runway_ends(icao):
				var a1: Vector2 = to_s.call(float(e.thr_x), float(e.thr_z))
				var dv := Vector2(sin(deg_to_rad(e.hdg)), -cos(deg_to_rad(e.hdg)))
				var a2: Vector2 = to_s.call(float(e.thr_x) + dv.x * float(e.len), float(e.thr_z) + dv.y * float(e.len))
				ci.draw_line(a1, a2, WHITE, 2.0, true)
	# route
	var plan: Array = ac.ap.plan
	if plan.size() > 1:
		var prev := Vector2.INF
		for i in plan.size():
			var wp: Dictionary = plan[i]
			var p3: Vector2 = to_s.call(float(wp.x), float(wp.z))
			if prev != Vector2.INF and i >= ac.ap.leg:
				_clip_line(ci, prev, p3, clip_poly, MAGENTA if i == ac.ap.leg else WHITE, 2.0)
			prev = p3
			if i >= ac.ap.leg and p3.distance_to(c) < rad * 1.1:
				var wc := MAGENTA if i == ac.ap.leg else WHITE
				ci.draw_colored_polygon(PackedVector2Array([p3 + Vector2(0, -6), p3 + Vector2(6, 0), p3 + Vector2(0, 6), p3 + Vector2(-6, 0)]), wc)
				text(ci, p3 + Vector2(9, 0), String(wp.name), int(fs * 0.75), wc)
	# traffic
	for tr in traffic:
		var p4: Vector2 = to_s.call(float(tr.x), float(tr.z))
		if p4.distance_to(c) > rad:
			continue
		var dalt := (float(tr.alt) - float(n.alt)) / U.FT / 100.0
		var lvl := int(tr.get("level", 0))
		var tc := WHITE if lvl == 0 else (AMBER if lvl == 1 else RED)
		if lvl == 2:
			ci.draw_rect(Rect2(p4 - Vector2(5, 5), Vector2(10, 10)), tc)
		elif lvl == 1:
			ci.draw_circle(p4, 5.0, tc)
		else:
			ci.draw_colored_polygon(PackedVector2Array([p4 + Vector2(0, -6), p4 + Vector2(6, 0), p4 + Vector2(0, 6), p4 + Vector2(-6, 0)]), tc if absf(dalt) < 12 else GREY)
		text(ci, p4 + Vector2(0, (-12 if dalt > 0 else 14)), "%s%02d" % ["+" if dalt > 0 else "-", absi(int(dalt))], int(fs * 0.65), tc, HORIZONTAL_ALIGNMENT_CENTER)
	# ownship
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -14), c + Vector2(9, 8), c + Vector2(0, 3), c + Vector2(-9, 8)]), Color(1, 0.85, 0.1))
	# header data
	var gs_kt := float(n.gs) / U.KT
	text(ci, r.position + Vector2(6, fs), "GS %d  TAS %d" % [int(gs_kt), int(float(n.tas) / U.KT)], int(fs * 0.85), WHITE)
	var wv := Vector2(ac.wind.x, ac.wind.z)
	if wv.length() > 0.5:
		var wfrom := posmod(int(round(rad_to_deg(atan2(-wv.x, wv.y)))), 360)
		text(ci, r.position + Vector2(6, fs * 2.1), "%03d/%d" % [wfrom, int(wv.length() / U.KT)], int(fs * 0.85), WHITE)
		var wa := deg_to_rad(float(wfrom) + 180.0 - hdg)
		var wc2 := r.position + Vector2(fs * 1.4, fs * 3.8)
		var wdir := Vector2(sin(wa), -cos(wa))
		ci.draw_line(wc2 - wdir * fs, wc2 + wdir * fs, WHITE, 2.0, true)
		ci.draw_line(wc2 + wdir * fs, wc2 + wdir * fs * 0.4 + Vector2(-wdir.y, wdir.x) * fs * 0.4, WHITE, 2.0, true)
	if plan.size() > ac.ap.leg:
		var nw: Dictionary = plan[ac.ap.leg]
		var dist_nm := U.dist2d(float(n.x), float(n.z), float(nw.x), float(nw.z)) / U.NM
		text(ci, r.position + Vector2(w - 6, fs), String(nw.name), int(fs * 0.9), MAGENTA, HORIZONTAL_ALIGNMENT_RIGHT)
		text(ci, r.position + Vector2(w - 6, fs * 2.1), "%.1f NM" % dist_nm, int(fs * 0.85), WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	text(ci, r.position + Vector2(w * 0.5, fs * 0.9), "%03d" % int(posmod(int(round(hdg)), 360)), int(fs * 1.0), WHITE, HORIZONTAL_ALIGNMENT_CENTER, -1.0, mono())
	text(ci, r.position + Vector2(w - 6, h - fs), "%d NM" % int(range_nm), int(fs * 0.75), CYAN, HORIZONTAL_ALIGNMENT_RIGHT)


# =============================================================================== EICAS / ECAM upper
static func eicas(ci: CanvasItem, r: Rect2, ac: Aircraft) -> void:
	ci.draw_rect(r, BG)
	var sys := ac.sys
	var w := r.size.x
	var h := r.size.y
	var fs := int(clampf(h * 0.05, 8.0, 32.0))
	var ne := sys.n_eng
	var gauge_w := w * 0.55 / maxi(ne, 1)
	var rad := minf(gauge_w * 0.36, h * 0.11)
	var et := sys.etype
	var prim := "N1" if et == "turbofan" else ("TQ" if et == "turboprop" else "RPM")
	var sec := "EGT" if et != "turboprop" else "ITT"
	text(ci, r.position + Vector2(w * 0.04, h * 0.1), prim, int(fs * 0.8), CYAN)
	text(ci, r.position + Vector2(w * 0.04, h * 0.33), sec, int(fs * 0.8), CYAN)
	for i in ne:
		var e: Dictionary = sys.eng[i]
		var cx := r.position.x + w * 0.08 + gauge_w * (i + 0.5)
		var pval := float(e.n1)
		var pmax := 110.0
		var ptxt := "%.1f" % pval
		if et == "turboprop":
			pval = float(e.get("torque", e.n1))
			ptxt = "%.0f" % pval
		elif et == "piston":
			pval = float(e.get("rpm", e.n1 * 27.0))
			pmax = 2900.0
			ptxt = "%d" % int(pval)
		var pcol := RED if e.fire else (AMBER if e.failed != "" else WHITE)
		_dial(ci, Vector2(cx, r.position.y + h * 0.13), rad, pval / pmax, 0.92, ptxt, pcol, fs)
		# thrust lever position marker
		var tl := float(sys.throttle[i])
		var ta := deg_to_rad(180.0 + 210.0 * clampf(tl * 0.95, 0.0, 1.0))
		ci.draw_circle(Vector2(cx, r.position.y + h * 0.13) + Vector2(cos(ta), sin(ta)) * rad * 1.1, 2.5, CYAN)
		var egt := float(e.egt)
		_dial(ci, Vector2(cx, r.position.y + h * 0.36), rad * 0.85, egt / 1000.0, 0.9, "%d" % int(egt), RED if egt > 950.0 else WHITE, fs)
		var ff_kgh := float(e.ff) * 3600.0
		text(ci, Vector2(cx, r.position.y + h * 0.52), "%d" % int(ff_kgh), int(fs * 0.85), GREEN if e.running else GREY, HORIZONTAL_ALIGNMENT_CENTER)
		if e.fire:
			text(ci, Vector2(cx, r.position.y + h * 0.58), "FIRE", fs, RED, HORIZONTAL_ALIGNMENT_CENTER)
		elif e.starting:
			text(ci, Vector2(cx, r.position.y + h * 0.58), "START", int(fs * 0.8), CYAN, HORIZONTAL_ALIGNMENT_CENTER)
		elif e.rev > 0.1:
			text(ci, Vector2(cx, r.position.y + h * 0.58), "REV", int(fs * 0.8), GREEN if e.rev > 0.9 else AMBER, HORIZONTAL_ALIGNMENT_CENTER)
		elif not e.running:
			text(ci, Vector2(cx, r.position.y + h * 0.58), "OFF" if e.cutoff else "FAIL", int(fs * 0.8), AMBER, HORIZONTAL_ALIGNMENT_CENTER)
	text(ci, r.position + Vector2(w * 0.04, h * 0.52), "FF", int(fs * 0.8), CYAN)
	# fuel, flaps, gear
	var x2 := r.position.x + w * 0.66
	text(ci, Vector2(x2, r.position.y + h * 0.07), "FOB", int(fs * 0.8), CYAN)
	text(ci, Vector2(x2 + w * 0.12, r.position.y + h * 0.07), "%d KG" % int(sys.fuel_total()), int(fs * 0.9), GREEN)
	var fl := ac.flap_label()
	text(ci, Vector2(x2, r.position.y + h * 0.17), "FLAP", int(fs * 0.8), CYAN)
	var nf: int = ac.spec.flaps.size()
	var bar := Rect2(Vector2(x2 + w * 0.12, r.position.y + h * 0.15), Vector2(w * 0.18, h * 0.035))
	ci.draw_rect(bar, GREY, false, 1.0)
	ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(sys.flap_pos / maxf(nf - 1, 1), 0.0, 1.0), bar.size.y)), GREEN if not sys.flaps_jammed else AMBER)
	text(ci, Vector2(x2 + w * 0.32, r.position.y + h * 0.17), fl, int(fs * 0.9), GREEN)
	if bool(ac.spec.gear_retract):
		for g in 3:
			var gx := x2 + w * (0.05 + g * 0.09)
			var gy := r.position.y + h * 0.26
			var gp: float = sys.gear_pos[g]
			var gr := Rect2(Vector2(gx, gy), Vector2(w * 0.07, h * 0.05))
			if gp > 0.99:
				ci.draw_rect(gr, Color(0.0, 0.45, 0.1))
				text(ci, gr.get_center() - Vector2(0, 1), "DN", int(fs * 0.7), GREEN, HORIZONTAL_ALIGNMENT_CENTER)
			elif gp > 0.01:
				ci.draw_rect(gr, Color(0.45, 0.0, 0.0))
				text(ci, gr.get_center(), "TRN", int(fs * 0.6), RED, HORIZONTAL_ALIGNMENT_CENTER)
			else:
				ci.draw_rect(gr, GREY, false, 1.0)
				text(ci, gr.get_center(), "UP", int(fs * 0.6), GREY, HORIZONTAL_ALIGNMENT_CENTER)
	if sys.spoilers > 0.05:
		text(ci, Vector2(x2, r.position.y + h * 0.35), "SPD BRK", int(fs * 0.85), GREEN if ac.fdm.on_ground else AMBER)
	text(ci, Vector2(x2, r.position.y + h * 0.42), "TRIM %+.1f" % (sys.trim * 10.0), int(fs * 0.75), WHITE)
	text(ci, Vector2(x2, r.position.y + h * 0.48), "CAB ALT %d" % int(sys.cabin_alt / U.FT), int(fs * 0.75), AMBER if sys.cabin_alt > 3048.0 else WHITE)
	# alert list
	ci.draw_line(r.position + Vector2(w * 0.03, h * 0.64), r.position + Vector2(w * 0.97, h * 0.64), GREY, 1.0)
	var y := r.position.y + h * 0.69
	var msgs := sys.messages.duplicate()
	msgs.sort_custom(func(a, b): return int(a.level) > int(b.level))
	var shown := 0
	for m in msgs:
		if shown >= 6:
			break
		var col := RED if int(m.level) == 2 else (AMBER if int(m.level) == 1 else GREEN)
		text(ci, Vector2(r.position.x + w * 0.05, y), String(m.text), int(fs * 0.85), col)
		y += fs * 1.15
		shown += 1
	# memos
	var memo := []
	if sys.lights.get("seatbelt", false):
		memo.append("SEAT BELTS")
	if sys.parking_brake:
		memo.append("PARK BRK")
	if sys.ground_spoilers_armed and not ac.fdm.on_ground:
		memo.append("GND SPLRS ARMED")
	if sys.autobrake > 0:
		memo.append("AUTO BRK " + ["", "LO", "MED", "MAX", "RTO"][sys.autobrake])
	if sys.apu_on:
		memo.append("APU AVAIL" if sys.apu_n > 95.0 else "APU START")
	var my := r.position.y + h * 0.69
	for mm in memo:
		text(ci, Vector2(r.position.x + w * 0.62, my), mm, int(fs * 0.8), GREEN)
		my += fs * 1.1


static func _dial(ci: CanvasItem, c: Vector2, rad: float, frac: float, red_frac: float, txt: String, col: Color, fs: int) -> void:
	var a0 := deg_to_rad(180.0)
	var sweep := deg_to_rad(210.0)
	ci.draw_arc(c, rad, a0, a0 + sweep * red_frac, 32, WHITE, 1.5, true)
	ci.draw_arc(c, rad, a0 + sweep * red_frac, a0 + sweep, 8, RED, 2.5, true)
	var f := clampf(frac, 0.0, 1.05)
	var pts := PackedVector2Array([c])
	var steps := 16
	for i in steps + 1:
		var a := a0 + sweep * f * float(i) / steps
		pts.append(c + Vector2(cos(a), sin(a)) * rad * 0.95)
	if f > 0.01:
		ci.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.18))
	var na := a0 + sweep * f
	ci.draw_line(c, c + Vector2(cos(na), sin(na)) * rad, col, 2.5, true)
	var box := Rect2(c + Vector2(rad * 0.05, -rad * 0.05 - fs * 0.9), Vector2(rad * 1.05, fs * 1.1))
	ci.draw_rect(box, GREY, false, 1.0)
	text(ci, Vector2(box.end.x - 2, box.get_center().y), txt, int(fs * 0.9), col, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, mono())


# =============================================================================== lower ECAM / system display
static func sd(ci: CanvasItem, r: Rect2, ac: Aircraft, page: String) -> void:
	ci.draw_rect(r, BG)
	var sys := ac.sys
	var w := r.size.x
	var h := r.size.y
	var fs := int(clampf(h * 0.05, 8.0, 30.0))
	text(ci, r.position + Vector2(w * 0.5, fs), page, fs, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	ci.draw_line(r.position + Vector2(w * 0.35, fs * 1.8), r.position + Vector2(w * 0.65, fs * 1.8), WHITE, 1.0)
	match page:
		"FUEL":
			var names := ["LEFT", "CTR", "RIGHT"]
			for i in 3:
				var cap: float = sys.fuel_cap[i]
				if cap <= 0.0:
					continue
				var tr := Rect2(r.position + Vector2(w * (0.06 + i * 0.32), h * 0.3), Vector2(w * 0.25, h * 0.36))
				ci.draw_rect(tr, GREY, false, 1.5)
				var f := clampf(float(sys.fuel[i]) / cap, 0.0, 1.0)
				ci.draw_rect(Rect2(Vector2(tr.position.x, tr.end.y - tr.size.y * f), Vector2(tr.size.x, tr.size.y * f)), Color(0.1, 0.5, 0.2, 0.7))
				text(ci, Vector2(tr.get_center().x, tr.position.y - fs * 0.6), names[i], int(fs * 0.8), WHITE, HORIZONTAL_ALIGNMENT_CENTER)
				text(ci, Vector2(tr.get_center().x, tr.get_center().y), "%d" % int(sys.fuel[i]), fs, GREEN, HORIZONTAL_ALIGNMENT_CENTER)
			text(ci, r.position + Vector2(w * 0.5, h * 0.8), "XFEED " + ("OPEN" if sys.crossfeed else "SHUT"), fs, GREEN if not sys.crossfeed else AMBER, HORIZONTAL_ALIGNMENT_CENTER)
			text(ci, r.position + Vector2(w * 0.5, h * 0.9), "USED %d KG   FOB %d KG" % [int(sys.fuel_used), int(sys.fuel_total())], int(fs * 0.85), WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		"HYD":
			var hn := ["GREEN", "YELLOW"] if ac.spec.fbw else ["SYS A", "SYS B"]
			for i2 in 2:
				var x := r.position.x + w * (0.3 + i2 * 0.4)
				var pr: float = sys.hyd[i2]
				var col := GREEN if pr > 2500.0 else (AMBER if pr > 1200.0 else RED)
				text(ci, Vector2(x, r.position.y + h * 0.3), hn[i2], fs, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
				text(ci, Vector2(x, r.position.y + h * 0.45), "%d PSI" % int(pr), int(fs * 1.1), col, HORIZONTAL_ALIGNMENT_CENTER)
				ci.draw_rect(Rect2(Vector2(x - w * 0.06, r.position.y + h * 0.55), Vector2(w * 0.12, h * 0.25)), GREY, false, 1.0)
				var q: float = sys.hyd_qty[i2]
				ci.draw_rect(Rect2(Vector2(x - w * 0.06, r.position.y + h * (0.55 + 0.25 * (1.0 - q))), Vector2(w * 0.12, h * 0.25 * q)), Color(col.r, col.g, col.b, 0.4))
		"ELEC":
			text(ci, r.position + Vector2(w * 0.5, h * 0.25), "BAT %d%%" % int(sys.battery_charge * 100.0), fs, GREEN if sys.battery else AMBER, HORIZONTAL_ALIGNMENT_CENTER)
			text(ci, r.position + Vector2(w * 0.5, h * 0.37), "AC BUS " + ("NORM" if sys.ac_power else "OFF"), fs, GREEN if sys.ac_power else RED, HORIZONTAL_ALIGNMENT_CENTER)
			text(ci, r.position + Vector2(w * 0.5, h * 0.49), "DC BUS " + ("NORM" if sys.dc_power else "OFF"), fs, GREEN if sys.dc_power else RED, HORIZONTAL_ALIGNMENT_CENTER)
			for i3 in sys.n_eng:
				var x3 := r.position.x + w * (0.15 + 0.7 * float(i3) / maxf(sys.n_eng - 1, 1))
				var ok: bool = sys.eng[i3].running and not sys.gen_fail[i3]
				text(ci, Vector2(x3, r.position.y + h * 0.66), "GEN %d" % (i3 + 1), int(fs * 0.85), WHITE, HORIZONTAL_ALIGNMENT_CENTER)
				text(ci, Vector2(x3, r.position.y + h * 0.75), "115V" if ok else "OFF", int(fs * 0.85), GREEN if ok else AMBER, HORIZONTAL_ALIGNMENT_CENTER)
			text(ci, r.position + Vector2(w * 0.5, h * 0.88), "APU GEN " + ("ON" if sys.apu_n > 95.0 else "OFF") + ("   RAT" if sys.rat else "") + ("   EXT PWR" if sys.ext_power else ""), int(fs * 0.85), WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		"PRESS":
			text(ci, r.position + Vector2(w * 0.5, h * 0.3), "CAB ALT %d FT" % int(sys.cabin_alt / U.FT), int(fs * 1.1), AMBER if sys.cabin_alt > 3048.0 else GREEN, HORIZONTAL_ALIGNMENT_CENTER)
			text(ci, r.position + Vector2(w * 0.5, h * 0.45), "CAB V/S %d FPM" % int(sys.cabin_rate / U.FPM), fs, GREEN, HORIZONTAL_ALIGNMENT_CENTER)
			text(ci, r.position + Vector2(w * 0.5, h * 0.6), "PACK 1 %s   PACK 2 %s" % ["ON" if sys.packs[0] else "OFF", "ON" if sys.packs[1] else "OFF"], fs, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
			text(ci, r.position + Vector2(w * 0.5, h * 0.75), "CAB TEMP %d C" % int(sys.cabin_temp), fs, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
			if sys.masks_deployed:
				text(ci, r.position + Vector2(w * 0.5, h * 0.88), "PAX OXY MASKS DEPLOYED", fs, AMBER, HORIZONTAL_ALIGNMENT_CENTER)
		"DOOR":
			var doors: Dictionary = ac.get_meta("door_state", {})
			var y := r.position.y + h * 0.26
			if doors.is_empty():
				text(ci, Vector2(r.position.x + w * 0.5, y), "ALL DOORS CLOSED", fs, GREEN, HORIZONTAL_ALIGNMENT_CENTER)
			for dn in doors.keys():
				var open: bool = doors[dn]
				text(ci, Vector2(r.position.x + w * 0.5, y), "%s  %s" % [dn, "OPEN" if open else "CLOSED"], int(fs * 0.9), AMBER if open else GREEN, HORIZONTAL_ALIGNMENT_CENTER)
				y += fs * 1.2
		"WHEEL":
			text(ci, r.position + Vector2(w * 0.5, h * 0.3), "BRAKE TEMP %d C" % int(sys.brake_temp), fs, AMBER if sys.brake_temp > 300.0 else GREEN, HORIZONTAL_ALIGNMENT_CENTER)
			text(ci, r.position + Vector2(w * 0.5, h * 0.45), "AUTOBRAKE " + ["OFF", "LO", "MED", "MAX", "RTO"][sys.autobrake], fs, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
			text(ci, r.position + Vector2(w * 0.5, h * 0.6), "PARK BRK " + ("SET" if sys.parking_brake else "OFF"), fs, AMBER if sys.parking_brake else GREEN, HORIZONTAL_ALIGNMENT_CENTER)
			text(ci, r.position + Vector2(w * 0.5, h * 0.75), "GEAR " + ac.gear_state_text(), fs, GREEN, HORIZONTAL_ALIGNMENT_CENTER)
		_:
			# CRUISE / STATUS summary
			text(ci, r.position + Vector2(w * 0.5, h * 0.3), "OAT %d C   TAT %d C" % [int(ac.oat), int(ac.oat + pow(float(ac.fdm.mach), 2.0) * 0.2 * (ac.oat + 273.0))], fs, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
			text(ci, r.position + Vector2(w * 0.5, h * 0.42), "GW %d KG" % int(ac.total_mass()), fs, GREEN, HORIZONTAL_ALIGNMENT_CENTER)
			text(ci, r.position + Vector2(w * 0.5, h * 0.54), "CAB ALT %d   DP %.1f PSI" % [int(sys.cabin_alt / U.FT), maxf((Atmo.pressure(sys.cabin_alt) - Atmo.pressure(float(ac.nav_state().alt))) / 6894.76, 0.0)], int(fs * 0.9), WHITE, HORIZONTAL_ALIGNMENT_CENTER)
			var t := Time.get_datetime_dict_from_unix_time(int(WorldSim.clock))
			text(ci, r.position + Vector2(w * 0.5, h * 0.7), "UTC %02d:%02d" % [t.hour, t.minute], fs, GREEN, HORIZONTAL_ALIGNMENT_CENTER)


# =============================================================================== MCP / FCU readouts
static func mcp(ci: CanvasItem, r: Rect2, ac: Aircraft) -> void:
	ci.draw_rect(r, Color(0.02, 0.02, 0.02))
	var ap := ac.ap
	var w := r.size.x
	var h := r.size.y
	var fs := int(clampf(h * 0.42, 8.0, 40.0))
	var amber := Color(1.0, 0.62, 0.15)
	var cells := [
		["SPD" if not ap.use_mach else "MACH", str(int(ap.spd_sel)) if not ap.use_mach else ".%02d" % int(ap.mach_sel * 100.0)],
		["HDG", "%03d" % int(posmod(int(round(ap.hdg_sel)), 360))],
		["ALT", "%05d" % int(round(ap.alt_sel / U.FT / 100.0) * 100)],
		["V/S", ("%+05d" % int(round(ap.vs_sel / U.FPM / 100.0) * 100)) if ap.vert_mode == "VS" else "-----"],
	]
	for i in cells.size():
		var cx := r.position.x + w * (0.125 + 0.25 * i)
		text(ci, Vector2(cx, r.position.y + h * 0.22), cells[i][0], int(fs * 0.55), WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		text(ci, Vector2(cx, r.position.y + h * 0.66), cells[i][1], fs, amber, HORIZONTAL_ALIGNMENT_CENTER, -1.0, mono())


# =============================================================================== GA analogue panel
static func ga_panel(ci: CanvasItem, r: Rect2, ac: Aircraft) -> void:
	ci.draw_rect(r, Color(0.08, 0.08, 0.085))
	var n := ac.nav_state()
	var cw := r.size.x / 3.0
	var ch := r.size.y / 2.0
	var rad := minf(cw, ch) * 0.42
	var cs := []
	for row in 2:
		for col in 3:
			cs.append(r.position + Vector2(cw * (col + 0.5), ch * (row + 0.5)))
	var fs := int(rad * 0.2)
	# airspeed
	_gauge_face(ci, cs[0], rad)
	var spec := ac.spec
	var vmax := 200.0
	var arcs := [[float(spec.vs0), float(spec.flaps[spec.flaps.size() - 1].vfe), WHITE, 0.82], [float(spec.vs1), float(spec.cruise_ias) + 10.0, GREEN, 0.9], [float(spec.cruise_ias) + 10.0, float(spec.vmo), Color(1, 0.85, 0.1), 0.9]]
	for a in arcs:
		ci.draw_arc(cs[0], rad * float(a[3]), _asi_ang(float(a[0]), vmax), _asi_ang(float(a[1]), vmax), 24, a[2], rad * 0.07, true)
	ci.draw_line(cs[0] + Vector2(cos(_asi_ang(float(spec.vmo), vmax)), sin(_asi_ang(float(spec.vmo), vmax))) * rad * 0.8, cs[0] + Vector2(cos(_asi_ang(float(spec.vmo), vmax)), sin(_asi_ang(float(spec.vmo), vmax))) * rad, RED, 3.0)
	for k in range(40, 201, 20):
		var a2 := _asi_ang(float(k), vmax)
		text(ci, cs[0] + Vector2(cos(a2), sin(a2)) * rad * 0.68, str(k), fs, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_needle(ci, cs[0], _asi_ang(float(n.ias_kt), vmax), rad * 0.85)
	text(ci, cs[0] + Vector2(0, rad * 0.35), "KNOTS", int(fs * 0.7), WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	# attitude
	var ar := rad * 0.95
	var c1: Vector2 = cs[1]
	var bank := deg_to_rad(float(n.bank))
	var hz := float(n.pitch) * ar / 25.0
	var pts_s := PackedVector2Array()
	var pts_g := PackedVector2Array()
	for i in 33:
		var a3 := TAU * float(i) / 32.0
		var p := c1 + Vector2(cos(a3), sin(a3)) * ar
		var local := (p - c1).rotated(bank)
		if local.y < hz:
			pts_s.append(p)
	ci.draw_circle(c1, ar, GROUND)
	var sky_poly := PackedVector2Array()
	var big := ar * 3.0
	var sky_quad := PackedVector2Array([Vector2(-big, hz), Vector2(big, hz), Vector2(big, -big), Vector2(-big, -big)])
	for q in sky_quad:
		sky_poly.append(c1 + q.rotated(-bank))
	var circle := PackedVector2Array()
	for i2 in 40:
		var a4 := TAU * float(i2) / 40.0
		circle.append(c1 + Vector2(cos(a4), sin(a4)) * ar)
	for poly in Geometry2D.intersect_polygons(circle, sky_poly):
		ci.draw_colored_polygon(poly, SKY)
	ci.draw_line(c1 + Vector2(-big, hz).rotated(-bank), c1 + Vector2(big, hz).rotated(-bank), WHITE, 2.0)
	for k2 in [-20, -10, 10, 20]:
		var y := hz - float(k2) * ar / 25.0
		var hw := ar * (0.25 if absi(k2) == 10 else 0.4)
		_clip_line(ci, c1 + Vector2(-hw, y).rotated(-bank), c1 + Vector2(hw, y).rotated(-bank), circle, WHITE, 1.5)
	ci.draw_line(c1 + Vector2(-ar * 0.55, 0), c1 + Vector2(-ar * 0.18, 0), Color(1, 0.7, 0.1), 4.0)
	ci.draw_line(c1 + Vector2(ar * 0.18, 0), c1 + Vector2(ar * 0.55, 0), Color(1, 0.7, 0.1), 4.0)
	ci.draw_circle(c1, 4.0, Color(1, 0.7, 0.1))
	ci.draw_arc(c1, ar, 0, TAU, 40, Color(0.2, 0.2, 0.22), 6.0)
	# altimeter
	_gauge_face(ci, cs[2], rad)
	var alt_ft := float(n.alt) / U.FT
	for k3 in 10:
		var a5 := -PI * 0.5 + TAU * float(k3) / 10.0
		text(ci, cs[2] + Vector2(cos(a5), sin(a5)) * rad * 0.74, str(k3), int(fs * 1.2), WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		ci.draw_line(cs[2] + Vector2(cos(a5), sin(a5)) * rad * 0.88, cs[2] + Vector2(cos(a5), sin(a5)) * rad, WHITE, 2.0)
	_needle(ci, cs[2], -PI * 0.5 + TAU * fmod(alt_ft, 1000.0) / 1000.0, rad * 0.85)
	_needle(ci, cs[2], -PI * 0.5 + TAU * fmod(alt_ft, 10000.0) / 10000.0, rad * 0.5, 4.0)
	text(ci, cs[2] + Vector2(0, rad * 0.35), "%d FT" % int(alt_ft), int(fs * 0.75), WHITE, HORIZONTAL_ALIGNMENT_CENTER, -1.0, mono())
	# turn coordinator
	_gauge_face(ci, cs[3], rad)
	var turn_rate := rad_to_deg(-ac.fdm.omega.y)
	var tilt := clampf(turn_rate / 3.0 * deg_to_rad(20.0), -0.7, 0.7)
	var wing := Vector2(rad * 0.6, 0).rotated(tilt)
	ci.draw_line(cs[3] - wing, cs[3] + wing, WHITE, 4.0)
	ci.draw_circle(cs[3], rad * 0.1, WHITE)
	var slip := clampf(rad_to_deg(ac.fdm.beta) / 8.0, -1.0, 1.0)
	ci.draw_arc(cs[3] + Vector2(0, rad * 0.25), rad * 0.5, deg_to_rad(60), deg_to_rad(120), 16, GREY, rad * 0.14, true)
	var bp := cs[3] + Vector2(0, rad * 0.25) + Vector2(cos(deg_to_rad(90 - slip * 28.0)), sin(deg_to_rad(90 - slip * 28.0))) * rad * 0.5
	ci.draw_circle(bp, rad * 0.06, Color.BLACK)
	text(ci, cs[3] + Vector2(0, -rad * 0.5), "TURN COORD", int(fs * 0.6), WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	# heading indicator
	_gauge_face(ci, cs[4], rad)
	var hdg := float(n.hdg)
	for d in range(0, 360, 10):
		var a6 := deg_to_rad(float(d) - hdg - 90.0)
		var l := rad * (0.14 if d % 30 == 0 else 0.07)
		ci.draw_line(cs[4] + Vector2(cos(a6), sin(a6)) * rad * 0.92, cs[4] + Vector2(cos(a6), sin(a6)) * (rad * 0.92 - l), WHITE, 1.5)
		if d % 30 == 0:
			var lbl := {0: "N", 90: "E", 180: "S", 270: "W"}.get(d, str(d / 10))
			text(ci, cs[4] + Vector2(cos(a6), sin(a6)) * rad * 0.62, lbl, fs, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	ci.draw_colored_polygon(PackedVector2Array([cs[4] + Vector2(0, -rad * 0.5), cs[4] + Vector2(rad * 0.2, rad * 0.3), cs[4] + Vector2(-rad * 0.2, rad * 0.3)]), Color(1, 0.7, 0.1))
	var bug := deg_to_rad(float(ac.ap.hdg_sel) - hdg - 90.0)
	ci.draw_rect(Rect2(cs[4] + Vector2(cos(bug), sin(bug)) * rad * 0.95 - Vector2(4, 4), Vector2(8, 8)), Color(1, 0.4, 0.1))
	# vertical speed
	_gauge_face(ci, cs[5], rad)
	var vs_fpm := clampf(float(n.vs) / U.FPM, -2000.0, 2000.0)
	for k4 in [-2, -1, 0, 1, 2]:
		var a7 := PI - float(k4) * deg_to_rad(80.0)
		text(ci, cs[5] + Vector2(cos(a7), sin(a7)) * rad * 0.7, str(absi(k4)), fs, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_needle(ci, cs[5], PI - vs_fpm / 1000.0 * deg_to_rad(80.0), rad * 0.85)
	text(ci, cs[5] + Vector2(rad * 0.2, rad * 0.4), "VSI x1000", int(fs * 0.6), WHITE, HORIZONTAL_ALIGNMENT_CENTER)


static func _asi_ang(v: float, vmax: float) -> float:
	return deg_to_rad(-90.0 + clampf(v / vmax, 0.0, 1.0) * 320.0)


static func _gauge_face(ci: CanvasItem, c: Vector2, rad: float) -> void:
	ci.draw_circle(c, rad * 1.06, Color(0.2, 0.2, 0.22))
	ci.draw_circle(c, rad, Color(0.03, 0.03, 0.035))


static func _needle(ci: CanvasItem, c: Vector2, ang: float, length: float, width: float = 3.0) -> void:
	var tip := c + Vector2(cos(ang), sin(ang)) * length
	ci.draw_line(c - Vector2(cos(ang), sin(ang)) * length * 0.15, tip, WHITE, width, true)
	ci.draw_circle(c, width * 1.5, Color(0.3, 0.3, 0.3))


## Engine strip for the trainer: RPM, fuel, oil.
static func ga_engine(ci: CanvasItem, r: Rect2, ac: Aircraft) -> void:
	ci.draw_rect(r, Color(0.08, 0.08, 0.085))
	var e: Dictionary = ac.sys.eng[0]
	var rad := minf(r.size.x / 3.0, r.size.y) * 0.4
	var fs := int(rad * 0.25)
	var c0 := r.position + Vector2(r.size.x / 6.0, r.size.y * 0.5)
	_gauge_face(ci, c0, rad)
	var rpm := float(e.get("rpm", float(e.n1) * 27.0))
	ci.draw_arc(c0, rad * 0.9, deg_to_rad(150.0 + 300.0 * 2100.0 / 3000.0), deg_to_rad(150.0 + 300.0 * 2700.0 / 3000.0), 16, GREEN, rad * 0.08)
	_needle(ci, c0, deg_to_rad(150.0 + 300.0 * clampf(rpm / 3000.0, 0.0, 1.0)), rad * 0.85)
	text(ci, c0 + Vector2(0, rad * 0.45), "RPM %d" % int(rpm), fs, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var c1 := r.position + Vector2(r.size.x * 0.5, r.size.y * 0.5)
	_gauge_face(ci, c1, rad)
	text(ci, c1 + Vector2(0, -rad * 0.4), "FUEL", fs, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var cap: float = ac.spec.max_fuel
	_needle(ci, c1, deg_to_rad(210.0 + 120.0 * clampf(ac.sys.fuel_total() / cap, 0.0, 1.0)), rad * 0.8)
	text(ci, c1 + Vector2(0, rad * 0.45), "%d KG" % int(ac.sys.fuel_total()), fs, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var c2 := r.position + Vector2(r.size.x * 5.0 / 6.0, r.size.y * 0.5)
	_gauge_face(ci, c2, rad)
	text(ci, c2 + Vector2(0, -rad * 0.4), "OIL", fs, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_needle(ci, c2, deg_to_rad(210.0 + 120.0 * clampf(float(e.oil_p) / 100.0, 0.0, 1.0)), rad * 0.8)
	text(ci, c2 + Vector2(0, rad * 0.45), "%d PSI" % int(e.oil_p), fs, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
