class_name RealBuilder
## Geometry for RealLayout airports (see RealAirports): the real pavement (concrete aprons and
## asphalt taxiways), yellow taxiway centrelines, holding points with their signs, the real
## building footprints extruded to their real heights (lit, glazed terminals; hangars, car parks,
## offices and sheds), green taxiway centreline lights, stop bars and apron floodlight masts.
## Safe on worker threads, like AirportBuilder.

const Geo := preload("res://src/world/models/airports/terminal_geo.gd")
const K := preload("res://src/world/models/model_kit.gd")
const APRON_Y := 0.04
const TWY_Y := 0.05
const YELLOW := Color(0.86, 0.68, 0.1)
const PLANT := Color(0.55, 0.57, 0.58)
const STEEL_DARK := Color(0.24, 0.25, 0.27)
const WINDOW := Color(0.1, 0.13, 0.17)


# ------------------------------------------------------------------ pavement and paint
static func pavement(L: Dictionary, prod: Dictionary) -> void:
	var R: Dictionary = L.real_data
	var conc := MeshBuilder.new()
	_tris(conc, R.pa_vf, R.pa_ii, APRON_Y, true)
	AirportBuilder._mesh(prod, conc, "apron", {"mode": 2, "priority": 1.0, "tint": 0.8})
	var asph := MeshBuilder.new()
	_tris(asph, R.pt_vf, R.pt_ii, TWY_Y, false)
	AirportBuilder._mesh(prod, asph, "taxiway", {"mode": 1, "rw_wid": 23.0, "priority": 2.0})
	var paint := MeshBuilder.new()
	var nodes: Array = L.taxi_nodes
	for e in L.taxi_edges:
		var nm := String(e.name)
		if nm.begins_with("RWY") or nm.begins_with("stand"):
			continue
		AirportBuilder._paint_line(paint, nodes[e.a].pos, nodes[e.b].pos, 0.3, YELLOW)
	# runway holding points: two solid and two dashed lines across the taxiway, sign beside it
	var adj := AirportLayout._adjacency(L)
	for nd in nodes:
		if nd.kind != "hold":
			continue
		var rk := int(nd.get("runway", -1))
		if rk < 0 or rk >= L.runways.size():
			continue
		var rw: Dictionary = L.runways[rk]
		var hp: Vector2 = nd.pos
		var dirv := _toward_runway(L, adj, nd.id, rw)
		if dirv == Vector2.ZERO:
			continue
		var sv := Vector2(-dirv.y, dirv.x)
		var w := 23.0
		for k in 4:
			var off := dirv * (float(k) * 0.9 - 1.35)
			if k < 2:
				AirportBuilder._paint_line(paint, hp + off - sv * w * 0.5, hp + off + sv * w * 0.5, 0.3, YELLOW)
			else:
				for q in int(w / 2.0):
					if q % 2 == 0:
						var s0 := -w * 0.5 + q * 2.0
						AirportBuilder._paint_line(paint, hp + off + sv * s0, hp + off + sv * (s0 + 2.0), 0.3, YELLOW)
		AirportBuilder._sign_box(prod, hp + sv * (w * 0.5 + 6.0) - dirv * 2.0, -dirv, String(rw.id).replace("/", "-"), Color(0.7, 0.05, 0.05), Color(1, 1, 1))
	AirportBuilder._mesh(prod, paint, "paint", {})


static func _toward_runway(L: Dictionary, adj: Array, ni: int, rw: Dictionary) -> Vector2:
	## Direction from a holding point along its taxiway toward the runway it protects.
	var p: Vector2 = L.taxi_nodes[ni].pos
	var cen: Vector2 = rw.center
	var right: Vector2 = rw.right
	var d0 := absf((p - cen).dot(right))
	var best := Vector2.ZERO
	var bd := d0
	for nb in adj[ni]:
		var q: Vector2 = L.taxi_nodes[nb[0]].pos
		var dq := absf((q - cen).dot(right))
		if dq < bd and q.distance_to(p) > 0.5:
			bd = dq
			best = (q - p).normalized()
	return best


static func _tris(mb: MeshBuilder, v: PackedFloat32Array, idx: PackedInt32Array, y: float, world_uv: bool) -> void:
	var base := mb.vcount()
	var n := v.size() / 2
	for i in n:
		var x := v[i * 2]
		var z := v[i * 2 + 1]
		mb.add_vertex(Vector3(x, y, z), Vector3.UP, Color.WHITE, Vector2(x, z) if world_uv else Vector2(1000.0, z))
	for t in idx.size() / 3:
		var a := idx[t * 3]
		var b := idx[t * 3 + 1]
		var c := idx[t * 3 + 2]
		_tri_up(mb, base + a, base + b, base + c)


static func _tri_up(mb: MeshBuilder, a: int, b: int, c: int) -> void:
	var pa: Vector3 = mb.verts[a]
	var e1: Vector3 = mb.verts[b] - pa
	var e2: Vector3 = mb.verts[c] - pa
	if e1.cross(e2).y > 0.0:
		mb.add_tri_idx(a, c, b)
	else:
		mb.add_tri_idx(a, b, c)


# ------------------------------------------------------------------ lighting
static func lights(L: Dictionary, prod: Dictionary) -> void:
	var buf: PackedFloat32Array = prod.lights
	var green := Color(0.25, 1.0, 0.45)
	var red := Color(1.0, 0.1, 0.05)
	var nodes: Array = L.taxi_nodes
	# green centreline lights every 30 m
	for e in L.taxi_edges:
		var nm := String(e.name)
		if nm.begins_with("RWY") or nm.begins_with("stand"):
			continue
		var a: Vector2 = nodes[e.a].pos
		var b: Vector2 = nodes[e.b].pos
		var ln := a.distance_to(b)
		var k := 0.0
		while k < ln:
			AirportBuilder._push_light(buf, AirportBuilder._v3(a.lerp(b, k / maxf(ln, 0.01)), 0.12), 0.24, green, -1.0)
			k += 30.0
	# stop bars at the holding points
	var adj := AirportLayout._adjacency(L)
	for nd in nodes:
		if nd.kind != "hold":
			continue
		var rk := int(nd.get("runway", -1))
		if rk < 0 or rk >= L.runways.size():
			continue
		var dirv := _toward_runway(L, adj, nd.id, L.runways[rk])
		if dirv == Vector2.ZERO:
			continue
		var sv := Vector2(-dirv.y, dirv.x)
		for q in range(-7, 8):
			AirportBuilder._push_light(buf, AirportBuilder._v3((nd.pos as Vector2) + sv * q * 1.5, 0.15), 0.3, red, -1.0)
	# apron floodlight masts between every other pair of contact stands, close to the terminal
	var poles := MeshBuilder.new()
	var stands: Array = L.stands
	var used := {}
	for i in stands.size():
		var s: Dictionary = stands[i]
		var best := -1
		var bd := 130.0
		for j in stands.size():
			if j == i:
				continue
			var o: Dictionary = stands[j]
			if (s.normal as Vector2).dot(o.normal) < 0.9:
				continue
			var d: float = (s.facade_origin as Vector2).distance_to(o.facade_origin)
			if d < bd and d > 38.0:
				bd = d
				best = j
		if best < 0:
			continue
		var key := "%d_%d" % [mini(i, best), maxi(i, best)]
		if used.has(key) or (i % 2 == 1):
			continue
		used[key] = true
		var o2: Dictionary = stands[best]
		var nn: Vector2 = ((s.normal as Vector2) + (o2.normal as Vector2)).normalized()
		var fp: Vector2 = ((s.facade_origin as Vector2) + (o2.facade_origin as Vector2)) * 0.5 + nn * 11.0
		AirportBuilder._flood_mast(poles, fp, nn, Vector2(-nn.y, nn.x))
		AirportBuilder._push_light(buf, AirportBuilder._v3(fp + nn * 0.6, 23.6), 1.8, Color(1.0, 0.88, 0.65), -1.0)
	AirportBuilder._mesh(prod, poles, "vcolor", {}, false)


# ------------------------------------------------------------------ buildings
static func building(m: Dictionary, prod: Dictionary, L: Dictionary, a: Dictionary, b: Dictionary, st: Dictionary, bi: int, detail: float) -> void:
	if String(b.kind) == "terminal":
		_terminal(m, prod, L, a, b, st, bi, detail)
	else:
		_block(m, prod, L, b, st, bi)


static func _rings(b: Dictionary) -> Array:
	var out := [b.poly]
	for h in b.holes:
		out.append(h)
	return out


static func _terminal(m: Dictionary, prod: Dictionary, L: Dictionary, a: Dictionary, b: Dictionary, st: Dictionary, bi: int, detail: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = bi * 977 + U.hash_str(String(L.icao))
	var clad: Color = st.clad
	var v: MeshBuilder = m.far
	var FL := Geo.FL
	var top := maxf(float(b.h), FL + 7.0)
	var glaze_top := top - 1.6
	var props := detail > 0.45
	var longest := 0.0
	var sign_at := Vector2.ZERO
	var sign_out := Vector2.ZERO
	for ri in _rings(b).size():
		var ring: PackedVector2Array = _rings(b)[ri]
		var n := ring.size()
		for i in n:
			var p0 := ring[i]
			var p1 := ring[(i + 1) % n]
			var dv := p1 - p0
			var W := dv.length()
			if W < 0.4:
				continue
			var dn := dv / W
			var out := Vector2(dn.y, -dn.x)
			var n3 := Vector3(out.x, 0, out.y)
			# service level, roof fascia and (on short faces) solid cladding
			Geo.wq(v, Vector3(p0.x, 0, p0.y), Vector3(p1.x, 0, p1.y), Vector3(p1.x, FL, p1.y), Vector3(p0.x, FL, p0.y), n3, clad * Color(0.82, 0.82, 0.82))
			Geo.wq(v, Vector3(p0.x, glaze_top, p0.y), Vector3(p1.x, glaze_top, p1.y), Vector3(p1.x, top + 0.9, p1.y), Vector3(p0.x, top + 0.9, p0.y), n3, clad)
			if W >= 8.0:
				var mid := (p0 + p1) * 0.5
				var basis := Basis(Vector3(-dn.x, 0, -dn.y), Vector3.UP, n3)
				var xf := Transform3D(basis, Vector3(mid.x, 0, mid.y))
				Geo.light_face(m, prod, xf, W, FL, glaze_top, 7.0 if W > 20.0 else 4.0, st, rng, props and W > 14.0, 3.2 if W < 400.0 else 4.8)
				if ri == 0 and W > longest:
					longest = W
					sign_at = mid
					sign_out = out
			else:
				Geo.wq(v, Vector3(p0.x, FL, p0.y), Vector3(p1.x, FL, p1.y), Vector3(p1.x, glaze_top, p1.y), Vector3(p0.x, glaze_top, p0.y), n3, clad)
	# metal roofs read as light grey from the air rather than snow white
	_roof(v, b, top + 0.9, (st.roof_col as Color).lerp(Color(0.6, 0.62, 0.64), 0.45))
	_roof_plant(m.misc, b, top + 0.9, rng)
	var title := String(b.get("title", ""))
	if b.unit == L.buildings[0].unit or title == "":
		title = String(a.name) if b.unit == L.buildings[0].unit else ""
	if title != "" and longest > 40.0:
		AirportBuilder._sign_label(prod, title.to_upper(), Vector3(sign_at.x + sign_out.x * 0.8, top + 2.4, sign_at.y + sign_out.y * 0.8), sign_out,
			3.4 if longest > 120.0 else 2.2, Color(0.95, 0.97, 1.0), 6)


const BLOCK_COLS := [Color(0.82, 0.8, 0.76), Color(0.72, 0.74, 0.76), Color(0.86, 0.85, 0.82), Color(0.62, 0.64, 0.66),
	Color(0.78, 0.74, 0.66), Color(0.9, 0.9, 0.88), Color(0.68, 0.7, 0.72)]


static func _block(m: Dictionary, prod: Dictionary, L: Dictionary, b: Dictionary, st: Dictionary, bi: int) -> void:
	var v: MeshBuilder = m.far
	var kind := String(b.kind)
	var h := float(b.h)
	var y0 := minf(float(b.min_h), h - 2.0)
	var hs := U.hash_str(String(L.icao) + str(bi))
	var col: Color = BLOCK_COLS[hs % BLOCK_COLS.size()]
	match kind:
		"hangar":
			col = [Color(0.78, 0.8, 0.83), Color(0.88, 0.89, 0.9), Color(0.62, 0.66, 0.72)][hs % 3]
		"garage":
			col = Color(0.74, 0.73, 0.7)
		"hotel":
			col = [Color(0.86, 0.84, 0.8), Color(0.55, 0.6, 0.66), Color(0.8, 0.76, 0.7)][hs % 3]
		"cargo":
			col = [Color(0.8, 0.8, 0.78), Color(0.7, 0.72, 0.68), Color(0.82, 0.78, 0.7)][hs % 3]
	var roof_c := col * Color(0.78, 0.78, 0.8)
	var floor_h := 3.0 if kind == "garage" else 3.6
	var floors := int((h - y0) / floor_h)
	var longest := 0.0
	var door := []
	for ring in _rings(b):
		var n := (ring as PackedVector2Array).size()
		for i in n:
			var p0: Vector2 = ring[i]
			var p1: Vector2 = ring[(i + 1) % n]
			var dv := p1 - p0
			var W := dv.length()
			if W < 0.3:
				continue
			var dn := dv / W
			var out := Vector2(dn.y, -dn.x)
			var n3 := Vector3(out.x, 0, out.y)
			Geo.wq(v, Vector3(p0.x, y0, p0.y), Vector3(p1.x, y0, p1.y), Vector3(p1.x, h, p1.y), Vector3(p0.x, h, p0.y), n3, col)
			# a darker plinth
			if y0 < 0.5:
				var o := out * 0.04
				Geo.wq(v, Vector3(p0.x + o.x, 0, p0.y + o.y), Vector3(p1.x + o.x, 0, p1.y + o.y), Vector3(p1.x + o.x, 0.9, p1.y + o.y), Vector3(p0.x + o.x, 0.9, p0.y + o.y), n3, col * Color(0.6, 0.6, 0.6))
			if W > longest:
				longest = W
				door = [p0, p1, out]
			if W < 4.0:
				continue
			# window bands (offices, hotels), open decks (car parks)
			if kind in ["garage", "hotel", "other", "cargo"] and floors >= 1 and h - y0 > 5.0:
				var o2 := out * 0.06
				var inset := minf(0.8, W * 0.1)
				var q0 := p0 + dn * inset + o2
				var q1 := p1 - dn * inset + o2
				for f in floors:
					var fy := y0 + float(f) * floor_h
					var wy0 := fy + (1.0 if kind == "garage" else 1.0)
					var wy1 := fy + (2.5 if kind == "garage" else 2.6)
					if wy1 > h - 0.4:
						break
					if kind == "cargo" and f > 0:
						break
					var wc := Color(0.14, 0.14, 0.15) if kind == "garage" else WINDOW
					Geo.wq(v, Vector3(q0.x, wy0, q0.y), Vector3(q1.x, wy0, q1.y), Vector3(q1.x, wy1, q1.y), Vector3(q0.x, wy1, q0.y), n3, wc)
	# hangar door on the longest face
	if kind == "hangar" and not door.is_empty() and longest > 25.0:
		var p0d: Vector2 = door[0]
		var p1d: Vector2 = door[1]
		var od: Vector2 = door[2]
		var o3 := od * 0.08
		var dl := p1d - p0d
		var dh := minf(h * 0.82, h - 2.0)
		var a0 := p0d + dl * 0.07 + o3
		var a1 := p1d - dl * 0.07 + o3
		Geo.wq(v, Vector3(a0.x, 0, a0.y), Vector3(a1.x, 0, a1.y), Vector3(a1.x, dh, a1.y), Vector3(a0.x, dh, a0.y), Vector3(od.x, 0, od.y), Color(0.4, 0.45, 0.5))
		var leaves := int(longest / 12.0)
		for k in range(1, leaves):
			var lp := a0.lerp(a1, float(k) / leaves) + od * 0.02
			Geo.wq(v, Vector3(lp.x - dl.normalized().x * 0.15, 0, lp.y - dl.normalized().y * 0.15), Vector3(lp.x + dl.normalized().x * 0.15, 0, lp.y + dl.normalized().y * 0.15),
				Vector3(lp.x + dl.normalized().x * 0.15, dh, lp.y + dl.normalized().y * 0.15), Vector3(lp.x - dl.normalized().x * 0.15, dh, lp.y - dl.normalized().y * 0.15), Vector3(od.x, 0, od.y), Color(0.3, 0.33, 0.37))
	_roof(v, b, h, roof_c)
	if float(b.len) * float(b.depth) > 1800.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = hs
		_roof_plant(m.misc, b, h, rng)


static func _roof(v: MeshBuilder, b: Dictionary, y: float, col: Color) -> void:
	var base := v.vcount()
	for ring in _rings(b):
		for p in ring:
			v.add_vertex(Vector3(p.x, y, p.y), Vector3.UP, col)
	var idx: PackedInt32Array = b.roof
	var nv := v.vcount() - base
	for t in idx.size() / 3:
		var i0 := idx[t * 3]
		var i1 := idx[t * 3 + 1]
		var i2 := idx[t * 3 + 2]
		if i0 >= nv or i1 >= nv or i2 >= nv:
			continue
		_tri_up(v, base + i0, base + i1, base + i2)


static func _roof_plant(misc: MeshBuilder, b: Dictionary, y: float, rng: RandomNumberGenerator) -> void:
	## HVAC units and vents scattered over a flat roof (inside the footprint).
	var poly: PackedVector2Array = b.poly
	var c: Vector2 = b.center
	var ax: Vector2 = b.axis
	var nn := Vector2(-ax.y, ax.x)
	var area := float(b.len) * float(b.depth)
	var want := clampi(int(area / 900.0), 2, 40)
	var tries := want * 4
	var placed := 0
	while placed < want and tries > 0:
		tries -= 1
		var p := c + ax * rng.randf_range(-0.45, 0.45) * float(b.len) + nn * rng.randf_range(-0.45, 0.45) * float(b.depth)
		if not Geometry2D.is_point_in_polygon(p, poly):
			continue
		var inside_hole := false
		for hr in b.holes:
			if Geometry2D.is_point_in_polygon(p, hr):
				inside_hole = true
		if inside_hole:
			continue
		var sz := Vector3(rng.randf_range(2.0, 5.0), rng.randf_range(1.2, 2.4), rng.randf_range(2.0, 7.0))
		misc.xf = Transform3D(Basis(Vector3.UP, atan2(ax.x, ax.y)), Vector3(p.x, y, p.y))
		misc.add_box(Vector3(0, sz.y * 0.5, 0), sz, PLANT)
		K.cyl(misc, Vector3(0, sz.y, 0), Vector3(0, sz.y + 0.25, 0), minf(sz.x, sz.z) * 0.32, minf(sz.x, sz.z) * 0.32, 8, STEEL_DARK)
		placed += 1
	misc.xf = Transform3D.IDENTITY
