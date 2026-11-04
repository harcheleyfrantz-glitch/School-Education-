extends RefCounted
## See-through interiors for the exterior aircraft model: what you see through the cabin windows
## and the flight deck glazing from outside. The paint shader opens the glass within RANGE metres
## of the camera (see_through) and this fills the space behind it:
##  - the cabin lining, with the far-side windows glowing as they do from across the aisle,
##    overhead bins with their light strips, the floor and the end bulkheads
##  - every seat of the type's seat map in the airline's colours, white headrest covers, and
##    passengers in most of them (shirt, skin tone and hair vary per passenger)
##  - a compact flight deck: glareshield, panel with glowing screens, pedestal, overhead panel,
##    the two pilot seats and both pilots in white shirts with their headsets
## Shells and flight decks are cached per type; seats and passengers are instanced per aircraft.

const RANGE := 175.0

static var _shell_cache := {}
static var _deck_cache := {}
static var _glass_cache := {}
static var _glass_mat: StandardMaterial3D
static var _seat_mesh: ArrayMesh
static var _person_mesh: ArrayMesh
static var _mat_tint: ShaderMaterial
static var _mat_plain: ShaderMaterial
static var _lining_shader: Shader

const TINT_SHADER := """
shader_type spatial;
render_mode cull_back, shadows_disabled;
uniform float glow = 0.2;
varying vec4 cd;
void vertex() {
	cd = INSTANCE_CUSTOM;
}
void fragment() {
	vec3 base = COLOR.rgb;
	vec3 c = base;
	if (COLOR.a > 0.75) {
		c = base * cd.rgb;
	} else if (COLOR.a > 0.25) {
		c = base * mix(vec3(0.98, 0.8, 0.68), vec3(0.36, 0.24, 0.17), cd.a);
	}
	ALBEDO = c;
	ROUGHNESS = 0.85;
	EMISSION = c * glow;
}
"""

const PLAIN_SHADER := """
shader_type spatial;
render_mode cull_back, shadows_disabled;
uniform float glow = 0.18;
void fragment() {
	vec3 c = COLOR.rgb;
	ALBEDO = c;
	ROUGHNESS = 0.75;
	EMISSION = c * (glow + (1.0 - COLOR.a) * 3.0);
}
"""

const LINING_SHADER := """
shader_type spatial;
render_mode cull_back, shadows_disabled;
uniform vec4 win = vec4(0.3, 0.17, 0.115, 0.53);
uniform vec2 win_range = vec2(-14.0, 14.0);
uniform vec3 wall : source_color = vec3(0.86, 0.85, 0.82);
uniform vec3 sky : source_color = vec3(0.66, 0.76, 0.88);
uniform float glow = 0.28;
varying vec3 lp;
void vertex() {
	lp = VERTEX;
}
void fragment() {
	float k = floor((lp.z - win_range.x) / win.w + 0.5);
	float wz = win_range.x + k * win.w;
	float inr = step(win_range.x - 0.2, wz) * step(wz, win_range.y + 0.2);
	vec2 q = abs(vec2(lp.z - wz, lp.y - win.x)) - win.zy * vec2(1.2, 1.15);
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 0.05;
	float reveal = clamp(0.5 - d / max(fwidth(d), 1e-4), 0.0, 1.0) * inr;
	// a soft frame around each reveal, lower dado panel slightly darker
	float frame = clamp(0.5 - (d - 0.05) / max(fwidth(d), 1e-4), 0.0, 1.0) * (1.0 - reveal) * inr;
	vec3 col = wall * mix(1.0, 0.9, step(lp.y, win.x - win.y - 0.35));
	col = mix(col, wall * 0.78, frame);
	ALBEDO = col * (1.0 - reveal);
	ROUGHNESS = 0.85;
	EMISSION = col * glow * (1.0 - reveal) + sky * reveal * 1.6;
}
"""


static func _materials() -> void:
	if _mat_tint != null:
		return
	var st := Shader.new()
	st.code = TINT_SHADER
	_mat_tint = ShaderMaterial.new()
	_mat_tint.shader = st
	var sp := Shader.new()
	sp.code = PLAIN_SHADER
	_mat_plain = ShaderMaterial.new()
	_mat_plain.shader = sp
	_lining_shader = Shader.new()
	_lining_shader.code = LINING_SHADER
	# window glass: faintly tinted, mirror smooth, so the sky reflects off it at shallow angles
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.albedo_color = Color(0.05, 0.07, 0.09, 0.22)
	_glass_mat.roughness = 0.03
	_glass_mat.metallic_specular = 0.9
	_glass_mat.cull_mode = BaseMaterial3D.CULL_BACK


# ================================================================== building
static func build(type_id: String, spec: Dictionary, livery: String, reg: String, geo: Dictionary) -> Node3D:
	_materials()
	var root := Node3D.new()
	root.name = "InteriorProxy"
	var lay := CabinLayout.get_layout(type_id)
	var cat := String(spec.category)
	var eye := _eye(spec, lay, geo)
	# ---- flight deck
	if not _deck_cache.has(type_id):
		_deck_cache[type_id] = _deck(spec, lay, eye, cat == "trainer")
	var deck := MeshInstance3D.new()
	deck.name = "FlightDeck"
	deck.mesh = _deck_cache[type_id]
	deck.material_override = _mat_plain
	_cull(deck)
	root.add_child(deck)
	# the two pilots (instanced like passengers)
	var crew := []
	var px := minf(0.55, maxf(CabinLayout.half_width(spec, eye.z, eye.y) * 0.45, 0.3))
	if cat == "trainer":
		px = 0.3
	for sx in [-px, px]:
		crew.append({"xf": Transform3D(Basis.IDENTITY, Vector3(sx, eye.y - 1.12, eye.z + 0.05)), "shirt": Color(0.95, 0.96, 0.97)})
	# ---- cabin
	var seats: Array = lay.get("seats", [])
	var has_cabin := AircraftTypes.is_passenger(type_id) and cat != "trainer" and not seats.is_empty() and geo.has("win")
	var people := crew.duplicate()
	if has_cabin:
		var zs := _cabin_extent(seats, geo, eye)
		if not _shell_cache.has(type_id):
			_shell_cache[type_id] = _shell(spec, lay, zs.x, zs.y)
		var shell := MeshInstance3D.new()
		shell.name = "CabinShell"
		shell.mesh = (_shell_cache[type_id] as Array)[0]
		var lm := ShaderMaterial.new()
		lm.shader = _lining_shader
		lm.set_shader_parameter("win", geo.win)
		lm.set_shader_parameter("win_range", geo.win_range)
		shell.material_override = lm
		_cull(shell)
		root.add_child(shell)
		var fit := MeshInstance3D.new()
		fit.name = "CabinFittings"
		fit.mesh = (_shell_cache[type_id] as Array)[1]
		fit.material_override = _mat_plain
		_cull(fit)
		root.add_child(fit)
		# seats in the airline's colours, passengers in most of them
		var lc := Airlines.livery_colors(livery)
		var eco: Color = (lc.get("tail", Color(0.15, 0.22, 0.4)) as Color).darkened(0.35)
		var biz: Color = (lc.get("body", Color(0.3, 0.3, 0.32)) as Color).darkened(0.7).lerp(Color(0.32, 0.26, 0.22), 0.5)
		var r := U.rng(U.hash_str(reg + type_id + "pax"))
		var load_f := r.randf_range(0.62, 0.95)
		var seat_xf := []
		var seat_col := []
		for s in seats:
			var p: Vector3 = s.pos
			var faces_aft := float(s.get("facing", -1.0)) > 0.0
			var b := Basis(Vector3.UP, PI) if faces_aft else Basis.IDENTITY
			var big := String(s.cls) in ["business", "vip", "premium", "first"]
			var wsc := clampf(float(s.get("width", 0.46)) / 0.46, 0.8, 1.9)
			b = b.scaled(Vector3(wsc, 1.06 if big else 1.0, 1.25 if big else 1.0))
			seat_xf.append(Transform3D(b, p))
			seat_col.append(biz if big else eco)
			if r.randf() < load_f:
				var shirt := Color.from_hsv(r.randf(), r.randf_range(0.08, 0.5), r.randf_range(0.14, 0.82))
				people.append({"xf": Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI) if faces_aft else Basis.IDENTITY, p + Vector3(0, 0.0, 0.0)),
					"shirt": shirt, "skin": r.randf()})
		root.add_child(_multimesh("Seats", _seat(), seat_xf, seat_col, []))
	# glass in every window and flight deck pane, just inside the skin
	if not _glass_cache.has(type_id):
		_glass_cache[type_id] = _glass(spec, geo, eye)
	if _glass_cache[type_id] != null:
		var gl := MeshInstance3D.new()
		gl.name = "Glass"
		gl.mesh = _glass_cache[type_id]
		gl.material_override = _glass_mat
		_cull(gl)
		root.add_child(gl)
	var pxf := []
	var pcol := []
	var pskin := []
	for pp in people:
		pxf.append(pp.xf)
		pcol.append(pp.shirt)
		pskin.append(float(pp.get("skin", 0.3)))
	root.add_child(_multimesh("People", _person(), pxf, pcol, pskin))
	return root


static func _cull(mi: GeometryInstance3D) -> void:
	mi.visibility_range_end = RANGE
	mi.visibility_range_end_margin = 10.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _multimesh(nm: String, mesh: ArrayMesh, xfs: Array, cols: Array, alphas: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		var c: Color = cols[i]
		mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, float(alphas[i]) if i < alphas.size() else 0.3))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.material_override = _mat_tint
	_cull(mmi)
	return mmi


static func _eye(spec: Dictionary, lay: Dictionary, geo: Dictionary) -> Vector3:
	## Pilots' eye point (body frame): eye station from the nose; the eyes sit about 0.3 m above
	## the lower sill of the windscreen (from the glazing geometry), else a seated height off the floor.
	var z: float = float(lay.nose_z) + AircraftModel.pilot_eye_station(spec)
	var trainer := String(spec.category) == "trainer"
	var y: float = float(lay.floor_y) + (0.95 if trainer else 1.12)
	var po = geo.get("pane_o", [])
	var n := 0
	var sy := 0.0
	for p in po:
		var v: Vector3 = p
		if v != Vector3.ZERO:
			sy += v.y
			n += 1
	if n > 0:
		y = sy / float(n) + (0.2 if trainer else 0.3)
	return Vector3(0.0, y, z)


static func _cabin_extent(seats: Array, geo: Dictionary, eye: Vector3) -> Vector2:
	var z0 := INF
	var z1 := -INF
	for s in seats:
		var p: Vector3 = s.pos
		z0 = minf(z0, p.z)
		z1 = maxf(z1, p.z)
	var wr: Vector2 = geo.win_range
	z0 = maxf(minf(z0 - 1.6, wr.x - 0.6), eye.z + 1.5)
	z1 = minf(maxf(z1 + 1.6, wr.y + 0.6), wr.y + 2.5)
	return Vector2(z0, z1)


# ================================================================== cabin shell and fittings
static func _section(spec: Dictionary, z: float, fy: float, cy: float) -> PackedVector3Array:
	## Inner lining cross-section, left floor up over the ceiling down to right floor.
	var hs := [fy + 0.02, fy + 0.45, fy + 0.9, fy + 1.3, fy + 1.6, cy - 0.35]
	var pts := PackedVector3Array()
	for y in hs:
		var hw := CabinLayout.half_width(spec, z, float(y))
		pts.append(Vector3(-(maxf(hw - 0.12, 0.3)), float(y), z))
	var hwc := CabinLayout.half_width(spec, z, cy - 0.1)
	pts.append(Vector3(-maxf(hwc - 0.45, 0.25), cy, z))
	pts.append(Vector3(maxf(hwc - 0.45, 0.25), cy, z))
	for i in range(hs.size() - 1, -1, -1):
		var hw2 := CabinLayout.half_width(spec, z, float(hs[i]))
		pts.append(Vector3(maxf(hw2 - 0.12, 0.3), float(hs[i]), z))
	return pts


static func _shell(spec: Dictionary, lay: Dictionary, z0: float, z1: float) -> Array:
	var fy: float = lay.floor_y
	var cy: float = lay.ceil_y
	var mb := MeshBuilder.new()
	var fit := MeshBuilder.new()
	var wall := Color(0.86, 0.85, 0.82)
	var n := maxi(int((z1 - z0) / 0.8), 2)
	var prev := _section(spec, z0, fy, cy)
	for i in n:
		var zb := lerpf(z0, z1, float(i + 1) / n)
		var cur := _section(spec, zb, fy, cy)
		for k in prev.size() - 1:
			mb.add_quad(prev[k], prev[k + 1], cur[k + 1], cur[k], wall)
		prev = cur
	# floor (carpet), overhead bins with light strips and the aisle lights, built in short
	# sections so they follow the fuselage as it narrows; end bulkheads on the real cross-section
	var seg_n := maxi(int((z1 - z0) / 2.0), 1)
	for i in seg_n:
		var za := lerpf(z0, z1, float(i) / seg_n)
		var zb := lerpf(z0, z1, float(i + 1) / seg_n)
		var zm := (za + zb) * 0.5
		var hz := (zb - za)
		var hwf := minf(CabinLayout.half_width(spec, za, fy + 0.05), CabinLayout.half_width(spec, zb, fy + 0.05)) - 0.14
		if hwf > 0.3:
			fit.add_quad(Vector3(-hwf, fy + 0.01, zb), Vector3(hwf, fy + 0.01, zb), Vector3(hwf, fy + 0.01, za), Vector3(-hwf, fy + 0.01, za), Color(0.17, 0.19, 0.25))
		var hwb := minf(CabinLayout.half_width(spec, za, cy - 0.3), CabinLayout.half_width(spec, zb, cy - 0.3))
		if hwb > 0.9:
			for sd in [-1.0, 1.0]:
				var bx: float = sd * (hwb - 0.42)
				fit.add_box(Vector3(bx, cy - 0.3, zm), Vector3(0.56, 0.4, hz - 0.04), Color(0.9, 0.9, 0.88))
				fit.add_box(Vector3(bx - sd * 0.3, cy - 0.52, zm), Vector3(0.04, 0.03, hz - 0.1), Color(1.0, 0.92, 0.78, 0.4))
		fit.add_box(Vector3(0.0, cy - 0.015, zm), Vector3(0.16, 0.02, hz - 0.2), Color(1.0, 0.96, 0.88, 0.5))
	_cap(fit, spec, z0, fy, cy, 1.0, Color(0.8, 0.79, 0.76))
	_cap(fit, spec, z1, fy, cy, -1.0, Color(0.8, 0.79, 0.76))
	return [mb.commit(), fit.commit()]


static func _cap(mb: MeshBuilder, spec: Dictionary, z: float, y0: float, y1: float, face: float, col: Color) -> void:
	## A wall across the fuselage at body z on its real cross-section between heights y0 and y1,
	## facing +z (face 1) or -z (face -1), inset a little from the skin.
	var ys := []
	var n := 8
	for i in n + 1:
		ys.append(lerpf(y0, y1, float(i) / n))
	var pts := []
	for y in ys:
		pts.append(Vector3(-maxf(CabinLayout.half_width(spec, z, float(y)) - 0.06, 0.05), float(y), z))
	for i in range(ys.size() - 1, -1, -1):
		pts.append(Vector3(maxf(CabinLayout.half_width(spec, z, float(ys[i])) - 0.06, 0.05), float(ys[i]), z))
	var c := Vector3(0.0, (y0 + y1) * 0.5, z)
	var nrm := Vector3(0, 0, face)
	var ic := mb.add_vertex(c, nrm, col)
	var ids := []
	for p in pts:
		ids.append(mb.add_vertex(p, nrm, col))
	for k in ids.size() - 1:
		if face < 0.0:
			mb.add_tri_idx(ic, ids[k + 1], ids[k])
		else:
			mb.add_tri_idx(ic, ids[k], ids[k + 1])


static func _glass(spec: Dictionary, geo: Dictionary, eye: Vector3) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var gc := Color(1, 1, 1)
	# cabin windows (both sides), skipping the doors as the paint shader does; exits keep theirs
	if geo.has("win") and geo.has("win_range"):
		var w: Vector4 = geo.win
		var wr: Vector2 = geo.win_range
		var dz: Vector4 = geo.get("door_z", Vector4(-1e4, -1e4, -1e4, -1e4))
		var ez: Vector4 = geo.get("exit_z", Vector4(-1e4, -1e4, -1e4, -1e4))
		var zs := []
		if w.w > 0.0:
			var k := 0
			while true:
				var z := wr.x + float(k) * w.w
				if z > wr.y + 0.01 or k > 400:
					break
				k += 1
				var ok := true
				for i in 4:
					if absf(z - dz[i]) < 0.76 or absf(z - ez[i]) < 0.55:
						ok = false
				if ok:
					zs.append(z)
		for i in 4:
			if ez[i] > -1e3:
				zs.append(ez[i])
		var hh := w.y + 0.05
		var hw := w.z + 0.05
		for z in zs:
			# the skin curves inward above and below the window centre: keep the whole pane inside
			var x := minf(minf(CabinLayout.half_width(spec, float(z), w.x - hh), CabinLayout.half_width(spec, float(z), w.x)), CabinLayout.half_width(spec, float(z), w.x + hh)) - 0.04
			if x < 0.3:
				continue
			var zf: float = z
			mb.add_quad(Vector3(x, w.x - hh, zf + hw), Vector3(x, w.x - hh, zf - hw), Vector3(x, w.x + hh, zf - hw), Vector3(x, w.x + hh, zf + hw), gc)
			mb.add_quad(Vector3(-x, w.x - hh, zf - hw), Vector3(-x, w.x - hh, zf + hw), Vector3(-x, w.x + hh, zf + hw), Vector3(-x, w.x + hh, zf - hw), gc)
	# flight deck panes (defined for the right side, mirrored to the left), grown a little and set
	# back 3 cm so the skin frames them
	var po: Array = geo.get("pane_o", [])
	var pu: Array = geo.get("pane_u", [])
	var pv: Array = geo.get("pane_v", [])
	var pa: Array = geo.get("pane_a", [])
	var pb: Array = geo.get("pane_b", [])
	for i in int(geo.get("pane_count", 0)):
		var o: Vector3 = po[i]
		var u: Vector3 = pu[i]
		var v: Vector3 = pv[i]
		var a4: Vector4 = pa[i]
		var b4: Vector4 = pb[i]
		var c2 := [Vector2(a4.x, a4.y), Vector2(a4.z, a4.w), Vector2(b4.x, b4.y), Vector2(b4.z, b4.w)]
		var cen: Vector2 = ((c2[0] as Vector2) + (c2[1] as Vector2) + (c2[2] as Vector2) + (c2[3] as Vector2)) * 0.25
		var pts := []
		for c in c2:
			var cc: Vector2 = cen + ((c as Vector2) - cen) * 1.08
			pts.append(o + u * cc.x + v * cc.y)
		for side in [1.0, -1.0]:
			var q := []
			var qc := Vector3.ZERO
			for p in pts:
				var m := Vector3((p as Vector3).x * side, (p as Vector3).y, (p as Vector3).z)
				q.append(m)
				qc += m * 0.25
			# set back 3 cm towards the pilots' eyes (always inside), then face away from them
			var to_in: Vector3 = (eye - qc).normalized()
			for k in 4:
				q[k] = (q[k] as Vector3) + to_in * 0.03
			var n2: Vector3 = ((q[1] as Vector3) - (q[0] as Vector3)).cross((q[3] as Vector3) - (q[0] as Vector3))
			if n2.dot(-to_in) < 0.0:
				q.reverse()
			mb.add_quad(q[0], q[1], q[2], q[3], gc)
	if mb.vcount() == 0:
		return null
	return mb.commit()


static func _top_y(spec: Dictionary, z: float, x: float, y_hi: float, y_lo: float) -> float:
	## Highest height (scanning down from y_hi) where the skin is still wider than |x| + 0.12.
	var y := y_hi
	while y > y_lo:
		if CabinLayout.half_width(spec, z, y) > absf(x) + 0.12:
			return y
		y -= 0.02
	return y_lo


# ================================================================== flight deck
static func _deck(spec: Dictionary, lay: Dictionary, eye: Vector3, trainer: bool) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var dark := Color(0.09, 0.1, 0.11)
	var panel := Color(0.16, 0.17, 0.19)
	var z_gs := eye.z - (0.62 if trainer else 0.85)
	var fl := eye.y - 1.12
	var wgs := clampf(2.0 * CabinLayout.half_width(spec, z_gs, eye.y - 0.3) - 0.3, 0.4, 2.1)
	var wp := clampf(2.0 * CabinLayout.half_width(spec, z_gs + 0.12, eye.y - 0.62) - 0.3, 0.4, 2.0)
	# glareshield and the main panel under it
	mb.add_box(Vector3(0, eye.y - 0.3, z_gs + 0.04), Vector3(wgs, 0.1, 0.36), dark)
	mb.add_box(Vector3(0, eye.y - 0.62, z_gs + 0.14), Vector3(wp, 0.54, 0.1), panel)
	# screens on the panel, facing the pilots (and seen from the side windows)
	var n_scr := 2 if trainer else (6 if wp > 1.5 else 4)
	for i in n_scr:
		var fx := (float(i) + 0.5) / n_scr - 0.5
		var sw := wp * 0.82 / n_scr
		var col := Color(0.05, 0.16, 0.35, 0.15) if i % 2 == 0 else Color(0.04, 0.24, 0.16, 0.2)
		mb.add_box(Vector3(fx * wp * 0.86, eye.y - 0.6, z_gs + 0.195), Vector3(sw * 0.86, 0.3, 0.02), col)
	# mode control panel along the glareshield
	mb.add_box(Vector3(0, eye.y - 0.23, z_gs + 0.12), Vector3(wgs * 0.55, 0.07, 0.11), Color(0.12, 0.13, 0.14))
	mb.add_box(Vector3(0, eye.y - 0.23, z_gs + 0.18), Vector3(wgs * 0.45, 0.022, 0.01), Color(0.9, 0.55, 0.15, 0.3))
	var px := minf(0.55, maxf(CabinLayout.half_width(spec, eye.z, eye.y) * 0.45, 0.3)) if not trainer else 0.3
	if not trainer:
		# centre pedestal with its glowing radios
		mb.add_box(Vector3(0, eye.y - 0.86, z_gs + 0.62), Vector3(0.4, 0.5, 0.9), panel)
		mb.add_box(Vector3(0, eye.y - 0.6, z_gs + 0.62), Vector3(0.28, 0.02, 0.6), Color(0.08, 0.22, 0.12, 0.35))
		# overhead panel, kept under the crown where it sits
		var ow := minf(px * 1.6, 1.0)
		var top := _top_y(spec, eye.z - 0.75, ow * 0.5, eye.y + 1.2, eye.y) - 0.06
		if top > eye.y + 0.32:
			mb.add_box(Vector3(0, top - 0.06, eye.z - 0.15), Vector3(ow, 0.1, 1.2), panel)
			for k in 6:
				mb.add_box(Vector3((float(k) - 2.5) * ow * 0.15, top - 0.115, eye.z - 0.5 + float(k % 3) * 0.25), Vector3(0.05, 0.01, 0.03), Color(0.95, 0.75, 0.2, 0.4))
	# pilot seats
	for sx in [-px, px]:
		mb.add_box(Vector3(sx, fl + 0.4, eye.z + 0.25), Vector3(0.5, 0.12, 0.5), dark)
		mb.add_box_xf(Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(sx, fl + 0.88, eye.z + 0.5)), Vector3(0.5, 0.85, 0.12), dark)
		mb.add_box(Vector3(sx, fl + 1.25, eye.z + 0.47), Vector3(0.3, 0.18, 0.1), Color(0.14, 0.15, 0.16))
	# back wall of the flight deck (the cockpit door bulkhead) on the real cross-section
	var zb := eye.z + (0.9 if trainer else 1.3)
	_cap(mb, spec, zb, fl, _top_y(spec, zb, 0.0, eye.y + 1.4, eye.y), -1.0, Color(0.46, 0.47, 0.49))
	# floor, as wide as the nose allows where the glareshield is
	var wf := clampf(2.0 * CabinLayout.half_width(spec, z_gs, fl + 0.05) - 0.2, 0.3, 2.2)
	mb.add_quad(Vector3(-wf * 0.5, fl, zb), Vector3(wf * 0.5, fl, zb), Vector3(wf * 0.5, fl, z_gs), Vector3(-wf * 0.5, fl, z_gs), Color(0.12, 0.12, 0.13))
	return mb.commit()


# ================================================================== instanced meshes
static func _seat() -> ArrayMesh:
	## One seat at the origin (floor level), the occupant facing -z. Vertex alpha: 1 = fabric in
	## the instance colour, 0 = fixed colour (headrest cover, arm rests, frame).
	if _seat_mesh != null:
		return _seat_mesh
	var mb := MeshBuilder.new()
	var fabric := Color(1, 1, 1, 1)
	mb.add_rounded_box(Vector3(0, 0.44, -0.03), Vector3(0.44, 0.12, 0.46), fabric, 0.35, 8, 4)
	var back := Basis(Vector3.RIGHT, -0.14)
	mb.add_rounded_box(Vector3(0, 0.84, 0.22), Vector3(0.44, 0.76, 0.12), fabric, 0.3, 8, 6, back)
	mb.add_rounded_box(Vector3(0, 1.13, 0.18), Vector3(0.36, 0.17, 0.125), Color(0.94, 0.94, 0.92, 0.0), 0.4, 8, 4, back)
	for sx in [-0.235, 0.235]:
		mb.add_rounded_box(Vector3(sx, 0.62, 0.0), Vector3(0.05, 0.05, 0.42), Color(0.22, 0.23, 0.24, 0.0), 0.45, 6, 3)
	mb.add_box(Vector3(0, 0.22, 0.0), Vector3(0.36, 0.3, 0.05), Color(0.25, 0.26, 0.28, 0.0))
	_seat_mesh = mb.commit()
	return _seat_mesh


static func _person() -> ArrayMesh:
	## A seated passenger (or pilot) at the seat origin. Vertex alpha: 1 = shirt (instance colour),
	## 0.5 = skin (instance tone), 0 = fixed (hair, trousers).
	if _person_mesh != null:
		return _person_mesh
	var mb := MeshBuilder.new()
	var shirt := Color(1, 1, 1, 1)
	var skin := Color(1, 1, 1, 0.5)
	# torso, shoulders and upper arms resting on the arm rests
	mb.add_rounded_box(Vector3(0, 0.79, 0.07), Vector3(0.38, 0.5, 0.23), shirt, 0.4, 10, 6)
	mb.add_rounded_box(Vector3(0, 0.99, 0.07), Vector3(0.44, 0.12, 0.22), shirt, 0.5, 10, 4)
	for sx in [-0.23, 0.23]:
		mb.add_rounded_box(Vector3(sx, 0.8, 0.02), Vector3(0.09, 0.32, 0.11), shirt, 0.5, 6, 4)
		mb.add_rounded_box(Vector3(sx * 0.9, 0.66, -0.14), Vector3(0.08, 0.08, 0.3), skin, 0.5, 6, 3)
	# lap and legs
	mb.add_rounded_box(Vector3(0, 0.53, -0.14), Vector3(0.36, 0.14, 0.42), Color(0.18, 0.2, 0.26, 0.0), 0.4, 8, 3)
	# neck, head and hair
	mb.add_cylinder(Vector3(0, 1.03, 0.06), Vector3(0, 1.09, 0.05), 0.05, 0.05, 10, skin, false)
	mb.add_sphere(Vector3(0, 1.18, 0.04), Vector3(0.092, 0.115, 0.105), 16, 10, skin)
	mb.add_sphere(Vector3(0, 1.215, 0.065), Vector3(0.098, 0.088, 0.1), 16, 8, Color(0.15, 0.1, 0.07, 0.0))
	_person_mesh = mb.commit()
	return _person_mesh
