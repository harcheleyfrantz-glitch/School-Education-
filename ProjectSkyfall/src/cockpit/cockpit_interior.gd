class_name CockpitInterior
extends Node3D
## Fully modelled, interactive flight deck generated from the aircraft type: nose shell with
## windscreen and side windows cut along the pilots' sightlines, main panel with live screens,
## glareshield autopilot panel, overhead panel, pedestal levers, yokes or sidesticks, pedals and
## seats. Every switch is registered as a clickable control (see hit_test / Aircraft.cockpit_action).
## Body frame: +X right, +Y up, -Z forward (same as Aircraft).

const PANEL_TILT := 0.17
const LABEL_COL := Color(0.9, 0.92, 0.94)

var spec: Dictionary
var lay: Dictionary
var ck: Dictionary
var cat := ""
var style := ""
var fbw := false
var n_eng := 2
var E := Vector3.ZERO           # captain eye point
var floor_y := 0.0
var z_panel := 0.0
var c_panel := Color(0.3, 0.34, 0.38)
var c_dark := Color(0.055, 0.06, 0.065)
var c_shell := Color(0.6, 0.62, 0.64)
var c_trim := Color(0.24, 0.26, 0.29)
var mat: StandardMaterial3D
var mat_glass: StandardMaterial3D
var mat_screen: ShaderMaterial
var mat_ind: ShaderMaterial
var label_font: SystemFont
var mb: MeshBuilder
var controls: Array = []        # {id, label, kind, aabb}
var parts := {}                 # name -> Node3D for animated parts
var indicators := {}            # id -> MeshInstance3D
var viewport: SubViewport
var canvas: CockpitDisplays
var screens: Array[MeshInstance3D] = []
var dome: OmniLight3D
var floods: Array[OmniLight3D] = []
var _redraw_t := 0.0
var _box_cache := {}
var ac: Aircraft


func build(type_id: String, airline_code: String, quality: String = "high") -> void:
	spec = AircraftTypes.get_type(type_id)
	lay = CabinLayout.get_layout(type_id)
	ck = lay.cockpit
	cat = spec.category
	style = String(spec.cockpit)
	fbw = bool(spec.fbw)
	n_eng = int(spec.engine_count)
	floor_y = float(ck.floor_y)
	E = Vector3(-float(ck.seat_x), float(ck.eye_y), float(ck.eye_z))
	z_panel = E.z - (0.76 if cat != "trainer" else 0.72)
	name = "CockpitInterior"
	match style:
		"airbus":
			c_panel = Color(0.29, 0.33, 0.38)
			c_shell = Color(0.72, 0.75, 0.78)
			c_trim = Color(0.33, 0.37, 0.42)
		"boeing":
			c_panel = Color(0.33, 0.335, 0.34)
			c_shell = Color(0.74, 0.73, 0.7)
			c_trim = Color(0.36, 0.36, 0.37)
		"bizjet":
			c_panel = Color(0.2, 0.21, 0.23)
			c_shell = Color(0.82, 0.78, 0.7)
			c_trim = Color(0.4, 0.33, 0.26)
		"turboprop":
			c_panel = Color(0.27, 0.29, 0.31)
			c_shell = Color(0.7, 0.71, 0.72)
			c_trim = Color(0.34, 0.35, 0.37)
		"ga":
			c_panel = Color(0.1, 0.1, 0.11)
			c_shell = Color(0.66, 0.64, 0.6)
			c_trim = Color(0.26, 0.25, 0.24)
	mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true      # colours below are picked in sRGB
	mat.roughness = 0.78                 # flight-deck plastics and paint are matte
	mat.metallic_specular = 0.3
	mat_glass = StandardMaterial3D.new()
	mat_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_glass.albedo_color = Color(0.55, 0.65, 0.72, 0.1)
	mat_glass.roughness = 0.03
	mat_glass.metallic_specular = 1.0
	mat_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_ind = ShaderMaterial.new()
	mat_ind.shader = load("res://shaders/indicator.gdshader")
	label_font = SystemFont.new()
	label_font.font_names = PackedStringArray(["Roboto Condensed", "DejaVu Sans Condensed", "Arial Narrow", "sans-serif"])
	label_font.multichannel_signed_distance_field = true
	_setup_displays(quality)
	mb = MeshBuilder.new()
	_build_shell()
	if cat == "trainer":
		_build_ga()
	else:
		_build_main_panel()
		_build_glareshield()
		_build_overhead()
		_build_pedestal()
		_build_side_consoles()
		_build_flight_controls()
		_build_back_wall()
	_build_seats()
	_build_pedals()
	var mi := MeshInstance3D.new()
	mi.name = "Panels"
	mi.mesh = mb.commit()
	mi.material_override = mat
	add_child(mi)
	_build_lights()
	# interior ambient (see CabinInterior._build_interior_probe): daylight floods a flight deck
	# more than a cabin, so it is brighter and cooler here
	var zb := float(ck.back_z) if cat != "trainer" else float(lay.cabin_back)
	var zf := E.z - 2.8
	var top := _shell_point(0.0, E.z, 0.0).y
	var bottom := _shell_point(PI, E.z, 0.0).y
	add_child(CabinInterior.make_interior_probe("InteriorProbe", Vector3(0, (top + bottom) * 0.5, (zf + zb) * 0.5),
		Vector3(float(spec.fuse_w) + 0.4, top - bottom + 0.4, maxf(zb - zf, 1.0)), Color(0.9, 0.93, 0.97), 0.38))
	CabinInterior.tag_interior(self)


# ============================================================================== helpers
func _frame(o: Vector3, up: Vector3, n: Vector3) -> Transform3D:
	var u := up.normalized()
	var nn := n.normalized()
	var r := u.cross(nn).normalized()
	return Transform3D(Basis(r, u, nn), o)


func _fbox(fr: Transform3D, uvw: Vector3, size: Vector3, col: Color, b: MeshBuilder = null) -> void:
	(b if b else mb).add_box_xf(fr * Transform3D(Basis(), uvw), size, col)


func _fcyl(fr: Transform3D, a: Vector3, b: Vector3, r0: float, r1: float, col: Color, segs: int = 12, bld: MeshBuilder = null) -> void:
	(bld if bld else mb).add_cylinder(fr * a, fr * b, r0, r1, segs, col, true)


func _label(fr: Transform3D, uvw: Vector3, text: String, h: float = 0.0075, col: Color = LABEL_COL, parent: Node3D = null) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = label_font
	l.font_size = 40
	l.pixel_size = h / 40.0
	l.modulate = col
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.transform = fr * Transform3D(Basis(), uvw + Vector3(0, 0, 0.0012))
	(parent if parent else self).add_child(l)
	return l


func _ctl(id: String, label: String, kind: String, fr: Transform3D, uvw: Vector3, size: Vector3) -> void:
	var xf := fr * Transform3D(Basis(), uvw)
	var aabb := AABB(xf.origin, Vector3.ZERO)
	for sx in [-0.5, 0.5]:
		for sy in [-0.5, 0.5]:
			for sz in [-0.5, 0.5]:
				aabb = aabb.expand(xf * Vector3(sx * size.x, sy * size.y, sz * size.z))
	controls.append({"id": id, "label": label, "kind": kind, "aabb": aabb.grow(0.006)})


func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "%.4f,%.4f,%.4f" % [size.x, size.y, size.z]
	if not _box_cache.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		_box_cache[key] = bm
	return _box_cache[key]


func _ind(id: String, fr: Transform3D, uvw: Vector3, size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(size)
	mi.material_override = mat_ind
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = fr * Transform3D(Basis(), uvw)
	add_child(mi)
	mi.set_instance_shader_parameter("light_color", Vector3(col.r, col.g, col.b))
	indicators[id] = mi
	return mi


## Push button with a lit legend bar; registered as a control.
func _pb(id: String, label: String, fr: Transform3D, u: float, v: float, col: Color = Color(0.3, 0.75, 1.0), w: float = 0.028) -> void:
	_fbox(fr, Vector3(u, v, 0.004), Vector3(w + 0.006, w + 0.006, 0.008), c_dark)
	_fbox(fr, Vector3(u, v, 0.009), Vector3(w, w, 0.006), Color(0.12, 0.13, 0.14))
	_ind(id, fr, Vector3(u, v - w * 0.18, 0.0125), Vector3(w * 0.78, w * 0.26, 0.002), col)
	_label(fr, Vector3(u, v + w * 0.22, 0.0125), label, 0.0055)
	_ctl(id, label, "button", fr, Vector3(u, v, 0.01), Vector3(w, w, 0.02))


## Rotary knob with an index mark.
func _knob(id: String, label: String, fr: Transform3D, u: float, v: float, r: float = 0.011, show_label: bool = true) -> void:
	_fcyl(fr, Vector3(u, v, 0.0), Vector3(u, v, 0.012), r * 1.15, r, c_dark, 14)
	_fcyl(fr, Vector3(u, v, 0.012), Vector3(u, v, 0.02), r * 0.85, r * 0.75, Color(0.1, 0.105, 0.11), 14)
	_fbox(fr, Vector3(u, v + r * 0.55, 0.0205), Vector3(r * 0.16, r * 0.6, 0.002), Color(0.9, 0.9, 0.9))
	if show_label:
		_label(fr, Vector3(u, v + r * 1.9, 0.002), label, 0.0055)
	_ctl(id, label, "knob", fr, Vector3(u, v, 0.012), Vector3(r * 2.4, r * 2.4, 0.03))


## Toggle switch (bat-handle) whose lever node animates.
func _toggle(id: String, label: String, fr: Transform3D, u: float, v: float, guard: bool = false) -> void:
	_fbox(fr, Vector3(u, v, 0.002), Vector3(0.016, 0.022, 0.004), c_dark)
	var piv := Node3D.new()
	piv.transform = fr * Transform3D(Basis(), Vector3(u, v, 0.004))
	add_child(piv)
	var lb := MeshBuilder.new()
	lb.add_cylinder(Vector3.ZERO, Vector3(0, 0, 0.022), 0.0028, 0.0022, 8, Color(0.82, 0.82, 0.8))
	lb.add_sphere(Vector3(0, 0, 0.023), Vector3(0.0035, 0.0035, 0.0035), 8, 4, Color(0.85, 0.85, 0.83))
	var li := MeshInstance3D.new()
	li.mesh = lb.commit()
	li.material_override = mat
	piv.add_child(li)
	parts["sw:" + id] = piv
	if guard:
		_fbox(fr, Vector3(u, v + 0.004, 0.02), Vector3(0.02, 0.026, 0.002), Color(0.75, 0.12, 0.1, 1.0))
	_label(fr, Vector3(u, v + 0.02, 0.002), label, 0.005)
	_ctl(id, label, "toggle", fr, Vector3(u, v, 0.012), Vector3(0.02, 0.026, 0.03))


func _screen(kind: String, cell: int, fr: Transform3D, u: float, v: float, w: float, h: float) -> void:
	# bezel with buttons, then the glass screen mapped to an atlas cell
	_fbox(fr, Vector3(u, v, 0.006), Vector3(w + 0.03, h + 0.03, 0.012), c_dark)
	_fbox(fr, Vector3(u, v, 0.0125), Vector3(w + 0.012, h + 0.012, 0.002), Color(0.02, 0.022, 0.025))
	for k in 4:
		_fbox(fr, Vector3(u - w * 0.5 - 0.009, v + h * (0.3 - k * 0.2), 0.013), Vector3(0.006, 0.01, 0.004), Color(0.16, 0.17, 0.18))
	var rect: Rect2 = canvas.cells[cell].rect if cell < canvas.cells.size() else Rect2()
	var vs := Vector2(viewport.size)
	var uv0 := rect.position / vs
	var uv1 := rect.end / vs
	var smb := MeshBuilder.new()
	var o := Vector3(u, v, 0.0145)
	var n := Vector3(0, 0, 1)
	var c := Color.WHITE
	var p0 := fr * (o + Vector3(-w * 0.5, -h * 0.5, 0))
	var p1 := fr * (o + Vector3(w * 0.5, -h * 0.5, 0))
	var p2 := fr * (o + Vector3(w * 0.5, h * 0.5, 0))
	var p3 := fr * (o + Vector3(-w * 0.5, h * 0.5, 0))
	var nn := (fr.basis * n).normalized()
	var i0 := smb.add_vertex(p0, nn, c, Vector2(uv0.x, uv1.y))
	var i1 := smb.add_vertex(p1, nn, c, Vector2(uv1.x, uv1.y))
	var i2 := smb.add_vertex(p2, nn, c, Vector2(uv1.x, uv0.y))
	var i3 := smb.add_vertex(p3, nn, c, Vector2(uv0.x, uv0.y))
	smb.add_tri_idx(i0, i2, i1)
	smb.add_tri_idx(i0, i3, i2)
	var mi := MeshInstance3D.new()
	mi.mesh = smb.commit()
	mi.material_override = mat_screen
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Screen_" + kind
	add_child(mi)
	screens.append(mi)
	_ctl("screen_" + kind + str(cell), kind.to_upper(), "screen", fr, Vector3(u, v, 0.014), Vector3(w, h, 0.01))


# ============================================================================== displays
func _setup_displays(quality: String) -> void:
	var px := 384 if quality in ["high", "ultra"] else 256
	viewport = SubViewport.new()
	viewport.size = Vector2i(px * 4, px * 2)
	viewport.transparent_bg = false
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.gui_disable_input = true
	add_child(viewport)
	canvas = CockpitDisplays.new()
	canvas.size = Vector2(viewport.size)
	viewport.add_child(canvas)
	var kinds := ["pfd", "nd", "eicas", "sd", "nd", "pfd", "mcp", "mcdu"]
	if cat == "trainer":
		kinds = ["ga", "ga", "ga_engine", "nd", "radio", "pfd", "mcp", "mcdu"]
	for i in 8:
		var r := Rect2(Vector2((i % 4) * px, (i / 4) * px), Vector2(px, px))
		canvas.cells.append({"kind": kinds[i], "rect": r})
	if cat == "trainer":
		# the analogue panel spans two cells; the radio strip is a short band
		canvas.cells[0].rect = Rect2(Vector2(0, 0), Vector2(px * 2, px))
		canvas.cells[1].kind = "none"
		canvas.cells[4].rect = Rect2(Vector2(0, px), Vector2(px, px * 0.25))
	else:
		# MCP readout strip shares cell 6 with the standby instrument
		canvas.cells[6].rect = Rect2(Vector2(2 * px, px), Vector2(px, px * 0.22))
		canvas.cells.append({"kind": "isis", "rect": Rect2(Vector2(2 * px, px * 1.25), Vector2(px * 0.75, px * 0.75))})
		canvas.cells.append({"kind": "radio", "rect": Rect2(Vector2(3 * px, px), Vector2(px, px * 0.2))})
		canvas.cells.append({"kind": "mcdu", "rect": Rect2(Vector2(3 * px, px * 1.25), Vector2(px * 0.75, px * 0.75))})
	mat_screen = ShaderMaterial.new()
	mat_screen.shader = load("res://shaders/cockpit_display.gdshader")
	mat_screen.set_shader_parameter("screen", viewport.get_texture())


# ============================================================================== shell
var _rake_z0 := -INF                # windscreen rake: the crown may not rise above a line
var _rake_y0 := 0.0                 # through (_rake_z0, _rake_y0) climbing aft at _rake_slope
var _rake_slope := 0.0


func _shell_point(th: float, z: float, inset: float) -> Vector3:
	var L: float = spec.length
	var t := clampf((z - float(lay.nose_z)) / L, 0.0, 1.0)
	var sp := AircraftModel.section(spec, t)
	var rw := float(spec.fuse_w) * 0.5
	var rh := float(spec.fuse_h) * 0.5
	var sy := sp.y if cos(th) >= 0.0 else sp.z
	if cos(th) > 0.0 and _rake_z0 > -INF:
		# the crown comes down towards the nose along the raked windscreen line
		var lim := _rake_y0 + (z - _rake_z0) * _rake_slope
		sy = minf(sy, maxf((lim - sp.w) / rh, sp.y * 0.08))
	var o := Vector3(sin(th) * rw * sp.x, cos(th) * rh * sy + sp.w, z)
	if inset <= 0.0:
		return o
	var axis := Vector3(0, sp.w, z)
	var d := o - axis
	return axis + d * (1.0 - inset / maxf(d.length(), 0.2))


func _build_shell() -> void:
	## Nose shell on a fine (theta, z) grid. Windows come from a smooth field of the pilots'
	## sightlines. Every cell is clipped exactly along iso-contours - the glass edge, the outer
	## edge of the window frame (a fixed width in metres) and the sill line - so frames and trim
	## are crisp curves whatever the grid resolution. Normals are smooth across the lining.
	var smb := MeshBuilder.new()
	var gmb := MeshBuilder.new()
	var z0 := maxf(float(lay.nose_z) + 0.25, E.z - 2.6)
	if cat == "trainer":
		z0 = E.z - 1.25
	var z1 := float(ck.back_z) if cat != "trainer" else float(lay.cabin_back)
	var nz := int((z1 - z0) / 0.025)
	var nth := 220
	var inset := 0.07 if cat != "trainer" else 0.05
	var eyes := [E, Vector3(-E.x, E.y, E.z)]
	var band := 0.05 if cat != "trainer" else 0.035        # window frame width (m)
	_glaze_z0 = z0 + 0.04 if cat != "trainer" else z_panel - 0.08
	# raked windscreen: from just above the coaming (or the cowling) at the front of the shell
	_rake_z0 = z0
	if cat == "trainer":
		_rake_y0 = E.y - 0.2 - (z_panel - z0) * tan(deg_to_rad(10.0)) + 0.03
		_rake_slope = tan(deg_to_rad(30.0))
	else:
		_rake_y0 = E.y - 0.175
		_rake_slope = tan(deg_to_rad(38.0))
	var y_sill := E.y - (0.2 if cat != "trainer" else 0.24)
	var c_frame := Color(0.1, 0.105, 0.11)
	var c_reveal := Color(0.07, 0.072, 0.075)
	var c_upper := c_shell
	var c_lower := c_trim.lightened(0.25)
	var c_accent := c_trim.darkened(0.35)
	var pin := []
	var pout := []
	var fv := []
	var fv2 := []
	for j in nz + 1:
		var z := lerpf(z0, z1, float(j) / nz)
		var ri := []
		var ro := []
		var rf := []
		var r2 := []
		for i in nth + 1:
			var th := -PI + TAU * float(i) / nth
			var p := _shell_point(th, z, inset)
			ri.append(p)
			ro.append(_shell_point(th, z, 0.004))
			var wf := _window_fields(p, eyes)
			rf.append(wf.x)
			r2.append(wf.y)
		pin.append(ri)
		pout.append(ro)
		fv.append(rf)
		fv2.append(r2)
	# per-vertex smooth inward normals, and the field's gradient so the field can be turned into
	# a signed distance to the glass edge in metres (blurred: the field has kinks where windows meet)
	var nrm := []
	var grad := []
	for j in nz + 1:
		var rn := []
		var rg := PackedFloat32Array()
		var ja := maxi(j - 1, 0)
		var jb := mini(j + 1, nz)
		for i in nth + 1:
			var ia := maxi(i - 1, 0)
			var ib := mini(i + 1, nth)
			var p: Vector3 = pin[j][i]
			var du: Vector3 = (pin[j][ib] as Vector3) - pin[j][ia]
			var dv: Vector3 = (pin[jb][i] as Vector3) - pin[ja][i]
			var n := du.cross(dv).normalized()
			var axis := Vector3(0.0, _shell_point(0.0, p.z, 0.5).y * 0.5 + _shell_point(PI, p.z, 0.5).y * 0.5, p.z)
			if n.dot(axis - p) < 0.0:
				n = -n
			rn.append(n)
			var gu := (float(fv[j][ib]) - float(fv[j][ia])) / maxf(du.length(), 1e-4)
			var gv := (float(fv[jb][i]) - float(fv[ja][i])) / maxf(dv.length(), 1e-4)
			rg.append(sqrt(gu * gu + gv * gv))
		nrm.append(rn)
		grad.append(rg)
	for _blur in 3:
		var sm := []
		for j in nz + 1:
			var row := PackedFloat32Array()
			row.resize(nth + 1)
			for i in nth + 1:
				var acc := 0.0
				var cnt := 0.0
				for dj in [-1, 0, 1]:
					for di in [-1, 0, 1]:
						var jj := clampi(j + dj, 0, nz)
						var ii := clampi(i + di, 0, nth)
						acc += (grad[jj] as PackedFloat32Array)[ii]
						cnt += 1.0
				row[i] = acc / cnt
			sm.append(row)
		grad = sm
	var dist := []
	for j in nz + 1:
		var rd := []
		for i in nth + 1:
			var g := maxf((grad[j] as PackedFloat32Array)[i], 0.05)
			var d := float(fv[j][i]) / g
			# on a post between two windows the frames merge into one solid dark pillar
			if d < 0.0 and float(fv2[j][i]) / g > -band * 3.0:
				d = maxf(d, -band * 0.6)
			rd.append(d)
		dist.append(rd)
	for j2 in nz:
		var zc := lerpf(z0, z1, (float(j2) + 0.5) / nz)
		var axis_y := (_shell_point(0.0, zc, 0.5).y + _shell_point(PI, zc, 0.5).y) * 0.5
		for i2 in nth:
			var idx := [Vector2i(i2, j2), Vector2i(i2 + 1, j2), Vector2i(i2 + 1, j2 + 1), Vector2i(i2, j2 + 1)]
			var ins := []
			var outs := []
			var ns := []
			var ds := []
			var low := true
			for c in idx:
				var pi_: Vector3 = pin[c.y][c.x]
				ins.append(pi_)
				outs.append(pout[c.y][c.x])
				ns.append(nrm[c.y][c.x])
				ds.append(float(dist[c.y][c.x]))
				if pi_.y > floor_y - 0.12:
					low = false
			if low:
				continue
			var ctr: Vector3 = (ins[0] + ins[2]) * 0.5
			var inward := Vector3(-ctr.x, axis_y - ctr.y, 0.0)
			# glass on the outer skin
			var gl := _clip_poly(outs, ns, ds, 0.0, true)
			if (gl[0] as Array).size() >= 3:
				var gc := []
				for g2 in gl[0]:
					gc.append(Color.WHITE)
				_poly(gmb, gl[0], gc, inward)
			var wall := _clip_poly(ins, ns, ds, 0.0, false)
			if (wall[0] as Array).size() < 3:
				continue
			# frame band next to the glass, lining beyond it
			var fr := _clip_poly(wall[0], wall[1], wall[2], -band, true)
			_poly_smooth(smb, fr[0], fr[1], c_frame, inward)
			var lin := _clip_poly(wall[0], wall[1], wall[2], -band, false)
			if (lin[0] as Array).size() >= 3:
				# two-tone lining split at the sill line, with a narrow accent stripe
				var ys := []
				for q in lin[0]:
					ys.append((q as Vector3).y)
				var up := _clip_poly(lin[0], lin[1], ys, y_sill, true)
				_poly_smooth(smb, up[0], up[1], c_upper, inward)
				var dn := _clip_poly(lin[0], lin[1], ys, y_sill, false)
				if (dn[0] as Array).size() >= 3:
					var ys2 := []
					for q2 in dn[0]:
						ys2.append((q2 as Vector3).y)
					var acc := _clip_poly(dn[0], dn[1], ys2, y_sill - 0.014, true)
					_poly_smooth(smb, acc[0], acc[1], c_accent, inward)
					var lo := _clip_poly(dn[0], dn[1], ys2, y_sill - 0.014, false)
					_poly_smooth(smb, lo[0], lo[1], c_lower, inward)
			# reveal: the frame's depth between the lining and the glass along the window edge
			var cut_in := []
			var cut_out := []
			for k in 4:
				var k2 := (k + 1) % 4
				var fa: float = ds[k]
				var fb: float = ds[k2]
				if (fa < 0.0) != (fb < 0.0):
					var t := fa / (fa - fb)
					cut_in.append((ins[k] as Vector3).lerp(ins[k2], t))
					cut_out.append((outs[k] as Vector3).lerp(outs[k2], t))
			# (a saddle cell, with four crossings, is ambiguous: its neighbours carry the reveal)
			for pr in range(0, cut_in.size() - 1 if cut_in.size() == 2 else 0, 2):
				var a: Vector3 = cut_in[pr]
				var b: Vector3 = cut_in[pr + 1]
				var mid := (a + b) * 0.5
				var gside := Vector3.ZERO
				for k3 in 4:
					if float(ds[k3]) >= 0.0:
						gside += (ins[k3] as Vector3) - mid
				if gside.length_squared() < 1e-10:
					gside = -inward
				_quad_in(smb, a, b, cut_out[pr + 1], cut_out[pr], gside, c_reveal)
	# glareshield coaming deck runs forward to the windscreen, hiding the nose bay below
	if cat != "trainer":
		var yd := E.y - 0.205
		var zd := z0
		var deck := Color(0.045, 0.047, 0.05)
		while zd < z_panel - 0.05:
			var zn := minf(zd + 0.05, z_panel - 0.05)
			var wa := CabinLayout.half_width(spec, zd, yd) - inset - 0.005
			var wb := CabinLayout.half_width(spec, zn, yd) - inset - 0.005
			if wa > 0.02 and wb > 0.02:
				_quad_in(smb, Vector3(-wa, yd, zd), Vector3(wa, yd, zd), Vector3(wb, yd, zn), Vector3(-wb, yd, zn), Vector3.UP, deck)
			zd = zn
	# forward bulkhead closing the nose below the coaming (above it the view runs out through
	# the windscreen); a trainer looks out over a sloping engine cowling instead
	var cap_top := E.y - 0.205
	if cat == "trainer":
		var y_back := E.y - 0.2
		var y_front := y_back - (z_panel - z0) * tan(deg_to_rad(10.0))
		cap_top = y_front
		var cowl := Color(0.86, 0.87, 0.88)
		var zc := z0
		while zc < z_panel - 0.02:
			var zn2 := minf(zc + 0.05, z_panel - 0.02)
			var ya := lerpf(y_front, y_back, (zc - z0) / (z_panel - z0))
			var yb := lerpf(y_front, y_back, (zn2 - z0) / (z_panel - z0))
			var wa2 := CabinLayout.half_width(spec, zc, ya) - inset - 0.004
			var wb2 := CabinLayout.half_width(spec, zn2, yb) - inset - 0.004
			if wa2 > 0.02 and wb2 > 0.02:
				_quad_in(smb, Vector3(-wa2, ya, zc), Vector3(wa2, ya, zc), Vector3(wb2, yb, zn2), Vector3(-wb2, yb, zn2), Vector3.UP, cowl)
			zc = zn2
	var cap_pts := []
	var cap_ns := []
	var cap_ys := []
	for i3 in nth:
		var th3 := -PI + TAU * float(i3) / nth
		var cp := _shell_point(th3, z0, inset)
		cap_pts.append(cp)
		cap_ns.append(Vector3(0, 0, 1))
		cap_ys.append(cp.y)
	var capc := _clip_poly(cap_pts, cap_ns, cap_ys, cap_top, false)
	_poly_smooth(smb, capc[0], capc[1], c_trim.darkened(0.3), Vector3(0, 0, 1))
	# floor: dark carpet with a lighter kick strip along the walls
	var fz0 := E.z - (1.0 if cat != "trainer" else 0.9)
	var fhw := CabinLayout.half_width(spec, (fz0 + z1) * 0.5, floor_y + 0.05) - inset
	smb.add_rounded_box(Vector3(0, floor_y - 0.02, (fz0 + z1) * 0.5), Vector3(fhw * 2.0, 0.04, z1 - fz0), Color(0.11, 0.115, 0.125), 0.2, 8, 4)
	var mi := MeshInstance3D.new()
	mi.name = "Shell"
	mi.mesh = smb.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	add_child(mi)
	var gi := MeshInstance3D.new()
	gi.name = "Glass"
	gi.mesh = gmb.commit()
	gi.material_override = mat_glass
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gi)
	if cat != "trainer":
		_wipers(pout, fv, nth, nz)


static func _clip_poly(pts: Array, ns: Array, vals: Array, t: float, keep_above: bool) -> Array:
	## Sutherland-Hodgman clip of a convex polygon against a linearly interpolated scalar:
	## keeps the part where val >= t (keep_above) or val < t. Returns [points, normals, values].
	var op := []
	var on := []
	var ov := []
	var n := pts.size()
	for k in n:
		var k2 := (k + 1) % n
		var a: float = vals[k]
		var b: float = vals[k2]
		var ina := (a >= t) == keep_above
		var inb := (b >= t) == keep_above
		if ina:
			op.append(pts[k])
			on.append(ns[k])
			ov.append(a)
		if ina != inb and absf(b - a) > 1e-9:
			var u := (t - a) / (b - a)
			op.append((pts[k] as Vector3).lerp(pts[k2], u))
			on.append((ns[k] as Vector3).lerp(ns[k2], u).normalized())
			ov.append(t)
	return [op, on, ov]


func _poly_smooth(b: MeshBuilder, pts: Array, ns: Array, col: Color, facing: Vector3) -> void:
	## Convex polygon with per-vertex normals, wound to face `facing`.
	if pts.size() < 3:
		return
	var n := Vector3.ZERO
	for i in range(1, pts.size() - 1):
		n += ((pts[i] as Vector3) - pts[0]).cross((pts[i + 1] as Vector3) - pts[0])
	if n.length_squared() < 1e-14:
		return
	var flip := n.dot(facing) < 0.0
	var base := b.vcount()
	for i in pts.size():
		b.add_vertex(pts[i], ns[i], col)
	for i in range(1, pts.size() - 1):
		if flip:
			b.add_tri_idx(base, base + i, base + i + 1)
		else:
			b.add_tri_idx(base, base + i + 1, base + i)


func _quad_in(b: MeshBuilder, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, facing: Vector3, col: Color) -> void:
	var n := (p1 - p0).cross(p3 - p0)
	if n.dot(facing) < 0.0:
		b.add_quad(p0, p3, p2, p1, col)
	else:
		b.add_quad(p0, p1, p2, p3, col)


func _poly(b: MeshBuilder, pts: Array, cols: Array, facing: Vector3) -> void:
	var n := Vector3.ZERO
	for i in range(1, pts.size() - 1):
		n += ((pts[i] as Vector3) - pts[0]).cross((pts[i + 1] as Vector3) - pts[0])
	if n.length_squared() < 1e-14:
		return
	var flip := n.dot(facing) < 0.0
	var nn := n.normalized() * (-1.0 if flip else 1.0)
	var base := b.vcount()
	for i in pts.size():
		b.add_vertex(pts[i], nn, cols[i])
	for i in range(1, pts.size() - 1):
		# MeshBuilder faces are clockwise when seen from the front
		if flip:
			b.add_tri_idx(base, base + i, base + i + 1)
		else:
			b.add_tri_idx(base, base + i + 1, base + i)


## Positive inside a window, negative on the wall (roughly metres-scaled near the edges).
func _window_field(p: Vector3, eyes: Array) -> float:
	return _window_fields(p, eyes).x


## x: the field of the nearest window; y: the field of the next nearest, different window
## (high on the posts between two windows).
func _window_fields(p: Vector3, eyes: Array) -> Vector2:
	var best := -1.0
	var second := -1.0
	var wins := []
	match cat:
		"trainer":
			wins = [[0.0, 37.0, 8.0, 16.0], [83.0, 36.0, 0.0, 22.0], [136.0, 12.0, 3.0, 16.0]]
		"bizjet":
			wins = [[2.0, 27.0, 1.0, 15.0], [52.0, 13.0, 0.0, 10.0], [76.0, 7.0, 0.0, 7.5]]
		"turboprop", "regional":
			wins = [[1.0, 28.0, 2.0, 17.0], [54.0, 15.0, 1.0, 12.0], [82.0, 9.0, 1.0, 9.0]]
		_:
			wins = [[1.0, 29.0, 2.5, 18.5], [55.0, 16.5, 1.5, 13.5], [87.5, 10.0, 1.5, 10.0]]
	# the posts that matter lie between neighbouring windows on the same side, so the runner-up
	# is taken from the windows of the eye on this side only
	for k in eyes.size():
		var eye: Vector3 = eyes[k]
		var d := (p - eye).normalized()
		var az := rad_to_deg(atan2(d.x, -d.z))
		var el := rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))
		var outb := -az if k == 0 else az
		var same_side := (p.x < 0.0) == (k == 0)
		for w in wins:
			var nx := absf(outb - float(w[0])) / float(w[1])
			var ny := absf(el - float(w[2])) / float(w[3])
			var nrm := pow(pow(nx, 5.0) + pow(ny, 5.0), 0.2)
			var v := (1.0 - nrm) * 0.5
			if v > best:
				if same_side:
					second = best
				best = v
			elif v > second and same_side:
				second = v
	# centre windscreen post
	if cat != "trainer":
		var post := (absf(p.x) - 0.035) * 3.0
		if post < best:
			second = maxf(second, best)
			best = post
	# glazing starts just ahead of the glareshield; the nose further forward is solid
	var nose := (p.z - _glaze_z0) * 4.0
	best = minf(best, nose)
	second = minf(second, nose)
	return Vector2(best, second)


func _wipers(pout: Array, fv: Array, nth: int, nz: int) -> void:
	var wmb := MeshBuilder.new()
	for sx in [-1.0, 1.0]:
		var best := Vector3.ZERO
		var by := INF
		for j in nz + 1:
			for i in nth + 1:
				if float(fv[j][i]) < 0.02:
					continue
				var p: Vector3 = pout[j][i]
				var eye := Vector3(sx * absf(E.x), E.y, E.z)
				var el := (p - eye).normalized().y
				if signf(p.x) == sx and absf(p.x - sx * 0.42) < 0.16 and p.z < E.z - 0.5 and el < by:
					by = el
					best = p
		if by < INF:
			var base := best + Vector3(sx * 0.12, -0.03, 0.02)
			var tip := best + Vector3(-sx * 0.2, 0.0, -0.02)
			wmb.add_cylinder(base, tip, 0.008, 0.006, 6, Color(0.04, 0.04, 0.04), true)
			wmb.add_box(base.lerp(tip, 0.6) + Vector3(0, 0.006, 0), Vector3(0.34, 0.014, 0.012), Color(0.04, 0.04, 0.04))
	var mi := MeshInstance3D.new()
	mi.mesh = wmb.commit()
	mi.material_override = mat
	add_child(mi)


# ============================================================================== main panel
func _panel_frame(v_off: float = 0.0) -> Transform3D:
	var o := Vector3(0, E.y - 0.45 + v_off, z_panel)
	return _frame(o, Vector3(0, cos(PANEL_TILT), -sin(PANEL_TILT)), Vector3(0, sin(PANEL_TILT), cos(PANEL_TILT)))


func _build_main_panel() -> void:
	var fr := _panel_frame()
	var hw := minf(CabinLayout.half_width(spec, z_panel, E.y - 0.4) - 0.1, 1.05)
	var bottom := floor_y + 0.55 - (E.y - 0.45)
	var top := 0.27
	var hgt := top - bottom
	# panel slab with a subtle inset border
	_fbox(fr, Vector3(0, (top + bottom) * 0.5, -0.03), Vector3(hw * 2.0, hgt, 0.06), c_panel)
	_fbox(fr, Vector3(0, bottom + 0.012, 0.002), Vector3(hw * 2.0 - 0.02, 0.02, 0.004), c_panel.darkened(0.25))
	# knee panel below
	var kfr := _frame(Vector3(0, floor_y + 0.3, z_panel + 0.1), Vector3(0, 1, 0.35), Vector3(0, -0.35, 1))
	_fbox(kfr, Vector3(0, 0, -0.03), Vector3(hw * 2.0, 0.48, 0.05), c_trim)
	var w := 0.205
	var y := 0.0
	var bizjet := cat == "bizjet"
	if bizjet:
		w = 0.21
		_screen("pfd", 0, fr, -0.53, y, w, w)
		_screen("nd", 1, fr, -0.29, y, w, w)
		_screen("eicas", 2, fr, 0.29, y, w, w)
		_screen("pfd", 5, fr, 0.53, y, w, w)
		_screen("sd", 3, fr, 0.0, -0.06, 0.16, 0.16)
	else:
		_screen("pfd", 0, fr, -0.7, y, w, w)
		_screen("nd", 1, fr, -0.46, y, w, w)
		_screen("eicas", 2, fr, 0.0, y + 0.01, w, w)
		_screen("nd", 4, fr, 0.46, y, w, w)
		_screen("pfd", 5, fr, 0.7, y, w, w)
		_screen("sd", 3, fr, 0.0, y - 0.235, w, w)
	# standby instrument and clock
	_screen("isis", 8, fr, -0.2, y + 0.06, 0.085, 0.085)
	_fcyl(fr, Vector3(-0.2, -0.085, 0.0), Vector3(-0.2, -0.085, 0.012), 0.032, 0.03, c_dark, 18)
	_fcyl(fr, Vector3(-0.2, -0.085, 0.012), Vector3(-0.2, -0.085, 0.0135), 0.027, 0.027, Color(0.02, 0.02, 0.02), 18)
	_label(fr, Vector3(-0.2, -0.085, 0.015), "CLOCK", 0.006)
	# landing gear lever with three-green indication
	var gu := 0.2 if not bizjet else 0.15
	var gv := -0.12
	_fbox(fr, Vector3(gu, gv, 0.004), Vector3(0.07, 0.17, 0.008), c_panel.darkened(0.15))
	_fbox(fr, Vector3(gu, gv, 0.009), Vector3(0.012, 0.13, 0.004), Color(0.03, 0.03, 0.03))
	var gl := Node3D.new()
	gl.transform = fr * Transform3D(Basis(), Vector3(gu, gv, 0.012))
	add_child(gl)
	var glb := MeshBuilder.new()
	glb.add_box(Vector3(0, 0, 0.02), Vector3(0.008, 0.008, 0.04), Color(0.8, 0.8, 0.8))
	glb.add_cylinder(Vector3(-0.012, 0, 0.045), Vector3(0.012, 0, 0.045), 0.019, 0.019, 16, Color(0.92, 0.92, 0.9), true)
	var gli := MeshInstance3D.new()
	gli.mesh = glb.commit()
	gli.material_override = mat
	gl.add_child(gli)
	parts["gear"] = gl
	_label(fr, Vector3(gu, gv + 0.095, 0.009), "L/G", 0.007)
	_label(fr, Vector3(gu, gv - 0.077, 0.009), "UP     DN", 0.005)
	_ctl("gear", "LANDING GEAR", "lever", fr, Vector3(gu, gv, 0.03), Vector3(0.06, 0.16, 0.06))
	if bool(spec.gear_retract):
		for g in 3:
			var gx := gu + 0.055 + (g - 1) * 0.022
			_ind("gear_dn%d" % g, fr, Vector3(gx, gv + 0.03 + (0.012 if g == 1 else 0.0), 0.009), Vector3(0.016, 0.012, 0.004), Color(0.1, 1.0, 0.3))
			_ind("gear_tr%d" % g, fr, Vector3(gx, gv + 0.012 + (0.012 if g == 1 else 0.0), 0.009), Vector3(0.016, 0.01, 0.004), Color(1.0, 0.15, 0.1))
	# autobrake and miscellaneous switches
	var abr := ["LO", "MED", "MAX"]
	for i in 3:
		_pb("autobrake_%d" % (i + 1), abr[i], fr, -0.2 - 0.0 + (i - 1) * 0.036, -0.2, Color(0.2, 1.0, 0.4), 0.026)
	_pb("brake_fan", "BRK FAN", fr, gu + 0.08, -0.2, Color(0.95, 0.95, 0.95), 0.024)
	_pb("terr", "TERR", fr, -0.5, -0.155, Color(0.95, 0.95, 0.95), 0.024)
	_knob("disp_brt", "BRT", fr, -0.85, -0.12, 0.009)
	# brake pressure triple gauge
	_fcyl(fr, Vector3(gu, -0.29, 0.0), Vector3(gu, -0.29, 0.01), 0.028, 0.026, c_dark, 16)
	_label(fr, Vector3(gu, -0.29, 0.0115), "BRAKES", 0.0045)
	# panel screws, seams and labels add realism
	for sx in [-1.0, 1.0]:
		_fbox(fr, Vector3(sx * (hw - 0.02), 0.0, 0.002), Vector3(0.004, hgt - 0.05, 0.004), c_panel.darkened(0.3))
	_label(fr, Vector3(0.0, top - 0.025, 0.002), String(spec.name).to_upper(), 0.0065, Color(0.75, 0.78, 0.8))


# ============================================================================== glareshield + MCP
func _build_glareshield() -> void:
	var hw := minf(CabinLayout.half_width(spec, z_panel - 0.1, E.y - 0.18) - 0.08, 1.08)
	var gy := E.y - 0.18
	# padded glareshield coaming
	var top_fr := _frame(Vector3(0, gy, z_panel - 0.12), Vector3(0, 0, -1), Vector3(0, 1, 0))
	mb.add_rounded_box(Vector3(0, gy - 0.012, z_panel - 0.12), Vector3(hw * 2.0, 0.034, 0.32), Color(0.07, 0.072, 0.075), 0.25, 24, 8)
	mb.add_rounded_box(Vector3(0, gy - 0.022, z_panel + 0.035), Vector3(hw * 2.0 + 0.02, 0.06, 0.07), Color(0.075, 0.078, 0.08), 0.45, 24, 8)
	var face := _frame(Vector3(0, gy - 0.075, z_panel + 0.055), Vector3(0, 1, 0.08), Vector3(0, -0.08, 1))
	_fbox(face, Vector3(0, 0, -0.03), Vector3(hw * 2.0, 0.11, 0.06), Color(0.09, 0.095, 0.1))
	# autopilot control panel (FCU / MCP)
	var mw := 0.86 if cat != "bizjet" else 0.72
	_fbox(face, Vector3(0, 0, 0.005), Vector3(mw, 0.095, 0.012), c_panel)
	var rect: Rect2 = canvas.cells[6].rect
	var vs := Vector2(viewport.size)
	var smb := MeshBuilder.new()
	var o := Vector3(0, 0.022, 0.0118)
	var sw := mw * 0.82
	var sh := 0.026
	var nn := (face.basis * Vector3(0, 0, 1)).normalized()
	var uv0 := rect.position / vs
	var uv1 := rect.end / vs
	var i0 := smb.add_vertex(face * (o + Vector3(-sw * 0.5, -sh * 0.5, 0)), nn, Color.WHITE, Vector2(uv0.x, uv1.y))
	var i1 := smb.add_vertex(face * (o + Vector3(sw * 0.5, -sh * 0.5, 0)), nn, Color.WHITE, Vector2(uv1.x, uv1.y))
	var i2 := smb.add_vertex(face * (o + Vector3(sw * 0.5, sh * 0.5, 0)), nn, Color.WHITE, Vector2(uv1.x, uv0.y))
	var i3 := smb.add_vertex(face * (o + Vector3(-sw * 0.5, sh * 0.5, 0)), nn, Color.WHITE, Vector2(uv0.x, uv0.y))
	smb.add_tri_idx(i0, i2, i1)
	smb.add_tri_idx(i0, i3, i2)
	var smi := MeshInstance3D.new()
	smi.mesh = smb.commit()
	smi.material_override = mat_screen
	add_child(smi)
	screens.append(smi)
	var k := mw * 0.82 / 4.0
	var kx := -mw * 0.41
	_knob("spd_knob", "SPD", face, kx + k * 0.5, -0.02, 0.012, false)
	_knob("hdg_knob", "HDG", face, kx + k * 1.5, -0.02, 0.012, false)
	_knob("alt_knob", "ALT", face, kx + k * 2.5, -0.02, 0.012, false)
	_knob("vs_wheel", "V/S", face, kx + k * 3.5, -0.02, 0.012, false)
	var btn_y := -0.03
	_pb("spd_mach", "SPD/MACH", face, kx + k * 0.5 + 0.035, btn_y, Color(0.3, 1.0, 0.4), 0.02)
	_pb("lnav", "LNAV" if style != "airbus" else "NAV", face, kx + k * 1.5 + 0.035, btn_y, Color(0.3, 1.0, 0.4), 0.02)
	_pb("loc", "LOC", face, kx + k * 1.5 - 0.035, btn_y, Color(0.3, 1.0, 0.4), 0.02)
	_pb("ap", "AP", face, kx + k * 2.0, 0.01, Color(0.3, 1.0, 0.4), 0.024)
	_pb("athr", "A/THR", face, kx + k * 2.0, -0.025, Color(0.3, 1.0, 0.4), 0.022)
	_pb("flch", "LVL CHG" if style != "airbus" else "EXPED", face, kx + k * 2.5 + 0.035, btn_y, Color(0.3, 1.0, 0.4), 0.02)
	_pb("alt_hold", "ALT HOLD", face, kx + k * 2.5 - 0.035, btn_y, Color(0.3, 1.0, 0.4), 0.02)
	_pb("vs_mode", "V/S", face, kx + k * 3.5 + 0.035, btn_y, Color(0.3, 1.0, 0.4), 0.02)
	_pb("appr", "APP", face, kx + k * 3.0, 0.01, Color(0.3, 1.0, 0.4), 0.022)
	_pb("hdg_mode", "HDG SEL", face, kx + k * 1.0, 0.01, Color(0.3, 1.0, 0.4), 0.02)
	# EFIS panels and master warning/caution for each pilot
	for side in [-1.0, 1.0]:
		var ex = side * (mw * 0.5 + 0.13)
		_fbox(face, Vector3(ex, 0, 0.004), Vector3(0.2, 0.09, 0.01), c_panel)
		_knob("nd_range_" + ("l" if side < 0 else "r"), "RANGE", face, ex + 0.05, -0.012, 0.01)
		_knob("baro_" + ("l" if side < 0 else "r"), "BARO", face, ex - 0.05, -0.012, 0.01)
		_pb("fd_" + ("l" if side < 0 else "r"), "FD", face, ex, 0.02, Color(0.3, 1.0, 0.4), 0.02)
		_pb("wxr_" + ("l" if side < 0 else "r"), "WXR", face, ex, -0.022, Color(0.3, 1.0, 0.4), 0.018)
		var wx = side * (mw * 0.5 + 0.3)
		_fbox(face, Vector3(wx, 0, 0.004), Vector3(0.075, 0.09, 0.01), c_panel)
		_ind("master_warn_" + ("l" if side < 0 else "r"), face, Vector3(wx, 0.018, 0.012), Vector3(0.05, 0.026, 0.008), Color(1.0, 0.1, 0.08))
		_label(face, Vector3(wx, 0.018, 0.0165), "MASTER\nWARN", 0.0055, Color(0.15, 0.02, 0.02))
		_ctl("master_warn", "MASTER WARNING", "button", face, Vector3(wx, 0.018, 0.012), Vector3(0.05, 0.026, 0.02))
		_ind("master_caut_" + ("l" if side < 0 else "r"), face, Vector3(wx, -0.016, 0.012), Vector3(0.05, 0.026, 0.008), Color(1.0, 0.65, 0.05))
		_label(face, Vector3(wx, -0.016, 0.0165), "MASTER\nCAUT", 0.0055, Color(0.18, 0.1, 0.0))
		_ctl("master_caut", "MASTER CAUTION", "button", face, Vector3(wx, -0.016, 0.012), Vector3(0.05, 0.026, 0.02))



# ============================================================================== overhead panel
func _build_overhead() -> void:
	var front := Vector3(0, E.y + 0.5, E.z - 0.6)
	var back := Vector3(0, E.y + 0.78, E.z + 0.48)
	var d := (back - front).normalized()
	var n := Vector3(0, -d.z, d.y).normalized()
	if n.y > 0.0:
		n = -n
	var mid := (front + back) * 0.5
	var fr := _frame(mid, d, n)
	var length := front.distance_to(back)
	var w := 0.82
	_fbox(fr, Vector3(0, 0, -0.03), Vector3(w, length, 0.06), c_panel)
	# section frames
	var rows := [
		["EXT LT", [["strobe", "STROBE"], ["beacon", "BEACON"], ["wing_lt", "WING"], ["nav_lt", "NAV & LOGO"], ["rwy_lt", "RWY TURN OFF"], ["land_lt", "LAND"], ["taxi_lt", "NOSE"]]],
		["SIGNS / ANTI ICE", [["seatbelt", "SEAT BELTS"], ["nosmoking", "NO SMOKING"], ["emer_lt", "EMER EXIT LT"], ["wing_ai", "WING A.ICE"], ["eng_ai", "ENG A.ICE"], ["probe_heat", "PROBE HEAT"]]],
		["APU / AIR", [["apu_master", "APU MASTER"], ["apu_start", "APU START"], ["apu_bleed", "APU BLEED"], ["pack1", "PACK 1"], ["pack2", "PACK 2"], ["press_mode", "PRESS MAN"]]],
		["FUEL", [["pump_l", "L TK PUMPS"], ["xfeed", "X FEED"], ["pump_c", "CTR TK PUMPS"], ["pump_r", "R TK PUMPS"]]],
		["HYD", [["hyd_a", "ENG 1 PUMP"], ["ptu", "PTU"], ["hyd_b", "ENG 2 PUMP"], ["elec_pump", "ELEC PUMP"]]],
		["ELEC", [["bat", "BAT"], ["ext_pwr", "EXT PWR"], ["gen1", "GEN 1"], ["apu_gen", "APU GEN"], ["gen2", "GEN 2"]]],
		["ENG FIRE / OXY", [["fire1", "ENG 1 FIRE"], ["agent1", "AGENT 1"], ["agent2", "AGENT 2"], ["fire2", "ENG 2 FIRE"], ["pax_oxy", "MASK MAN ON"], ["crew_oxy", "CREW SUPPLY"]]],
		["CABIN", [["cabin_call", "CALL CABIN"], ["pa", "PA"], ["dome", "DOME"], ["flood", "FLOOD"], ["evac", "EVAC CMD"]]],
	]
	var nrows := rows.size()
	var pitch := (length - 0.08) / nrows
	for ri in nrows:
		var v := length * 0.5 - 0.06 - ri * pitch
		var row: Array = rows[ri]
		# each system gets its own inset sub-panel with a white outline
		var sub := Vector3(0, v - pitch * 0.02, 0.0015)
		_fbox(fr, sub, Vector3(w - 0.03, pitch * 0.86, 0.003), c_panel.darkened(0.08))
		for e in [-1.0, 1.0]:
			_fbox(fr, sub + Vector3(0, e * pitch * 0.43, 0.002), Vector3(w - 0.03, 0.0025, 0.002), Color(0.82, 0.84, 0.86))
			_fbox(fr, sub + Vector3(e * (w - 0.03) * 0.5, 0, 0.002), Vector3(0.0025, pitch * 0.86, 0.002), Color(0.82, 0.84, 0.86))
		_label(fr, Vector3(-w * 0.5 + 0.075, v + pitch * 0.3, 0.0045), String(row[0]), 0.0065)
		var items: Array = row[1]
		var ni := items.size()
		for k in ni:
			var it: Array = items[k]
			var u := -w * 0.5 + 0.1 + (w - 0.16) * (float(k) + 0.5) / ni
			var col := Color(0.35, 0.75, 1.0)
			if String(it[0]).begins_with("fire"):
				col = Color(1.0, 0.12, 0.1)
				_fbox(fr, Vector3(u, v - 0.012, 0.012), Vector3(0.05, 0.03, 0.022), Color(0.7, 0.08, 0.06))
				_label(fr, Vector3(u, v - 0.012, 0.0235), String(it[1]), 0.006, Color(1, 1, 1))
				_ind(String(it[0]), fr, Vector3(u, v + 0.012, 0.012), Vector3(0.044, 0.01, 0.004), col)
				_ctl(String(it[0]), String(it[1]), "button", fr, Vector3(u, v - 0.012, 0.015), Vector3(0.05, 0.03, 0.03))
				continue
			if String(it[0]) in ["pax_oxy", "evac"]:
				_fbox(fr, Vector3(u, v - 0.012, 0.024), Vector3(0.036, 0.036, 0.002), Color(0.8, 0.12, 0.1))
			_pb(String(it[0]), String(it[1]), fr, u, v - 0.012, col, 0.032)
	# engine start selector and engine anti-ice for 4-engine types
	if n_eng > 2:
		_label(fr, Vector3(w * 0.5 - 0.08, length * 0.5 - 0.04, 0.002), "4 ENG", 0.005)


# ============================================================================== pedestal
func _build_pedestal() -> void:
	var hw := 0.2 if cat != "bizjet" else 0.17
	var zf := z_panel + 0.06
	var zr := E.z + 0.45
	var top_front := floor_y + 0.86
	var top_rear := floor_y + 0.72
	# body: sloped front face, quadrant, flat rear
	var pts_side := [Vector2(zf, floor_y), Vector2(zf, floor_y + 0.62), Vector2(zf + 0.18, top_front), Vector2(E.z - 0.05, top_front - 0.02), Vector2(E.z + 0.02, top_rear), Vector2(zr, top_rear), Vector2(zr, floor_y)]
	for sx in [-hw, hw]:
		# side walls as a fan polygon
		var c0 := Vector3(sx, (floor_y + top_rear) * 0.5, (zf + zr) * 0.5)
		for i in pts_side.size():
			var a2: Vector2 = pts_side[i]
			var b2: Vector2 = pts_side[(i + 1) % pts_side.size()]
			var pa := Vector3(sx, a2.y, a2.x)
			var pb := Vector3(sx, b2.y, b2.x)
			var nrm := Vector3(signf(sx), 0, 0)
			var i0 := mb.add_vertex(c0, nrm, c_panel.darkened(0.35))
			var i1 := mb.add_vertex(pa, nrm, c_panel.darkened(0.35))
			var i2 := mb.add_vertex(pb, nrm, c_panel.darkened(0.35))
			if ((pa - c0).cross(pb - c0)).dot(nrm) > 0.0:
				mb.add_tri_idx(i0, i2, i1)
			else:
				mb.add_tri_idx(i0, i1, i2)
	for i3 in range(1, pts_side.size() - 1):
		var a3: Vector2 = pts_side[i3]
		var b3: Vector2 = pts_side[i3 + 1]
		var p0 := Vector3(-hw, a3.y, a3.x)
		var p1 := Vector3(hw, a3.y, a3.x)
		var p2 := Vector3(hw, b3.y, b3.x)
		var p3 := Vector3(-hw, b3.y, b3.x)
		var nn := (p1 - p0).cross(p3 - p0)
		if nn.y < 0.0 and nn.z < 0.1:
			mb.add_quad(p0, p3, p2, p1, c_panel.darkened(0.22))
		else:
			mb.add_quad(p0, p1, p2, p3, c_panel.darkened(0.22))
	# rounded edge trims along the pedestal top
	for sx4 in [-hw, hw]:
		mb.add_cylinder(Vector3(sx4, top_front, zf + 0.18), Vector3(sx4, top_front - 0.02, E.z - 0.05), 0.012, 0.012, 8, c_panel.darkened(0.4), true)
		mb.add_cylinder(Vector3(sx4, top_rear, E.z + 0.02), Vector3(sx4, top_rear, zr), 0.012, 0.012, 8, c_panel.darkened(0.4), true)
	# front sloped face: system display page buttons and the two MCDUs
	var slope_fr := _frame(Vector3(0, floor_y + 0.75, zf + 0.09), Vector3(0, 0.5, -0.87), Vector3(0, 0.87, 0.5))
	var pages := ["ENG", "BLEED", "PRESS", "ELEC", "HYD", "FUEL", "DOOR", "WHEEL"]
	for i4 in pages.size():
		_pb("sd_" + pages[i4], pages[i4], slope_fr, -0.16 + i4 * 0.046, 0.075, Color(0.95, 0.95, 0.95), 0.022)
	var mcdu_fr := _frame(Vector3(0, floor_y + 0.8, E.z - 0.36), Vector3(0, 0.82, -0.57), Vector3(0, 0.57, 0.82))
	for sx2 in [-0.1, 0.1]:
		_fbox(mcdu_fr, Vector3(sx2, 0.0, 0.004), Vector3(0.15, 0.17, 0.01), c_dark)
		var rect: Rect2 = canvas.cells[canvas.cells.size() - 1].rect
		_screen_quad(mcdu_fr, Vector3(sx2, 0.032, 0.0095), 0.11, 0.08, rect)
		for r in 4:
			for c in 5:
				_fbox(mcdu_fr, Vector3(sx2 - 0.05 + c * 0.025, -0.03 - r * 0.014, 0.011), Vector3(0.018, 0.01, 0.004), Color(0.2, 0.21, 0.22))
		_ctl("mcdu", "FLIGHT MANAGEMENT", "screen", mcdu_fr, Vector3(sx2, 0, 0.01), Vector3(0.15, 0.17, 0.02))
	# thrust quadrant
	var qz := E.z - 0.22
	var qy := top_front - 0.02
	var qfr := _frame(Vector3(0, qy, qz), Vector3(0, 0, -1), Vector3(0, 1, 0))
	_fbox(qfr, Vector3(0, 0, 0.004), Vector3(hw * 2.0 - 0.02, 0.24, 0.008), Color(0.08, 0.085, 0.09))
	for i5 in n_eng:
		var lx := (float(i5) - (n_eng - 1) * 0.5) * (0.05 if n_eng <= 2 else 0.036)
		_fbox(qfr, Vector3(lx, 0, 0.01), Vector3(0.008, 0.2, 0.004), Color(0.02, 0.02, 0.02))
		var piv := Node3D.new()
		piv.position = Vector3(lx, qy - 0.1, qz)
		add_child(piv)
		var lb := MeshBuilder.new()
		var hwid := 0.036 if n_eng <= 2 else 0.027
		lb.add_rounded_box(Vector3(0, 0.12, 0), Vector3(0.014, 0.24, 0.022), Color(0.5, 0.51, 0.53), 0.4, 8, 6)
		lb.add_rounded_box(Vector3(0, 0.255, -0.004), Vector3(hwid, 0.04, 0.052), Color(0.07, 0.07, 0.075), 0.35, 12, 8)
		lb.add_rounded_box(Vector3(0, 0.276, 0.0), Vector3(hwid * 0.86, 0.008, 0.034), Color(0.9, 0.9, 0.88), 0.4, 10, 4)
		# TO/GA switch on the grip and the reverse thrust latch
		lb.add_rounded_box(Vector3(0, 0.25, -0.03), Vector3(hwid * 0.6, 0.012, 0.008), Color(0.12, 0.12, 0.12), 0.4, 8, 4)
		lb.add_rounded_box(Vector3(0, 0.205, -0.02), Vector3(0.02, 0.05, 0.01), Color(0.82, 0.82, 0.8), 0.4, 8, 6)
		var li := MeshInstance3D.new()
		li.mesh = lb.commit()
		li.material_override = mat
		piv.add_child(li)
		parts["thr%d" % i5] = piv
	for gv in [0.105, 0.075, 0.035, -0.06]:
		_fbox(qfr, Vector3(0, gv, 0.009), Vector3(0.11 if n_eng <= 2 else 0.15, 0.003, 0.002), Color(0.85, 0.86, 0.88))
	_label(qfr, Vector3(-0.075 if n_eng <= 2 else -0.09, 0.075, 0.009), "FLX", 0.006)
	_label(qfr, Vector3(0, 0.12, 0.009), "TOGA", 0.006)
	_label(qfr, Vector3(0, 0.035, 0.009), "CL", 0.006)
	_label(qfr, Vector3(0, -0.06, 0.009), "IDLE", 0.006)
	_ctl("thrust", "THRUST LEVERS", "lever", qfr, Vector3(0, 0, 0.12), Vector3(0.12, 0.26, 0.24))
	# speedbrake (left) and flaps (right)
	var sbp := Node3D.new()
	sbp.position = Vector3(-hw + 0.035, qy - 0.06, qz)
	add_child(sbp)
	var sbb := MeshBuilder.new()
	sbb.add_box(Vector3(0, 0.08, 0), Vector3(0.01, 0.16, 0.014), Color(0.6, 0.6, 0.6))
	sbb.add_box(Vector3(0, 0.165, 0), Vector3(0.05, 0.018, 0.024), Color(0.85, 0.85, 0.83))
	var sbi := MeshInstance3D.new()
	sbi.mesh = sbb.commit()
	sbi.material_override = mat
	sbp.add_child(sbi)
	parts["speedbrake"] = sbp
	_label(qfr, Vector3(-hw + 0.035, -0.115, 0.009), "SPEED BRAKE", 0.005)
	_ctl("speedbrake", "SPEED BRAKE", "lever", qfr, Vector3(-hw + 0.035, 0, 0.1), Vector3(0.06, 0.2, 0.2))
	var flp := Node3D.new()
	flp.position = Vector3(hw - 0.035, qy - 0.06, qz)
	add_child(flp)
	var flb := MeshBuilder.new()
	flb.add_box(Vector3(0, 0.08, 0), Vector3(0.01, 0.16, 0.014), Color(0.6, 0.6, 0.6))
	flb.add_box(Vector3(0, 0.165, 0), Vector3(0.028, 0.03, 0.05), Color(0.9, 0.9, 0.88))
	var fli := MeshInstance3D.new()
	fli.mesh = flb.commit()
	fli.material_override = mat
	flp.add_child(fli)
	parts["flaps"] = flp
	var nf: int = spec.flaps.size()
	for fi in nf:
		var fv := 0.09 - 0.18 * float(fi) / maxf(nf - 1, 1)
		_label(qfr, Vector3(hw - 0.075, fv, 0.009), String(spec.flaps[fi].label), 0.0055)
	_ctl("flaps", "FLAPS", "lever", qfr, Vector3(hw - 0.035, 0, 0.1), Vector3(0.06, 0.2, 0.2))
	# engine master / fuel control switches, start selector, parking brake
	var rfr := _frame(Vector3(0, top_rear + 0.001, E.z + 0.12), Vector3(0, 0, -1), Vector3(0, 1, 0))
	for i6 in n_eng:
		var ex := (float(i6) - (n_eng - 1) * 0.5) * 0.06
		_fbox(rfr, Vector3(ex, 0.03, 0.004), Vector3(0.045, 0.06, 0.008), c_dark)
		_toggle("eng_master_%d" % i6, "ENG %d" % (i6 + 1), rfr, ex, 0.03, false)
	_knob("eng_start", "ENG MODE  IGN/START", rfr, 0.0, -0.035, 0.016)
	_fbox(rfr, Vector3(0, -0.1, 0.006), Vector3(0.09, 0.05, 0.012), c_dark)
	var pbk := Node3D.new()
	pbk.transform = rfr * Transform3D(Basis(), Vector3(0, -0.1, 0.012))
	add_child(pbk)
	var pkb := MeshBuilder.new()
	pkb.add_box(Vector3(0, 0, 0.012), Vector3(0.06, 0.014, 0.024), Color(0.92, 0.92, 0.9))
	var pki := MeshInstance3D.new()
	pki.mesh = pkb.commit()
	pki.material_override = mat
	pbk.add_child(pki)
	parts["park_brake"] = pbk
	_label(rfr, Vector3(0, -0.13, 0.002), "PARK BRK", 0.0055)
	_ctl("park_brake", "PARKING BRAKE", "toggle", rfr, Vector3(0, -0.1, 0.02), Vector3(0.09, 0.05, 0.04))
	# radio management / transponder strip and audio panels
	var rect2: Rect2 = canvas.cells[canvas.cells.size() - 2].rect
	_fbox(rfr, Vector3(0, -0.19, 0.004), Vector3(hw * 2.0 - 0.03, 0.07, 0.008), c_dark)
	_screen_quad(rfr, Vector3(0, -0.18, 0.0085), hw * 2.0 - 0.08, 0.026, rect2)
	_ctl("radio", "RADIO / ATC", "screen", rfr, Vector3(-0.05, -0.19, 0.01), Vector3(0.18, 0.07, 0.03))
	_ctl("xpdr", "TRANSPONDER", "screen", rfr, Vector3(0.12, -0.19, 0.01), Vector3(0.1, 0.07, 0.03))
	_label(rfr, Vector3(-0.1, -0.21, 0.009), "COM 1", 0.005)
	_label(rfr, Vector3(0.12, -0.21, 0.009), "ATC XPDR", 0.005)
	# pitch trim wheels on the quadrant sides (all but fly-by-wire sidestick types show them)
	for sx3 in [-1.0, 1.0]:
		var tw := Node3D.new()
		tw.position = Vector3(sx3 * (hw + 0.006), qy - 0.12, qz + 0.05)
		add_child(tw)
		var twb := MeshBuilder.new()
		twb.add_cylinder(Vector3(-0.012 * sx3, 0, 0), Vector3(0.012 * sx3, 0, 0), 0.085, 0.085, 24, Color(0.08, 0.08, 0.08), true)
		for k2 in 6:
			var a := TAU * k2 / 6.0
			twb.add_box(Vector3(0, cos(a) * 0.086, sin(a) * 0.086), Vector3(0.026, 0.008, 0.008), Color(0.9, 0.9, 0.9))
		var twi := MeshInstance3D.new()
		twi.mesh = twb.commit()
		twi.material_override = mat
		tw.add_child(twi)
		parts["trim_wheel_%d" % (0 if sx3 < 0 else 1)] = tw
	_ctl("trim", "PITCH TRIM", "wheel", _frame(Vector3(hw + 0.01, qy - 0.12, qz + 0.05), Vector3(0, 1, 0), Vector3(1, 0, 0)), Vector3.ZERO, Vector3(0.18, 0.18, 0.04))


func _screen_quad(fr: Transform3D, o: Vector3, w: float, h: float, rect: Rect2) -> void:
	var vs := Vector2(viewport.size)
	var uv0 := rect.position / vs
	var uv1 := rect.end / vs
	var smb := MeshBuilder.new()
	var nn := (fr.basis * Vector3(0, 0, 1)).normalized()
	var i0 := smb.add_vertex(fr * (o + Vector3(-w * 0.5, -h * 0.5, 0)), nn, Color.WHITE, Vector2(uv0.x, uv1.y))
	var i1 := smb.add_vertex(fr * (o + Vector3(w * 0.5, -h * 0.5, 0)), nn, Color.WHITE, Vector2(uv1.x, uv1.y))
	var i2 := smb.add_vertex(fr * (o + Vector3(w * 0.5, h * 0.5, 0)), nn, Color.WHITE, Vector2(uv1.x, uv0.y))
	var i3 := smb.add_vertex(fr * (o + Vector3(-w * 0.5, h * 0.5, 0)), nn, Color.WHITE, Vector2(uv0.x, uv0.y))
	smb.add_tri_idx(i0, i2, i1)
	smb.add_tri_idx(i0, i3, i2)
	var mi := MeshInstance3D.new()
	mi.mesh = smb.commit()
	mi.material_override = mat_screen
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	screens.append(mi)


# ============================================================================== side consoles
func _build_side_consoles() -> void:
	for side in [-1.0, 1.0]:
		var zc := E.z - 0.05
		var xw := CabinLayout.half_width(spec, zc, floor_y + 0.7) - 0.08
		var x0 = side * (absf(E.x) + 0.24)
		var cw := maxf(xw - absf(x0), 0.12)
		var cx = side * (absf(x0) + cw * 0.5)
		mb.add_box(Vector3(cx, floor_y + 0.36, zc), Vector3(cw, 0.72, 0.9), c_panel.darkened(0.12))
		var tfr := _frame(Vector3(cx, floor_y + 0.721, zc), Vector3(0, 0, -1), Vector3(0, 1, 0))
		# tiller (nose wheel steering)
		var tz := -0.3
		_fcyl(tfr, Vector3(0, tz, 0.0), Vector3(0, tz, 0.03), 0.045, 0.045, c_dark, 18)
		_fbox(tfr, Vector3(0.03, tz, 0.045), Vector3(0.02, 0.02, 0.03), Color(0.1, 0.1, 0.1))
		_label(tfr, Vector3(0, tz - 0.06, 0.001), "STEERING", 0.005)
		# oxygen mask stowage box
		_fbox(tfr, Vector3(0.0, 0.22, 0.04), Vector3(0.11, 0.12, 0.08), Color(0.12, 0.13, 0.14))
		_label(tfr, Vector3(0.0, 0.22, 0.081), "OXY MASK", 0.0055)
		_ctl("crew_mask", "OXYGEN MASK", "button", tfr, Vector3(0, 0.22, 0.05), Vector3(0.11, 0.12, 0.09))
		# clipboard / map table
		_fbox(tfr, Vector3(0.0, 0.05, 0.004), Vector3(0.14, 0.2, 0.006), Color(0.18, 0.19, 0.2))
		_fbox(tfr, Vector3(0.0, 0.05, 0.0075), Vector3(0.12, 0.17, 0.001), Color(0.92, 0.92, 0.88))
		_label(tfr, Vector3(0.0, 0.11, 0.0085), "CHECKLIST", 0.006, Color(0.1, 0.1, 0.1))
		_ctl("checklist", "CHECKLIST", "screen", tfr, Vector3(0, 0.05, 0.01), Vector3(0.14, 0.2, 0.02))


# ============================================================================== yokes / sidesticks
func _build_flight_controls() -> void:
	for side in [-1.0, 1.0]:
		var key := "l" if side < 0 else "r"
		if fbw:
			var sx = side * (absf(E.x) + 0.3)
			var base := Vector3(sx, floor_y + 0.72, E.z - 0.12)
			mb.add_cylinder(base, base + Vector3(0, 0.03, 0), 0.04, 0.03, 14, Color(0.05, 0.05, 0.05), true)
			var piv := Node3D.new()
			piv.position = base + Vector3(0, 0.02, 0)
			add_child(piv)
			var sb := MeshBuilder.new()
			sb.add_cylinder(Vector3(0, 0, 0), Vector3(0, 0.05, 0), 0.016, 0.013, 10, Color(0.15, 0.15, 0.15), false)
			sb.add_cylinder(Vector3(0, 0.05, 0), Vector3(0, 0.17, -0.025), 0.019, 0.017, 12, Color(0.12, 0.12, 0.12), true)
			sb.add_box(Vector3(-side * 0.012, 0.15, -0.035), Vector3(0.012, 0.02, 0.012), Color(0.75, 0.1, 0.08))
			sb.add_box(Vector3(0, 0.1, -0.024), Vector3(0.008, 0.02, 0.012), Color(0.08, 0.08, 0.08))
			var si := MeshInstance3D.new()
			si.mesh = sb.commit()
			si.material_override = mat
			piv.add_child(si)
			parts["stick_" + key] = piv
		else:
			var cz := E.z - 0.5
			var cx2 = side * absf(E.x)
			var piv2 := Node3D.new()
			piv2.position = Vector3(cx2, floor_y + 0.05, cz + 0.05)
			add_child(piv2)
			var cb := MeshBuilder.new()
			cb.add_cylinder(Vector3(0, 0, 0), Vector3(0, 0.62, -0.04), 0.03, 0.026, 12, Color(0.12, 0.12, 0.13), true)
			cb.add_box(Vector3(0, 0.05, 0), Vector3(0.1, 0.1, 0.12), Color(0.1, 0.1, 0.1))
			var ci := MeshInstance3D.new()
			ci.mesh = cb.commit()
			ci.material_override = mat
			piv2.add_child(ci)
			var yoke := Node3D.new()
			yoke.position = Vector3(0, 0.62, -0.06)
			piv2.add_child(yoke)
			var yb := MeshBuilder.new()
			yb.add_box(Vector3(0, 0, 0), Vector3(0.12, 0.05, 0.05), Color(0.1, 0.1, 0.1))
			yb.add_box(Vector3(0, 0.0, 0.026), Vector3(0.06, 0.03, 0.004), Color(0.6, 0.62, 0.6))
			for hs in [-1.0, 1.0]:
				yb.add_cylinder(Vector3(hs * 0.06, 0, 0), Vector3(hs * 0.15, 0.025, 0), 0.016, 0.016, 10, Color(0.09, 0.09, 0.09), false)
				yb.add_cylinder(Vector3(hs * 0.15, 0.025, 0), Vector3(hs * 0.16, 0.12, 0), 0.019, 0.017, 12, Color(0.08, 0.08, 0.08), true)
				yb.add_box(Vector3(hs * 0.16, 0.13, -0.01), Vector3(0.012, 0.012, 0.012), Color(0.75, 0.1, 0.08))
			var yi := MeshInstance3D.new()
			yi.mesh = yb.commit()
			yi.material_override = mat
			yoke.add_child(yi)
			parts["column_" + key] = piv2
			parts["yoke_" + key] = yoke


# ============================================================================== back wall
func _build_back_wall() -> void:
	var bz := float(ck.back_z) - 0.03
	var wmb := MeshBuilder.new()
	var levels := 12
	for k in levels:
		var ya := lerpf(floor_y, E.y + 0.85, float(k) / levels)
		var yb := lerpf(floor_y, E.y + 0.85, float(k + 1) / levels)
		var xa := CabinLayout.half_width(spec, bz, ya) - 0.06
		var xb := CabinLayout.half_width(spec, bz, yb) - 0.06
		if xa <= 0.05 or xb <= 0.05:
			continue
		var ym := (ya + yb) * 0.5
		if ym < floor_y + 1.95:
			for sx in [-1.0, 1.0]:
				wmb.add_quad(Vector3(sx * 0.42, ya, bz), Vector3(sx * xa, ya, bz), Vector3(sx * xb, yb, bz), Vector3(sx * 0.42, yb, bz), c_shell.darkened(0.08))
		else:
			wmb.add_quad(Vector3(-xa, ya, bz), Vector3(xa, ya, bz), Vector3(xb, yb, bz), Vector3(-xb, yb, bz), c_shell.darkened(0.08))
	# make both faces visible
	var flip := MeshBuilder.new()
	flip.add_mesh_builder(wmb)
	for i in range(0, flip.indices.size(), 3):
		var t := flip.indices[i + 1]
		flip.indices[i + 1] = flip.indices[i + 2]
		flip.indices[i + 2] = t
	wmb.add_mesh_builder(flip)
	mb.add_mesh_builder(wmb)
	# circuit breaker panel (left) and emergency equipment
	var cbf := _frame(Vector3(-0.75, E.y + 0.1, bz - 0.01), Vector3(0, 1, 0), Vector3(0, 0, -1))
	_fbox(cbf, Vector3(0, 0, 0.004), Vector3(0.42, 0.5, 0.008), c_panel)
	for r in 9:
		for c in 12:
			_fcyl(cbf, Vector3(-0.18 + c * 0.033, -0.2 + r * 0.05, 0.008), Vector3(-0.18 + c * 0.033, -0.2 + r * 0.05, 0.016), 0.0055, 0.005, Color(0.05, 0.05, 0.05), 6)
	_label(cbf, Vector3(0, 0.235, 0.009), "CIRCUIT BREAKERS", 0.007)
	mb.add_cylinder(Vector3(0.7, floor_y + 0.05, bz - 0.08), Vector3(0.7, floor_y + 0.5, bz - 0.08), 0.055, 0.055, 14, Color(0.75, 0.08, 0.06), true)
	mb.add_box(Vector3(0.62, floor_y + 0.9, bz - 0.04), Vector3(0.05, 0.4, 0.03), Color(0.85, 0.75, 0.1))
	# cockpit door with keypad
	var door := Node3D.new()
	door.position = Vector3(-0.42, floor_y, bz)
	add_child(door)
	var db := MeshBuilder.new()
	db.add_box(Vector3(0.42, 0.975, 0.0), Vector3(0.82, 1.94, 0.05), c_shell.darkened(0.15))
	db.add_box(Vector3(0.72, 1.0, -0.035), Vector3(0.04, 0.12, 0.03), Color(0.3, 0.3, 0.32))
	db.add_cylinder(Vector3(0.42, 1.55, -0.026), Vector3(0.42, 1.55, 0.026), 0.012, 0.012, 8, Color(0.05, 0.05, 0.05), true)
	var di := MeshInstance3D.new()
	di.mesh = db.commit()
	di.material_override = mat
	door.add_child(di)
	parts["door"] = door
	_ctl("cockpit_door", "FLIGHT DECK DOOR", "door", Transform3D(Basis(), Vector3(0, floor_y + 1.0, bz)), Vector3.ZERO, Vector3(0.8, 1.9, 0.12))
	# observer seat folded against the wall
	mb.add_box(Vector3(0.45, floor_y + 0.85, bz - 0.06), Vector3(0.4, 0.5, 0.06), Color(0.14, 0.15, 0.18))


# ============================================================================== seats
func _build_seats() -> void:
	var seat_col := Color(0.11, 0.13, 0.19) if cat != "bizjet" else Color(0.5, 0.42, 0.32)
	if cat == "trainer":
		seat_col = Color(0.36, 0.3, 0.24)
	var trim := Color(0.06, 0.06, 0.07)
	var seats := []
	for side in [-1.0, 1.0]:
		seats.append(Vector3(side * absf(E.x), floor_y, E.z + 0.12))
	if cat == "trainer":
		seats.clear()
		for st in lay.seats:
			seats.append(st.pos)
	for sp in seats:
		var p: Vector3 = sp
		var ga := cat == "trainer"
		var smb := MeshBuilder.new()
		var w := 0.5 if not ga else 0.46
		# pedestal base on floor rails
		smb.add_rounded_box(Vector3(0, 0.13, 0.02), Vector3(0.3, 0.24, 0.42), trim, 0.35, 12, 6)
		for rx in [-0.13, 0.13]:
			smb.add_box(Vector3(rx, 0.01, 0.0), Vector3(0.03, 0.02, 0.8), Color(0.35, 0.35, 0.36))
		# seat pan: firm shell with a soft cushion and rolled front edge
		smb.add_rounded_box(Vector3(0, 0.33, -0.02), Vector3(w + 0.02, 0.07, 0.5), trim, 0.3, 14, 6)
		smb.add_rounded_box(Vector3(0, 0.39, -0.03), Vector3(w - 0.03, 0.09, 0.47), seat_col, 0.45, 16, 8)
		smb.add_rounded_box(Vector3(0, 0.39, -0.27), Vector3(w - 0.02, 0.1, 0.08), seat_col.darkened(0.06), 0.6, 14, 6)
		# backrest with lumbar, side bolsters and a winged headrest
		var bb := Basis(Vector3.RIGHT, 0.2)
		smb.add_rounded_box(Vector3(0, 0.83, 0.21), Vector3(w, 0.8, 0.12), seat_col, 0.38, 16, 10, bb)
		smb.add_rounded_box(Vector3(0, 0.64, 0.15), Vector3(w * 0.8, 0.22, 0.06), seat_col.lightened(0.04), 0.5, 12, 6, bb)
		for bx in [-1.0, 1.0]:
			smb.add_rounded_box(Vector3(bx * w * 0.46, 0.85, 0.17), Vector3(0.07, 0.68, 0.11), seat_col.darkened(0.1), 0.45, 10, 8, bb * Basis(Vector3.UP, -bx * 0.25))
		smb.add_rounded_box(Vector3(0, 1.3, 0.3), Vector3(w * 0.66, 0.2, 0.13), seat_col.darkened(0.12), 0.4, 14, 8, bb)
		if not ga:
			for bx2 in [-1.0, 1.0]:
				# fold-down armrests
				smb.add_rounded_box(Vector3(bx2 * (w * 0.5 + 0.04), 0.62, 0.0), Vector3(0.065, 0.06, 0.4), trim, 0.5, 10, 6)
				smb.add_box(Vector3(bx2 * (w * 0.5 + 0.04), 0.53, 0.16), Vector3(0.035, 0.18, 0.04), trim)
			# five-point harness
			for hx in [-0.11, 0.11]:
				smb.add_box(Vector3(hx, 0.95, 0.125), Vector3(0.045, 0.62, 0.008), Color(0.2, 0.22, 0.27))
			smb.add_rounded_box(Vector3(0, 0.47, -0.17), Vector3(0.07, 0.07, 0.025), Color(0.62, 0.64, 0.66), 0.4, 10, 6)
			for lx in [-0.18, 0.18]:
				smb.add_box(Vector3(lx * 0.75, 0.45, -0.1), Vector3(0.04, 0.008, 0.16), Color(0.2, 0.22, 0.27))
		var mi := MeshInstance3D.new()
		mi.mesh = smb.commit()
		mi.material_override = mat
		mi.position = p
		add_child(mi)


func _build_pedals() -> void:
	for side in [-1.0, 1.0]:
		var px = side * absf(E.x)
		var pz := E.z - 0.82
		for k in [-1.0, 1.0]:
			var piv := Node3D.new()
			piv.position = Vector3(px + k * 0.09, floor_y + 0.04, pz)
			add_child(piv)
			var pb := MeshBuilder.new()
			pb.add_box(Vector3(0, 0.1, 0.0), Vector3(0.065, 0.2, 0.02), Color(0.12, 0.12, 0.13))
			pb.add_box(Vector3(0, 0.0, 0.02), Vector3(0.02, 0.04, 0.06), Color(0.3, 0.3, 0.3))
			var pi := MeshInstance3D.new()
			pi.mesh = pb.commit()
			pi.material_override = mat
			pi.rotation.x = -0.35
			piv.add_child(pi)
			parts["pedal_%s_%d" % ["l" if side < 0 else "r", 0 if k < 0 else 1]] = piv


# ============================================================================== GA (trainer) cockpit
func _build_ga() -> void:
	var fr := _panel_frame()
	var hw := CabinLayout.half_width(spec, z_panel, E.y - 0.3) - 0.04
	var bottom := floor_y + 0.42 - (E.y - 0.45)
	var top := 0.3
	_fbox(fr, Vector3(0, (top + bottom) * 0.5, -0.03), Vector3(hw * 2.0, top - bottom, 0.06), Color(0.16, 0.16, 0.17))
	# glare shield
	mb.add_box(Vector3(0, E.y - 0.14, z_panel - 0.06), Vector3(hw * 2.0, 0.03, 0.2), Color(0.05, 0.05, 0.05))
	# six-pack analogue panel in front of the left seat
	var rect: Rect2 = canvas.cells[0].rect
	_fbox(fr, Vector3(-0.2, 0.02, 0.004), Vector3(0.38, 0.2, 0.01), Color(0.03, 0.03, 0.03))
	_screen_quad(fr, Vector3(-0.2, 0.02, 0.0105), 0.36, 0.18, rect)
	_ctl("screen_ga", "FLIGHT INSTRUMENTS", "screen", fr, Vector3(-0.2, 0.02, 0.01), Vector3(0.36, 0.18, 0.02))
	var rect2: Rect2 = canvas.cells[2].rect
	_screen_quad(fr, Vector3(-0.2, -0.11, 0.0105), 0.3, 0.1, Rect2(rect2.position, Vector2(rect2.size.x, rect2.size.y * 0.34)))
	# radio stack (centre)
	var rect3: Rect2 = canvas.cells[4].rect
	_fbox(fr, Vector3(0.08, 0.0, 0.004), Vector3(0.16, 0.2, 0.01), Color(0.04, 0.04, 0.04))
	_screen_quad(fr, Vector3(0.08, 0.06, 0.0105), 0.14, 0.035, rect3)
	_ctl("radio", "COM / NAV RADIO", "screen", fr, Vector3(0.08, 0.0, 0.01), Vector3(0.16, 0.2, 0.02))
	var rect4: Rect2 = canvas.cells[3].rect
	_screen_quad(fr, Vector3(0.08, -0.03, 0.0105), 0.13, 0.1, rect4)
	# switches row (rocker switches)
	var sw := [["master", "MASTER"], ["avionics", "AVIONICS"], ["beacon", "BCN"], ["land_lt", "LAND"], ["taxi_lt", "TAXI"], ["nav_lt", "NAV"], ["strobe", "STROBE"], ["probe_heat", "PITOT HT"], ["pump_c", "FUEL PUMP"]]
	for i in sw.size():
		_toggle(String(sw[i][0]), String(sw[i][1]), fr, -0.35 + i * 0.035, -0.19, false)
	# ignition key, primer, throttle, mixture, carb heat, flap switch
	_knob("eng_start", "MAGNETOS", fr, -0.42, -0.12, 0.014)
	var thr := Node3D.new()
	thr.transform = fr * Transform3D(Basis(), Vector3(0.0, -0.17, 0.0))
	add_child(thr)
	var tb := MeshBuilder.new()
	tb.add_cylinder(Vector3(0, 0, 0), Vector3(0, 0, 0.12), 0.004, 0.004, 8, Color(0.75, 0.75, 0.75))
	tb.add_cylinder(Vector3(0, 0, 0.12), Vector3(0, 0, 0.14), 0.018, 0.018, 14, Color(0.06, 0.06, 0.06))
	var ti := MeshInstance3D.new()
	ti.mesh = tb.commit()
	ti.material_override = mat
	thr.add_child(ti)
	parts["ga_throttle"] = thr
	_label(fr, Vector3(0.0, -0.205, 0.002), "THROTTLE", 0.0055)
	_ctl("thrust", "THROTTLE", "lever", fr, Vector3(0, -0.17, 0.08), Vector3(0.05, 0.05, 0.16))
	_fcyl(fr, Vector3(0.06, -0.17, 0.0), Vector3(0.06, -0.17, 0.09), 0.003, 0.003, Color(0.7, 0.7, 0.7), 8)
	_fcyl(fr, Vector3(0.06, -0.17, 0.09), Vector3(0.06, -0.17, 0.105), 0.015, 0.015, Color(0.75, 0.08, 0.06), 12)
	_label(fr, Vector3(0.06, -0.205, 0.002), "MIXTURE", 0.0055)
	_ctl("mixture", "MIXTURE", "lever", fr, Vector3(0.06, -0.17, 0.06), Vector3(0.04, 0.04, 0.12))
	_fcyl(fr, Vector3(-0.05, -0.17, 0.0), Vector3(-0.05, -0.17, 0.05), 0.003, 0.003, Color(0.7, 0.7, 0.7), 8)
	_fcyl(fr, Vector3(-0.05, -0.17, 0.05), Vector3(-0.05, -0.17, 0.065), 0.014, 0.014, Color(0.1, 0.1, 0.1), 12)
	_label(fr, Vector3(-0.05, -0.205, 0.002), "CARB HEAT", 0.0055)
	var flp := Node3D.new()
	flp.transform = fr * Transform3D(Basis(), Vector3(0.22, -0.15, 0.01))
	add_child(flp)
	var fb := MeshBuilder.new()
	fb.add_box(Vector3(0, 0, 0.02), Vector3(0.012, 0.012, 0.04), Color(0.7, 0.7, 0.7))
	fb.add_box(Vector3(0, 0, 0.045), Vector3(0.04, 0.02, 0.014), Color(0.9, 0.9, 0.9))
	var fi := MeshInstance3D.new()
	fi.mesh = fb.commit()
	fi.material_override = mat
	flp.add_child(fi)
	parts["flaps"] = flp
	_label(fr, Vector3(0.22, -0.1, 0.002), "FLAPS", 0.006)
	_ctl("flaps", "FLAPS", "lever", fr, Vector3(0.22, -0.15, 0.03), Vector3(0.06, 0.1, 0.06))
	# trim wheel and fuel selector between the seats
	var tw := Node3D.new()
	tw.position = Vector3(0, floor_y + 0.25, E.z - 0.15)
	add_child(tw)
	var twb := MeshBuilder.new()
	twb.add_cylinder(Vector3(-0.012, 0, 0), Vector3(0.012, 0, 0), 0.09, 0.09, 24, Color(0.08, 0.08, 0.08), true)
	var twi := MeshInstance3D.new()
	twi.mesh = twb.commit()
	twi.material_override = mat
	tw.add_child(twi)
	parts["trim_wheel_0"] = tw
	_ctl("trim", "ELEVATOR TRIM", "wheel", Transform3D(Basis(), tw.position), Vector3.ZERO, Vector3(0.05, 0.2, 0.2))
	mb.add_box(Vector3(0, floor_y + 0.02, E.z - 0.35), Vector3(0.2, 0.04, 0.15), Color(0.2, 0.2, 0.2))
	_label(_frame(Vector3(0, floor_y + 0.041, E.z - 0.35), Vector3(0, 0, -1), Vector3(0, 1, 0)), Vector3.ZERO, "FUEL  BOTH", 0.008)
	# yokes on columns coming out of the panel
	for side in [-1.0, 1.0]:
		var key := "l" if side < 0 else "r"
		var col := Node3D.new()
		col.transform = fr * Transform3D(Basis(), Vector3(-0.2 if side < 0 else 0.3, 0.0, 0.0))
		add_child(col)
		var cb := MeshBuilder.new()
		cb.add_cylinder(Vector3(0, 0, 0), Vector3(0, 0, 0.17), 0.012, 0.012, 10, Color(0.6, 0.6, 0.6), false)
		var cbi := MeshInstance3D.new()
		cbi.mesh = cb.commit()
		cbi.material_override = mat
		col.add_child(cbi)
		var yoke := Node3D.new()
		yoke.position = Vector3(0, 0, 0.17)
		col.add_child(yoke)
		var yb := MeshBuilder.new()
		yb.add_rounded_box(Vector3(0, -0.01, 0), Vector3(0.11, 0.045, 0.035), Color(0.08, 0.08, 0.08), 0.4, 12, 6)
		for hs in [-1.0, 1.0]:
			yb.add_cylinder(Vector3(hs * 0.05, -0.01, 0), Vector3(hs * 0.13, 0.02, 0), 0.014, 0.014, 10, Color(0.07, 0.07, 0.07), false)
			yb.add_cylinder(Vector3(hs * 0.13, 0.02, 0), Vector3(hs * 0.14, 0.1, 0), 0.016, 0.015, 10, Color(0.07, 0.07, 0.07), true)
		var yi := MeshInstance3D.new()
		yi.mesh = yb.commit()
		yi.material_override = mat
		yoke.add_child(yi)
		parts["column_" + key] = col
		parts["yoke_" + key] = yoke
	# rear bench back and baggage wall
	mb.add_box(Vector3(0, floor_y + 0.55, float(lay.cabin_back) - 0.05), Vector3(1.0, 0.9, 0.06), Color(0.32, 0.3, 0.28))


# ============================================================================== lighting
var day_fills: Array[OmniLight3D] = []
var _glaze_z0 := 0.0                # glazing never starts forward of this station


func _build_lights() -> void:
	# daylight through the glazing: soft unshadowed fill (the shell shadows the sun inside)
	for spec_f in [[Vector3(0, E.y + 0.05, E.z - 0.35), 3.0, 1.1], [Vector3(0, E.y + 0.1, E.z + 0.75), 2.4, 0.5]]:
		var df := OmniLight3D.new()
		df.position = spec_f[0]
		df.omni_range = spec_f[1]
		df.omni_attenuation = 0.6
		df.light_energy = spec_f[2]
		df.set_meta("day", spec_f[2])
		df.light_color = Color(0.94, 0.97, 1.0)
		df.light_specular = 0.0
		df.shadow_enabled = false
		add_child(df)
		day_fills.append(df)
	dome = OmniLight3D.new()
	dome.position = Vector3(0, E.y + 0.55, E.z + 0.1)
	dome.omni_range = 2.2
	dome.light_energy = 0.0
	dome.light_color = Color(1.0, 0.92, 0.8)
	dome.shadow_enabled = false
	add_child(dome)
	for sx in [-1.0, 1.0]:
		var f := OmniLight3D.new()
		f.position = Vector3(sx * 0.4, E.y - 0.05, z_panel + 0.3)
		f.omni_range = 0.9
		f.light_energy = 0.0
		f.light_color = Color(1.0, 0.85, 0.65)
		f.shadow_enabled = false
		add_child(f)
		floods.append(f)


func set_night(night: float) -> void:
	for f in floods:
		f.light_energy = 0.35 * night
	for df in day_fills:
		df.light_energy = float(df.get_meta("day")) * clampf(1.0 - night * 1.15, 0.0, 1.0)
	mat_screen.set_shader_parameter("brightness", lerpf(1.0, 0.75, night))
	mat_ind.set_shader_parameter("night", night)


# ============================================================================== runtime
func attach(aircraft: Aircraft) -> void:
	ac = aircraft
	canvas.ac = aircraft
	canvas.sd_page = "AUTO"


func hit_test(origin: Vector3, dir: Vector3, max_dist: float = 3.0) -> Dictionary:
	## origin/dir in this node's local space; returns the nearest control or {}.
	var best := {}
	var bd := max_dist
	for c in controls:
		var aabb: AABB = c.aabb
		var hit = aabb.intersects_ray(origin, dir)
		if hit != null:
			var d: float = (hit - origin).length()
			if d < bd:
				bd = d
				best = c
	return best


func _process(delta: float) -> void:
	if ac == null:
		return
	_redraw_t -= delta
	if _redraw_t <= 0.0 and visible:
		_redraw_t = 1.0 / 20.0
		canvas.powered = ac.sys.ac_power or ac.sys.battery
		canvas.queue_redraw()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_animate(delta)


func _animate(delta: float) -> void:
	var sys := ac.sys
	for i in n_eng:
		if parts.has("thr%d" % i):
			var tl: float = sys.throttle[i] if i < sys.throttle.size() else ac.throttle_lever
			var ang := lerpf(-0.45, 0.42, clampf(tl, 0.0, 1.0))
			if sys.reverse_cmd:
				ang = -0.6
			(parts["thr%d" % i] as Node3D).rotation.x = -ang
	if parts.has("ga_throttle"):
		var g: Node3D = parts["ga_throttle"]
		g.position = g.position.lerp(_ga_throttle_pos(), 0.3)
	if parts.has("flaps"):
		var nf: int = spec.flaps.size()
		var f := float(sys.flap_lever) / maxf(nf - 1, 1)
		var fp: Node3D = parts["flaps"]
		if cat == "trainer":
			fp.rotation.x = lerpf(0.4, -0.4, f)
		else:
			fp.rotation.x = -lerpf(0.35, -0.35, f)
	if parts.has("speedbrake"):
		(parts["speedbrake"] as Node3D).rotation.x = lerpf(-0.1, 0.5, sys.spoiler_lever) + (0.08 if sys.ground_spoilers_armed else 0.0)
	if parts.has("gear"):
		var gp: Node3D = parts["gear"]
		var target := -0.035 if sys.gear_down_cmd else 0.035
		var base: Transform3D = gp.get_meta("base", gp.transform)
		if not gp.has_meta("base"):
			gp.set_meta("base", gp.transform)
		gp.transform = base * Transform3D(Basis(), Vector3(0, lerpf(float(gp.get_meta("pos", target)), target, minf(delta * 8.0, 1.0)), 0))
		gp.set_meta("pos", lerpf(float(gp.get_meta("pos", target)), target, minf(delta * 8.0, 1.0)))
	if parts.has("park_brake"):
		(parts["park_brake"] as Node3D).rotation.z = 1.4 if sys.parking_brake else 0.0
	var trim_ang := float(sys.trim) * 6.0
	for k in 2:
		if parts.has("trim_wheel_%d" % k):
			(parts["trim_wheel_%d" % k] as Node3D).rotation.x = trim_ang
	# controls follow the flight control surfaces
	var pitch := clampf(ac.fdm.elevator, -1.0, 1.0)
	var roll := clampf(ac.fdm.aileron, -1.0, 1.0)
	var yaw := clampf(ac.fdm.rudder, -1.0, 1.0)
	for key in ["l", "r"]:
		if parts.has("stick_" + key):
			(parts["stick_" + key] as Node3D).rotation = Vector3(pitch * 0.3, 0, -roll * 0.3)
		if parts.has("column_" + key):
			(parts["column_" + key] as Node3D).rotation.x = pitch * 0.14 if cat != "trainer" else 0.0
			if cat == "trainer":
				var col: Node3D = parts["column_" + key]
				if not col.has_meta("base"):
					col.set_meta("base", col.transform)
				col.transform = (col.get_meta("base") as Transform3D) * Transform3D(Basis(), Vector3(0, 0, -pitch * 0.06))
		if parts.has("yoke_" + key):
			(parts["yoke_" + key] as Node3D).rotation.z = -roll * 1.1 if cat != "trainer" else 0.0
			if cat == "trainer":
				(parts["yoke_" + key] as Node3D).rotation.z = -roll * 1.0
		for pi in 2:
			var pk := "pedal_%s_%d" % [key, pi]
			if parts.has(pk):
				(parts[pk] as Node3D).position.z = (E.z - 0.82) + (yaw * 0.05 if pi == 0 else -yaw * 0.05)
	# switch levers
	for id in parts.keys():
		if String(id).begins_with("sw:"):
			var on := state(String(id).substr(3))
			(parts[id] as Node3D).rotation.x = -0.45 if on else 0.45
	# annunciators
	for iid in indicators.keys():
		var lit := 0.0
		var s := String(iid)
		if s.begins_with("gear_dn"):
			lit = 1.0 if sys.gear_pos[int(s.substr(7))] > 0.99 else 0.0
		elif s.begins_with("gear_tr"):
			var gpos: float = sys.gear_pos[int(s.substr(7))]
			lit = 1.0 if gpos > 0.01 and gpos < 0.99 else 0.0
		elif s.begins_with("master_warn"):
			lit = 1.0 if sys.master_warning and int(Time.get_ticks_msec() / 500) % 2 == 0 else 0.0
		elif s.begins_with("master_caut"):
			lit = 1.0 if sys.master_caution else 0.0
		elif s.begins_with("fire"):
			var ei := int(s.substr(4)) - 1
			lit = 1.0 if ei < sys.eng.size() and sys.eng[ei].fire else 0.0
		else:
			lit = 1.0 if state(s) else 0.0
		(indicators[iid] as MeshInstance3D).set_instance_shader_parameter("lit", lit)
	if parts.has("door"):
		var dn: Node3D = parts["door"]
		dn.rotation.y = lerp_angle(dn.rotation.y, -1.4 if ac.get_meta("cockpit_door_open", false) else 0.0, minf(delta * 3.0, 1.0))
	dome.light_energy = 0.8 if state("dome") else 0.0


func _ga_throttle_pos() -> Vector3:
	var fr := _panel_frame()
	return (fr * Transform3D(Basis(), Vector3(0.0, -0.17, -0.07 + 0.07 * ac.throttle_lever))).origin


## On/off state of a cockpit control for lights and switch positions.
func state(id: String) -> bool:
	var sys := ac.sys
	var ap := ac.ap
	match id:
		"strobe": return sys.lights.get("strobe", false)
		"beacon": return sys.lights.get("beacon", false)
		"wing_lt": return sys.lights.get("wing", false)
		"nav_lt": return sys.lights.get("nav", false)
		"rwy_lt": return sys.lights.get("runway", false)
		"land_lt": return sys.lights.get("landing", false)
		"taxi_lt": return sys.lights.get("taxi", false)
		"seatbelt": return sys.lights.get("seatbelt", false)
		"nosmoking": return sys.lights.get("nosmoking", true)
		"emer_lt": return sys.lights.get("emergency", false)
		"wing_ai": return sys.wing_anti_ice
		"eng_ai": return sys.eng_anti_ice
		"probe_heat": return sys.pitot_heat
		"apu_master": return sys.apu_on
		"apu_start": return sys.apu_on and sys.apu_n < 95.0
		"apu_bleed": return sys.apu_n > 95.0
		"apu_gen": return sys.apu_n > 95.0
		"pack1": return sys.packs[0]
		"pack2": return sys.packs[1]
		"xfeed": return sys.crossfeed
		"pump_l", "pump_c", "pump_r": return sys.ac_power or sys.battery
		"hyd_a": return sys.hyd[0] > 2000.0
		"hyd_b": return sys.hyd[1] > 2000.0
		"bat", "master": return sys.battery
		"ext_pwr": return sys.ext_power
		"gen1": return sys.n_eng > 0 and sys.eng[0].running and not sys.gen_fail[0]
		"gen2": return sys.n_eng > 1 and sys.eng[1].running and not sys.gen_fail[1]
		"pax_oxy": return sys.masks_deployed
		"crew_oxy": return true
		"dome": return bool(ac.get_meta("dome_light", false))
		"ap": return ap.engaged
		"athr": return ap.at_engaged
		"lnav": return ap.lat_mode == "LNAV"
		"hdg_mode": return ap.lat_mode == "HDG"
		"loc": return ap.lat_mode == "LOC" or ap.arm_loc
		"appr": return ap.arm_gs or ap.vert_mode in ["GS", "FLARE"]
		"flch": return ap.vert_mode == "FLCH"
		"alt_hold": return ap.vert_mode == "ALT"
		"vs_mode": return ap.vert_mode == "VS"
		"spd_mach": return ap.use_mach
		"fd_l", "fd_r": return ap.fd_on
		"park_brake": return sys.parking_brake
		"avionics": return sys.ac_power
	if id.begins_with("autobrake_"):
		return sys.autobrake == int(id.substr(10))
	if id.begins_with("eng_master_"):
		var i := int(id.substr(11))
		return i < sys.eng.size() and not sys.eng[i].cutoff
	if id.begins_with("sd_"):
		return canvas.sd_page == id.substr(3)
	return false
