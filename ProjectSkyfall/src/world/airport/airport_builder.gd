class_name AirportBuilder
## Builds an airport's geometry as plain arrays (safe on worker threads). AirportView turns the
## product into nodes. Coordinates are airport-local with y = height above field elevation.

const PAINT_Y := 0.075
const RWY_Y := 0.06
const TWY_Y := 0.05
const APRON_Y := 0.04


static func build(icao: String, detail: float) -> Dictionary:
	var L := AirportLayout.get_layout(icao)
	var a: Dictionary = Airports.get_ap(icao)
	var prod := {
		"icao": icao, "meshes": [], "labels": [], "bridges": [], "windsocks": [], "beacon": Vector3.ZERO,
		"lights": PackedFloat32Array(), "cars": PackedFloat32Array(), "props": PackedFloat32Array(),
	}
	_runways(L, prod)
	_taxiways(L, prod)
	_aprons(L, prod)
	_buildings(L, a, prod, detail)
	_lights(L, prod)
	return prod


# ------------------------------------------------------------------ helpers
static func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


static func _strip(mb: MeshBuilder, a: Vector2, b: Vector2, w: float, y: float, uv_along0: float = 0.0) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.01:
		return
	d /= length
	var side := Vector2(-d.y, d.x) * (w * 0.5)
	var segs := maxi(1, int(length / 120.0))
	var base := mb.vcount()
	for i in segs + 1:
		var t := float(i) / segs
		var p := a + d * length * t
		mb.add_vertex(_v3(p - side, y), Vector3.UP, Color.WHITE, Vector2(-w * 0.5, uv_along0 + length * t))
		mb.add_vertex(_v3(p + side, y), Vector3.UP, Color.WHITE, Vector2(w * 0.5, uv_along0 + length * t))
	for i in segs:
		var i0 := base + i * 2
		_quad_idx(mb, i0, i0 + 1, i0 + 2, i0 + 3)


static func _quad_idx(mb: MeshBuilder, l0: int, r0: int, l1: int, r1: int) -> void:
	# strip quad (l0,r0 at start; l1,r1 at end); choose winding so the face points up
	var n := (mb.verts[r0] - mb.verts[l0]).cross(mb.verts[l1] - mb.verts[l0])
	if n.y > 0.0:
		mb.add_tri_idx(l0, l1, r0)
		mb.add_tri_idx(r0, l1, r1)
	else:
		mb.add_tri_idx(l0, r0, l1)
		mb.add_tri_idx(r0, r1, l1)


static func _disc(mb: MeshBuilder, c: Vector2, r: float, y: float, segs: int = 14) -> void:
	var center := mb.add_vertex(_v3(c, y), Vector3.UP, Color.WHITE, Vector2.ZERO)
	for i in segs + 1:
		var ang := TAU * float(i) / segs
		mb.add_vertex(_v3(c + Vector2(cos(ang), sin(ang)) * r, y), Vector3.UP, Color.WHITE, Vector2(cos(ang) * r, sin(ang) * r))
	for i in segs:
		# clockwise when seen from above
		mb.add_tri_idx(center, center + 2 + i, center + 1 + i)


static func _rect(mb: MeshBuilder, c: Vector2, axis: Vector2, length: float, depth: float, y: float, uv_world: bool = true) -> void:
	var n := Vector2(-axis.y, axis.x)
	var hl := axis * length * 0.5
	var hd := n * depth * 0.5
	var p0 := c - hl - hd
	var p1 := c + hl - hd
	var p2 := c + hl + hd
	var p3 := c - hl + hd
	var i0 := mb.add_vertex(_v3(p0, y), Vector3.UP, Color.WHITE, Vector2(0, 0) if not uv_world else Vector2(-length * 0.5, 0))
	var i1 := mb.add_vertex(_v3(p1, y), Vector3.UP, Color.WHITE, Vector2(length, 0) if not uv_world else Vector2(length * 0.5, 0))
	var i2 := mb.add_vertex(_v3(p2, y), Vector3.UP, Color.WHITE, Vector2(length, depth) if not uv_world else Vector2(length * 0.5, depth))
	var i3 := mb.add_vertex(_v3(p3, y), Vector3.UP, Color.WHITE, Vector2(0, depth) if not uv_world else Vector2(-length * 0.5, depth))
	var nrm := (mb.verts[i1] - mb.verts[i0]).cross(mb.verts[i3] - mb.verts[i0])
	if nrm.y > 0.0:
		mb.add_tri_idx(i0, i3, i1)
		mb.add_tri_idx(i1, i3, i2)
	else:
		mb.add_tri_idx(i0, i1, i3)
		mb.add_tri_idx(i1, i2, i3)


static func _paint_line(mb: MeshBuilder, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.01:
		return
	d /= length
	var s := Vector2(-d.y, d.x) * (w * 0.5)
	var i0 := mb.add_vertex(_v3(a - s, PAINT_Y), Vector3.UP, col)
	var i1 := mb.add_vertex(_v3(a + s, PAINT_Y), Vector3.UP, col)
	var i2 := mb.add_vertex(_v3(b - s, PAINT_Y), Vector3.UP, col)
	var i3 := mb.add_vertex(_v3(b + s, PAINT_Y), Vector3.UP, col)
	_quad_idx(mb, i0, i1, i2, i3)


static func _flat_label(prod: Dictionary, text: String, p: Vector2, up_dir: Vector2, height_m: float, col: Color, y: float = 0.09) -> void:
	var yv := Vector3(up_dir.x, 0, up_dir.y).normalized()
	var zv := Vector3.UP
	var xv := yv.cross(zv)
	prod.labels.append({"text": text, "pos": Vector3(p.x, y, p.y), "basis": Basis(xv, yv, zv), "size": height_m, "color": col, "outline": 0})


static func _sign_label(prod: Dictionary, text: String, p: Vector3, facing: Vector2, height_m: float, col: Color, outline: int = 0) -> void:
	var zv := Vector3(facing.x, 0, facing.y).normalized()
	var yv := Vector3.UP
	var xv := yv.cross(zv)
	prod.labels.append({"text": text, "pos": p, "basis": Basis(xv, yv, zv), "size": height_m, "color": col, "outline": outline})


static func _mesh(prod: Dictionary, mb: MeshBuilder, key: String, params: Dictionary = {}, shadow: bool = false) -> void:
	if mb.verts.is_empty():
		return
	prod.meshes.append({"arrays": mb.arrays(), "key": key, "params": params, "shadow": shadow})


static func _push_light(buf: PackedFloat32Array, p: Vector3, size: float, col: Color, facing: float) -> void:
	buf.append_array([size, 0.0, 0.0, p.x, 0.0, size, 0.0, p.y, 0.0, 0.0, size, p.z, col.r, col.g, col.b, facing])


static func _push_prop(buf: PackedFloat32Array, p: Vector3, yaw: float, s: Vector3, col: Color) -> void:
	var c := cos(yaw)
	var sn := sin(yaw)
	buf.append_array([c * s.x, 0.0, sn * s.z, p.x, 0.0, s.y, 0.0, p.y, -sn * s.x, 0.0, c * s.z, p.z, col.r, col.g, col.b, 0.0])


static func _des(name: String) -> Vector3i:
	var digits := int(name.substr(0, 2))
	var letter := 0
	if name.length() > 2:
		letter = {"L": 1, "C": 2, "R": 3}.get(name.substr(2, 1), 0)
	return Vector3i(digits / 10, digits % 10, letter)


# ------------------------------------------------------------------ pavement
static func _runways(L: Dictionary, prod: Dictionary) -> void:
	for rw in L.runways:
		var mb := MeshBuilder.new()
		var c: Vector2 = rw.center
		var d: Vector2 = rw.dir
		var half: float = rw.half
		var w: float = rw.wid + (15.0 if rw.surface == "asphalt" else 0.0)
		_strip(mb, c - d * half, c + d * half, w, RWY_Y, 0.0)
		var mode := 0 if rw.surface == "asphalt" else 4
		_mesh(prod, mb, "runway", {"mode": mode, "rw_len": rw.len, "rw_wid": rw.wid, "priority": 3.0,
			"des0": _des(rw.names[0]), "des1": _des(rw.names[1])})


static func _taxiways(L: Dictionary, prod: Dictionary) -> void:
	var mb := MeshBuilder.new()
	var paint := MeshBuilder.new()
	var nodes: Array = L.taxi_nodes
	var tw_w := 23.0
	var junctions := {}
	for t in L.taxiways:
		var pa: Vector2 = nodes[t.a].pos
		var pb: Vector2 = nodes[t.b].pos
		var w: float = t.w
		if w <= 0.0:
			continue
		tw_w = w
		_strip(mb, pa, pb, w, TWY_Y)
		junctions[t.a] = w
		junctions[t.b] = w
		if t.has("hold"):
			var hp: Vector2 = nodes[t.hold].pos
			var dirv: Vector2 = (pb - pa).normalized()
			var sv := Vector2(-dirv.y, dirv.x)
			# runway holding position: two solid + two dashed lines across the taxiway
			for k in 4:
				var off := dirv * (float(k) * 0.9 - 1.35)
				if k < 2:
					_paint_line(paint, hp + off - sv * w * 0.5, hp + off + sv * w * 0.5, 0.3, Color(0.85, 0.66, 0.08))
				else:
					var dashes := int(w / 2.0)
					for q in dashes:
						if q % 2 == 0:
							var s0 := -w * 0.5 + q * 2.0
							_paint_line(paint, hp + off + sv * s0, hp + off + sv * (s0 + 2.0), 0.3, Color(0.85, 0.66, 0.08))
			# holding position sign (red, white text) beside the line
			var rwi: int = int(nodes[t.hold].get("runway", 0))
			var rwd: Dictionary = L.runways[rwi]
			var sign_p: Vector2 = hp + sv * (w * 0.5 + 6.0)
			_sign_box(prod, sign_p, -dirv, String(rwd.id).replace("/", "-"), Color(0.7, 0.05, 0.05), Color(1, 1, 1))
	for j in junctions.keys():
		_disc(mb, nodes[j].pos, junctions[j] * 0.75, TWY_Y - 0.003)
	_mesh(prod, mb, "taxiway", {"mode": 1, "rw_wid": tw_w, "priority": 2.0})
	_mesh(prod, paint, "paint", {})


static func _sign_box(prod: Dictionary, p: Vector2, facing: Vector2, text: String, bg: Color, fg: Color) -> void:
	var mb := MeshBuilder.new()
	var w := 0.9 + text.length() * 0.62
	var yaw := atan2(facing.x, facing.y)
	mb.xf = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0, p.y))
	mb.add_box(Vector3(0, 0.95, 0), Vector3(w, 1.0, 0.35), bg)
	mb.add_box(Vector3(-w * 0.35, 0.25, 0), Vector3(0.1, 0.5, 0.1), Color(0.3, 0.3, 0.3))
	mb.add_box(Vector3(w * 0.35, 0.25, 0), Vector3(0.1, 0.5, 0.1), Color(0.3, 0.3, 0.3))
	_mesh(prod, mb, "vcolor", {})
	_sign_label(prod, text, Vector3(p.x + facing.x * 0.19, 0.95, p.y + facing.y * 0.19), facing, 0.62, fg)
	_sign_label(prod, text, Vector3(p.x - facing.x * 0.19, 0.95, p.y - facing.y * 0.19), -facing, 0.62, fg)


static func _aprons(L: Dictionary, prod: Dictionary) -> void:
	var mb := MeshBuilder.new()
	for ap in L.aprons:
		_rect(mb, ap.center, ap.axis, ap.len, ap.depth, APRON_Y)
	_mesh(prod, mb, "apron", {"mode": 2, "priority": 1.0})
	var paint := MeshBuilder.new()
	var yellow := Color(0.86, 0.68, 0.1)
	for s in L.stands:
		var stop: Vector2 = s.stop
		var lead: Vector2 = s.lead
		_paint_line(paint, lead, stop, 0.22, yellow)
		var ax: Vector2 = s.axis
		_paint_line(paint, stop - ax * 2.5, stop + ax * 2.5, 0.35, yellow)
		# stand number on the apron, readable to an arriving pilot
		var to_term: Vector2 = -(s.normal as Vector2)
		_flat_label(prod, s.name, lead + (stop - lead) * 0.35 + ax * 6.0, to_term, 3.2, yellow)
		# stand safety envelope (red dashes)
		if s.bridge:
			var nrm2: Vector2 = s.normal
			for side in [-1.0, 1.0]:
				var e0: Vector2 = stop + ax * side * 26.0
				var e1: Vector2 = e0 + nrm2 * 60.0
				_paint_line(paint, e0, e1, 0.18, Color(0.75, 0.12, 0.1))
	for pk in L.parking:
		_rect(mb, pk.center, pk.axis, pk.len, pk.depth, APRON_Y)
	_mesh(prod, paint, "paint", {})
	# landside roads
	var rmb := MeshBuilder.new()
	for r in L.roads:
		_strip(rmb, r.a, r.b, r.w, 0.03)
	_mesh(prod, rmb, "road", {"mode": 3, "rw_wid": 14.0, "priority": 0.5})


# ------------------------------------------------------------------ buildings
const FIN := Color(0.66, 0.69, 0.73)
const DARK_GLASS := Color(0.07, 0.1, 0.13)
const STEEL_DARK := Color(0.24, 0.25, 0.27)
const PLANT := Color(0.55, 0.57, 0.58)


static func _side_is_airside(L: Dictionary, c: Vector2, wn: Vector2, half_depth: float) -> bool:
	for f in L.facades:
		var fn: Vector2 = f.normal
		var fo: Vector2 = f.origin
		if fn.dot(wn) > 0.9 and absf((fo - c).dot(wn) - half_depth) < 8.0:
			return true
	return false


static func _roof_plant(misc: MeshBuilder, t: Transform3D, y: float, hx: float, hz: float, seed: int) -> void:
	## HVAC units, vents and a parapet on a flat roof (local frame t, footprint half extents).
	var r := RandomNumberGenerator.new()
	r.seed = seed
	misc.xf = t
	for sx in [-1.0, 1.0]:
		misc.add_box(Vector3(sx * (hx - 0.15), y + 0.45, 0), Vector3(0.3, 0.9, hz * 2.0), Color(0.7, 0.7, 0.68))
		misc.add_box(Vector3(0, y + 0.45, sx * (hz - 0.15)), Vector3(hx * 2.0, 0.9, 0.3), Color(0.7, 0.7, 0.68))
	var n := clampi(int(hx * hz / 120.0), 2, 10)
	for k in n:
		var p := Vector3(r.randf_range(-hx * 0.7, hx * 0.7), y, r.randf_range(-hz * 0.7, hz * 0.7))
		var sz := Vector3(r.randf_range(2.0, 4.5), r.randf_range(1.2, 2.2), r.randf_range(2.0, 6.0))
		misc.add_box(p + Vector3(0, sz.y * 0.5, 0), sz, PLANT)
		misc.add_cylinder(p + Vector3(0, sz.y, 0), p + Vector3(0, sz.y + 0.25, 0), minf(sz.x, sz.z) * 0.32, minf(sz.x, sz.z) * 0.32, 8, STEEL_DARK)
	misc.xf = Transform3D.IDENTITY


static func _buildings(L: Dictionary, a: Dictionary, prod: Dictionary, detail: float) -> void:
	var glass := MeshBuilder.new()
	var concrete := MeshBuilder.new()
	var metal := MeshBuilder.new()
	var cab := MeshBuilder.new()
	var misc := MeshBuilder.new()
	var bi := 0
	for b in L.buildings:
		bi += 1
		var c: Vector2 = b.center
		var ax: Vector2 = b.axis
		var yaw := atan2(ax.x, ax.y)
		var basis := Basis(Vector3.UP, yaw)
		# MeshBuilder boxes are axis aligned: x across, z along after rotation
		var t := Transform3D(basis, _v3(c, 0))
		var bh: float = b.h
		var bd: float = b.depth
		var bl: float = b.len
		if b.kind in ["terminal", "concourse"]:
			# ground floor (baggage, services), glazed departures level (level with the jet bridge
			# stubs, see TerminalInterior.FLOOR), wavy roof
			var fl := TerminalInterior.FLOOR
			concrete.xf = t
			concrete.add_box(Vector3(0, fl * 0.5, 0), Vector3(bd - 2.0, fl, bl - 2.0), Color.WHITE, true)
			glass.xf = t
			glass.add_box(Vector3(0, fl + (bh - fl) * 0.5, 0), Vector3(bd, bh - fl, bl), Color.WHITE, true)
			metal.xf = t
			var bays := maxi(2, int(bl / 90.0))
			var rise := 7.0 if L.size == "hub" else 4.0
			for k in bays:
				var zc: float = -bl * 0.5 + (k + 0.5) * (bl / bays)
				metal.add_arch(Vector3(0, bh, zc), bd + 14.0, rise, bl / bays + 0.5, 14, Color.WHITE)
			# roof-edge fascia under the overhanging eaves
			for sx in [-1.0, 1.0]:
				metal.add_box(Vector3(sx * (bd * 0.5 + 6.6), bh + 0.25, 0), Vector3(0.9, 1.1, bl + 0.5), Color.WHITE)
			# structural columns along both facades
			for k in int(bl / 18.0) + 1:
				var zc2: float = -bl * 0.5 + k * 18.0
				concrete.add_box(Vector3(bd * 0.5 + 0.6, bh * 0.5, zc2), Vector3(1.0, bh, 1.0), Color.WHITE, true)
				concrete.add_box(Vector3(-bd * 0.5 - 0.6, bh * 0.5, zc2), Vector3(1.0, bh, 1.0), Color.WHITE, true)
			metal.xf = Transform3D.IDENTITY
			# facade detail: mullion fins and the floor-line spandrel on the glazed level; the
			# landside gets the departures canopy on slim columns and entrance doors
			misc.xf = t
			for sx2 in [-1.0, 1.0]:
				var wn3: Vector3 = basis * Vector3(sx2, 0, 0)
				var wn := Vector2(wn3.x, wn3.z)
				var airside := _side_is_airside(L, c, wn, bd * 0.5)
				var fx: float = sx2 * (bd * 0.5 + 0.2)
				misc.add_box(Vector3(fx, fl + 0.1, 0), Vector3(0.45, 0.9, bl), FIN)
				misc.add_box(Vector3(fx, bh - 0.6, 0), Vector3(0.45, 1.2, bl), FIN)
				var nf := int(bl / 12.0)
				for k2 in nf + 1:
					var zf: float = -bl * 0.5 + bl * float(k2) / maxf(nf, 1)
					misc.add_box(Vector3(fx, fl + (bh - fl) * 0.5, zf), Vector3(0.6, bh - fl, 0.22), FIN)
				if not airside:
					var cx: float = sx2 * (bd * 0.5 + 7.5)
					misc.add_box(Vector3(cx, fl - 0.15, 0), Vector3(15.0, 0.45, bl * 0.72), Color(0.86, 0.87, 0.88))
					misc.add_box(Vector3(sx2 * (bd * 0.5 + 14.8), fl - 0.55, 0), Vector3(0.5, 0.5, bl * 0.72), FIN)
					var nc := int(bl * 0.72 / 18.0)
					for k3 in nc + 1:
						var zc3: float = -bl * 0.36 + bl * 0.72 * float(k3) / maxf(nc, 1)
						misc.add_cylinder(Vector3(sx2 * (bd * 0.5 + 13.5), 0, zc3), Vector3(sx2 * (bd * 0.5 + 13.5), fl - 0.35, zc3), 0.22, 0.2, 8, FIN, false)
					var nd := int(bl / 36.0)
					for k4 in nd:
						var zd: float = -bl * 0.5 + (k4 + 0.5) * bl / maxf(nd, 1)
						misc.add_box(Vector3(sx2 * (bd * 0.5 - 0.9), 1.6, zd), Vector3(0.3, 3.2, 6.0), DARK_GLASS)
						misc.add_box(Vector3(sx2 * (bd * 0.5 - 0.75), 3.35, zd), Vector3(0.4, 0.3, 6.4), FIN)
			misc.xf = Transform3D.IDENTITY
			# airport name on both long sides (the satellite carries its concourse letters)
			var n := Vector2(-ax.y, ax.x)
			for sgn in [1.0, -1.0]:
				var face: Vector2 = c + n * sgn * (bd * 0.5 + 0.4)
				var title := String(a.name).to_upper() if b.kind == "terminal" else ("CONCOURSE C" if sgn > 0.0 else "CONCOURSE D")
				_sign_label(prod, title, Vector3(face.x, bh - 3.0, face.y), n * sgn, 3.4 if L.size == "hub" else 2.2, Color(0.95, 0.97, 1.0), 6)
		else:
			concrete.xf = t
			concrete.add_box(Vector3(0, bh * 0.5, 0), Vector3(bd, bh, bl), Color.WHITE, true)
			glass.xf = t
			glass.add_box(Vector3(0, bh * 0.45, 0), Vector3(bd + 0.2, bh * 0.4, bl * 0.8), Color.WHITE, true)
			misc.xf = t
			# entrance canopy and a darker plinth
			misc.add_box(Vector3(bd * 0.5 + 2.0, minf(3.2, bh * 0.5), 0), Vector3(4.0, 0.3, minf(bl * 0.3, 14.0)), FIN)
			misc.add_box(Vector3(0, 0.4, 0), Vector3(bd + 0.1, 0.8, bl + 0.1), Color(0.45, 0.46, 0.47))
			misc.xf = Transform3D.IDENTITY
			_roof_plant(misc, t, bh, bd * 0.5, bl * 0.5, bi * 31 + U.hash_str(L.icao))
			var n2 := Vector2(-ax.y, ax.x)
			_sign_label(prod, "%s AVIATION" % String(a.short).to_upper(), Vector3(c.x + n2.x * (bd * 0.5 + 0.3), bh - 1.0, c.y + n2.y * (bd * 0.5 + 0.3)), n2, 1.0, Color(0.1, 0.2, 0.4))
	glass.xf = Transform3D.IDENTITY
	concrete.xf = Transform3D.IDENTITY
	# control tower: base building, ribbed tapering shaft, glazed equipment floor, catwalk,
	# the cab with slanted glazing and mullions, overhanging roof, radome and masts
	var tp: Vector2 = L.tower
	var th: float = L.tower_h
	var tr := 4.0 if th > 50.0 else (2.6 if th > 20.0 else 1.6)
	if th > 20.0:
		var bb := Vector2(tr * 3.6, tr * 0.5)
		concrete.add_box(_v3(tp + bb, 4.5), Vector3(tr * 5.5, 9.0, tr * 4.0), Color.WHITE, true)
		glass.add_box(_v3(tp + bb, 5.0), Vector3(tr * 5.5 + 0.2, 2.6, tr * 4.0 + 0.2), Color.WHITE, true)
		_roof_plant(misc, Transform3D(Basis(), _v3(tp + bb, 0)), 9.0, tr * 2.75, tr * 2.0, U.hash_str(L.icao) + 7)
	concrete.add_cylinder(_v3(tp, 0), _v3(tp, th - 4.0), tr * 1.3, tr, 12, Color.WHITE)
	for k5 in 4:
		var ang := TAU * k5 / 4.0 + PI * 0.25
		var dv := Vector2(cos(ang), sin(ang))
		misc.add_box_xf(Transform3D(Basis(Vector3.UP, -ang), _v3(tp + dv * tr * 1.05, (th - 4.0) * 0.5)), Vector3(tr * 0.5, th - 4.0, tr * 0.35), Color(0.8, 0.8, 0.78))
	concrete.add_cylinder(_v3(tp, th - 4.0), _v3(tp, th - 3.4), tr * 1.05, tr * 1.85, 12, Color.WHITE)
	glass.add_cylinder(_v3(tp, th - 3.4), _v3(tp, th - 0.5), tr * 1.85, tr * 1.85, 12, Color.WHITE)
	concrete.add_cylinder(_v3(tp, th - 0.5), _v3(tp, th + 0.2), tr * 2.65, tr * 2.6, 16, Color.WHITE)
	cab.add_cylinder(_v3(tp, th + 0.2), _v3(tp, th + 5.0), tr * 2.0, tr * 2.35, 12, Color.WHITE)
	for k6 in 12:
		var a6 := TAU * (float(k6) + 0.5) / 12.0
		var d6 := Vector2(cos(a6), sin(a6))
		misc.add_cylinder(_v3(tp + d6 * tr * 1.99, th + 0.2), _v3(tp + d6 * tr * 2.34, th + 5.0), 0.07, 0.07, 4, STEEL_DARK, false)
	for k7 in 24:
		var a7 := TAU * float(k7) / 24.0
		var a8 := TAU * float(k7 + 1) / 24.0
		var p7 := tp + Vector2(cos(a7), sin(a7)) * tr * 2.55
		var p8 := tp + Vector2(cos(a8), sin(a8)) * tr * 2.55
		misc.add_cylinder(_v3(p7, th + 0.2), _v3(p7, th + 1.25), 0.04, 0.04, 3, FIN, false)
		misc.add_cylinder(_v3(p7, th + 1.25), _v3(p8, th + 1.25), 0.05, 0.05, 3, FIN, false)
	concrete.add_cylinder(_v3(tp, th + 5.0), _v3(tp, th + 5.8), tr * 2.7, tr * 2.55, 16, Color.WHITE)
	concrete.add_cylinder(_v3(tp, th + 5.8), _v3(tp, th + 6.4), tr * 1.6, tr * 1.25, 12, Color.WHITE)
	misc.add_sphere(_v3(tp + Vector2(tr * 0.7, 0), th + 6.4 + tr * 0.28), Vector3.ONE * tr * 0.3, 10, 6, Color(0.92, 0.92, 0.9))
	misc.add_cylinder(_v3(tp + Vector2(-tr * 0.6, tr * 0.4), th + 6.4), _v3(tp + Vector2(-tr * 0.6, tr * 0.4), th + 9.5), 0.06, 0.04, 4, FIN, false)
	misc.add_cylinder(_v3(tp, th + 6.4), _v3(tp, th + 11.0), 0.12, 0.08, 4, Color(0.8, 0.1, 0.1))
	prod.beacon = _v3(tp, th + 6.8)
	prod.tower_top = _v3(tp, th + 3.0)
	# hangars: corrugated shed under a barrel roof, segmented doors with a header beam and
	# windows, an office lean-to on the back and ridge vents
	var hi := 0
	for hg in L.hangars:
		hi += 1
		var hc: Vector2 = hg.center
		var hax: Vector2 = hg.axis
		var hw: float = hg.w
		var hd: float = hg.d
		var hh: float = hg.h
		var yaw2 := atan2(hax.x, hax.y)
		var hb := Basis(Vector3.UP, yaw2)
		metal.xf = Transform3D(hb, _v3(hc, 0))
		metal.add_box(Vector3(0, hh * 0.5, 0), Vector3(hd, hh, hw), Color.WHITE, true)
		metal.add_arch(Vector3(0, hh, 0), hd, hh * 0.32, hw, 16, Color.WHITE)
		metal.xf = Transform3D.IDENTITY
		var dn: Vector2 = hg.door_normal
		var ldn: Vector3 = hb.inverse() * Vector3(dn.x, 0, dn.y)
		var back := -signf(ldn.x) if absf(ldn.x) > 0.5 else 1.0
		# office lean-to along the back wall
		concrete.xf = Transform3D(hb, _v3(hc, 0))
		concrete.add_box(Vector3(back * (hd * 0.5 + 4.0), hh * 0.2, 0), Vector3(8.0, hh * 0.4, hw * 0.7), Color.WHITE, true)
		glass.xf = Transform3D(hb, _v3(hc, 0))
		glass.add_box(Vector3(back * (hd * 0.5 + 4.0), hh * 0.24, 0), Vector3(8.2, hh * 0.12, hw * 0.66), Color.WHITE, true)
		concrete.xf = Transform3D.IDENTITY
		glass.xf = Transform3D.IDENTITY
		misc.xf = Transform3D(hb, _v3(hc, 0))
		var nv := int(hw / 14.0)
		for k8 in nv:
			var zv := -hw * 0.5 + (k8 + 0.5) * hw / maxf(nv, 1)
			misc.add_box(Vector3(0, hh + hh * 0.32 + 0.3, zv), Vector3(2.2, 0.8, 3.0), PLANT)
		misc.xf = Transform3D.IDENTITY
		var door_c: Vector2 = hc + dn * (hd * 0.5 + 0.2)
		var door_yaw := atan2(dn.x, dn.y)
		misc.xf = Transform3D(Basis(Vector3.UP, door_yaw), _v3(door_c, 0))
		var dw := hw * 0.84
		var dh := hh * 0.84
		var leaves := 8 if hw > 60.0 else 6
		var lw := dw / leaves
		for k9 in leaves:
			var xl := -dw * 0.5 + (k9 + 0.5) * lw
			var zl := 0.18 if k9 % 2 == 1 else 0.0
			var lc := Color(0.36, 0.41, 0.47) if k9 % 2 == 0 else Color(0.4, 0.45, 0.51)
			misc.add_box(Vector3(xl, dh * 0.5, zl), Vector3(lw - 0.2, dh, 0.3), lc)
			misc.add_box(Vector3(xl, dh * 0.62, zl + 0.17), Vector3(lw * 0.7, minf(1.2, dh * 0.08), 0.06), DARK_GLASS)
			for kr in 3:
				misc.add_box(Vector3(xl, dh * (0.2 + kr * 0.2), zl + 0.16), Vector3(lw - 0.4, 0.12, 0.05), Color(0.3, 0.34, 0.38))
		misc.add_box(Vector3(0, dh + 0.9, 0.2), Vector3(dw + 2.4, 1.8, 0.9), STEEL_DARK)
		misc.add_box(Vector3(0, 0.05, 0.6), Vector3(dw + 1.0, 0.1, 1.2), Color(0.2, 0.2, 0.21))
		for sx4 in [-1.0, 1.0]:
			misc.add_box(Vector3(sx4 * (dw * 0.5 + 0.9), dh * 0.5, 0.25), Vector3(1.4, dh, 0.8), Color(0.75, 0.76, 0.77))
		misc.xf = Transform3D.IDENTITY
		_sign_label(prod, "HANGAR %d" % hi, Vector3(door_c.x + dn.x * 0.7, dh + 0.9, door_c.y + dn.y * 0.7), dn, minf(1.6, hh * 0.06), Color(0.95, 0.96, 0.98))
	# fire station: apparatus bays with glazed doors, hose-drying tower, roof plant
	if L.arff != Vector2.ZERO:
		var fc: Vector2 = L.arff
		misc.add_box(_v3(fc, 4.5), Vector3(36, 9, 22), Color(0.82, 0.8, 0.76))
		misc.add_box(_v3(fc, 9.2), Vector3(36.6, 0.5, 22.6), Color(0.72, 0.1, 0.08))
		for k in 4:
			var dp := fc + Vector2(-13.5 + k * 9.0, 11.1)
			misc.add_box(_v3(dp, 3.4), Vector3(7.0, 6.2, 0.3), Color(0.75, 0.08, 0.06))
			misc.add_box(_v3(dp + Vector2(0, 0.17), 4.6), Vector3(6.2, 1.0, 0.06), DARK_GLASS)
			for kr2 in 4:
				misc.add_box(_v3(dp + Vector2(0, 0.16), 1.0 + kr2 * 1.1), Vector3(6.8, 0.08, 0.05), Color(0.6, 0.06, 0.05))
		misc.add_box(_v3(fc + Vector2(20.5, -6.0), 9.0), Vector3(5.0, 18.0, 5.0), Color(0.82, 0.8, 0.76))
		misc.add_box(_v3(fc + Vector2(20.5, -6.0), 18.3), Vector3(5.4, 0.6, 5.4), Color(0.72, 0.1, 0.08))
		_roof_plant(misc, Transform3D(Basis(), _v3(fc, 0)), 9.0, 18.0, 11.0, U.hash_str(L.icao) + 3)
		_sign_label(prod, "FIRE & RESCUE", Vector3(fc.x, 7.6, fc.y + 11.3), Vector2(0, 1), 1.4, Color(0.95, 0.95, 0.95), 4)
	# fuel farm: domed tanks with stair landings inside a bund wall
	if L.fuel != Vector2.ZERO:
		var fuel: Vector2 = L.fuel
		for sx5 in [-1.0, 1.0]:
			misc.add_box(_v3(fuel + Vector2(0, sx5 * 17.0), 0.6), Vector3(78.0, 1.2, 0.6), Color(0.66, 0.66, 0.64))
			misc.add_box(_v3(fuel + Vector2(sx5 * 39.0, 0), 0.6), Vector3(0.6, 1.2, 34.0), Color(0.66, 0.66, 0.64))
		for k in 3:
			var fp: Vector2 = fuel + Vector2(k * 24.0 - 24.0, 0)
			misc.add_cylinder(_v3(fp, 0), _v3(fp, 12.0), 9.0, 9.0, 24, Color(0.92, 0.92, 0.9))
			misc.add_cylinder(_v3(fp, 12.0), _v3(fp, 13.6), 9.0, 2.0, 24, Color(0.86, 0.86, 0.84))
			misc.add_cylinder(_v3(fp, 4.0), _v3(fp, 4.6), 9.05, 9.05, 24, Color(0.8, 0.15, 0.1), false)
			for ks in 6:
				var sa := float(ks) / 6.0 * PI * 0.9
				var sp := fp + Vector2(cos(sa), sin(sa)) * 9.6
				misc.add_box(_v3(sp, 1.0 + ks * 2.0), Vector3(1.2, 0.15, 1.2), STEEL_DARK)
			misc.add_cylinder(_v3(fp + Vector2(9.6, 0), 0), _v3(fp + Vector2(9.6, 0), 13.0), 0.05, 0.05, 3, FIN, false)
	# car parks with cars and lamp posts
	for pk in L.parking:
		var pc: Vector2 = pk.center
		var pax: Vector2 = pk.axis
		var pn := Vector2(-pax.y, pax.x)
		var rows := int(pk.depth / 12.0)
		var cols := int(pk.len / 2.8)
		var r := RandomNumberGenerator.new()
		r.seed = U.hash_str(L.icao)
		for row in rows:
			for col in cols:
				if r.randf() > 0.72 * detail:
					continue
				var pos: Vector2 = pc + pax * (col * 2.8 - pk.len * 0.5 + 1.4) + pn * (row * 12.0 - pk.depth * 0.5 + 6.0)
				var car_col: Color = U.pick(r, [Color(0.9, 0.9, 0.9), Color(0.1, 0.1, 0.12), Color(0.55, 0.57, 0.6), Color(0.6, 0.1, 0.1), Color(0.15, 0.25, 0.5), Color(0.75, 0.75, 0.78), Color(0.25, 0.3, 0.25)])
				_push_prop(prod.cars, Vector3(pos.x, 0.0, pos.y), atan2(pn.x, pn.y), Vector3(1, 1, 1), car_col)
		for row2 in rows + 1:
			for col2 in int(pk.len / 30.0) + 1:
				var lp2: Vector2 = pc + pax * (col2 * 30.0 - pk.len * 0.5) + pn * (row2 * 12.0 - pk.depth * 0.5)
				misc.add_cylinder(_v3(lp2, 0), _v3(lp2, 8.0), 0.12, 0.08, 6, FIN, false)
				misc.add_box(_v3(lp2, 8.05), Vector3(0.9, 0.2, 0.4), STEEL_DARK)
	# jet bridges and stand equipment
	for i in L.stands.size():
		var s: Dictionary = L.stands[i]
		if s.bridge:
			var nn: Vector2 = s.normal
			var left := Vector2(-nn.y, nn.x)
			prod.bridges.append({"stand": i, "root": (s.facade_origin as Vector2) + left * 9.0 + nn * 1.0, "axis": s.axis, "normal": nn, "left": left})
	# windsocks
	for ws in L.windsocks:
		prod.windsocks.append(_v3(ws, 0))
	# ILS antennas and glideslope masts
	for ils in L.ils:
		var lp: Vector2 = ils.loc
		var lax := Vector2(sin(deg_to_rad(ils.hdg)), -cos(deg_to_rad(ils.hdg)))
		var lperp := Vector2(-lax.y, lax.x)
		for k in 12:
			var ap2: Vector2 = lp + lperp * (k - 5.5) * 3.0
			misc.add_box(_v3(ap2, 1.2), Vector3(0.25, 2.4, 0.25), Color(0.85, 0.85, 0.85))
			misc.add_box(_v3(ap2, 2.6), Vector3(0.18, 0.18, 1.6), Color(0.85, 0.85, 0.85))
		misc.add_box(_v3(lp, 2.4), Vector3(36.0, 0.2, 0.3), Color(0.85, 0.85, 0.85))
		misc.add_box(_v3(lp - lax * 6.0, 1.4), Vector3(3.0, 2.8, 2.4), Color(0.9, 0.9, 0.88))
		misc.add_box(_v3(ils.gs, 7.0), Vector3(0.6, 14.0, 0.6), Color(0.85, 0.3, 0.1))
		for kg in 3:
			misc.add_box(_v3(ils.gs, 4.0 + kg * 3.5), Vector3(0.3, 1.2, 1.4), Color(0.9, 0.9, 0.9))
		misc.add_box(_v3(ils.gs + Vector2(0, 3), 1.5), Vector3(3, 3, 3), Color(0.9, 0.9, 0.88))
	# PAPI housings
	for rw in L.runways:
		for e in rw.ends:
			if not e.has("papi"):
				continue
			for k in 4:
				var pp: Vector2 = (e.papi as Vector2) + (e.papi_side as Vector2) * (k * 9.0)
				misc.add_box(_v3(pp, 0.45), Vector3(1.4, 0.7, 1.4), Color(0.2, 0.2, 0.2))
				misc.add_box(_v3(pp, 0.08), Vector3(1.8, 0.16, 1.8), Color(0.6, 0.6, 0.58))
	_mesh(prod, glass, "glass", {}, true)
	_mesh(prod, concrete, "concrete", {}, true)
	_mesh(prod, metal, "metal", {}, true)
	_mesh(prod, cab, "cab", {}, false)
	_mesh(prod, misc, "vcolor", {}, true)


# ------------------------------------------------------------------ lighting
static func _lights(L: Dictionary, prod: Dictionary) -> void:
	var buf: PackedFloat32Array = prod.lights
	var white := Color(1.0, 0.92, 0.75)
	var yellow := Color(1.0, 0.72, 0.18)
	var green := Color(0.25, 1.0, 0.45)
	var red := Color(1.0, 0.1, 0.05)
	var blue := Color(0.25, 0.4, 1.0)
	var big: bool = L.size == "hub"
	for rw in L.runways:
		if rw.surface != "asphalt":
			continue
		var c: Vector2 = rw.center
		var d: Vector2 = rw.dir
		var right: Vector2 = rw.right
		var half: float = rw.half
		var hw: float = rw.wid * 0.5 + 1.5
		# edge lights (yellow over the last 600 m in each direction)
		var n_edge := int(rw.len / 60.0)
		for k in n_edge + 1:
			var along = -half + k * (rw.len / n_edge)
			for sd in [-1.0, 1.0]:
				var p: Vector2 = c + d * along + right * sd * hw
				var col := white
				if along > half - 600.0:
					col = yellow
				_push_light(buf, _v3(p, 0.45), 0.55, col, U.wrap_deg(rw.hdg + 180.0) / 360.0)
				col = white if along > -half + 600.0 else yellow
				_push_light(buf, _v3(p, 0.45), 0.55, col, rw.hdg / 360.0)
		# centreline lights (both directions, red/white coding near each end)
		if rw.wid >= 45.0:
			var n_cl := int(rw.len / 15.0)
			for k in n_cl + 1:
				var along2 := -half + k * 15.0
				var p2: Vector2 = c + d * along2 + right * 0.8
				var rem_fwd := half - along2
				var rem_back := along2 + half
				var col_f := white if rem_fwd > 900.0 else (red if rem_fwd < 300.0 or k % 2 == 0 else white)
				var col_b := white if rem_back > 900.0 else (red if rem_back < 300.0 or k % 2 == 0 else white)
				_push_light(buf, _v3(p2, 0.12), 0.32, col_f, U.wrap_deg(rw.hdg + 180.0) / 360.0)
				_push_light(buf, _v3(p2, 0.12), 0.32, col_b, rw.hdg / 360.0)
		for e in rw.ends:
			var thr: Vector2 = e.thr
			var ed: Vector2 = e.dir
			var es := Vector2(-ed.y, ed.x)
			var app_facing := U.wrap_deg(e.hdg + 180.0) / 360.0
			# threshold (green toward the approach) and runway end (red toward the rollout)
			var n_thr := int(rw.wid / 3.0)
			for k in n_thr + 1:
				var x = -rw.wid * 0.5 + k * (rw.wid / n_thr)
				_push_light(buf, _v3(thr + es * x - ed * 1.5, 0.3), 0.5, green, app_facing)
				_push_light(buf, _v3(thr + es * x - ed * 1.5, 0.3), 0.5, red, e.hdg / 360.0)
			# touchdown zone barrettes
			if big and rw.wid >= 45.0:
				for k in 30:
					var along3 := 60.0 + k * 30.0
					for sd in [-1.0, 1.0]:
						for q in 3:
							var p3: Vector2 = thr + ed * along3 + es * sd * (11.0 + q * 1.5)
							_push_light(buf, _v3(p3, 0.12), 0.3, white, app_facing)
			# approach lighting system
			if e.ils:
				var als_len := 900.0 if big else 420.0
				var n_bar := int(als_len / 30.0)
				for k in range(1, n_bar + 1):
					var dist := k * 30.0
					var bp: Vector2 = thr - ed * dist
					for q in 5:
						_push_light(buf, _v3(bp + es * (q - 2) * 1.05, 1.2), 0.65, white, app_facing)
					if k == 10 or (not big and k == 7):
						for q in range(-7, 8):
							if absi(q) > 2:
								_push_light(buf, _v3(bp + es * q * 1.5, 1.2), 0.6, white, app_facing)
					if dist >= 300.0:
						# sequenced flasher ("the rabbit") runs toward the runway
						_push_light(buf, _v3(bp + Vector2(0, 0), 2.0), 0.9, Color(1, 1, 1), -10.0 - float(n_bar - k))
			# PAPI: four units, thresholds 3.5, 3.17, 2.83, 2.5 degrees (outermost first)
			if e.has("papi"):
				var slope := 3.0
				for ils in L.ils:
					if ils.end == e.name:
						slope = ils.slope
				for k in 4:
					var pp: Vector2 = (e.papi as Vector2) + (e.papi_side as Vector2) * (k * 9.0)
					var thr_ang := slope + 0.5 - k * 0.333
					_push_light(buf, _v3(pp, 0.8), 0.9, white, -5.0 - thr_ang)
	# taxiway edge lights (blue)
	var nodes: Array = L.taxi_nodes
	for t in L.taxiways:
		var pa: Vector2 = nodes[t.a].pos
		var pb: Vector2 = nodes[t.b].pos
		var w: float = t.w
		if w <= 0.0:
			continue
		var dv := pb - pa
		var length := dv.length()
		if length < 1.0:
			continue
		dv /= length
		var sv := Vector2(-dv.y, dv.x)
		var n := maxi(1, int(length / 45.0))
		for k in n + 1:
			var p4 := pa + dv * (length * k / n)
			for sd in [-1.0, 1.0]:
				_push_light(buf, _v3(p4 + sv * sd * (w * 0.5 + 1.0), 0.3), 0.3, blue, -1.0)
		if t.has("hold"):
			# stop bar
			var hp: Vector2 = nodes[t.hold].pos
			for q in range(-int(w / 3.0), int(w / 3.0) + 1):
				_push_light(buf, _v3(hp + sv * q * 1.5, 0.15), 0.3, red, -1.0)
	# apron flood light poles and obstruction lights
	var poles := MeshBuilder.new()
	for ap in L.aprons:
		var ac: Vector2 = ap.center
		var aax: Vector2 = ap.axis
		var an := Vector2(-aax.y, aax.x)
		var nn := int(ap.len / 90.0)
		for k in nn + 1:
			for sd in [-1.0, 1.0]:
				var fp: Vector2 = ac + aax * (k * (ap.len / maxf(nn, 1)) - ap.len * 0.5) + an * sd * (ap.depth * 0.5 + 6.0)
				if L.size == "ga" and sd < 0.0:
					continue
				_flood_mast(poles, fp, -an * sd, aax)
				_push_light(buf, _v3(fp - an * sd * 0.6, 23.6), 1.8, Color(1.0, 0.88, 0.65), -1.0)
	_mesh(prod, poles, "vcolor", {}, false)
	_push_light(buf, prod.beacon, 1.2, Color(0.4, 1.0, 0.5), -10.0)
	_push_light(buf, prod.beacon + Vector3(0, 0.3, 0), 1.2, Color(1, 1, 1), -10.5)
	_push_light(buf, (prod.tower_top as Vector3) + Vector3(0, 8.0, 0), 0.6, red, -1.0)
	for hg in L.hangars:
		_push_light(buf, _v3(hg.center, hg.h + hg.d * 0.5 + 0.5), 0.5, red, -1.0)


static func _flood_mast(mb: MeshBuilder, fp: Vector2, facing: Vector2, along: Vector2) -> void:
	## Apron high mast: plinth, tapered octagonal pole, service platform with a rail and a
	## head frame of floodlights tilted down at the stands.
	var grey := Color(0.58, 0.59, 0.61)
	mb.add_cylinder(_v3(fp, 0.0), _v3(fp, 0.7), 0.85, 0.75, 8, Color(0.62, 0.62, 0.6))
	mb.add_cylinder(_v3(fp, 0.7), _v3(fp, 24.0), 0.42, 0.2, 8, grey, false)
	mb.add_cylinder(_v3(fp, 22.6), _v3(fp, 22.8), 1.4, 1.4, 8, Color(0.3, 0.3, 0.32))
	for k in 8:
		var a0 := TAU * k / 8.0
		var a1 := TAU * (k + 1) / 8.0
		var p0 := fp + Vector2(cos(a0), sin(a0)) * 1.35
		var p1 := fp + Vector2(cos(a1), sin(a1)) * 1.35
		mb.add_cylinder(_v3(p0, 22.8), _v3(p1, 23.7), 0.04, 0.04, 3, grey, false)
	var yawf := atan2(facing.x, facing.y)
	var hb := Basis(Vector3.UP, yawf)
	mb.add_box_xf(Transform3D(hb, _v3(fp, 24.1)), Vector3(4.2, 0.25, 0.3), Color(0.3, 0.3, 0.32))
	mb.add_box_xf(Transform3D(hb, _v3(fp, 25.0)), Vector3(4.2, 0.25, 0.3), Color(0.3, 0.3, 0.32))
	for k2 in 4:
		var off := along * (k2 - 1.5) * 1.0
		for row in 2:
			var lb := hb * Basis(Vector3.RIGHT, 0.55)
			var lp := _v3(fp + off + facing * 0.35, 24.1 + row * 0.9)
			mb.add_box_xf(Transform3D(lb, lp), Vector3(0.85, 0.6, 0.3), Color(0.22, 0.22, 0.24))
			mb.add_box_xf(Transform3D(lb, lp + (lb * Vector3(0, 0, 0.16))), Vector3(0.7, 0.45, 0.04), Color(0.95, 0.93, 0.85))
