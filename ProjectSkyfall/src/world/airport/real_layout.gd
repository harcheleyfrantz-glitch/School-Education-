class_name RealLayout
## Fills an AirportLayout plan from RealAirports data: the real, named taxiway network with its
## holding points, every gate at its real position and heading, and the real building footprints.
## Runways come from the airport's own data (src/data/airports.gd holds the real runways, in the
## order the network's runway indices use).

const KINDS := ["taxi", "hold", "rwy", "apron", "stand"]


static func fill(L: Dictionary, icao: String) -> void:
	var R := RealAirports.get_data(icao)
	if R.is_empty():
		return
	L.real = true
	L.real_data = R
	var nv: PackedFloat32Array = R.nodes_f
	var kinds: PackedInt32Array = R.kinds_i
	var nrw: PackedInt32Array = R.nrw_i
	var ev: PackedInt32Array = R.edges_i
	var names: Array = R.names
	var n := kinds.size()
	var nodes: Array = L.taxi_nodes
	nodes.resize(n)
	for i in n:
		var p := Vector2(nv[i * 2], nv[i * 2 + 1])
		var kind: String = KINDS[clampi(kinds[i], 0, KINDS.size() - 1)]
		var nd := {"id": i, "pos": p, "kind": kind, "name": "", "links": []}
		var rk := nrw[i]
		if rk >= 0 and rk < L.runways.size() and kind in ["hold", "rwy"]:
			var rw: Dictionary = L.runways[rk]
			nd.runway = rk
			nd.along = (p - (rw.center as Vector2)).dot(rw.dir)
		elif kind in ["hold", "rwy"]:
			nd.kind = "taxi"
		nodes[i] = nd
	var edges: Array = L.taxi_edges
	for k in ev.size() / 3:
		var a := ev[k * 3]
		var b := ev[k * 3 + 1]
		var nm: String = names[ev[k * 3 + 2]]
		edges.append({"a": a, "b": b, "name": nm})
		if not nm.begins_with("stand") and not nm.begins_with("RWY"):
			if nodes[a].name == "":
				nodes[a].name = nm
			if nodes[b].name == "":
				nodes[b].name = nm
	# holding points that the gates cannot reach without using a runway are not departure points
	var par := PackedInt32Array()
	par.resize(n)
	for i in n:
		par[i] = i
	for e in edges:
		if String(e.name).begins_with("RWY"):
			continue
		var ra := _find(par, int(e.a))
		var rb := _find(par, int(e.b))
		if ra != rb:
			par[ra] = rb
	var count := {}
	for s0 in R.stands:
		var r0i := _find(par, int(s0.node))
		count[r0i] = int(count.get(r0i, 0)) + 1
	var main := -1
	for k in count:
		if main < 0 or int(count[k]) > int(count[main]):
			main = k
	for nd in nodes:
		if nd.kind == "hold" and _find(par, int(nd.id)) != main:
			nd.kind = "taxi"
	# gates: real positions, nose-in toward the terminal facade
	var seen := {}
	for s in R.stands:
		var f := Vector2(float(s.f[0]), float(s.f[1]))
		var d := Vector2(float(s.d[0]), float(s.d[1])).normalized()
		var ax := Vector2(-d.y, d.x)
		var span := float(s.span)
		var nm := String(s.n)
		if seen.has(nm):
			seen[nm] += 1
			nm = "%s-%d" % [nm, seen[nm]]
		else:
			seen[nm] = 1
		var lead := int(s.lead)
		L.stands.append({"name": nm, "stop": f + d * 14.0, "lead": nodes[lead].pos, "node": int(s.node), "lane_node": lead,
			"hdg": U.dir_to_heading(Vector3(-d.x, 0, -d.y)), "normal": d, "axis": ax, "facade_origin": f,
			"heavy": span >= 60.0, "bridge": bool(s.br), "max_span": span})
		L.facades.append({"origin": f, "axis": ax, "normal": d, "len": maxf(span, 30.0), "gates": 1, "rw": 0, "letter": "", "lane_nodes": [lead]})
	# buildings: footprints with an oriented box for the systems that want one; the best
	# rectangular terminal with gates goes first (it hosts the walkable departures hall)
	var gates_on := {}
	var blist := []
	var ui := 0
	for b in R.buildings:
		var o: Array = b.obb
		var k := String(b.k)
		var h := float(b.h)
		blist.append({"kind": k, "center": Vector2(float(o[0]), float(o[1])), "axis": Vector2(float(o[2]), float(o[3])).normalized(),
			"len": float(o[4]), "depth": float(o[5]), "h": h, "levels": (3 if h > 18.0 else 2) if k == "terminal" else 1, "unit": ui,
			"poly": b.poly, "holes": b.hole_rings, "roof": b.roof, "min_h": float(b.mh), "title": String(b.n), "fill": float(b.get("fill", 0.8)),
			"real": true})
		ui += 1
	for bd in blist:
		if bd.kind != "terminal":
			continue
		var cnt := 0
		var bax: Vector2 = bd.axis
		var bn := Vector2(-bax.y, bax.x)
		for st in L.stands:
			var rel: Vector2 = (st.facade_origin as Vector2) - (bd.center as Vector2)
			if absf(absf(rel.dot(bn)) - float(bd.depth) * 0.5) < 10.0 and absf(rel.dot(bax)) < float(bd.len) * 0.5 + 10.0:
				cnt += 1
		gates_on[bd.unit] = cnt
	blist.sort_custom(func(x, y):
		var sx := (float(gates_on.get(x.unit, 0)) + 1.0) * (float(x.fill) if x.kind == "terminal" else 0.0)
		var sy := (float(gates_on.get(y.unit, 0)) + 1.0) * (float(y.fill) if y.kind == "terminal" else 0.0)
		return sx > sy)
	L.buildings = blist
	# control tower: its real position and height
	if R.get("tower") != null:
		L.tower = Vector2(float(R.tower[0]), float(R.tower[1]))
		L.tower_h = clampf(float(R.tower[2]), 40.0, 135.0)
	elif not blist.is_empty():
		L.tower = (blist[0].center as Vector2) + (blist[0].axis as Vector2) * (float(blist[0].len) * 0.5 + 120.0)
		L.tower_h = 80.0
	if float(L.style.get("tower_h", 0.0)) > 0.0 and R.get("tower") == null:
		L.tower_h = float(L.style.tower_h)
	# rescue and fire service starts from the taxiway nearest the middle of the main runway
	var r0: Dictionary = L.runways[0]
	var best := -1
	var bd2 := INF
	var tc: Vector2 = (blist[0].center as Vector2) if not blist.is_empty() else Vector2.ZERO
	var toward: Vector2 = (r0.right as Vector2) * signf((tc - (r0.center as Vector2)).dot(r0.right))
	var want: Vector2 = (r0.center as Vector2) + toward * 260.0
	for nd in nodes:
		if nd.kind == "taxi":
			var dd: float = (nd.pos as Vector2).distance_squared_to(want)
			if dd < bd2:
				bd2 = dd
				best = nd.id
	L.arff = nodes[best].pos if best >= 0 else want
	L.fuel = Vector2.ZERO
	L.outline = RealAirports.outline(icao)


static func _find(par: PackedInt32Array, x: int) -> int:
	while par[x] != x:
		par[x] = par[par[x]]
		x = par[x]
	return x
