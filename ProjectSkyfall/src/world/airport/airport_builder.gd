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
static func _buildings(L: Dictionary, a: Dictionary, prod: Dictionary, detail: float) -> void:
	var glass := MeshBuilder.new()
	var concrete := MeshBuilder.new()
	var metal := MeshBuilder.new()
	var cab := MeshBuilder.new()
	var misc := MeshBuilder.new()
	for b in L.buildings:
		var c: Vector2 = b.center
		var ax: Vector2 = b.axis
		var yaw := atan2(ax.x, ax.y)
		var basis := Basis(Vector3.UP, yaw)
		# MeshBuilder boxes are axis aligned: x across, z along after rotation
		var t := Transform3D(basis, _v3(c, 0))
		if b.kind == "terminal":
			# ground floor (baggage, services), glazed departures level (level with the jet bridge
			# stubs, see TerminalInterior.FLOOR), wavy roof
			var fl := TerminalInterior.FLOOR
			concrete.xf = t
			concrete.add_box(Vector3(0, fl * 0.5, 0), Vector3(b.depth - 2.0, fl, b.len - 2.0), Color.WHITE, true)
			glass.xf = t
			glass.add_box(Vector3(0, fl + (b.h - fl) * 0.5, 0), Vector3(b.depth, b.h - fl, b.len), Color.WHITE, true)
			metal.xf = t
			var bays := maxi(2, int(b.len / 90.0))
			for k in bays:
				var zc: float = -b.len * 0.5 + (k + 0.5) * (b.len / bays)
				metal.add_arch(Vector3(0, b.h, zc), b.depth + 14.0, 7.0 if L.size == "hub" else 4.0, b.len / bays + 0.5, 10, Color.WHITE)
			# structural columns along the airside
			for k in int(b.len / 18.0) + 1:
				var zc2: float = -b.len * 0.5 + k * 18.0
				concrete.add_box(Vector3(b.depth * 0.5 + 0.6, b.h * 0.5, zc2), Vector3(1.0, b.h, 1.0), Color.WHITE, true)
				concrete.add_box(Vector3(-b.depth * 0.5 - 0.6, b.h * 0.5, zc2), Vector3(1.0, b.h, 1.0), Color.WHITE, true)
			metal.xf = Transform3D.IDENTITY
			# airport name on both long sides
			var n := Vector2(-ax.y, ax.x)
			for sgn in [1.0, -1.0]:
				var face: Vector2 = c + n * sgn * (b.depth * 0.5 + 0.4)
				_sign_label(prod, String(a.name).to_upper(), Vector3(face.x, b.h - 3.0, face.y), n * sgn, 3.4 if L.size == "hub" else 2.2, Color(0.95, 0.97, 1.0), 6)
		else:
			concrete.xf = t
			concrete.add_box(Vector3(0, b.h * 0.5, 0), Vector3(b.depth, b.h, b.len), Color.WHITE, true)
			glass.xf = t
			glass.add_box(Vector3(0, b.h * 0.45, 0), Vector3(b.depth + 0.2, b.h * 0.4, b.len * 0.8), Color.WHITE, true)
			var n2 := Vector2(-ax.y, ax.x)
			_sign_label(prod, "%s AVIATION" % String(a.short).to_upper(), Vector3(c.x + n2.x * (b.depth * 0.5 + 0.3), b.h - 1.0, c.y + n2.y * (b.depth * 0.5 + 0.3)), n2, 1.0, Color(0.1, 0.2, 0.4))
	glass.xf = Transform3D.IDENTITY
	concrete.xf = Transform3D.IDENTITY
	# control tower
	var tp: Vector2 = L.tower
	var th: float = L.tower_h
	var tr := 4.0 if th > 50.0 else (2.6 if th > 20.0 else 1.6)
	concrete.add_cylinder(_v3(tp, 0), _v3(tp, th), tr * 1.25, tr, 12, Color.WHITE)
	concrete.add_cylinder(_v3(tp, th), _v3(tp, th + 1.2), tr * 2.0, tr * 2.0, 8, Color.WHITE)
	cab.add_cylinder(_v3(tp, th + 1.2), _v3(tp, th + 5.0), tr * 2.0, tr * 2.25, 8, Color.WHITE)
	concrete.add_cylinder(_v3(tp, th + 5.0), _v3(tp, th + 6.0), tr * 2.4, tr * 1.6, 8, Color.WHITE)
	misc.add_cylinder(_v3(tp, th + 6.0), _v3(tp, th + 11.0), 0.12, 0.08, 4, Color(0.8, 0.1, 0.1))
	prod.beacon = _v3(tp, th + 6.6)
	prod.tower_top = _v3(tp, th + 3.0)
	# hangars
	for hg in L.hangars:
		var hc: Vector2 = hg.center
		var hax: Vector2 = hg.axis
		var yaw2 := atan2(hax.x, hax.y)
		metal.xf = Transform3D(Basis(Vector3.UP, yaw2), _v3(hc, 0))
		metal.add_box(Vector3(0, hg.h * 0.5, 0), Vector3(hg.d, hg.h, hg.w), Color.WHITE, true)
		metal.add_arch(Vector3(0, hg.h, 0), hg.d, hg.h * 0.32, hg.w, 10, Color.WHITE)
		var dn: Vector2 = hg.door_normal
		misc.xf = Transform3D.IDENTITY
		var door_c: Vector2 = hc + dn * (hg.d * 0.5 + 0.2)
		var door_yaw := atan2(dn.x, dn.y)
		misc.add_box_xf(Transform3D(Basis(Vector3.UP, door_yaw), _v3(door_c, hg.h * 0.42)), Vector3(hg.w * 0.82, hg.h * 0.84, 0.3), Color(0.35, 0.4, 0.46))
	metal.xf = Transform3D.IDENTITY
	# fire station
	if L.arff != Vector2.ZERO:
		var fc: Vector2 = L.arff
		misc.add_box(_v3(fc, 4.5), Vector3(36, 9, 22), Color(0.82, 0.8, 0.76))
		for k in 4:
			misc.add_box(_v3(fc + Vector2(-13.5 + k * 9.0, 11.1), 3.4), Vector3(7.0, 6.2, 0.3), Color(0.75, 0.08, 0.06))
		_sign_label(prod, "FIRE & RESCUE", Vector3(fc.x, 7.6, fc.y + 11.3), Vector2(0, 1), 1.4, Color(0.95, 0.95, 0.95), 4)
	# fuel farm
	if L.fuel != Vector2.ZERO:
		for k in 3:
			var fp: Vector2 = (L.fuel as Vector2) + Vector2(k * 24.0 - 24.0, 0)
			misc.add_cylinder(_v3(fp, 0), _v3(fp, 12.0), 9.0, 9.0, 16, Color(0.92, 0.92, 0.9))
	# car parks with cars
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
		misc.add_box(_v3(lp, 2.4), Vector3(36.0, 0.2, 0.3), Color(0.85, 0.85, 0.85))
		misc.add_box(_v3(ils.gs, 7.0), Vector3(0.6, 14.0, 0.6), Color(0.85, 0.3, 0.1))
		misc.add_box(_v3(ils.gs + Vector2(0, 3), 1.5), Vector3(3, 3, 3), Color(0.9, 0.9, 0.88))
	# PAPI housings
	for rw in L.runways:
		for e in rw.ends:
			if not e.has("papi"):
				continue
			for k in 4:
				var pp: Vector2 = (e.papi as Vector2) + (e.papi_side as Vector2) * (k * 9.0)
				misc.add_box(_v3(pp, 0.45), Vector3(1.4, 0.7, 1.4), Color(0.2, 0.2, 0.2))
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
				poles.add_cylinder(_v3(fp, 0.0), _v3(fp, 24.0), 0.35, 0.22, 6, Color(0.55, 0.56, 0.58), false)
				poles.add_box(_v3(fp, 24.4), Vector3(3.0, 0.8, 1.2), Color(0.3, 0.3, 0.32))
				_push_light(buf, _v3(fp, 23.8), 1.8, Color(1.0, 0.88, 0.65), -1.0)
	_mesh(prod, poles, "vcolor", {}, false)
	_push_light(buf, prod.beacon, 1.2, Color(0.4, 1.0, 0.5), -10.0)
	_push_light(buf, prod.beacon + Vector3(0, 0.3, 0), 1.2, Color(1, 1, 1), -10.5)
	_push_light(buf, (prod.tower_top as Vector3) + Vector3(0, 8.0, 0), 0.6, red, -1.0)
	for hg in L.hangars:
		_push_light(buf, _v3(hg.center, hg.h + hg.d * 0.5 + 0.5), 0.5, red, -1.0)
