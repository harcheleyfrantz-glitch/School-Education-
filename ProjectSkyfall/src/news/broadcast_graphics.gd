class_name BroadcastGraphics
extends Control
## Everything drawn over the picture of a broadcast, as a pure function of the playhead: the
## channel bug and clock, the BREAKING NEWS bumper, headline straps, name supers, the ticker,
## captions, shot labels (RECONSTRUCTION, LIVE, VIEWER VIDEO), the phone camera UI, a flight
## tracker with a mini map, the investigation flight-data panel with CVR transcript, and the
## safety board's report cards. Drawn at the 1280x720 frame resolution.

const W := 1280.0
const H := 720.0
const M := 48.0

var program: Dictionary = {}
var t := 0.0
var seg: Dictionary = {}
var seg_i := -1
var captions := true
var outlet := "skyline"
var prim := Color.RED
var dark := Color.BLACK
var hi := Color.YELLOW
var acc := Color.WHITE
var f_head: Font
var f_body: Font
var f_bold: Font
var f_mono: Font
var f_mono_b: Font
var samples: Array = []
var map_tex: Texture2D
var map_center := Vector2.ZERO
var map_half := 20000.0
var wall_tex: Texture2D = null
var phone_rect := Rect2(437, 0, 406, 720)
var cam_label := ""
var _ticker := ""
var _ticker_w := 1.0
var _segs: Array = []
var _lines: Array = []
var _thirds: Array = []
var _ranges := {}


func setup(prog: Dictionary) -> void:
	program = prog
	outlet = String(prog.get("outlet", "skyline"))
	prim = NewsStyle.col(outlet, "primary")
	dark = NewsStyle.col(outlet, "secondary")
	hi = NewsStyle.col(outlet, "hi")
	acc = NewsStyle.col(outlet, "accent")
	f_head = NewsStyle.head_font(outlet, 800)
	f_body = NewsStyle.body_font(outlet, 500)
	f_bold = NewsStyle.font("sans", 800)
	f_mono = NewsStyle.font("mono", 500)
	f_mono_b = NewsStyle.font("mono", 700)
	_segs = prog.get("segments", [])
	_lines = prog.get("lines", [])
	_thirds = prog.get("thirds", [])
	var tk: Array = prog.get("ticker", [])
	_ticker = ""
	for s in tk:
		_ticker += String(s) + "     ◆     "
	_ticker_w = maxf(f_bold.get_string_size(_ticker, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x, 1.0)
	var w: Dictionary = prog.get("world", {})
	samples = w.get("samples", [])
	if samples.size() >= 2:
		var lo := Vector2(INF, INF)
		var hi2 := Vector2(-INF, -INF)
		for s2 in samples:
			lo = Vector2(minf(lo.x, float(s2[1])), minf(lo.y, float(s2[2])))
			hi2 = Vector2(maxf(hi2.x, float(s2[1])), maxf(hi2.y, float(s2[2])))
		map_center = (lo + hi2) * 0.5
		map_half = clampf(maxf(hi2.x - lo.x, hi2.y - lo.y) * 0.65, 4000.0, 120000.0)
		map_tex = NewsMap.texture(map_center, map_half, 160, Color(0.1, 0.24, 0.42), Color(0.36, 0.45, 0.32), Color(0.66, 0.62, 0.52), Color(0.75, 0.88, 1.0))
		for k in [3, 4, 5, 6, 7]:
			var a := INF
			var b := -INF
			for s3 in samples:
				var v := float(s3[k])
				a = minf(a, v)
				b = maxf(b, v)
			_ranges[k] = [a, b]


# ================================================================== helpers
func _txt(pos: Vector2, s: String, f: Font, fs: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	draw_string(f, pos + Vector2(0, f.get_ascent(fs)), s, align, width, fs, col)


func _tw(s: String, f: Font, fs: int) -> float:
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


static func _ease(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - c, 3.0)


## In/out envelope for an element visible between a and b.
func _env(a: float, b: float, tin: float = 0.4, tout: float = 0.3) -> float:
	if t < a or t > b:
		return 0.0
	return minf(_ease((t - a) / tin), _ease((b - t) / tout))


func _wrap(s: String, f: Font, fs: int, width: float) -> Array:
	return StoryGraphic._wrap(s, f, fs, width)


func _seg_kind() -> String:
	return String(seg.get("kind", ""))


func _lt() -> float:
	return t - float(seg.get("t0", 0.0))


## Recorder sample time shown by the current segment (or -1).
func _sample_t() -> float:
	return BroadcastPlayer.seg_sample_time(seg, _lt(), samples)


# ================================================================== frame
func _draw() -> void:
	if seg.is_empty():
		return
	var kind := _seg_kind()
	var raw := bool(program.get("raw", false))
	var card := String(seg.get("card", ""))
	if kind == "phone":
		if bool(seg.get("landscape", false)):
			_dashcam_ui()
		else:
			_phone_ui()
	if bool(seg.get("fdr", false)):
		_fdr_panel()
	elif kind == "recon":
		_tracker()
	if kind == "replay":
		_replay_hud()
	if card != "":
		_card(card)
	if kind == "bumper":
		_bumper()
	elif not raw and card == "" and kind != "title":
		_label_badge()
		_bug()
		_thirds_draw()
		if not bool(program.get("no_ticker", false)):
			_ticker_draw()
	elif String(program.get("kind", "")) == "inv_report" and kind != "title":
		_board_bug()
	if captions:
		_captions()
	_transition()
	if kind == "studio" and String(seg.get("graphic", "")) == "story" and wall_tex:
		_ots()


# ================================================================== channel identity
func _bug() -> void:
	var st := NewsStyle.get_style(outlet)
	var name := String(st.short)
	var fs := 22
	var w := _tw(name, f_head, fs) + 66.0
	var x := W - M - w
	var y := 30.0
	draw_rect(Rect2(x, y, w, 40), Color(prim, 0.92))
	_logo_mark(Vector2(x + 10, y + 7), 26.0)
	_txt(Vector2(x + 46, y + 7), name, f_head, fs, Color.WHITE)
	# clock and live pill under the bug
	var clock := float(program.get("air_clock", WorldSim.clock)) + t
	var ctext := U.fmt_clock(clock)
	var live := bool(seg.get("live", false))
	var cy := y + 44
	if live:
		var lw := 64.0
		var blink := 0.75 + 0.25 * sin(t * 6.0)
		draw_rect(Rect2(W - M - lw - 72, cy, lw, 26), Color(0.85, 0.05, 0.05, blink))
		_txt(Vector2(W - M - lw - 72, cy + 3), "LIVE", f_bold, 17, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, lw)
	draw_rect(Rect2(W - M - 66, cy, 66, 26), Color(0, 0, 0, 0.6))
	_txt(Vector2(W - M - 66, cy + 3), ctext, f_bold, 17, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 66)


func _logo_mark(p: Vector2, s: float) -> void:
	match String(NewsStyle.get_style(outlet).bug):
		"skyline":
			var hs := [0.45, 0.8, 0.6, 1.0, 0.7, 0.5]
			for i in hs.size():
				var bh := s * float(hs[i])
				draw_rect(Rect2(p.x + i * s / 6.0, p.y + s - bh, s / 6.0 - 1.0, bh), Color.WHITE)
		"herald", "post":
			draw_rect(Rect2(p, Vector2(s, s)), Color.WHITE, false, 2.0)
			_txt(p + Vector2(0, -1), "H" if String(NewsStyle.get_style(outlet).bug) == "herald" else "P", NewsStyle.font("serif", 700), int(s * 0.9), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, s)
		"aeroweek":
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, s), p + Vector2(s * 0.5, 0), p + Vector2(s, s), p + Vector2(s * 0.5, s * 0.68)]), Color.WHITE)
		"skywatch":
			draw_circle(p + Vector2(s, s) * 0.5, s * 0.48, Color.WHITE)
			draw_circle(p + Vector2(s, s) * 0.5, s * 0.22, prim)
		_:
			draw_circle(p + Vector2(s, s) * 0.5, s * 0.45, Color.WHITE)


func _board_bug() -> void:
	draw_rect(Rect2(M, 30, 300, 40), Color(0.03, 0.07, 0.14, 0.85))
	draw_rect(Rect2(M, 30, 6, 40), Color(1.0, 0.69, 0.0))
	_emblem(Vector2(M + 30, 50), 15.0)
	_txt(Vector2(M + 52, 36), "CTSB · INVESTIGATION ANIMATION", f_bold, 15, Color.WHITE)
	_txt(Vector2(M + 52, 54), "Calderra Transport Safety Board", f_body, 11, Color(1, 1, 1, 0.7))


func _emblem(c: Vector2, r: float) -> void:
	draw_circle(c, r, Color(0.11, 0.3, 0.54))
	draw_arc(c, r, 0, TAU, 32, Color(1.0, 0.69, 0.0), 2.0)
	var wing := PackedVector2Array([c + Vector2(-r * 0.75, r * 0.1), c + Vector2(0, -r * 0.55), c + Vector2(r * 0.75, r * 0.1), c + Vector2(0, -r * 0.18)])
	draw_colored_polygon(wing, Color.WHITE)
	draw_rect(Rect2(c + Vector2(-r * 0.08, -r * 0.2), Vector2(r * 0.16, r * 0.75)), Color.WHITE)


func _label_badge() -> void:
	var lab := String(seg.get("label", ""))
	if lab == "":
		return
	var k := _env(float(seg.t0) + 0.3, float(seg.t1) - 0.2, 0.3, 0.2)
	if k <= 0.0:
		return
	var fs := 18
	var w := _tw(lab, f_bold, fs) + 34.0
	draw_rect(Rect2(M, 34, w * k, 34), Color(0, 0, 0, 0.62))
	draw_rect(Rect2(M, 34, 5, 34), prim)
	if k > 0.6:
		_txt(Vector2(M + 18, 40), lab, f_bold, fs, Color(1, 1, 1, (k - 0.6) / 0.4))


# ================================================================== lower thirds
func _thirds_draw() -> void:
	var name_k := 0.0
	var active_name: Dictionary = {}
	for th in _thirds:
		if String(th.kind) == "strap":
			continue
		var k := _env(float(th.t0), float(th.t1))
		if k > name_k:
			name_k = k
			active_name = th
	for th2 in _thirds:
		if String(th2.kind) != "strap":
			continue
		var k2 := _env(float(th2.t0), float(th2.t1), 0.5, 0.3) * (1.0 - name_k)
		if k2 > 0.0:
			_strap(th2, k2)
	if name_k > 0.0:
		_name_super(active_name, name_k)


func _strap(th: Dictionary, k: float) -> void:
	var y := H - 40.0 - 112.0 + (1.0 - k) * 30.0
	var a := clampf(k * 1.4, 0.0, 1.0)
	var tag := String(th.get("tag", ""))
	var x := M
	var w := W - 2.0 * M
	if tag != "":
		var tw := _tw(tag, f_bold, 19) + 30.0
		var pulse := 1.0 if not "BREAKING" in tag else 0.82 + 0.18 * sin(t * 5.0)
		draw_rect(Rect2(x, y, tw * k, 30), Color(prim.r * pulse, prim.g * pulse, prim.b * pulse, a))
		if k > 0.5:
			_txt(Vector2(x + 15, y + 4), tag, f_bold, 19, Color(1, 1, 1, a))
	var hy := y + 30.0
	var light := outlet in ["skyline", "gazette"]
	draw_rect(Rect2(x, hy, w * k, 54), Color(0.97, 0.97, 0.97, a) if light else Color(dark.lightened(0.05), 0.95 * a))
	draw_rect(Rect2(x, hy, 7, 54), Color(prim, a))
	var head := String(th.get("a", ""))
	var fs := 34
	while fs > 22 and _tw(head, f_head, fs) > w - 40.0:
		fs -= 2
	if k > 0.35:
		_txt(Vector2(x + 22, hy + (54 - fs * 1.2) * 0.5 + 1), head, f_head, fs, Color(0.06, 0.07, 0.09, a) if light else Color(1, 1, 1, a))
	var sy := hy + 54.0
	draw_rect(Rect2(x, sy, w * k, 28), Color(dark, 0.93 * a))
	if k > 0.5:
		_txt(Vector2(x + 22, sy + 4), String(th.get("b", "")), f_bold, 16, Color(1, 1, 1, 0.9 * a))


func _name_super(th: Dictionary, k: float) -> void:
	var kind := String(th.kind)
	var y := H - 40.0 - 100.0
	var a := String(th.get("a", ""))
	var b := String(th.get("b", ""))
	var fs := 30
	var w1 := maxf(_tw(a, f_head, fs) + 44.0, 260.0)
	var w2 := maxf(_tw(b, f_bold, 17) + 44.0, w1 * 0.7)
	var bar := prim if kind != "credit" else Color(0.1, 0.1, 0.12)
	if kind == "label":
		bar = Color(0.08, 0.09, 0.11)
	var tag := String(th.get("tag", ""))
	var x := M
	if tag != "":
		var tw := _tw(tag, f_bold, 18) + 26.0
		var blink := 0.8 + 0.2 * sin(t * 6.0)
		draw_rect(Rect2(x, y - 30.0, tw * k, 28), Color(0.85, 0.04, 0.05, blink))
		if k > 0.6:
			_txt(Vector2(x + 13, y - 27.0), tag, f_bold, 18, Color.WHITE)
	draw_rect(Rect2(x, y, w1 * k, 50), Color(bar, 0.96))
	draw_rect(Rect2(x, y + 50, w2 * k, 30), Color(0.97, 0.97, 0.97, 0.96) if outlet != "aeroweek" else Color(0.1, 0.12, 0.15, 0.96))
	if k > 0.45:
		var al := clampf((k - 0.45) / 0.55, 0.0, 1.0)
		_txt(Vector2(x + 22, y + 7), a, f_head, fs, Color(1, 1, 1, al))
		_txt(Vector2(x + 22, y + 55), b, f_bold, 17, Color(0.08, 0.09, 0.12, al) if outlet != "aeroweek" else Color(0.95, 0.65, 0.3, al))


func _ticker_draw() -> void:
	var y := H - 40.0
	draw_rect(Rect2(0, y, W, 40), NewsStyle.col(outlet, "ticker_bg"))
	var label := "BREAKING" if "BREAKING" in String(program.get("tag", "")) else String(NewsStyle.get_style(outlet).short)
	var lw := _tw(label, f_bold, 18) + 36.0
	var x0 := lw + 12.0
	var off := fmod(t * 95.0, _ticker_w)
	var x := x0 + 30.0 - off
	while x < W:
		draw_string(f_bold, Vector2(x, y + 27), _ticker, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, NewsStyle.col(outlet, "ticker_fg"))
		x += _ticker_w
	draw_rect(Rect2(0, y, lw, 40), prim)
	draw_colored_polygon(PackedVector2Array([Vector2(lw, y), Vector2(lw + 12, y), Vector2(lw, y + 40)]), prim)
	_txt(Vector2(0, y + 9), label, f_bold, 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, lw)


# ================================================================== captions
func _captions() -> void:
	var cur: Array = []
	for l in _lines:
		if t >= float(l.t0) and t <= float(l.t1) + 0.15:
			cur.append(l)
	if cur.is_empty():
		return
	var l0: Dictionary = cur[cur.size() - 1]
	var style := String(l0.get("style", "narr"))
	var text := String(l0.text)
	var fs := 25
	var f := f_body
	var col := Color.WHITE
	if style == "cvr":
		text = "%s: %s" % [String(l0.name), text]
		f = f_mono_b
		fs = 22
		col = Color(1.0, 0.86, 0.35) if String(l0.name) in ["GPWS", "AURAL"] else Color(0.92, 0.96, 1.0)
	elif style == "q":
		text = "REPORTER: %s" % text
		col = Color(1.0, 0.86, 0.45)
	elif style == "nat":
		text = "[%s]" % text
		col = Color(1, 1, 1, 0.92)
	var maxw := 920.0
	var rows := _wrap(text, f, fs, maxw)
	var lh := fs * 1.3
	var bottom := H - 40.0 - 150.0
	if bool(program.get("raw", false)) or String(seg.get("card", "")) != "" or bool(seg.get("fdr", false)):
		bottom = H - 70.0
	if _seg_kind() == "phone":
		bottom = H - (70.0 if bool(seg.get("landscape", false)) else 120.0)
	if bool(seg.get("fdr", false)) and style != "cvr":
		bottom = H - 210.0
	var y := bottom - rows.size() * lh
	for i in rows.size():
		var rw := _tw(String(rows[i]), f, fs) + 26.0
		var rx := (W - rw) * 0.5
		if bool(seg.get("fdr", false)):
			rx = (880.0 - rw) * 0.5
		draw_rect(Rect2(rx, y + i * lh - 3, rw, lh), Color(0, 0, 0, 0.72))
		_txt(Vector2(rx + 13, y + i * lh), String(rows[i]), f, fs, col)


# ================================================================== bumper and transitions
func _bumper() -> void:
	var lt := _lt()
	var d := float(seg.t1) - float(seg.t0)
	var out_k := _ease((lt - (d - 0.55)) / 0.55)
	var in_k := _ease(lt / 0.35)
	var cover := in_k * (1.0 - out_k)
	if cover <= 0.0:
		return
	draw_rect(Rect2(0, 0, W, H), Color(dark.darkened(0.3), 0.9 * cover))
	# sweeping diagonal bands
	for i in 7:
		var sp := 900.0 + i * 140.0
		var x := -400.0 + fmod(lt * sp + i * 260.0, W + 800.0)
		var bw := 40.0 + i * 18.0
		var pts := PackedVector2Array([Vector2(x, 0), Vector2(x + bw, 0), Vector2(x + bw - 300, H), Vector2(x - 300, H)])
		draw_colored_polygon(pts, Color(prim, (0.18 + 0.06 * (i % 3)) * cover))
	# concentric rings
	var c := Vector2(W * 0.5, H * 0.5)
	for k in 5:
		var rr := 80.0 + k * 90.0 + fmod(lt * 120.0, 90.0)
		draw_arc(c, rr, lt * (0.6 + k * 0.2), lt * (0.6 + k * 0.2) + PI * 1.3, 64, Color(1, 1, 1, 0.12 * cover), 2.0)
	# the words
	var fs := 112
	var w1 := _tw("BREAKING", f_head, fs)
	var w2 := _tw("NEWS", f_head, fs)
	var slide := (1.0 - _ease((lt - 0.1) / 0.45)) * W * 0.6
	var y := H * 0.5 - fs * 0.95
	draw_rect(Rect2(W * 0.5 - w1 * 0.5 - 30 - slide, y - 6, w1 + 60, fs * 1.12), Color(prim, cover))
	_txt(Vector2(W * 0.5 - w1 * 0.5 - slide, y), "BREAKING", f_head, fs, Color(1, 1, 1, cover))
	var y2 := y + fs * 1.16
	draw_rect(Rect2(W * 0.5 - w2 * 0.5 - 30 + slide, y2 - 6, w2 + 60, fs * 1.12), Color(1, 1, 1, cover))
	_txt(Vector2(W * 0.5 - w2 * 0.5 + slide, y2), "NEWS", f_head, fs, Color(prim.darkened(0.1), cover))
	var st := NewsStyle.get_style(outlet)
	_txt(Vector2(0, y2 + fs * 1.25), String(st.name).to_upper(), f_bold, 26, Color(1, 1, 1, 0.85 * cover * _ease((lt - 0.7) / 0.4)), HORIZONTAL_ALIGNMENT_CENTER, W)


func _transition() -> void:
	## A quick branded wipe whenever the picture moves between the studio and the field.
	for i in range(1, _segs.size()):
		var a: Dictionary = _segs[i - 1]
		var b: Dictionary = _segs[i]
		if String(a.stage) == String(b.stage) or String(a.kind) == "bumper":
			continue
		var tb := float(b.t0)
		var u := (t - (tb - 0.28)) / 0.56
		if u <= 0.0 or u >= 1.0:
			continue
		var x := lerpf(-W * 0.4, W * 1.4, u)
		var pts := PackedVector2Array([Vector2(x - 260, 0), Vector2(x + 140, 0), Vector2(x - 60, H), Vector2(x - 460, H)])
		draw_colored_polygon(pts, prim)
		var pts2 := PackedVector2Array([Vector2(x + 140, 0), Vector2(x + 170, 0), Vector2(x - 30, H), Vector2(x - 60, H)])
		draw_colored_polygon(pts2, Color.WHITE)
		_txt(Vector2(x - 300, H * 0.5 - 22), String(NewsStyle.get_style(outlet).short), f_head, 40, Color.WHITE)


func _ots() -> void:
	## Over-the-shoulder story box in anchor close-ups.
	var shot_cam := String(seg.get("_cam", ""))
	if not shot_cam.begins_with("single"):
		return
	var r := Rect2(W - M - 470, 120, 470, 264)
	var k := _env(float(seg.get("_shot_t0", 0.0)) + 0.4, float(seg.t1) - 0.2, 0.35, 0.25)
	if k <= 0.0:
		return
	var rr := Rect2(r.position + Vector2(r.size.x * (1.0 - k), 0), Vector2(r.size.x * k, r.size.y))
	draw_texture_rect_region(wall_tex, rr, Rect2(Vector2(1024.0 * (1.0 - k), 0), Vector2(1024.0 * k, 448.0)))
	draw_rect(rr, Color(1, 1, 1, 0.9), false, 2.0)


# ================================================================== field footage overlays
func _phone_ui() -> void:
	var r := phone_rect
	var lt := _lt()
	var raw := bool(program.get("raw", false))
	var rec_on := fmod(lt, 1.0) < 0.6
	if rec_on:
		draw_circle(r.position + Vector2(24, 30), 7.0, Color(1, 0.15, 0.1))
	_txt(r.position + Vector2(38, 20), "00:%02d" % int(lt + 3.0), f_bold, 17, Color.WHITE)
	_txt(r.position + Vector2(r.size.x - 70, 20), "%.1fx" % (2.0 + 0.6 * sin(lt * 0.4)), f_bold, 16, Color(1, 0.85, 0.2))
	# battery and signal
	var bx := r.position.x + r.size.x - 36
	draw_rect(Rect2(bx, 52, 24, 12), Color.WHITE, false, 1.5)
	draw_rect(Rect2(bx + 2, 54, 14, 8), Color.WHITE)
	for i in 4:
		draw_rect(Rect2(r.position.x + 18 + i * 6, 64 - i * 3, 4, 4 + i * 3), Color(1, 1, 1, 0.9))
	# focus brackets
	var c := r.get_center()
	var fb := 46.0 + 6.0 * sin(lt * 3.0)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var p := c + Vector2(sx * fb, sy * fb)
			draw_line(p, p - Vector2(sx * 14, 0), Color(1, 0.85, 0.2, 0.8), 2.0)
			draw_line(p, p - Vector2(0, sy * 14), Color(1, 0.85, 0.2, 0.8), 2.0)
	# shutter button
	draw_circle(Vector2(c.x, r.end.y - 50), 22, Color(1, 1, 1, 0.85))
	draw_circle(Vector2(c.x, r.end.y - 50), 17, Color(0.9, 0.1, 0.08) if rec_on else Color(0.8, 0.1, 0.08))
	if raw:
		var handle := String(seg.get("handle", ""))
		_txt(Vector2(r.position.x + 14, r.end.y - 104), handle, f_bold, 15, Color(1, 1, 1, 0.9))
	else:
		_bug()


func _dashcam_ui() -> void:
	## A car's dashcam: date and time burned in, speed and GPS, a REC dot and the camera's name.
	var lt := _lt()
	var clk := float(program.get("world", {}).get("clock", WorldSim.clock)) - 9.0 + lt
	var d := Time.get_datetime_dict_from_unix_time(int(clk))
	var stamp := "%04d/%02d/%02d  %02d:%02d:%02d" % [int(d.year), int(d.month), int(d.day), int(d.hour), int(d.minute), int(d.second)]
	draw_rect(Rect2(0, H - 46, W, 46), Color(0, 0, 0, 0.45))
	_txt(Vector2(18, H - 16), stamp, f_mono_b, 20, Color(1, 1, 1, 0.92))
	var kmh := maxi(0, 64 - int(maxf(lt - 9.5, 0.0) * 14.0))
	_txt(Vector2(W * 0.5 - 60, H - 16), "%d KM/H" % kmh, f_mono_b, 20, Color(1, 1, 1, 0.92))
	_txt(Vector2(W - 330, H - 16), "GPS  N%.4f  E%.4f" % [41.0 + fmod(float(seg.get("phone_seed", 1)) * 0.0007, 0.9), 12.0 + fmod(float(seg.get("phone_seed", 1)) * 0.0013, 0.9)], f_mono, 16, Color(1, 1, 1, 0.8))
	if fmod(lt, 1.0) < 0.6:
		draw_circle(Vector2(30, 34), 8.0, Color(1, 0.15, 0.1))
	_txt(Vector2(46, 42), "REC", f_bold, 18, Color.WHITE)
	_txt(Vector2(W - 190, 42), "DRIVECAM HD", f_bold, 16, Color(1, 1, 1, 0.7))
	if bool(program.get("raw", false)):
		_txt(Vector2(18, H - 62), String(seg.get("handle", "")), f_bold, 15, Color(1, 1, 1, 0.85))


func _tracker() -> void:
	## TV flight tracker: altitude, speed and descent, plus a mini map of the track.
	var st := _sample_t()
	if st < 0.0 or samples.is_empty():
		return
	var s := BroadcastPlayer.sample_at(samples, st)
	var k := _env(float(seg.t0) + 0.6, float(seg.t1) - 0.3, 0.4, 0.3)
	if k <= 0.0:
		return
	var x := M
	var y := 80.0
	draw_rect(Rect2(x, y, 300 * k, 104), Color(0.02, 0.03, 0.05, 0.78))
	draw_rect(Rect2(x, y, 4, 104), prim)
	if k > 0.7:
		var alt := int(float(s[3]) / U.FT)
		var vs := int(float(s[5]) / U.FPM)
		_txt(Vector2(x + 16, y + 8), "ALTITUDE", f_bold, 12, Color(1, 1, 1, 0.6))
		_txt(Vector2(x + 16, y + 22), "%s ft" % U.fmt_int(alt), f_bold, 22, Color.WHITE)
		_txt(Vector2(x + 160, y + 8), "SPEED", f_bold, 12, Color(1, 1, 1, 0.6))
		_txt(Vector2(x + 160, y + 22), "%d kt" % int(s[4]), f_bold, 22, Color.WHITE)
		_txt(Vector2(x + 16, y + 56), "VERTICAL SPEED", f_bold, 12, Color(1, 1, 1, 0.6))
		var vcol := Color.WHITE if vs > -2500 else (Color(1.0, 0.75, 0.2) if vs > -5000 else Color(1.0, 0.3, 0.25))
		_txt(Vector2(x + 16, y + 70), "%s%s ft/min" % ["▼ " if vs < -100 else ("▲ " if vs > 100 else ""), U.fmt_int(absi(vs))], f_bold, 22, vcol)
	# mini map
	if map_tex:
		var mr := Rect2(W - M - 220, 80, 220, 170)
		draw_rect(mr.grow(3), Color(0, 0, 0, 0.6 * k))
		draw_texture_rect_region(map_tex, mr, Rect2(0, 16, 160, 128), Color(1, 1, 1, k))
		var src_rect := Rect2(mr.position - Vector2(0, mr.size.y * 16.0 / 128.0), Vector2(mr.size.x, mr.size.y * 160.0 / 128.0))
		var pts := PackedVector2Array()
		var cur := Vector2.ZERO
		for s2 in samples:
			var p := NewsMap.to_px(Vector2(float(s2[1]), float(s2[2])), map_center, map_half, src_rect)
			if float(s2[0]) <= st:
				pts.append(p)
				cur = p
		if pts.size() >= 2:
			draw_polyline(pts, Color(1, 0.85, 0.2, k), 2.5)
		StoryGraphic.draw_plane(self, cur, deg_to_rad(float(s[8])), 9.0, Color(1, 1, 1, k))
		var endp := NewsMap.to_px(Vector2(float(samples[samples.size() - 1][1]), float(samples[samples.size() - 1][2])), map_center, map_half, src_rect)
		if st >= float(samples[samples.size() - 1][0]) - 0.5:
			draw_circle(endp, 8.0, Color(1, 0.15, 0.1, k))
		for pl in NewsMap.places_in(map_center, map_half * 0.8):
			var pp := NewsMap.to_px(pl.pos, map_center, map_half, src_rect)
			if mr.has_point(pp):
				draw_circle(pp, 4.0, Color(1, 1, 1, k))
				_txt(pp + Vector2(6, -16), String(pl.name).to_upper(), f_bold, 12, Color(1, 1, 1, k))


func _replay_hud() -> void:
	var st := _sample_t()
	if st < 0.0 or samples.is_empty():
		return
	var s := BroadcastPlayer.sample_at(samples, st)
	draw_rect(Rect2(M, 34, 230, 34), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(M, 34, 5, 34), prim)
	_txt(Vector2(M + 16, 40), "REPLAY · %s" % cam_label.to_upper(), f_bold, 17, Color.WHITE)
	var y := H - 150.0
	draw_rect(Rect2(M, y, 560, 58), Color(0.02, 0.03, 0.05, 0.72))
	var items := [["CALLSIGN", String(program.get("callsign", ""))], ["ALT", "%s ft" % U.fmt_int(int(float(s[3]) / U.FT))], ["IAS", "%d kt" % int(s[4])],
		["V/S", "%+d" % int(float(s[5]) / U.FPM)], ["HDG", "%03d°" % int(fposmod(float(s[8]), 360.0))]]
	var x := M + 14.0
	for it in items:
		_txt(Vector2(x, y + 7), String(it[0]), f_bold, 11, Color(1, 1, 1, 0.55))
		_txt(Vector2(x, y + 22), String(it[1]), f_mono_b, 19, Color.WHITE)
		x += 110.0 if String(it[0]) != "CALLSIGN" else 130.0


# ================================================================== investigation flight data
func _fdr_panel() -> void:
	var st := _sample_t()
	if st < 0.0 or samples.is_empty():
		return
	var t_end := float(samples[samples.size() - 1][0])
	var s := BroadcastPlayer.sample_at(samples, st)
	var k := _env(float(seg.t0) + 0.3, float(seg.t1) + 0.5, 0.5, 0.2)
	var px := 892.0
	var py := 78.0
	var pw := W - px - 28.0
	var ph := 560.0
	draw_rect(Rect2(px, py, pw, ph), Color(0.02, 0.04, 0.08, 0.8 * k))
	draw_rect(Rect2(px, py, pw, 3), Color(1.0, 0.69, 0.0, k))
	_txt(Vector2(px + 12, py + 9), "FLIGHT DATA RECORDER", f_bold, 13, Color(1, 1, 1, 0.75 * k))
	var tti := st - t_end
	_txt(Vector2(px + 12, py + 9), "T%+.1f s" % tti if tti < 0.0 else "IMPACT", f_mono_b, 14, Color(1.0, 0.75, 0.25, k), HORIZONTAL_ALIGNMENT_RIGHT, pw - 24)
	# attitude indicator
	var adi_c := Vector2(px + 62, py + 92)
	_adi(adi_c, 46.0, float(s[6]), float(s[7]), k)
	var rx := px + 124.0
	var rows := [["ALT", "%s ft" % U.fmt_int(int(float(s[3]) / U.FT))], ["IAS", "%d kt" % int(s[4])], ["V/S", "%+d fpm" % int(float(s[5]) / U.FPM)],
		["HDG", "%03d°" % int(fposmod(float(s[8]), 360.0))], ["PITCH", "%+.1f°" % float(s[6])], ["BANK", "%+.1f°" % float(s[7])]]
	for i in rows.size():
		var ry := py + 34.0 + i * 20.0
		_txt(Vector2(rx, ry), String(rows[i][0]), f_mono, 13, Color(1, 1, 1, 0.55 * k))
		_txt(Vector2(rx + 54, ry), String(rows[i][1]), f_mono_b, 14, Color(1, 1, 1, k))
	# strip charts over a 60 s window
	var charts := [[3, "ALTITUDE (ft)", 1.0 / U.FT, Color(0.4, 0.85, 1.0)], [4, "AIRSPEED (kt)", 1.0, Color(0.5, 1.0, 0.55)],
		[5, "VERTICAL SPEED (fpm)", 1.0 / U.FPM, Color(1.0, 0.7, 0.3)], [6, "PITCH (°)", 1.0, Color(0.9, 0.6, 1.0)], [7, "BANK (°)", 1.0, Color(1.0, 0.45, 0.45)]]
	var cy := py + 162.0
	var cw := pw - 24.0
	var chh := 52.0
	var win := 60.0
	for c in charts:
		var idx := int(c[0])
		var rng: Array = _ranges.get(idx, [0.0, 1.0])
		var lo := float(rng[0])
		var hi2 := float(rng[1])
		if idx in [6, 7]:
			var m := maxf(maxf(absf(lo), absf(hi2)), 10.0)
			lo = -m
			hi2 = m
		if hi2 - lo < 1.0:
			hi2 = lo + 1.0
		var cr := Rect2(px + 12, cy + 16, cw, chh)
		draw_rect(cr, Color(1, 1, 1, 0.04 * k))
		_txt(Vector2(cr.position.x, cy), String(c[1]), f_bold, 11, Color(c[3], 0.8 * k))
		if lo < 0.0 and hi2 > 0.0:
			var zy := cr.end.y - (0.0 - lo) / (hi2 - lo) * cr.size.y
			draw_line(Vector2(cr.position.x, zy), Vector2(cr.end.x, zy), Color(1, 1, 1, 0.15 * k), 1.0)
		var pts := PackedVector2Array()
		for s2 in samples:
			var stt := float(s2[0])
			if stt < st - win or stt > st:
				continue
			var xx := cr.end.x - (st - stt) / win * cr.size.x
			var yy := cr.end.y - (float(s2[idx]) - lo) / (hi2 - lo) * cr.size.y
			pts.append(Vector2(xx, clampf(yy, cr.position.y, cr.end.y)))
		if pts.size() >= 2:
			draw_polyline(pts, Color(c[3], k), 2.0, true)
		var val := float(s[idx]) * float(c[2])
		_txt(Vector2(cr.position.x, cy), U.fmt_int(int(val)) if absf(val) >= 100.0 else "%.1f" % val, f_mono_b, 12, Color(1, 1, 1, k), HORIZONTAL_ALIGNMENT_RIGHT, cw)
		cy += chh + 22.0
	# discrete parameters
	var chips := [["AP", "ON" if int(s[12]) == 1 else "OFF", int(s[12]) == 1], ["GEAR", "DOWN" if int(s[11]) == 1 else "UP", int(s[11]) == 1],
		["FLAPS", str(int(s[10])), true], ["THR", "%d%%" % int(float(s[9]) * 100.0), true]]
	var chx := px + 12.0
	for ch in chips:
		var cwid := (pw - 24.0 - 18.0) / 4.0
		draw_rect(Rect2(chx, cy, cwid, 34), Color(1, 1, 1, 0.06 * k))
		_txt(Vector2(chx, cy + 2), String(ch[0]), f_bold, 10, Color(1, 1, 1, 0.55 * k), HORIZONTAL_ALIGNMENT_CENTER, cwid)
		_txt(Vector2(chx, cy + 14), String(ch[1]), f_mono_b, 14, Color(0.45, 1.0, 0.55, k) if bool(ch[2]) else Color(1.0, 0.75, 0.25, k), HORIZONTAL_ALIGNMENT_CENTER, cwid)
		chx += cwid + 6.0
	_cvr_panel(k)
	_board_bug()


func _adi(c: Vector2, r: float, pitch: float, bank: float, k: float) -> void:
	var n := 40
	var pts_sky := PackedVector2Array()
	var pts_gnd := PackedVector2Array()
	var off := clampf(pitch, -40.0, 40.0) / 40.0 * r
	var rot := deg_to_rad(-bank)
	for i in n + 1:
		var a := TAU * float(i) / n
		var p := Vector2(cos(a), sin(a)) * r
		var q := p.rotated(-rot)
		if q.y + off < 0.0:
			pts_sky.append(c + p)
		else:
			pts_gnd.append(c + p)
	draw_circle(c, r, Color(0.55, 0.36, 0.18, k))
	var horizon_a := c + Vector2(-r * 1.2, -off).rotated(rot)
	var horizon_b := c + Vector2(r * 1.2, -off).rotated(rot)
	var sky := PackedVector2Array([horizon_a, horizon_b, horizon_b + Vector2(0, -r * 3).rotated(rot), horizon_a + Vector2(0, -r * 3).rotated(rot)])
	var clip := PackedVector2Array()
	for i2 in 48:
		var a2 := TAU * float(i2) / 48
		clip.append(c + Vector2(cos(a2), sin(a2)) * r)
	var inter := Geometry2D.intersect_polygons(sky, clip)
	for poly in inter:
		draw_colored_polygon(poly, Color(0.2, 0.5, 0.85, k))
	draw_line(horizon_a.lerp(horizon_b, 0.1), horizon_a.lerp(horizon_b, 0.9), Color(1, 1, 1, k), 1.5)
	draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.8 * k), 2.0)
	draw_line(c + Vector2(-r * 0.5, 0), c + Vector2(-r * 0.15, 0), Color(1, 0.85, 0.1, k), 3.0)
	draw_line(c + Vector2(r * 0.15, 0), c + Vector2(r * 0.5, 0), Color(1, 0.85, 0.1, k), 3.0)
	draw_circle(c, 2.5, Color(1, 0.85, 0.1, k))


func _cvr_panel(k: float) -> void:
	var r := Rect2(28, H - 196, 840, 150)
	draw_rect(r, Color(0.02, 0.04, 0.08, 0.78 * k))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(1.0, 0.69, 0.0, k))
	_txt(r.position + Vector2(12, 8), "COCKPIT VOICE RECORDER · TRANSCRIPT", f_bold, 12, Color(1, 1, 1, 0.7 * k))
	var shown := []
	for l in _lines:
		if String(l.get("style", "")) == "cvr" and float(l.t0) <= t and float(l.t0) >= float(seg.t0):
			shown.append(l)
	var recent := shown.slice(maxi(shown.size() - 5, 0))
	var y := r.position.y + 28.0
	var t_end := float(samples[samples.size() - 1][0]) if not samples.is_empty() else 0.0
	for l2 in recent:
		var rel := BroadcastPlayer.seg_sample_time(seg, float(l2.t0) - float(seg.t0), samples) - t_end
		var current := t <= float(l2.t1)
		var col := Color(1, 1, 1, (1.0 if current else 0.6) * k)
		var who := String(l2.name)
		var wcol := Color(1.0, 0.8, 0.3, k) if who in ["GPWS", "AURAL"] else (Color(0.5, 0.85, 1.0, k) if who in ["TWR", "APP", "GND", "CTR", "DEL"] else Color(0.6, 1.0, 0.65, k))
		_txt(Vector2(r.position.x + 12, y), "%+6.1f" % rel, f_mono, 14, Color(1, 1, 1, 0.5 * k))
		_txt(Vector2(r.position.x + 84, y), who, f_mono_b, 14, wcol)
		var tx := String(l2.text)
		if tx.length() > 78:
			tx = tx.substr(0, 76) + "…"
		_txt(Vector2(r.position.x + 150, y), tx, f_mono, 14, col)
		y += 22.0
	if recent.is_empty():
		_txt(Vector2(r.position.x + 12, y), "(no recorded speech in this period)", f_mono, 14, Color(1, 1, 1, 0.4 * k))


# ================================================================== safety board report cards
func _card(card: String) -> void:
	var lt := _lt()
	var k := _env(float(seg.t0), float(seg.t1) + 0.4, 0.6, 0.3)
	if card == "impact":
		_impact_box(k)
		return
	draw_rect(Rect2(0, 0, W, H), Color(0.015, 0.03, 0.06, (0.8 if card != "title" else 0.55) * k))
	var x := 150.0
	var w := W - 300.0
	var y := 96.0
	var gold := Color(1.0, 0.69, 0.0, k)
	var white := Color(1, 1, 1, k)
	var dim := Color(1, 1, 1, 0.7 * k)
	var ctx: Dictionary = program.get("ctx", {})
	match card:
		"title":
			_emblem(Vector2(W * 0.5, 190), 52.0)
			_txt(Vector2(0, 262), "CALDERRA TRANSPORT SAFETY BOARD", f_bold, 22, gold, HORIZONTAL_ALIGNMENT_CENTER, W)
			_txt(Vector2(0, 300), "AIRCRAFT ACCIDENT REPORT", f_head, 54, white, HORIZONTAL_ALIGNMENT_CENTER, W)
			_txt(Vector2(0, 372), "%s flight %s · %s · %s" % [ctx.get("airline", ""), ctx.get("num", ""), ctx.get("type", ""), String(ctx.get("reg", ""))], f_body, 24, dim, HORIZONTAL_ALIGNMENT_CENTER, W)
			_txt(Vector2(0, 408), "%s · %s" % [ctx.get("date", ""), ctx.get("place", "")], f_body, 22, dim, HORIZONTAL_ALIGNMENT_CENTER, W)
			_txt(Vector2(0, 470), String(program.get("tag", "")), f_bold, 18, gold, HORIZONTAL_ALIGNMENT_CENTER, W)
		"findings":
			_card_head(x, y, "FINDINGS", k)
			var items: Array = program.get("findings", [])
			var shown := 0
			for l in _lines:
				if l.has("item") and t >= float(l.t0) - 0.1:
					shown = maxi(shown, int(l.item) + 1)
			var yy := y + 70.0
			for i in mini(shown, items.size()):
				var rows := _wrap(String(items[i]), f_body, 22, w - 60.0)
				draw_circle(Vector2(x + 14, yy + 14), 13, Color(0.11, 0.3, 0.54, k))
				_txt(Vector2(x, yy + 2), str(i + 1), f_bold, 16, white, HORIZONTAL_ALIGNMENT_CENTER, 28)
				for rr in rows:
					_txt(Vector2(x + 44, yy), String(rr), f_body, 22, white)
					yy += 30.0
				yy += 12.0
		"cause":
			_card_head(x, y, "PROBABLE CAUSE", k)
			var rows2 := _wrap(String(program.get("cause", "")) + ".", f_head, 34, w)
			var yy2 := y + 90.0
			var reveal := _ease((lt - 1.2) / 0.8)
			for rr2 in rows2:
				_txt(Vector2(x, yy2), String(rr2), f_head, 34, Color(1, 1, 1, k * reveal))
				yy2 += 46.0
		"factors":
			_card_head(x, y, "CONTRIBUTING FACTORS AND RESPONSIBILITY", k)
			var fac: Array = program.get("factors", [])
			var yy3 := y + 70.0
			for f in fac.slice(0, 3):
				for rr3 in _wrap("• " + String(f), f_body, 20, w * 0.55):
					_txt(Vector2(x, yy3), String(rr3), f_body, 20, white)
					yy3 += 27.0
				yy3 += 8.0
			if fac.is_empty():
				_txt(Vector2(x, yy3), "No contributing factors were identified.", f_body, 20, dim)
			var sh: Dictionary = program.get("shares", {})
			var bx := x + w * 0.6
			var by := y + 74.0
			var labels := {"pilot": "Flight crew", "maintenance": "Maintenance", "weather": "Weather", "atc": "Air traffic control", "manufacturer": "Manufacturer"}
			var grow := _ease((lt - 0.8) / 1.5)
			for key in ["pilot", "maintenance", "weather", "atc", "manufacturer"]:
				var v := float(sh.get(key, 0.0))
				_txt(Vector2(bx, by), String(labels[key]), f_bold, 16, dim)
				draw_rect(Rect2(bx, by + 24, w * 0.38, 16), Color(1, 1, 1, 0.08 * k))
				draw_rect(Rect2(bx, by + 24, w * 0.38 * v * grow, 16), gold if key == "pilot" else Color(0.35, 0.65, 1.0, k))
				_txt(Vector2(bx, by), "%d%%" % int(v * 100.0 * grow), f_mono_b, 16, white, HORIZONTAL_ALIGNMENT_RIGHT, w * 0.38)
				by += 56.0
		"recs":
			_card_head(x, y, "SAFETY RECOMMENDATIONS", k)
			var recs: Array = program.get("recommendations", [])
			var yy4 := y + 70.0
			var n := 0
			for rc in recs.slice(0, 4):
				n += 1
				_txt(Vector2(x, yy4), "R%02d" % n, f_mono_b, 20, gold)
				for rr4 in _wrap(String(rc), f_body, 22, w - 80.0):
					_txt(Vector2(x + 70, yy4), String(rr4), f_body, 22, white)
					yy4 += 30.0
				yy4 += 14.0
		"remember":
			_txt(Vector2(0, 110), "IN MEMORY", f_bold, 22, gold, HORIZONTAL_ALIGNMENT_CENTER, W)
			_txt(Vector2(0, 146), "of the %s people who lost their lives" % U.fmt_int(int(ctx.get("fatal", 0))), f_body, 26, white, HORIZONTAL_ALIGNMENT_CENTER, W)
			var vic: Array = program.get("victims", [])
			var cols := 3
			var col_w := 330.0
			var gx := (W - cols * col_w) * 0.5
			var yy5 := 210.0
			var i5 := 0
			for v5 in vic.slice(0, 27):
				var cx := gx + (i5 % cols) * col_w
				var cyy := yy5 + (i5 / cols) * 34.0
				var fade := _ease((lt - 0.4 - i5 * 0.08) / 0.6)
				_txt(Vector2(cx, cyy), "%s, %d" % [v5.get("name", ""), int(v5.get("age", 0))], NewsStyle.font("serif", 500), 21, Color(1, 1, 1, 0.85 * k * fade), HORIZONTAL_ALIGNMENT_CENTER, col_w)
				i5 += 1
			if vic.size() > 27:
				_txt(Vector2(0, yy5 + 9 * 34.0 + 6), "and %d others" % (vic.size() - 27), f_body, 20, dim, HORIZONTAL_ALIGNMENT_CENTER, W)


func _card_head(x: float, y: float, title: String, k: float) -> void:
	_emblem(Vector2(x + 22, y + 22), 22.0)
	_txt(Vector2(x + 60, y + 2), title, f_head, 34, Color(1, 1, 1, k))
	draw_rect(Rect2(x, y + 54, 160, 3), Color(1.0, 0.69, 0.0, k))


func _impact_box(k: float) -> void:
	var ctx: Dictionary = program.get("ctx", {})
	var r := Rect2(W * 0.5 - 360, H - 230, 720, 92)
	draw_rect(r, Color(0.02, 0.04, 0.08, 0.82 * k))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color(1.0, 0.25, 0.2, k))
	_txt(r.position + Vector2(0, 10), "IMPACT", f_bold, 16, Color(1.0, 0.4, 0.35, k), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var items := [["SPEED", "%d kt" % int(ctx.get("impact_kt", 0))], ["DESCENT", "%s ft/min" % U.fmt_int(int(ctx.get("impact_fpm", 0)))],
		["PITCH", "%+d°" % int(ctx.get("impact_pitch", 0))], ["BANK", "%+d°" % int(ctx.get("impact_bank", 0))]]
	var cw := r.size.x / 4.0
	for i in 4:
		_txt(Vector2(r.position.x + i * cw, r.position.y + 36), String(items[i][0]), f_bold, 12, Color(1, 1, 1, 0.6 * k), HORIZONTAL_ALIGNMENT_CENTER, cw)
		_txt(Vector2(r.position.x + i * cw, r.position.y + 52), String(items[i][1]), f_mono_b, 22, Color(1, 1, 1, k), HORIZONTAL_ALIGNMENT_CENTER, cw)
	_board_bug()
