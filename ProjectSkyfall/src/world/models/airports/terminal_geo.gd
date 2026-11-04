extends RefCounted
## Airport architecture (terminal halls, roofs, control towers, landside buildings) built into
## the airport's shared MeshBuilders. Safe on worker threads. m = {glass, concrete, metal, cab,
## misc}: glass/concrete/metal/cab use the facility shader (fixed colours, glass glows at night),
## misc takes vertex colours (the per-airport cladding, roof and frame colours; fine detail with a
## view range), far the same for big structures (roofs, towers, car parks) seen from any distance.
##
## Lit interiors: each glazed face is open (mullions only) onto a shallow room: a floor, a
## glowing ceiling and back wall (facility glass: warm emission at night), seat rows, shops,
## hanging signs and people. Everything in the room faces outward, so it is culled from inside
## the building and the walkable TerminalInterior still looks out through the glass.

const K := preload("res://src/world/models/model_kit.gd")
const FL := 4.5          # departures floor (TerminalInterior.FLOOR, jet bridge sill)
const DARK := Color(0.08, 0.1, 0.12)
const FLOOR_C := Color(0.74, 0.72, 0.68)
const SEAT_C := Color(0.13, 0.17, 0.26)
const PEOPLE := [Color(0.12, 0.12, 0.14), Color(0.2, 0.22, 0.3), Color(0.35, 0.18, 0.15), Color(0.5, 0.48, 0.44),
	Color(0.16, 0.26, 0.2), Color(0.6, 0.55, 0.45), Color(0.25, 0.2, 0.3), Color(0.7, 0.68, 0.64)]
const SHOPS := [Color(0.85, 0.22, 0.18), Color(0.95, 0.75, 0.2), Color(0.2, 0.45, 0.8), Color(0.15, 0.6, 0.4),
	Color(0.9, 0.9, 0.88), Color(0.55, 0.3, 0.6), Color(0.95, 0.5, 0.15), Color(0.2, 0.2, 0.22)]
const WARM := Color(1.0, 0.86, 0.62)


# ------------------------------------------------------------------ primitives
static func wq(mb: MeshBuilder, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nrm: Vector3, col: Color, uv_off: Vector2 = Vector2.ZERO) -> void:
	## Quad p0..p3 (around the edge) facing nrm, UVs in metres (u along p0->p1, v along p0->p3).
	var u := p1 - p0
	var v := p3 - p0
	var lu := u.length()
	var lv := v.length()
	var i0 := mb.add_vertex(p0, nrm, col, uv_off)
	var i1 := mb.add_vertex(p1, nrm, col, uv_off + Vector2(lu, 0))
	var i2 := mb.add_vertex(p2, nrm, col, uv_off + Vector2(lu, lv))
	var i3 := mb.add_vertex(p3, nrm, col, uv_off + Vector2(0, lv))
	if u.cross(v).dot(nrm) >= 0.0:
		mb.add_tri_idx(i0, i2, i1)
		mb.add_tri_idx(i0, i3, i2)
	else:
		mb.add_tri_idx(i0, i1, i2)
		mb.add_tri_idx(i0, i2, i3)


static func push_light(buf: PackedFloat32Array, p: Vector3, size: float, col: Color, facing: float) -> void:
	buf.append_array([size, 0.0, 0.0, p.x, 0.0, size, 0.0, p.y, 0.0, 0.0, size, p.z, col.r, col.g, col.b, facing])


static func label(prod: Dictionary, text: String, p: Vector3, facing: Vector2, h: float, col: Color, outline: int = 0) -> void:
	var zv := Vector3(facing.x, 0, facing.y).normalized()
	var xv := Vector3.UP.cross(zv)
	prod.labels.append({"text": text, "pos": p, "basis": Basis(xv, Vector3.UP, zv), "size": h, "color": col, "outline": outline})


static func _face_xf(t: Transform3D, face: int, hx: float, hz: float) -> Transform3D:
	## Face frame: x along the face, y up, z out of the building; origin at the face centre.
	## face 0 = +x, 1 = -x, 2 = +z, 3 = -z (building local).
	match face:
		0:
			return t * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(hx, 0, 0))
		1:
			return t * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-hx, 0, 0))
		2:
			return t * Transform3D(Basis(), Vector3(0, 0, hz))
	return t * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -hz))


# ------------------------------------------------------------------ lit glazed face
static func light_face(m: Dictionary, prod: Dictionary, xf: Transform3D, W: float, y0: float, y1: float, D: float, st: Dictionary,
		rng: RandomNumberGenerator, props: bool, mull: float) -> void:
	var hw := W * 0.5
	var g: MeshBuilder = m.glass
	var v: MeshBuilder = m.misc
	g.xf = xf
	v.xf = xf
	var hgt := y1 - y0
	var lower := minf(3.6, hgt * 0.45)
	# room: glowing upper back wall and ceiling, shopfronts below, polished floor
	wq(g, Vector3(-hw, y0 + lower, -D), Vector3(hw, y0 + lower, -D), Vector3(hw, y1, -D), Vector3(-hw, y1, -D), Vector3(0, 0, 1), Color.WHITE)
	wq(g, Vector3(-hw, y1 - 0.3, 0.0), Vector3(hw, y1 - 0.3, 0.0), Vector3(hw, y1 - 0.3, -D), Vector3(-hw, y1 - 0.3, -D), Vector3.DOWN, Color.WHITE)
	wq(v, Vector3(-hw, y0 + 0.03, 0.0), Vector3(hw, y0 + 0.03, 0.0), Vector3(hw, y0 + 0.03, -D), Vector3(-hw, y0 + 0.03, -D), Vector3.UP, FLOOR_C)
	var x := -hw
	while x < hw - 1.0:
		var w := minf(rng.randf_range(7.0, 16.0), hw - x)
		var sc: Color = SHOPS[rng.randi() % SHOPS.size()]
		var wall := Color(0.86, 0.84, 0.8) if rng.randf() < 0.5 else Color(0.62, 0.6, 0.57)
		wq(v, Vector3(x, y0, -D + 0.02), Vector3(x + w, y0, -D + 0.02), Vector3(x + w, y0 + lower, -D + 0.02), Vector3(x, y0 + lower, -D + 0.02), Vector3(0, 0, 1), wall)
		if props and rng.randf() < 0.6:
			# shop fascia
			wq(v, Vector3(x + 0.4, y0 + lower - 0.9, -D + 0.06), Vector3(x + w - 0.4, y0 + lower - 0.9, -D + 0.06),
				Vector3(x + w - 0.4, y0 + lower - 0.2, -D + 0.06), Vector3(x + 0.4, y0 + lower - 0.2, -D + 0.06), Vector3(0, 0, 1), sc)
		x += w
	if props:
		# seat rows, people and the yellow wayfinding signs hung from the ceiling
		for rz in [2.4, 4.2]:
			if rz > D - 1.5:
				continue
			var sx := -hw + 2.0
			while sx < hw - 6.0:
				var sw := rng.randf_range(6.0, 12.0)
				wq(v, Vector3(sx, y0, -rz), Vector3(minf(sx + sw, hw), y0, -rz), Vector3(minf(sx + sw, hw), y0 + 0.85, -rz), Vector3(sx, y0 + 0.85, -rz), Vector3(0, 0, 1), SEAT_C)
				sx += sw + rng.randf_range(3.0, 8.0)
		var n_p := int(W / 6.5)
		for k in n_p:
			var px := rng.randf_range(-hw + 0.5, hw - 0.5)
			var pz := -rng.randf_range(1.0, maxf(D - 1.5, 1.2))
			var ph := rng.randf_range(1.55, 1.85)
			var pw := rng.randf_range(0.42, 0.55)
			wq(v, Vector3(px - pw * 0.5, y0, pz), Vector3(px + pw * 0.5, y0, pz), Vector3(px + pw * 0.4, y0 + ph, pz), Vector3(px - pw * 0.4, y0 + ph, pz), Vector3(0, 0, 1),
				PEOPLE[rng.randi() % PEOPLE.size()])
		var ns := int(W / 45.0)
		for k in ns:
			var gx := -hw + (k + 0.5) * W / maxf(ns, 1)
			wq(v, Vector3(gx - 1.6, y0 + 3.0, -1.6), Vector3(gx + 1.6, y0 + 3.0, -1.6), Vector3(gx + 1.6, y0 + 3.6, -1.6), Vector3(gx - 1.6, y0 + 3.6, -1.6), Vector3(0, 0, 1), Color(0.98, 0.82, 0.1))
	# ceiling lights: warm sprites glowing through the glass at night
	var buf: PackedFloat32Array = prod.lights
	var nl := int(W / 14.0)
	for k in nl:
		var lx := -hw + (k + 0.5) * W / maxf(nl, 1)
		push_light(buf, xf * Vector3(lx, y1 - 0.8, -minf(D * 0.5, 3.0)), 0.7, WARM, -1.0)
	# curtain wall: mullions, transom, sill and head
	var fr: Color = st.frame
	var nm := maxi(1, int(W / mull))
	for k in nm + 1:
		var mx := -hw + W * float(k) / nm
		v.add_box(Vector3(mx, (y0 + y1) * 0.5, 0.12), Vector3(0.22, hgt, 0.3), fr)
	v.add_box(Vector3(0, y0 + 0.2, 0.12), Vector3(W, 0.4, 0.34), fr)
	v.add_box(Vector3(0, y1 - 0.25, 0.12), Vector3(W, 0.5, 0.34), fr)
	if hgt > 8.0:
		v.add_box(Vector3(0, y0 + hgt * 0.55, 0.12), Vector3(W, 0.18, 0.26), fr)
	g.xf = Transform3D.IDENTITY
	v.xf = Transform3D.IDENTITY


# ------------------------------------------------------------------ terminal unit
static func unit(m: Dictionary, prod: Dictionary, L: Dictionary, b: Dictionary, st: Dictionary, walk: bool, seed_v: int) -> void:
	## A terminal or concourse: ground level, glazed departures level, optional upper level,
	## structural columns and the style's roof.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var c: Vector2 = b.center
	var ax: Vector2 = (b.axis as Vector2).normalized()
	var t := Transform3D(Basis(Vector3.UP, atan2(ax.x, ax.y)), Vector3(c.x, 0, c.y))
	var bd: float = b.depth
	var bl: float = b.len
	var bh: float = b.h
	var hx := bd * 0.5
	var hz := bl * 0.5
	var big := String(L.size) == "hub"
	var levels := int(b.get("levels", 1))
	var top := bh + (6.5 if levels >= 3 else 0.0)
	var clad: Color = st.clad
	# landside faces (the kerb side) get a lit arrivals hall on the ground level
	var land := [false, false, false, false]
	var ls: Dictionary = L.get("landside", {})
	if walk and not ls.is_empty():
		var lo: Vector2 = ls.origin
		var ln: Vector2 = ls.normal
		var ll: Vector3 = t.basis.inverse() * Vector3(ln.x, 0, ln.y)
		var lp: Vector3 = t.affine_inverse() * Vector3(lo.x, 0, lo.y)
		if absf(ll.x) > 0.7 and absf(absf(lp.x) - hx) < 6.0:
			land[0 if ll.x > 0.0 else 1] = true
		elif absf(ll.z) > 0.7 and absf(absf(lp.z) - hz) < 6.0:
			land[2 if ll.z > 0.0 else 3] = true
	var D := clampf(bd * 0.12, 6.0, 11.0)
	# ground level core (baggage, ramp services) recessed behind any lit landside hall
	var inset := [0.6, 0.6, 0.6, 0.6]
	for f in 4:
		if land[f]:
			inset[f] = D + 0.4
	var x0: float = -hx + float(inset[1])
	var x1: float = hx - float(inset[0])
	var z0: float = -hz + float(inset[3])
	var z1: float = hz - float(inset[2])
	var v: MeshBuilder = m.far
	v.xf = t
	v.add_box(Vector3((x0 + x1) * 0.5, FL * 0.5, (z0 + z1) * 0.5), Vector3(x1 - x0, FL, z1 - z0), clad * Color(0.82, 0.82, 0.82))
	# dark service windows along the airside ground floor
	for sx in [-1.0, 1.0]:
		if not land[0 if sx > 0.0 else 1]:
			v.add_box(Vector3(sx * (hx - 0.5), FL * 0.55, 0), Vector3(0.2, 1.4, bl * 0.86), DARK)
	v.xf = Transform3D.IDENTITY
	for f in 4:
		var W := bl if f < 2 else bd
		var fx := _face_xf(t, f, hx, hz)
		if land[f]:
			light_face(m, prod, fx, W - 0.4, 0.0, FL - 0.4, D, st, rng, true, 4.5)
		# departures level (glazed full height) and the upper level
		light_face(m, prod, fx, W, FL, bh, D, st, rng, true, 3.2 if W < 400.0 else 4.8)
		if top > bh + 0.5:
			light_face(m, prod, fx, W, bh + 0.6, top, 5.0, st, rng, false, 6.4)
	# floor-line and roof-line bands in the cladding colour
	v.xf = t
	for yb in ([FL, bh] if top > bh + 0.5 else [FL]):
		v.add_box(Vector3(0, yb, 0), Vector3(bd + 0.8, 0.9, bl + 0.8), clad)
	v.xf = Transform3D.IDENTITY
	roof(m, prod, t, L, st, hx, hz, top, big, rng)


# ------------------------------------------------------------------ roofs
static func _rh(kind: String, x: float, z: float, hx: float, hz: float, rise: float) -> float:
	var u := clampf(x / hx, -1.0, 1.0)
	match kind:
		"arch":
			return rise * sqrt(maxf(0.0, 1.0 - u * u))
		"vault":
			return rise * (1.0 - u * u)
		"wave":
			return 2.6 * sin((z + hz) / 64.0 * TAU) + rise * 0.35 * (1.0 - u * u)
		"sag":
			return rise * u * u + 0.6 * sin((z + hz) / 90.0 * TAU)
		"shell":
			var s := fposmod(z + hz, 72.0) / 72.0
			return rise * pow(sin(PI * s), 0.6) * (1.0 - 0.35 * u * u)
		"gable":
			return rise * (1.0 - absf(u))
		"tent":
			var px := hx * 0.45
			var dz := fposmod(z + hz, 48.0) - 24.0
			var d := Vector2(absf(x) - px, dz).length()
			return 1.5 + rise * pow(maxf(0.0, 1.0 - d / 30.0), 1.5)
	return 0.0


static func roof(m: Dictionary, prod: Dictionary, t: Transform3D, L: Dictionary, st: Dictionary, bhx: float, bhz: float, y0: float, big: bool, rng: RandomNumberGenerator) -> void:
	var kind: String = st.roof
	var ov := 7.0 if big else 4.0
	var hx := bhx + ov
	var hz := bhz + ov
	var col: Color = st.roof_col
	var soff := Color(0.9, 0.89, 0.86)
	var v: MeshBuilder = m.far
	var rise := 0.0
	match kind:
		"arch":
			rise = clampf(hx * 0.42, 5.0, 26.0)
		"vault":
			rise = clampf(hx * 0.16, 3.0, 12.0)
		"wave":
			rise = 3.0
		"sag":
			rise = clampf(hx * 0.12, 2.5, 8.0)
		"shell":
			rise = clampf(hx * 0.22, 4.0, 14.0)
		"gable":
			rise = clampf(hx * 0.38, 3.0, 12.0)
		"tent":
			rise = clampf(hx * 0.3, 8.0, 20.0)
	if kind == "saw":
		_saw_roof(m, t, hx, hz, y0, col, soff)
	elif kind == "flat":
		v.xf = t
		v.add_box(Vector3(0, y0 + 0.7, 0), Vector3(hx * 2.0, 1.4, hz * 2.0), col)
		v.add_box(Vector3(0, y0 + 1.6, 0), Vector3(bhx * 2.0 - 4.0, 0.6, bhz * 2.0 - 4.0), col * Color(0.85, 0.85, 0.85))
		# deep fascia with a coloured accent line
		for sx in [-1.0, 1.0]:
			v.add_box(Vector3(sx * hx, y0 + 0.9, 0), Vector3(0.4, 1.8, hz * 2.0), Color(0.95, 0.95, 0.95))
			v.add_box(Vector3(sx * (hx + 0.1), y0 + 0.5, 0), Vector3(0.3, 0.35, hz * 2.0), st.accent)
		v.xf = Transform3D.IDENTITY
	else:
		var nx := 16 if kind == "tent" else 12
		var cell := 7.0 if kind == "tent" else (10.0 if kind in ["wave", "shell"] else 18.0)
		var nz := clampi(int(hz * 2.0 / cell), 4, 140)
		_height_roof(v, t, kind, hx, hz, y0, rise, nx, nz, col, soff)
		# glazed lunettes / gable ends under curved roofs (glow at night like the Indianapolis hall)
		if kind in ["arch", "vault", "gable", "shell", "tent", "sag"]:
			var g: MeshBuilder = m.glass
			g.xf = t
			for sz in [-1.0, 1.0]:
				var zz: float = sz * bhz
				var n := 12
				for i in n:
					var xa := -bhx + bhx * 2.0 * float(i) / n
					var xb := -bhx + bhx * 2.0 * float(i + 1) / n
					var ya := _rh(kind, xa, zz, hx, hz, rise)
					var yb := _rh(kind, xb, zz, hx, hz, rise)
					if maxf(ya, yb) < 0.3:
						continue
					wq(g, Vector3(xa, y0, zz), Vector3(xb, y0, zz), Vector3(xb, y0 + yb, zz), Vector3(xa, y0 + ya, zz), Vector3(0, 0, sz), Color.WHITE, Vector2(xa + bhx, 0))
			g.xf = Transform3D.IDENTITY
	# structure: white ribs over arches, tree columns holding the eaves on big halls
	var fr: Color = st.frame
	if kind in ["arch", "vault"] and big:
		v.xf = t
		var nr := int(hz * 2.0 / 24.0)
		for k in nr + 1:
			var zr := -hz + hz * 2.0 * float(k) / maxf(nr, 1)
			var prev := Vector3.ZERO
			for i in 13:
				var xr := -hx + hx * 2.0 * float(i) / 12.0
				var p := Vector3(xr, y0 + _rh(kind, xr, zr, hx, hz, rise) + 0.45, zr)
				if i > 0:
					K.bar(v, prev, p, 0.45, Color(0.97, 0.97, 0.98))
				prev = p
		v.xf = Transform3D.IDENTITY
	if big and kind in ["arch", "vault", "wave", "shell", "sag", "tent"]:
		v.xf = t
		var nt := int(hz * 2.0 / 24.0)
		for k in nt + 1:
			var zt := -hz + 6.0 + (hz * 2.0 - 12.0) * float(k) / maxf(nt, 1)
			var tc: Color = fr
			if bool(st.get("rainbow", false)):
				tc = Color.from_hsv(0.62 - 0.62 * float(k) / maxf(nt, 1), 0.75, 0.9)
			for sx in [-1.0, 1.0]:
				var xt: float = sx * (bhx + ov * 0.55)
				var trunk_top := Vector3(xt, FL + 2.0, zt)
				K.cyl(v, Vector3(xt, 0, zt), trunk_top, 0.75, 0.6, 8, tc, false)
				for dz in [-7.0, 0.0, 7.0]:
					var ex: float = xt - sx * 3.0
					var ez: float = zt + dz
					var ey: float = y0 + _rh(kind, ex, ez, hx, hz, rise) - 0.7
					K.bar(v, trunk_top, Vector3(ex, ey, ez), 0.32, tc)
		v.xf = Transform3D.IDENTITY


static func _height_roof(v: MeshBuilder, t: Transform3D, kind: String, hx: float, hz: float, y0: float, rise: float, nx: int, nz: int, col: Color, soff: Color) -> void:
	v.xf = t
	var th := 0.9
	for layer in 2:
		var base := v.vcount()
		for j in nz + 1:
			var z := -hz + hz * 2.0 * float(j) / nz
			for i in nx + 1:
				var x := -hx + hx * 2.0 * float(i) / nx
				var y := _rh(kind, x, z, hx, hz, rise)
				var e := 0.5
				var gx := (_rh(kind, x + e, z, hx, hz, rise) - _rh(kind, x - e, z, hx, hz, rise)) / (2.0 * e)
				var gz := (_rh(kind, x, z + e, hx, hz, rise) - _rh(kind, x, z - e, hx, hz, rise)) / (2.0 * e)
				var n := Vector3(-gx, 1.0, -gz).normalized()
				if layer == 0:
					v.add_vertex(Vector3(x, y0 + y + th, z), n, col)
				else:
					v.add_vertex(Vector3(x, y0 + y, z), -n, soff)
		for j in nz:
			for i in nx:
				var a := base + j * (nx + 1) + i
				var bb := a + 1
				var cc := a + nx + 2
				var d := a + nx + 1
				if layer == 0:
					v.add_tri_idx(a, cc, d)
					v.add_tri_idx(a, bb, cc)
				else:
					v.add_tri_idx(a, d, cc)
					v.add_tri_idx(a, cc, bb)
	# fascia around the edge
	for side in 4:
		var n_e := nz if side < 2 else nx
		for k in n_e:
			var pa: Vector3
			var pb: Vector3
			var out: Vector3
			if side < 2:
				var sx := 1.0 if side == 0 else -1.0
				var za := -hz + hz * 2.0 * float(k) / nz
				var zb := -hz + hz * 2.0 * float(k + 1) / nz
				pa = Vector3(sx * hx, 0, za)
				pb = Vector3(sx * hx, 0, zb)
				out = Vector3(sx, 0, 0)
			else:
				var sz := 1.0 if side == 2 else -1.0
				var xa := -hx + hx * 2.0 * float(k) / nx
				var xb := -hx + hx * 2.0 * float(k + 1) / nx
				pa = Vector3(xa, 0, sz * hz)
				pb = Vector3(xb, 0, sz * hz)
				out = Vector3(0, 0, sz)
			var ya := y0 + _rh(kind, pa.x, pa.z, hx, hz, rise)
			var yb := y0 + _rh(kind, pb.x, pb.z, hx, hz, rise)
			wq(v, Vector3(pa.x, ya, pa.z), Vector3(pb.x, yb, pb.z), Vector3(pb.x, yb + th, pb.z), Vector3(pa.x, ya + th, pa.z), out, Color(0.95, 0.95, 0.95))
	v.xf = Transform3D.IDENTITY


static func _saw_roof(m: Dictionary, t: Transform3D, hx: float, hz: float, y0: float, col: Color, soff: Color) -> void:
	## Sawtooth north lights: sloping bays with glazed (night-glowing) clerestories.
	var v: MeshBuilder = m.far
	var g: MeshBuilder = m.glass
	v.xf = t
	g.xf = t
	var P := 18.0
	var rise := 4.5
	var n := maxi(2, int(hz * 2.0 / P))
	var bay := hz * 2.0 / n
	v.add_box(Vector3(0, y0 + 0.4, 0), Vector3(hx * 2.0, 0.8, hz * 2.0), soff)
	for k in n:
		var za := -hz + k * bay
		var zb := za + bay
		var top := y0 + 0.8 + rise
		wq(v, Vector3(-hx, y0 + 0.8, za), Vector3(hx, y0 + 0.8, za), Vector3(hx, top, zb), Vector3(-hx, top, zb), Vector3(0, bay, -rise).normalized(), col)
		wq(g, Vector3(-hx + 1.0, y0 + 0.8, zb), Vector3(hx - 1.0, y0 + 0.8, zb), Vector3(hx - 1.0, top, zb), Vector3(-hx + 1.0, top, zb), Vector3(0, 0, 1), Color.WHITE)
		for sx in [-1.0, 1.0]:
			K.tri(v, Vector3(sx * hx, y0 + 0.8, za), Vector3(sx * hx, y0 + 0.8, zb), Vector3(sx * hx, top, zb), Vector3(sx, 0, 0), col * Color(0.9, 0.9, 0.9))
	v.xf = Transform3D.IDENTITY
	g.xf = Transform3D.IDENTITY


# ------------------------------------------------------------------ control towers
static func tower(m: Dictionary, prod: Dictionary, tp: Vector2, th: float, kind: String, st: Dictionary) -> void:
	var con: MeshBuilder = m.concrete
	var gl: MeshBuilder = m.glass
	var v: MeshBuilder = m.far
	var tr := 4.0 if th > 50.0 else (2.6 if th > 20.0 else 1.6)
	var P := Vector3(tp.x, 0, tp.y)
	var white := Color(0.94, 0.94, 0.93)
	var shaft_c: Color = st.clad
	if th > 20.0:
		# base building with its own glazing band and roof plant
		var bb := Vector3(tr * 3.6, 0, tr * 0.5)
		v.add_box(P + bb + Vector3(0, 4.5, 0), Vector3(tr * 5.5, 9.0, tr * 4.0), shaft_c)
		gl.add_box(P + bb + Vector3(0, 5.0, 0), Vector3(tr * 5.5 + 0.2, 2.6, tr * 4.0 + 0.2), Color.WHITE, true)
	var cab_y := th
	var cab_r := tr * 2.2
	match kind:
		"torch":
			K.cyl(v, P, P + Vector3(0, th * 0.62, 0), tr * 1.2, tr * 0.85, 16, white, false)
			var prev_r := tr * 0.85
			for k in 6:
				var ya := th * 0.62 + (th - 1.0 - th * 0.62) * float(k) / 6.0
				var yb := th * 0.62 + (th - 1.0 - th * 0.62) * float(k + 1) / 6.0
				var rb := tr * 0.85 + tr * 1.75 * pow(float(k + 1) / 6.0, 2.2)
				K.cyl(v, P + Vector3(0, ya, 0), P + Vector3(0, yb, 0), prev_r, rb, 16, white, false)
				prev_r = rb
			K.cyl(v, P + Vector3(0, th - 1.0, 0), P + Vector3(0, th, 0), prev_r, prev_r, 16, white)
			cab_r = tr * 2.3
		"flared":
			K.cyl(con, P, P + Vector3(0, th - 14.0, 0), tr * 1.45, tr * 0.8, 12, Color.WHITE)
			for k in 4:
				var ang := TAU * k / 4.0
				var d := Vector3(cos(ang), 0, sin(ang))
				v.add_box_xf(Transform3D(Basis(Vector3.UP, -ang), P + d * tr * 1.0 + Vector3(0, (th - 14.0) * 0.5, 0)), Vector3(tr * 0.8, th - 14.0, tr * 0.25), white)
			K.cyl(v, P + Vector3(0, th - 14.0, 0), P + Vector3(0, th - 6.0, 0), tr * 0.8, tr * 1.5, 12, white, false)
			K.cyl(v, P + Vector3(0, th - 6.0, 0), P + Vector3(0, th, 0), tr * 1.5, tr * 2.7, 12, white)
			gl.add_box(P + Vector3(0, th - 9.0, 0), Vector3(tr * 1.6, 3.0, tr * 1.6), Color.WHITE, true)
			cab_r = tr * 2.4
		"slender":
			K.cyl(con, P, P + Vector3(0, th - 8.0, 0), tr * 1.05, tr * 0.6, 12, Color.WHITE)
			for k in 3:
				var ang2 := TAU * k / 3.0
				var d2 := Vector3(cos(ang2), 0, sin(ang2))
				K.tri(v, P + d2 * tr * 2.6, P + d2 * tr * 0.5, P + d2 * tr * 0.5 + Vector3(0, th - 6.0, 0), Vector3(-d2.z, 0, d2.x), white)
				K.tri(v, P + d2 * tr * 2.6, P + d2 * tr * 0.5 + Vector3(0, th - 6.0, 0), P + d2 * tr * 0.5, Vector3(d2.z, 0, -d2.x), white)
			K.cyl(v, P + Vector3(0, th - 8.0, 0), P + Vector3(0, th, 0), tr * 0.6, tr * 1.9, 12, white)
			cab_r = tr * 1.95
		"cylinder":
			K.cyl(con, P, P + Vector3(0, th - 4.0, 0), tr * 1.2, tr * 1.2, 16, Color.WHITE)
			var nb := int(th / 10.0)
			for k in nb:
				K.cyl(v, P + Vector3(0, 8.0 + k * 10.0, 0), P + Vector3(0, 8.6 + k * 10.0, 0), tr * 1.26, tr * 1.26, 16, shaft_c * Color(0.8, 0.8, 0.8), false)
			K.cyl(con, P + Vector3(0, th - 4.0, 0), P + Vector3(0, th, 0), tr * 1.2, tr * 2.4, 16, Color.WHITE)
			cab_r = tr * 2.3
		"box":
			v.add_box(P + Vector3(0, (th - 1.0) * 0.5, 0), Vector3(tr * 2.4, th - 1.0, tr * 2.4), shaft_c)
			gl.add_box(P + Vector3(0, (th - 1.0) * 0.5, tr * 1.2), Vector3(tr * 0.9, th - 4.0, 0.2), Color.WHITE, true)
			v.add_box(P + Vector3(0, th - 0.5, 0), Vector3(tr * 4.6, 1.0, tr * 4.6), shaft_c)
			cab_r = tr * 2.0
		"lantern":
			var hq := th - 18.0
			v.add_box(P + Vector3(0, hq * 0.5, 0), Vector3(tr * 2.2, hq, tr * 2.2), white)
			for k in 4:
				var ang3 := TAU * k / 4.0 + PI * 0.25
				var d3 := Vector3(cos(ang3), 0, sin(ang3))
				v.add_box(P + d3 * tr * 1.45 + Vector3(0, hq * 0.5, 0), Vector3(tr * 0.5, hq, tr * 0.5), shaft_c)
			gl.add_box(P + Vector3(0, hq + 7.0, 0), Vector3(tr * 3.4, 14.0, tr * 3.4), Color.WHITE, true)
			for k in 8:
				var a4 := TAU * k / 8.0
				v.add_box(P + Vector3(cos(a4) * tr * 1.72, hq + 7.0, sin(a4) * tr * 1.72), Vector3(0.3, 14.0, 0.3), st.frame)
			v.add_box(P + Vector3(0, hq + 14.5, 0), Vector3(tr * 3.8, 1.0, tr * 3.8), white)
			K.cyl(v, P + Vector3(0, hq + 15.0, 0), P + Vector3(0, th, 0), tr * 0.9, tr * 2.0, 12, white)
			cab_r = tr * 2.1
		_:
			K.cyl(con, P, P + Vector3(0, th - 4.0, 0), tr * 1.3, tr, 12, Color.WHITE)
			for k5 in 4:
				var ang5 := TAU * k5 / 4.0 + PI * 0.25
				var dv := Vector3(cos(ang5), 0, sin(ang5))
				v.add_box_xf(Transform3D(Basis(Vector3.UP, -ang5), P + dv * tr * 1.05 + Vector3(0, (th - 4.0) * 0.5, 0)), Vector3(tr * 0.5, th - 4.0, tr * 0.35), Color(0.8, 0.8, 0.78))
			K.cyl(con, P + Vector3(0, th - 4.0, 0), P + Vector3(0, th - 3.4, 0), tr * 1.05, tr * 1.85, 12, Color.WHITE)
			K.cyl(gl, P + Vector3(0, th - 3.4, 0), P + Vector3(0, th - 0.5, 0), tr * 1.85, tr * 1.85, 12, Color.WHITE)
			K.cyl(con, P + Vector3(0, th - 0.5, 0), P + Vector3(0, th, 0), tr * 2.65, tr * 2.6, 16, Color.WHITE)
			cab_r = tr * 2.2
	_cab(m, prod, P, cab_y, cab_r, tr, kind, st)


static func _cab(m: Dictionary, prod: Dictionary, P: Vector3, y: float, r: float, tr: float, kind: String, st: Dictionary) -> void:
	var cab: MeshBuilder = m.cab
	var v: MeshBuilder = m.far
	var ch := 6.5 if kind == "slender" else 4.8
	var square := kind == "box"
	var white := Color(0.94, 0.94, 0.93)
	if square:
		cab.add_box(P + Vector3(0, y + ch * 0.5, 0), Vector3(r * 1.8, ch, r * 1.8), Color.WHITE)
		v.add_box(P + Vector3(0, y + ch + 0.4, 0), Vector3(r * 2.1, 0.8, r * 2.1), white)
	else:
		cab.add_cylinder(P + Vector3(0, y, 0), P + Vector3(0, y + ch, 0), r * 0.88, r, 12, Color.WHITE, false)
		for k in 12:
			var a := TAU * (float(k) + 0.5) / 12.0
			var d := Vector3(cos(a), 0, sin(a))
			K.cyl(v, P + d * r * 0.87 + Vector3(0, y, 0), P + d * r * 0.99 + Vector3(0, y + ch, 0), 0.08, 0.08, 4, Color(0.24, 0.25, 0.27), false)
		var roof_r := r * (1.35 if kind in ["flared", "torch"] else 1.12)
		K.cyl(v, P + Vector3(0, y + ch, 0), P + Vector3(0, y + ch + 0.8, 0), roof_r, roof_r * 0.95, 16, white)
		if kind == "slender":
			K.cone(v, P + Vector3(0, y + ch + 0.8, 0), P + Vector3(0, y + ch + 9.0, 0), r * 0.8, 12, white)
			K.cyl(v, P + Vector3(0, y + ch + 9.0, 0), P + Vector3(0, y + ch + 24.0, 0), 0.35, 0.08, 6, Color(0.8, 0.82, 0.85), false)
		elif kind == "torch":
			K.cyl(v, P + Vector3(0, y + ch + 0.8, 0), P + Vector3(0, y + ch + 3.0, 0), roof_r * 0.95, roof_r * 1.12, 16, white)
	var rt := y + ch + (3.0 if kind == "torch" else 0.8)
	# radome and masts
	v.add_sphere(P + Vector3(tr * 0.7, rt + tr * 0.28, 0), Vector3.ONE * tr * 0.3, 10, 6, Color(0.92, 0.92, 0.9))
	K.cyl(v, P + Vector3(-tr * 0.6, rt, tr * 0.4), P + Vector3(-tr * 0.6, rt + 3.1, tr * 0.4), 0.06, 0.04, 4, Color(0.7, 0.72, 0.74), false)
	K.cyl(v, P + Vector3(0, rt, 0), P + Vector3(0, rt + 4.6, 0), 0.12, 0.08, 4, Color(0.8, 0.1, 0.1))
	if kind == "cylinder":
		for k in 3:
			var a2 := TAU * k / 3.0
			K.bar(v, P + Vector3(cos(a2) * 1.2, rt, sin(a2) * 1.2), P + Vector3(0, rt + 9.0, 0), 0.07, Color(0.85, 0.85, 0.85))
	prod.beacon = P + Vector3(0, rt + 0.6 + (24.0 if kind == "slender" else 0.0), 0)
	prod.tower_top = P + Vector3(0, y + 3.0, 0)


# ------------------------------------------------------------------ landside buildings
static func _frame(b: Dictionary) -> Transform3D:
	var c: Vector2 = b.center
	var ax: Vector2 = (b.axis as Vector2).normalized()
	return Transform3D(Basis(Vector3.UP, atan2(ax.x, ax.y)), Vector3(c.x, 0, c.y))


static func garage(m: Dictionary, prod: Dictionary, b: Dictionary, st: Dictionary, seed_v: int) -> void:
	## Multi-storey car park: open decks between parapet bands, a dark interior, stair cores,
	## cars on the roof deck and along the open edges.
	var t := _frame(b)
	var bd: float = b.depth
	var bl: float = b.len
	var lv := int(b.get("levels", 4))
	var fh := 3.2
	var v: MeshBuilder = m.far
	var con: MeshBuilder = m.concrete
	var clad: Color = st.clad
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	con.xf = t
	v.xf = t
	v.add_box(Vector3(0, lv * fh * 0.5, 0), Vector3(bd - 5.0, lv * fh, bl - 5.0), Color(0.16, 0.16, 0.17))
	for k in lv + 1:
		con.add_box(Vector3(0, k * fh + 0.2, 0), Vector3(bd, 0.4, bl), Color.WHITE, true)
		if k > 0:
			for sx in [-1.0, 1.0]:
				v.add_box(Vector3(sx * (bd * 0.5 + 0.1), k * fh + 0.95, 0), Vector3(0.3, 1.1, bl + 0.4), clad)
				v.add_box(Vector3(0, k * fh + 0.95, sx * (bl * 0.5 + 0.1)), Vector3(bd + 0.4, 1.1, 0.3), clad)
	var nc := int(bl / 8.0)
	for k in nc + 1:
		var zc := -bl * 0.5 + bl * float(k) / nc
		for sx in [-1.0, 1.0]:
			v.add_box(Vector3(sx * (bd * 0.5 - 0.4), lv * fh * 0.5, zc), Vector3(0.5, lv * fh, 0.5), Color(0.7, 0.7, 0.69))
	# stair and lift cores with glazed shafts
	for sz in [-1.0, 1.0]:
		v.add_box(Vector3(bd * 0.5 - 4.0, (lv * fh + 4.0) * 0.5, sz * (bl * 0.5 - 4.0)), Vector3(7.0, lv * fh + 4.0, 7.0), st.accent)
	var g: MeshBuilder = m.glass
	g.xf = t
	g.add_box(Vector3(bd * 0.5 - 0.4, (lv * fh + 4.0) * 0.5, -bl * 0.5 + 4.0), Vector3(0.3, lv * fh + 3.0, 4.0), Color.WHITE, true)
	g.xf = Transform3D.IDENTITY
	con.xf = Transform3D.IDENTITY
	v.xf = Transform3D.IDENTITY
	var cols := [Color(0.9, 0.9, 0.9), Color(0.1, 0.1, 0.12), Color(0.55, 0.57, 0.6), Color(0.6, 0.1, 0.1), Color(0.15, 0.25, 0.5), Color(0.75, 0.75, 0.78)]
	var ny := int(bl / 2.8)
	for k in lv + 1:
		var yk := k * fh + 0.4
		var rows := [-bd * 0.5 + 3.0, bd * 0.5 - 3.0] if k < lv else [-bd * 0.5 + 3.0, -bd * 0.5 + 15.0, -6.0, 6.0, bd * 0.5 - 15.0, bd * 0.5 - 3.0]
		for rx in rows:
			for j in ny:
				if r.randf() > (0.75 if k < lv else 0.55):
					continue
				var p := t * Vector3(rx, yk, -bl * 0.5 + 1.4 + j * 2.8)
				var yaw := atan2((t.basis * Vector3(1, 0, 0)).x, (t.basis * Vector3(1, 0, 0)).z)
				var cc: Color = cols[r.randi() % cols.size()]
				var c2 := cos(yaw)
				var s2 := sin(yaw)
				prod.cars.append_array([c2, 0.0, s2, p.x, 0.0, 1.0, 0.0, p.y, -s2, 0.0, c2, p.z, cc.r, cc.g, cc.b, 0.0])
	var n2 := (t.basis * Vector3(1, 0, 0))
	label(prod, "P", t * Vector3(bd * 0.5 + 0.4, lv * fh - 1.0, bl * 0.5 - 12.0), Vector2(n2.x, n2.z), 5.0, Color(0.95, 0.97, 1.0), 8)


static func hotel(m: Dictionary, prod: Dictionary, b: Dictionary, st: Dictionary, airport_short: String) -> void:
	var t := _frame(b)
	var bd: float = b.depth
	var bl: float = b.len
	var bh: float = b.h
	var v: MeshBuilder = m.far
	var g: MeshBuilder = m.glass
	v.xf = t
	g.xf = t
	v.add_box(Vector3(0, 4.0, 0), Vector3(bd + 16.0, 8.0, bl + 10.0), st.clad)
	g.add_box(Vector3(0, 3.0, 0), Vector3(bd + 16.4, 4.0, bl + 10.4), Color.WHITE, true)
	g.add_box(Vector3(0, 8.0 + (bh - 8.0) * 0.5, 0), Vector3(bd, bh - 8.0, bl), Color.WHITE, true)
	var nf := int(bl / 4.0)
	for k in nf + 1:
		var z := -bl * 0.5 + bl * float(k) / nf
		for sx in [-1.0, 1.0]:
			v.add_box(Vector3(sx * (bd * 0.5 + 0.25), 8.0 + (bh - 8.0) * 0.5, z), Vector3(0.5, bh - 8.0, 0.3), st.frame)
	for sz in [-1.0, 1.0]:
		v.add_box(Vector3(0, 8.0 + (bh - 8.0) * 0.5, sz * (bl * 0.5 + 0.6)), Vector3(bd + 1.0, bh - 8.0, 1.2), st.clad)
	v.add_box(Vector3(0, bh + 1.5, 0), Vector3(bd + 1.0, 3.0, bl + 2.4), st.clad)
	v.xf = Transform3D.IDENTITY
	g.xf = Transform3D.IDENTITY
	var n2 := (t.basis * Vector3(1, 0, 0))
	label(prod, "%s AIRPORT HOTEL" % airport_short.to_upper(), t * Vector3(bd * 0.5 + 0.8, bh + 1.5, 0), Vector2(n2.x, n2.z), 2.4, Color(0.95, 0.95, 0.9), 6)


static func cargo(m: Dictionary, prod: Dictionary, b: Dictionary, st: Dictionary) -> void:
	var t := _frame(b)
	var bd: float = b.depth
	var bl: float = b.len
	var bh: float = b.h
	var mt: MeshBuilder = m.metal
	var v: MeshBuilder = m.far
	mt.xf = t
	v.xf = t
	mt.add_box(Vector3(0, bh * 0.5, 0), Vector3(bd, bh, bl), Color.WHITE, true)
	v.add_box(Vector3(0, bh + 0.4, 0), Vector3(bd + 0.6, 0.8, bl + 0.6), Color(0.85, 0.85, 0.84))
	v.add_box(Vector3(-bd * 0.5 - 6.0, 5.0, 0), Vector3(12.0, 10.0, bl * 0.35), st.clad)
	var nd := int(bl / 9.0)
	for k in nd:
		var z := -bl * 0.5 + (k + 0.5) * bl / nd
		v.add_box(Vector3(bd * 0.5 + 0.1, 2.6, z), Vector3(0.2, 5.0, 6.0), Color(0.42, 0.46, 0.5))
		v.add_box(Vector3(bd * 0.5 + 1.2, 0.6, z), Vector3(2.4, 1.2, 6.4), Color(0.25, 0.25, 0.26))
	mt.xf = Transform3D.IDENTITY
	v.xf = Transform3D.IDENTITY
	var n2 := (t.basis * Vector3(1, 0, 0))
	label(prod, "CARGO CENTRE", t * Vector3(bd * 0.5 + 0.3, bh - 2.5, 0), Vector2(n2.x, n2.z), 3.0, Color(0.1, 0.2, 0.4))


static func landmark(m: Dictionary, prod: Dictionary, b: Dictionary, st: Dictionary) -> void:
	## Signature landside landmarks: LAX-style theme arches, a CDG-style round terminal drum, a
	## Changi-style glass dome with an indoor waterfall.
	var t := _frame(b)
	var v: MeshBuilder = m.far
	var g: MeshBuilder = m.glass
	var white := Color(0.96, 0.96, 0.95)
	v.xf = t
	match String(b.kind):
		"theme":
			var span := 40.0
			var h := 40.0
			for a in [0.0, PI * 0.5]:
				var d := Vector3(cos(a), 0, sin(a))
				var prev := -d * span
				for i in range(1, 17):
					var s := -1.0 + 2.0 * float(i) / 16.0
					var p := d * span * s + Vector3(0, h * (1.0 - s * s), 0)
					K.cyl(v, prev, p, 1.3, 1.3, 8, white, false)
					prev = p
			K.cyl(v, Vector3(0, 0, 0), Vector3(0, 18.0, 0), 4.0, 4.0, 16, white)
			K.cyl(v, Vector3(0, 18.0, 0), Vector3(0, 22.0, 0), 16.0, 20.0, 24, white)
			g.xf = t
			K.cyl(g, Vector3(0, 22.0, 0), Vector3(0, 25.0, 0), 19.5, 19.5, 24, Color.WHITE, false)
			g.xf = Transform3D.IDENTITY
			K.cyl(v, Vector3(0, 25.0, 0), Vector3(0, 26.5, 0), 20.5, 15.0, 24, white)
			push_light(prod.lights, t * Vector3(0, 21.0, 0), 4.0, Color(0.6, 0.3, 1.0), -1.0)
		"drum":
			var r: float = b.len * 0.5
			K.cyl(v, Vector3(0, 0, 0), Vector3(0, 28.0, 0), r, r, 40, Color(0.66, 0.65, 0.62))
			for k in 4:
				K.cyl(v, Vector3(0, 5.0 + k * 6.0, 0), Vector3(0, 6.6 + k * 6.0, 0), r + 0.25, r + 0.25, 40, DARK, false)
			K.cyl(v, Vector3(0, 28.0, 0), Vector3(0, 28.4, 0), r * 0.45, r * 0.45, 32, Color(0.2, 0.32, 0.18))
			# the glass escalator tubes crossing the central well
			g.xf = t
			for a2 in [0.4, 1.4, 2.4]:
				var d2 := Vector3(cos(a2), 0, sin(a2))
				K.cyl(g, -d2 * r * 0.42 + Vector3(0, 4.0, 0), d2 * r * 0.42 + Vector3(0, 22.0, 0), 1.6, 1.6, 8, Color.WHITE, false)
			g.xf = Transform3D.IDENTITY
			for k2 in 7:
				var a3 := TAU * k2 / 7.0
				var p2 := Vector3(cos(a3), 0, sin(a3)) * (r + 26.0)
				K.cyl(v, p2, p2 + Vector3(0, 9.0, 0), 9.0, 9.0, 16, Color(0.7, 0.69, 0.66))
				v.add_box_xf(Transform3D(Basis(Vector3.UP, -a3), Vector3(cos(a3), 0, sin(a3)) * (r + 10.0) + Vector3(0, 5.0, 0)), Vector3(22.0, 4.0, 4.0), Color(0.6, 0.6, 0.58))
		"jewel":
			var r2: float = b.len * 0.5
			v.add_sphere(Vector3(0, 0, 0), Vector3(r2, 34.0, r2 * 0.8), 28, 10, Color(0.38, 0.55, 0.6))
			for k3 in 5:
				var yy := 6.0 + k3 * 6.0
				var rr := r2 * sqrt(maxf(0.0, 1.0 - pow(yy / 34.0, 2.0)))
				K.cyl(v, Vector3(0, yy, 0), Vector3(0, yy + 0.4, 0), rr + 0.3, rr + 0.3, 28, Color(0.85, 0.87, 0.88), false)
			K.cyl(v, Vector3(0, 34.5, 0), Vector3(0, 35.5, 0), 7.0, 7.0, 16, Color(0.85, 0.87, 0.88))
			K.cyl(v, Vector3(0, 2.0, 0), Vector3(0, 34.0, 0), 3.0, 6.0, 16, Color(0.82, 0.9, 0.98), false)
			push_light(prod.lights, t * Vector3(0, 20.0, 0), 6.0, Color(0.5, 0.8, 1.0), -1.0)
	v.xf = Transform3D.IDENTITY


static func people_mover(m: Dictionary, a: Vector2, b: Vector2, accent: Color) -> void:
	## Elevated people-mover guideway between terminal units, with a two-car train.
	var v: MeshBuilder = m.far
	var d := b - a
	var length := d.length()
	if length < 10.0:
		return
	var ax := d / length
	var mid := (a + b) * 0.5
	var t := Transform3D(Basis(Vector3.UP, atan2(ax.x, ax.y)), Vector3(mid.x, 0, mid.y))
	v.xf = t
	v.add_box(Vector3(0, 10.0, 0), Vector3(7.5, 1.4, length), Color(0.86, 0.86, 0.85))
	for sx in [-1.0, 1.0]:
		v.add_box(Vector3(sx * 3.6, 11.2, 0), Vector3(0.3, 1.0, length), Color(0.7, 0.72, 0.74))
	var np := int(length / 34.0)
	for k in range(1, np):
		var z := -length * 0.5 + length * float(k) / np
		v.add_box(Vector3(0, 4.7, z), Vector3(1.8, 9.4, 1.8), Color(0.8, 0.8, 0.79))
	for k2 in 2:
		var zc := -6.0 + k2 * 12.4
		v.add_box(Vector3(-1.6, 12.6, zc), Vector3(2.8, 2.8, 12.0), Color(0.95, 0.95, 0.96))
		v.add_box(Vector3(-1.6, 12.9, zc), Vector3(2.9, 1.0, 11.0), DARK)
		v.add_box(Vector3(-1.6, 11.8, zc), Vector3(2.9, 0.25, 12.0), accent)
	v.xf = Transform3D.IDENTITY
