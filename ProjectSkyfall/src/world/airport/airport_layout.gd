class_name AirportLayout
## Pure-data airport plan in airport-local metres (origin at the airport reference point,
## x = east, z = south). Shared by the visual builder, ATC, ground operations and AI traffic.

static var _cache := {}


static func get_layout(icao: String) -> Dictionary:
	if not _cache.has(icao):
		_cache[icao] = _compute(icao)
	return _cache[icao]


static func _compute(icao: String) -> Dictionary:
	var a: Dictionary = Airports.get_ap(icao)
	var size: String = a.size
	var term: Dictionary = a.terminal
	var L := {
		"icao": icao, "size": size, "elev": float(a.elev), "runways": [], "taxi_nodes": [], "taxi_edges": [],
		"stands": [], "facades": [], "buildings": [], "aprons": [], "taxiways": [], "lights": [],
		"tower": Vector2.ZERO, "tower_h": 40.0, "arff": Vector2.ZERO, "windsocks": [], "ils": [],
		"roads": [], "parking": [], "hangars": [], "fuel": Vector2.ZERO, "gate_style": term.style,
	}
	var big := size == "hub"
	var ga := size == "ga"
	# ---------------------------------------------------------------- runways
	var ri := 0
	for r in a.runways:
		var h := deg_to_rad(float(r.hdg))
		var dir := Vector2(sin(h), -cos(h))
		var right := Vector2(-dir.y, dir.x)
		var c := right * float(r.off) + dir * float(r.along)
		var names: PackedStringArray = String(r.id).split("/")
		var half := float(r.len) * 0.5
		var rw := {
			"index": ri, "id": r.id, "names": names, "hdg": float(r.hdg), "dir": dir, "right": right, "center": c,
			"len": float(r.len), "wid": float(r.wid), "half": half, "surface": r.surface,
			"ends": [
				{"name": names[0], "thr": c - dir * half, "dir": dir, "hdg": float(r.hdg), "ils": bool(r.ils[0])},
				{"name": names[1], "thr": c + dir * half, "dir": -dir, "hdg": U.wrap_deg(float(r.hdg) + 180.0), "ils": bool(r.ils[1])},
			],
			"tw_name": ["A", "B", "C", "D"][ri],
		}
		L.runways.append(rw)
		ri += 1
	# terminal reference: which side of the main runway the terminal sits on
	var r0: Dictionary = L.runways[0]
	var between: bool = term.get("between", false) and L.runways.size() >= 2
	var tside := float(term.side)
	var tw_wid := 23.0 if big else (16.0 if not ga else 10.0)
	var gap := 168.0 if big else (115.0 if not ga else 70.0)
	# taxiway side per runway: towards the terminal area
	var term_center := Vector2.ZERO
	if between:
		term_center = (L.runways[0].center + L.runways[1].center) * 0.5
	else:
		term_center = r0.center + r0.right * tside * (gap + 260.0)
	for rw in L.runways:
		var to_t: Vector2 = term_center - rw.center
		var side := signf(to_t.dot(rw.right))
		if side == 0.0:
			side = tside
		if rw.index == 0 and not between:
			side = tside
		rw.tw_side = side
		rw.tw_off = rw.wid * 0.5 + gap - (0.0 if rw.surface == "asphalt" else 30.0)
		rw.tw_wid = tw_wid if rw.surface == "asphalt" else 0.0
	# ---------------------------------------------------------------- taxi graph
	var nodes: Array = L.taxi_nodes
	var edges: Array = L.taxi_edges
	var tw_nodes := {}
	for rw in L.runways:
		if rw.surface != "asphalt":
			continue
		var count := 4 if rw.len < 2000.0 else (5 if rw.len < 3000.0 else 7)
		if ga:
			count = 3
		var tlist := []
		for k in count:
			var f := float(k) / float(count - 1)
			var along = (f - 0.5) * rw.len
			var rp: Vector2 = rw.center + rw.dir * along
			var tp: Vector2 = rp + rw.right * rw.tw_side * rw.tw_off
			var hold_d: float = rw.wid * 0.5 + (75.0 if big else 50.0)
			if ga:
				hold_d = rw.wid * 0.5 + 25.0
			var hp: Vector2 = rp + rw.right * rw.tw_side * hold_d
			var conn: String = "%s%d" % [rw.tw_name, k + 1]
			var tn := _add_node(nodes, tp, "taxi", rw.tw_name)
			var hn := _add_node(nodes, hp, "hold", conn)
			var rn := _add_node(nodes, rp, "rwy", rw.id)
			nodes[hn].runway = rw.index
			nodes[hn].along = along
			nodes[rn].runway = rw.index
			nodes[rn].along = along
			_add_edge(edges, tn, hn, conn)
			_add_edge(edges, hn, rn, conn)
			if k > 0:
				_add_edge(edges, tlist[k - 1].t, tn, rw.tw_name)
				_add_edge(edges, tlist[k - 1].r, rn, "RWY " + String(rw.id))
			tlist.append({"t": tn, "h": hn, "r": rn, "along": along})
		tw_nodes[rw.index] = tlist
		# visual taxiway strips
		L.taxiways.append({"a": tlist[0].t, "b": tlist[count - 1].t, "w": rw.tw_wid, "name": rw.tw_name})
		for e in tlist:
			L.taxiways.append({"a": e.t, "b": e.r, "w": rw.tw_wid, "name": "conn", "hold": e.h})
	# ---------------------------------------------------------------- terminal, facades, stands
	var gates: int = int(term.gates)
	var spacing := 82.0 if big else 68.0
	var stand_depth := 95.0 if big else 82.0
	var lane := 48.0
	var facade_list := []
	if ga:
		_ga_apron(L, r0, tw_nodes)
	elif between:
		var rA: Dictionary = L.runways[0]
		var rB: Dictionary = L.runways[1]
		var mid: Vector2 = (rA.center + rB.center) * 0.5
		var depth := 120.0
		var length := float(maxi(gates / 2, 3)) * spacing + 120.0
		var axis: Vector2 = rA.dir
		var nA: Vector2 = (rA.center - mid).normalized()
		L.buildings.append({"kind": "terminal", "center": mid, "axis": axis, "len": length, "depth": depth, "h": 24.0})
		facade_list.append({"origin": mid + nA * depth * 0.5, "axis": axis, "normal": nA, "len": length, "gates": gates - gates / 2, "rw": 0})
		facade_list.append({"origin": mid - nA * depth * 0.5, "axis": axis, "normal": -nA, "len": length, "gates": gates / 2, "rw": 1})
	else:
		var depth2 := 105.0 if big else 62.0
		var length2 := float(maxi(gates, 2)) * spacing + (140.0 if big else 70.0)
		var nrm: Vector2 = -r0.right * r0.tw_side
		var front: Vector2 = r0.center + r0.right * r0.tw_side * (r0.tw_off + tw_wid * 0.5 + lane + stand_depth + 10.0)
		var center: Vector2 = front - nrm * depth2 * 0.5
		L.buildings.append({"kind": "terminal", "center": center, "axis": r0.dir, "len": length2, "depth": depth2, "h": 22.0 if big else 14.0})
		facade_list.append({"origin": front, "axis": r0.dir, "normal": nrm, "len": length2, "gates": gates, "rw": 0})
	var gate_letter := ["A", "B"]
	var fi := 0
	for fc in facade_list:
		var axis2: Vector2 = fc.axis
		var nrm2: Vector2 = fc.normal
		var n_g: int = fc.gates
		var lane_pos: Vector2 = fc.origin + nrm2 * (stand_depth + lane * 0.5)
		var lane_nodes := []
		for g in n_g:
			var t := (float(g) - (n_g - 1) * 0.5) * spacing
			var stop: Vector2 = fc.origin + axis2 * t + nrm2 * 14.0
			var lead: Vector2 = lane_pos + axis2 * t
			var sname := "%s%d" % [gate_letter[fi % 2], g + 1]
			var heavy := big and (g % 3 == 0)
			var ln := _add_node(nodes, lead, "apron", "apron")
			var sn := _add_node(nodes, stop, "stand", sname)
			_add_edge(edges, ln, sn, "stand " + sname)
			if g > 0:
				_add_edge(edges, lane_nodes[g - 1], ln, "apron")
			lane_nodes.append(ln)
			L.stands.append({"name": sname, "stop": stop, "lead": lead, "node": sn, "lane_node": ln,
				"hdg": U.dir_to_heading(Vector3(-nrm2.x, 0, -nrm2.y)), "normal": nrm2, "axis": axis2,
				"facade_origin": fc.origin + axis2 * t, "heavy": heavy, "bridge": true, "max_span": 66.0 if heavy else 40.0})
		fc.lane_nodes = lane_nodes
		L.facades.append(fc)
		# apron slab
		var apron_c: Vector2 = fc.origin + nrm2 * (stand_depth + lane) * 0.5
		L.aprons.append({"center": apron_c, "axis": axis2, "len": fc.len + 40.0, "depth": stand_depth + lane + 10.0})
		# connect both lane ends to the nearest parallel taxiway nodes
		if not lane_nodes.is_empty():
			var rwi: int = fc.rw
			if tw_nodes.has(rwi):
				for end_node in [lane_nodes[0], lane_nodes[lane_nodes.size() - 1]]:
					var best := -1
					var bd := INF
					for e in tw_nodes[rwi]:
						var d: float = nodes[e.t].pos.distance_to(nodes[end_node].pos)
						if d < bd:
							bd = d
							best = e.t
					if best >= 0:
						# extend the lane to the taxiway with an intermediate corner node
						var ep: Vector2 = nodes[end_node].pos
						var out_dir := axis2 * signf((ep - (fc.origin as Vector2)).dot(axis2))
						var corner := ep + out_dir * 40.0
						var cn := _add_node(nodes, corner, "apron", "apron")
						_add_edge(edges, end_node, cn, "apron")
						_add_edge(edges, cn, best, "J%d" % (fi * 2 + (1 if end_node == lane_nodes[0] else 2)))
						L.taxiways.append({"a": cn, "b": best, "w": tw_wid, "name": "J"})
						L.taxiways.append({"a": end_node, "b": cn, "w": tw_wid, "name": "apron"})
		fi += 1
	# link secondary runway taxiways into the main network
	for rw in L.runways:
		if rw.index == 0 or not tw_nodes.has(rw.index) or not tw_nodes.has(0):
			continue
		var best_a := -1
		var best_b := -1
		var bd2 := INF
		for ea in tw_nodes[0]:
			for eb in tw_nodes[rw.index]:
				var d2: float = nodes[ea.t].pos.distance_to(nodes[eb.t].pos)
				if d2 < bd2:
					bd2 = d2
					best_a = ea.t
					best_b = eb.t
		if best_a >= 0 and bd2 > 1.0:
			_add_edge(edges, best_a, best_b, "L")
			L.taxiways.append({"a": best_a, "b": best_b, "w": tw_wid, "name": "L"})
	# ---------------------------------------------------------------- support buildings
	if not ga and not L.buildings.is_empty():
		var tb: Dictionary = L.buildings[0]
		var tax: Vector2 = tb.axis
		var tn2: Vector2 = Vector2(-tax.y, tax.x)
		if (term_center - tb.center).dot(tn2) < 0.0:
			tn2 = -tn2
		var end_a: Vector2 = tb.center + tax * (tb.len * 0.5 + 90.0)
		L.tower = end_a + tn2 * 0.0
		L.tower_h = 72.0 if big else 38.0
		var hang_base: Vector2 = tb.center - tax * (tb.len * 0.5 + (150.0 if big else 90.0))
		var hn := 3 if big else 2
		for k in hn:
			var hp2: Vector2 = hang_base - tax * float(k) * (105.0 if big else 62.0)
			var hw := 88.0 if big else 50.0
			L.hangars.append({"center": hp2, "axis": tax, "w": hw, "d": hw * 0.8, "h": hw * 0.3, "door_normal": _facade_normal_towards(hp2, tax, r0)})
		L.arff = hang_base - tax * float(hn) * (105.0 if big else 62.0) - tax * 40.0
		L.fuel = hang_base + _facade_normal_towards(hang_base, tax, r0) * -170.0
		# landside: car park and access road behind the terminal (away from the runway)
		var back: Vector2 = -_facade_normal_towards(tb.center, tax, r0)
		if between:
			back = tax
		var park_c: Vector2 = tb.center + back * (tb.depth * 0.5 + 95.0)
		if between:
			park_c = tb.center + tax * (tb.len * 0.5 + 220.0)
		L.parking.append({"center": park_c, "axis": tax, "len": minf(tb.len, 360.0), "depth": 120.0})
		L.roads.append({"a": park_c - tax * minf(tb.len, 360.0) * 0.5, "b": park_c - tax * minf(tb.len, 360.0) * 0.5 + back * 900.0, "w": 14.0})
		L.roads.append({"a": tb.center + back * (tb.depth * 0.5 + 22.0) - tax * tb.len * 0.5, "b": tb.center + back * (tb.depth * 0.5 + 22.0) + tax * tb.len * 0.5, "w": 16.0})
	# ---------------------------------------------------------------- navaids & aids
	for rw in L.runways:
		if rw.surface != "asphalt":
			continue
		for e in rw.ends:
			var thr: Vector2 = e.thr
			var d: Vector2 = e.dir
			var side := Vector2(-d.y, d.x)
			# PAPI on the left of the approach, ~ 300 m in
			var papi_c: Vector2 = thr + d * (300.0 if rw.len > 1500.0 else 200.0) - side * (rw.wid * 0.5 + 18.0)
			e.papi = papi_c
			e.papi_side = -side
			e.tdz = thr + d * (300.0 if rw.len > 1500.0 else 150.0)
			if e.ils:
				L.ils.append({"runway": rw.index, "end": e.name, "loc": thr + d * (rw.len + 300.0), "gs": thr + d * 300.0 + side * (rw.wid * 0.5 + 120.0),
					"hdg": e.hdg, "thr": thr, "slope": 3.0 if L.icao != "SKHP" else 3.5})
			L.windsocks.append(thr + d * 150.0 + side * (rw.wid * 0.5 + 70.0))
	return L


static func _facade_normal_towards(p: Vector2, axis: Vector2, rw: Dictionary) -> Vector2:
	var n := Vector2(-axis.y, axis.x)
	if (rw.center - p).dot(n) < 0.0:
		n = -n
	return n


static func _ga_apron(L: Dictionary, r0: Dictionary, tw_nodes: Dictionary) -> void:
	var nrm: Vector2 = r0.right * r0.tw_side
	var apron_front: Vector2 = r0.center + nrm * (r0.tw_off + 40.0)
	var apron_c: Vector2 = apron_front + nrm * 55.0
	L.aprons.append({"center": apron_c, "axis": r0.dir, "len": 230.0, "depth": 110.0})
	var nodes: Array = L.taxi_nodes
	var edges: Array = L.taxi_edges
	var lane_nodes := []
	for g in 10:
		var t := (float(g) - 4.5) * 20.0
		var lead: Vector2 = apron_front + nrm * 20.0 + r0.dir * t
		var stop: Vector2 = lead + nrm * 22.0
		var ln := _add_node(nodes, lead, "apron", "apron")
		var sn := _add_node(nodes, stop, "stand", "P%d" % (g + 1))
		_add_edge(edges, ln, sn, "tie-down")
		if g > 0:
			_add_edge(edges, lane_nodes[g - 1], ln, "apron")
		lane_nodes.append(ln)
		L.stands.append({"name": "P%d" % (g + 1), "stop": stop, "lead": lead, "node": sn, "lane_node": ln,
			"hdg": U.dir_to_heading(Vector3(nrm.x, 0, nrm.y)), "normal": -nrm, "axis": r0.dir,
			"facade_origin": stop, "heavy": false, "bridge": false, "max_span": 16.0})
	if tw_nodes.has(0):
		var mid_t: int = tw_nodes[0][1].t
		_add_edge(edges, lane_nodes[5], mid_t, "A2")
		L.taxiways.append({"a": lane_nodes[5], "b": mid_t, "w": 10.0, "name": "A2"})
	L.buildings.append({"kind": "fbo", "center": apron_c + nrm * 95.0 + r0.dir * 40.0, "axis": r0.dir, "len": 36.0, "depth": 16.0, "h": 6.0})
	L.tower = apron_c + nrm * 95.0 - r0.dir * 40.0
	L.tower_h = 14.0
	for k in 3:
		L.hangars.append({"center": apron_c + nrm * 100.0 + r0.dir * (100.0 + k * 34.0), "axis": r0.dir, "w": 28.0, "d": 22.0, "h": 8.0, "door_normal": -nrm})
	L.arff = apron_c + nrm * 100.0 - r0.dir * 110.0
	L.fuel = apron_c - r0.dir * 120.0
	L.parking.append({"center": apron_c + nrm * 150.0, "axis": r0.dir, "len": 90.0, "depth": 40.0})


static func _add_node(nodes: Array, p: Vector2, kind: String, name: String) -> int:
	# merge coincident nodes so connectors share junctions
	for i in nodes.size():
		if nodes[i].pos.distance_to(p) < 2.0 and nodes[i].kind == kind:
			return i
	nodes.append({"id": nodes.size(), "pos": p, "kind": kind, "name": name, "links": []})
	return nodes.size() - 1


static func _add_edge(edges: Array, a: int, b: int, name: String) -> void:
	edges.append({"a": a, "b": b, "name": name})


# ------------------------------------------------------------------ queries
static func neighbours(L: Dictionary, node: int, allow_runway: bool) -> Array:
	var out := []
	for e in L.taxi_edges:
		if not allow_runway and String(e.name).begins_with("RWY"):
			continue
		if e.a == node:
			out.append([e.b, e.name])
		elif e.b == node:
			out.append([e.a, e.name])
	return out


## Dijkstra shortest path; returns [{node, name}] (name = edge used to reach node).
static func find_path(L: Dictionary, from_node: int, to_node: int, allow_runway: bool = false) -> Array:
	var dist := {from_node: 0.0}
	var prev := {}
	var open := [from_node]
	var nodes: Array = L.taxi_nodes
	while not open.is_empty():
		var best_i := 0
		for i in open.size():
			if dist[open[i]] < dist[open[best_i]]:
				best_i = i
		var cur: int = open[best_i]
		open.remove_at(best_i)
		if cur == to_node:
			break
		for nb in neighbours(L, cur, allow_runway):
			var nxt: int = nb[0]
			var d: float = dist[cur] + nodes[cur].pos.distance_to(nodes[nxt].pos)
			if not dist.has(nxt) or d < dist[nxt]:
				dist[nxt] = d
				prev[nxt] = [cur, nb[1]]
				if not nxt in open:
					open.append(nxt)
	if not dist.has(to_node):
		return []
	var path := []
	var c := to_node
	while c != from_node:
		var pv: Array = prev[c]
		path.push_front({"node": c, "name": pv[1]})
		c = pv[0]
	path.push_front({"node": from_node, "name": ""})
	return path


static func route_names(path: Array) -> Array:
	var names := []
	for step in path:
		var n: String = step.name
		if n == "" or n.begins_with("stand") or n == "tie-down":
			continue
		if names.is_empty() or names[names.size() - 1] != n:
			names.append(n)
	return names


static func hold_node_for(L: Dictionary, runway_end: String) -> int:
	## The holding point at the start of the given runway end (where departures line up from).
	for rw in L.runways:
		for e in rw.ends:
			if e.name == runway_end:
				var thr: Vector2 = e.thr
				var best := -1
				var bd := INF
				for n in L.taxi_nodes:
					if n.kind == "hold" and int(n.get("runway", -1)) == rw.index:
						var d: float = n.pos.distance_to(thr)
						if d < bd:
							bd = d
							best = n.id
				return best
	return -1


static func runway_node_near(L: Dictionary, rw_index: int, p: Vector2) -> int:
	var best := -1
	var bd := INF
	for n in L.taxi_nodes:
		if n.kind == "rwy" and int(n.get("runway", -1)) == rw_index:
			var d: float = n.pos.distance_to(p)
			if d < bd:
				bd = d
				best = n.id
	return best


static func nearest_node(L: Dictionary, p: Vector2, kinds: Array = []) -> int:
	var best := -1
	var bd := INF
	for n in L.taxi_nodes:
		if not kinds.is_empty() and not n.kind in kinds:
			continue
		var d: float = n.pos.distance_to(p)
		if d < bd:
			bd = d
			best = n.id
	return best


static func runway_info(L: Dictionary, end_name: String) -> Dictionary:
	for rw in L.runways:
		for e in rw.ends:
			if e.name == end_name:
				var out: Dictionary = e.duplicate()
				out.runway = rw.index
				out.len = rw.len
				out.wid = rw.wid
				out.center = rw.center
				return out
	return {}


static func stand_by_name(L: Dictionary, sname: String) -> Dictionary:
	for s in L.stands:
		if s.name == sname:
			return s
	return {}


static func free_stand(L: Dictionary, span: float, occupied: Array, seed_value: int = 0) -> Dictionary:
	var candidates := []
	for s in L.stands:
		if float(s.max_span) >= span and not s.name in occupied:
			candidates.append(s)
	if candidates.is_empty():
		return L.stands[0] if not L.stands.is_empty() else {}
	return candidates[seed_value % candidates.size()]
