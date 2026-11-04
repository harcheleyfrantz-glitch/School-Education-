class_name AirportLayout
## Pure-data airport plan in airport-local metres (origin at the airport reference point,
## x = east, z = south). Shared by the visual builder, ATC, ground operations and AI traffic.

const Styles := preload("res://src/world/models/airports/airport_styles.gd")

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
		# landside = the facade the curbside faces ({origin, normal, axis, len, h}); people_mover =
		# [{a, b}] links between terminal units; style = AirportStyles entry
		"landside": {}, "people_mover": [], "style": {},
	}
	var st: Dictionary = Styles.style_for(icao, size)
	L.style = st
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
			"tw_name": ["A", "B", "C", "D", "E", "F", "G", "H"][mini(ri, 7)],
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
	# real airports: the real taxiway network, gates and buildings (tools/real_airports)
	if RealAirports.has(icao):
		RealLayout.fill(L, icao)
		if L.get("real", false):
			_navaids(L)
			return L
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
	var gates: int = maxi(int(term.gates), int(st.gates)) if not ga else 0
	var spacing := 82.0 if big else 68.0
	var stand_depth := 95.0 if big else 82.0
	var lane := 48.0
	var facade_list := []
	if ga:
		_ga_apron(L, r0, tw_nodes)
	elif icao == "KMIA":
		_miami(L, facade_list, tw_nodes, tw_wid)
	elif between:
		var rA: Dictionary = L.runways[0]
		var rB: Dictionary = L.runways[1]
		var mid: Vector2 = (rA.center + rB.center) * 0.5
		var axis: Vector2 = rA.dir
		# facade normal: square to the runways, towards runway A (staggered runway centres
		# would otherwise skew it off the terminal faces)
		var nA := Vector2(-axis.y, axis.x)
		if (rA.center - mid).dot(nA) < 0.0:
			nA = -nA
		# midfield complex: the main terminal (check-in hall at its near end) and a row of
		# satellite concourses on a people mover. Shrink it until no runway crosses any of it.
		var total_g := maxi(gates, int(st.gates))
		var plan: Array = []
		# prefer: all satellites with room for the landside, then fewer satellites, then without
		# the landside check, then fewer gates
		for need_land in [true, false]:
			for ns in range(int(st.sats), -1, -1):
				if plan.is_empty():
					plan = _between_plan(L, mid, axis, nA, total_g, ns, spacing, big, need_land)
		while plan.is_empty() and total_g > 8:
			total_g -= 4
			plan = _between_plan(L, mid, axis, nA, total_g, 0, spacing, big, false)
		if plan.is_empty():
			plan = _between_plan(L, mid, axis, nA, total_g, 0, spacing, big, false, true)
		var letters := "ABCDEFGHJK"
		var bi := 0
		for pb in plan:
			var bc: Vector2 = pb.center
			var bdp: float = pb.depth
			var bln: float = pb.len
			var g: int = pb.gates
			L.buildings.append({"kind": "terminal" if bi == 0 else "concourse", "center": bc, "axis": axis, "len": bln, "depth": bdp,
				"h": 24.0 if bi == 0 else 20.0, "levels": int(st.levels) if bi == 0 else 2, "unit": bi})
			facade_list.append({"origin": bc + nA * bdp * 0.5, "axis": axis, "normal": nA, "len": bln, "gates": g - g / 2, "rw": 0, "letter": letters[bi * 2]})
			facade_list.append({"origin": bc - nA * bdp * 0.5, "axis": axis, "normal": -nA, "len": bln, "gates": g / 2, "rw": 1, "letter": letters[bi * 2 + 1]})
			bi += 1
		# landside: the check-in hall at the near (-axis) end of the main terminal; the kerb runs
		# across that end (see Landside._kerb_frame)
		var mt: Dictionary = plan[0]
		L.landside = {"origin": (mt.center as Vector2) - axis * float(mt.len) * 0.5, "normal": -axis, "axis": nA, "len": float(mt.depth), "h": 24.0}
		L.people_mover = []
		for k in range(1, plan.size()):
			var pa: Dictionary = plan[k - 1]
			var pb2: Dictionary = plan[k]
			L.people_mover.append({"a": (pa.center as Vector2) + axis * float(pa.len) * 0.5, "b": (pb2.center as Vector2) - axis * float(pb2.len) * 0.5})
	else:
		var depth2 := 105.0 if big else 62.0
		var length2 := float(maxi(gates, 2)) * spacing + (140.0 if big else 70.0)
		var nrm: Vector2 = -r0.right * r0.tw_side
		var front: Vector2 = r0.center + r0.right * r0.tw_side * (r0.tw_off + tw_wid * 0.5 + lane + stand_depth + 10.0)
		var center: Vector2 = front - nrm * depth2 * 0.5
		L.buildings.append({"kind": "terminal", "center": center, "axis": r0.dir, "len": length2, "depth": depth2, "h": 22.0 if big else 14.0,
			"levels": int(st.levels), "unit": 0, "plan": String(st.plan)})
		facade_list.append({"origin": front, "axis": r0.dir, "normal": nrm, "len": length2, "gates": gates, "rw": 0})
		L.landside = {"origin": center - nrm * depth2 * 0.5, "normal": -nrm, "axis": r0.dir, "len": length2, "h": 22.0 if big else 14.0}
	var gate_letter := ["A", "B", "C", "D"]
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
			var sname := "%s%d" % [String(fc.get("letter", gate_letter[fi % 4])), g + 1 + int(fc.get("start", 0))]
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
			var cand: Array = []
			if fc.has("link_nodes"):
				cand = fc.link_nodes
			elif tw_nodes.has(rwi):
				for e in tw_nodes[rwi]:
					cand.append(e.t)
			var ends: Array = [lane_nodes[0], lane_nodes[lane_nodes.size() - 1]]
			if fc.has("link_nodes"):
				# piers inside the horseshoe: only the open (west) end reaches the perimeter taxiway
				var w0: int = lane_nodes[0]
				var w1: int = lane_nodes[lane_nodes.size() - 1]
				ends = [w0 if (nodes[w0].pos as Vector2).x < (nodes[w1].pos as Vector2).x else w1]
			for end_node in ends:
				var best := -1
				var bd := INF
				for ci in cand:
					var dd: float = nodes[ci].pos.distance_to(nodes[end_node].pos)
					if dd < bd:
						bd = dd
						best = ci
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
		# stand the tower forward of the terminal, level with the airside facade, so the cab
		# looks along the stands rather than across the terminal roof
		var airside: Vector2 = facade_list[0].normal if not facade_list.is_empty() else tn2
		L.tower = end_a + airside * (float(tb.depth) * 0.5 + 25.0)
		if icao == "KMIA":
			L.tower = Vector2(-1260.0, 120.0)
		L.tower_h = 72.0 if big else 38.0
		if float(st.tower_h) > 0.0:
			L.tower_h = float(st.tower_h)
		elif big and gates >= 30:
			L.tower_h = 84.0
		# maintenance base: hangars, fire station, fuel farm and cargo. Beside the terminal row on
		# single-terminal fields; outside the runway pair (or past the far concourse) on midfield ones.
		var hw := 88.0 if big else 50.0
		var hn := 3 if big else 2
		var hstep := 105.0 if big else 62.0
		var cands := []
		if between:
			var rB2: Dictionary = L.runways[1]
			var rA2: Dictionary = L.runways[0]
			for rr in [rB2, rA2]:
				var out_s := signf((rr.center - term_center).dot(rr.right))
				if out_s == 0.0:
					out_s = 1.0
				var off: float = rr.wid * 0.5 + gap + tw_wid + 230.0
				cands.append({"base": (rr.center as Vector2) + (rr.right as Vector2) * out_s * off + (rr.dir as Vector2) * hw * 2.0, "axis": rr.dir, "door": -(rr.right as Vector2) * out_s})
			var last: Dictionary = L.buildings[L.buildings.size() - 2] if L.buildings.size() >= 2 else tb
			cands.append({"base": (last.center as Vector2) + tax * (float(last.len) * 0.5 + 260.0), "axis": tn2, "door": -tax})
		else:
			cands.append({"base": tb.center - tax * (tb.len * 0.5 + (150.0 if big else 90.0)), "axis": tax, "door": _facade_normal_towards(tb.center, tax, r0)})
		var chosen: Dictionary = cands[0]
		for cd in cands:
			var ok := true
			for k in hn + 2:
				var hp3: Vector2 = (cd.base as Vector2) - (cd.axis as Vector2) * float(k) * hstep
				if not _clear_of_runways(L, hp3, cd.axis, hw + 20.0, hw + 40.0):
					ok = false
			if ok:
				chosen = cd
				break
		var hang_base: Vector2 = chosen.base
		var hax: Vector2 = chosen.axis
		var door: Vector2 = chosen.door
		for k in hn:
			var hp2: Vector2 = hang_base - hax * float(k) * hstep
			L.hangars.append({"center": hp2, "axis": hax, "w": hw, "d": hw * 0.8, "h": hw * 0.3, "door_normal": door})
		L.arff = hang_base - hax * float(hn) * hstep - hax * 40.0
		L.fuel = hang_base - door * 170.0
		if bool(st.cargo) and big:
			var cg_c: Vector2 = hang_base + hax * (hw * 0.5 + 40.0 + 90.0)
			if not between:
				cg_c = tb.center + tax * (tb.len * 0.5 + 250.0) + airside * 40.0
			if _clear_of_runways(L, cg_c, hax, 180.0, 70.0) and _clear_of_buildings(L, cg_c, hax, 180.0, 60.0):
				L.buildings.append({"kind": "cargo", "center": cg_c - door * 10.0, "axis": hax, "len": 180.0, "depth": 60.0, "h": 16.0})
		# landside: multi-storey car parks and hotels, at least 90 m beyond the landside facade
		# (the curbside, its canopy and planting occupy the first 80 m), then a surface lot
		var ls: Dictionary = L.landside
		if not ls.is_empty():
			var lo: Vector2 = ls.origin
			var ln: Vector2 = ls.normal
			var la: Vector2 = ls.axis
			var row := 95.0
			var g_d := 64.0 if big else 44.0
			var slots := [1.0, -1.0, 2.0, -2.0, 3.0, -3.0]
			var si := 0
			var placed := []
			for k in int(st.garages):
				var lvl := 6 if big else 3
				placed.append({"kind": "garage", "len": 120.0 if big else 80.0, "depth": g_d, "h": float(lvl) * 3.2 + 1.2, "levels": lvl})
			for k in int(st.hotel):
				placed.append({"kind": "hotel", "len": 70.0, "depth": 24.0, "h": 46.0 if big else 30.0, "levels": 14 if big else 9})
			for pe in placed:
				while si < slots.size():
					var lat: float = slots[si] * (float(pe.len) * 0.5 + 18.0) * (1.0 if absf(slots[si]) < 1.5 else 1.0)
					if absf(slots[si]) >= 2.0:
						lat = signf(slots[si]) * (absf(slots[si]) - 0.5) * 140.0
					si += 1
					var pc2: Vector2 = lo + ln * (row + float(pe.depth) * 0.5) + la * lat
					if _clear_of_runways(L, pc2, la, float(pe.len), float(pe.depth)) and _clear_of_buildings(L, pc2, la, float(pe.len), float(pe.depth)):
						pe.center = pc2
						pe.axis = la
						L.buildings.append(pe)
						break
			# signature landmark (or JFK-style unit terminals) beyond the car parks
			var far := row + g_d + 40.0
			var sig := String(st.sig)
			if sig in ["theme", "drum", "jewel"]:
				var sz: float = {"theme": 90.0, "drum": 190.0, "jewel": 150.0}[sig]
				var sc: Vector2 = lo + ln * (far + sz * 0.5) + la * (70.0 if sig == "theme" else 0.0)
				if _clear_of_runways(L, sc, la, sz, sz) and _clear_of_buildings(L, sc, la, sz, sz):
					L.buildings.append({"kind": sig, "center": sc, "axis": la, "len": sz, "depth": sz, "h": 30.0})
					far += sz + 30.0
			elif sig == "loop":
				for sgn in [-1.0, 1.0]:
					var ac: Vector2 = lo + ln * (far + 40.0) + la * sgn * 190.0
					if _clear_of_runways(L, ac, la, 230.0, 70.0) and _clear_of_buildings(L, ac, la, 230.0, 70.0):
						L.buildings.append({"kind": "annex", "center": ac, "axis": la, "len": 230.0, "depth": 70.0, "h": 18.0, "levels": 2})
				far += 120.0
			# surface car park behind the garages and the access road out through it
			var lot_c: Vector2 = lo + ln * (far + 60.0)
			var lot_len := minf(float(ls.len), 360.0)
			if _clear_of_runways(L, lot_c, la, lot_len, 120.0):
				L.parking.append({"center": lot_c, "axis": la, "len": lot_len, "depth": 120.0})
			L.roads.append({"a": lo + ln * 70.0, "b": lo + ln * 1000.0, "w": 14.0})
			L.roads.append({"a": lo + ln * 22.0 - la * float(ls.len) * 0.5, "b": lo + ln * 22.0 + la * float(ls.len) * 0.5, "w": 16.0})
	_navaids(L)
	return L


static func _navaids(L: Dictionary) -> void:
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


static func _miami(L: Dictionary, facade_list: Array, tw_nodes: Dictionary, tw_wid: float) -> void:
	## Miami International as it really is: the horseshoe-shaped Central Terminal wrapped around
	## the Dolphin and Flamingo garages (kerbside on the inside, facing east), the long North
	## Terminal (Concourse D) with its Skytrain, the E/F and G/H piers pointing west, and the South
	## Terminal (Concourse J). Aprons between the piers open to the west onto a perimeter taxiway.
	var g0 := Vector2(600.0, 30.0)
	var rad := 450.0
	var segs := 7
	var arc := []
	for k in segs:
		var f0 := deg_to_rad(270.0 - 180.0 * float(k) / float(segs))
		var f1 := deg_to_rad(270.0 - 180.0 * float(k + 1) / float(segs))
		var fm := (f0 + f1) * 0.5
		var c: Vector2 = g0 + Vector2(cos(fm), sin(fm)) * rad
		var ax := Vector2(-sin(fm), cos(fm))
		arc.append({"kind": "terminal", "center": c, "axis": ax, "len": 2.0 * rad * sin(absf(f1 - f0) * 0.5) + 10.0, "depth": 62.0,
			"h": 26.0, "levels": 3, "unit": k})
	# the middle (west) segment first: it carries the main check-in hall and the kerb
	L.buildings.append(arc[3])
	for k in segs:
		if k != 3:
			L.buildings.append(arc[k])
	var east := Vector2(1.0, 0.0)
	var south := Vector2(0.0, 1.0)
	var north := -south
	var piers := [
		# [centre, length, depth]: D (North Terminal), E/F, G/H, J (South Terminal)
		[Vector2(-150.0, -420.0), 1600.0, 110.0],
		[Vector2(-200.0, -102.0), 600.0, 50.0],
		[Vector2(-200.0, 186.0), 600.0, 50.0],
		[Vector2(250.0, 479.0), 800.0, 60.0],
	]
	var ui := segs
	for pr in piers:
		L.buildings.append({"kind": "concourse", "center": pr[0], "axis": east, "len": pr[1], "depth": pr[2], "h": 19.0, "levels": 2, "unit": ui})
		ui += 1
	# perimeter taxiway "M" around the pier tips, joining the parallel taxiways of 8R/26L and 9/27
	var nodes: Array = L.taxi_nodes
	var edges: Array = L.taxi_edges
	var mx := -1100.0
	var m_nodes := []
	for mz in [-620.0, -246.0, 42.0, 330.0, 680.0]:
		m_nodes.append(_add_node(nodes, Vector2(mx, mz), "taxi", "M"))
	for k in range(1, m_nodes.size()):
		_add_edge(edges, m_nodes[k - 1], m_nodes[k], "M")
		L.taxiways.append({"a": m_nodes[k - 1], "b": m_nodes[k], "w": tw_wid, "name": "M"})
	for pair in [[0, m_nodes[0]], [1, m_nodes[m_nodes.size() - 1]]]:
		if not tw_nodes.has(int(pair[0])):
			continue
		var best := -1
		var bd := INF
		for e in tw_nodes[int(pair[0])]:
			var dd: float = (nodes[e.t].pos as Vector2).distance_to(nodes[int(pair[1])].pos)
			if dd < bd:
				bd = dd
				best = e.t
		if best >= 0:
			_add_edge(edges, int(pair[1]), best, "M")
			L.taxiways.append({"a": int(pair[1]), "b": best, "w": tw_wid, "name": "M"})
	var inner: Array = m_nodes.slice(1, 4)
	facade_list.append({"origin": Vector2(-150.0, -475.0), "axis": east, "normal": north, "len": 1600.0, "gates": 19, "rw": 0, "letter": "D"})
	facade_list.append({"origin": Vector2(-400.0, -365.0), "axis": east, "normal": south, "len": 1100.0, "gates": 13, "rw": 0, "letter": "D", "start": 19, "link_nodes": inner})
	facade_list.append({"origin": Vector2(-220.0, -127.0), "axis": east, "normal": north, "len": 560.0, "gates": 7, "rw": 0, "letter": "E", "link_nodes": inner})
	facade_list.append({"origin": Vector2(-220.0, -77.0), "axis": east, "normal": south, "len": 560.0, "gates": 7, "rw": 0, "letter": "F", "link_nodes": inner})
	facade_list.append({"origin": Vector2(-220.0, 161.0), "axis": east, "normal": north, "len": 560.0, "gates": 7, "rw": 1, "letter": "G", "link_nodes": inner})
	facade_list.append({"origin": Vector2(-220.0, 211.0), "axis": east, "normal": south, "len": 560.0, "gates": 7, "rw": 1, "letter": "H", "link_nodes": inner})
	facade_list.append({"origin": Vector2(0.0, 449.0), "axis": east, "normal": north, "len": 300.0, "gates": 3, "rw": 1, "letter": "J", "link_nodes": inner})
	facade_list.append({"origin": Vector2(250.0, 509.0), "axis": east, "normal": south, "len": 800.0, "gates": 9, "rw": 1, "letter": "J", "start": 3})
	# kerbside inside the horseshoe, facing the garages; the MIA Mover heads east to the
	# Miami Intermodal Center and the rental car centre
	var mid_seg: Dictionary = arc[3]
	L.landside = {"origin": (mid_seg.center as Vector2) + east * 31.0, "normal": east, "axis": south, "len": 520.0, "h": 26.0}
	L.people_mover = [{"a": Vector2(300.0, -40.0), "b": Vector2(1700.0, -40.0)}]


static func _between_plan(L: Dictionary, mid: Vector2, axis: Vector2, nA: Vector2, total_g: int, n_sat: int, spacing: float, big: bool, need_land: bool, force: bool = false) -> Array:
	## Main terminal plus n_sat satellites in a row along the runways, centred on the midfield
	## (shifted a little to leave room for the landside in front). Empty if a runway crosses it.
	var per := total_g / (n_sat + 1)
	var main_g := total_g - per * n_sat
	var depth := 120.0 if big else 96.0
	var units := [{"gates": main_g, "len": float(maxi(main_g / 2, 3)) * spacing + 120.0, "depth": depth}]
	for k in n_sat:
		units.append({"gates": per, "len": float(maxi(per / 2, 3)) * spacing + 80.0, "depth": depth * 0.75})
	var span := 0.0
	for u in units:
		span += float(u.len)
	span += 210.0 * n_sat
	var x := -span * 0.5 + 110.0
	for u in units:
		u.center = mid + axis * (x + float(u.len) * 0.5)
		x += float(u.len) + 210.0
	if force:
		return units
	# the head house and landside sit in front of the main terminal
	var hh: Vector2 = (units[0].center as Vector2) - axis * (float(units[0].len) * 0.5 + 200.0)
	if need_land and not _clear_of_runways(L, hh, axis, 300.0, 300.0):
		return []
	for u in units:
		if not _clear_of_runways(L, u.center, axis, float(u.len), float(u.depth)):
			return []
	return units


static func _clear_of_runways(L: Dictionary, c: Vector2, ax: Vector2, length: float, depth: float) -> bool:
	## Same test as tests/layout_check: no runway centreline point within the footprint + 40 m.
	var axn := ax.normalized()
	var nn := Vector2(-axn.y, axn.x)
	for rw in L.runways:
		for k in 41:
			var p: Vector2 = (rw.center as Vector2) + (rw.dir as Vector2) * (float(k) / 40.0 - 0.5) * float(rw.len)
			var rel := p - c
			if absf(rel.dot(axn)) < length * 0.5 + 60.0 and absf(rel.dot(nn)) < depth * 0.5 + 60.0:
				return false
	return true


static func _clear_of_buildings(L: Dictionary, c: Vector2, ax: Vector2, length: float, depth: float) -> bool:
	## Footprint overlap test (separating axes of the two rectangles) against placed buildings.
	var axn := ax.normalized()
	for b in L.buildings:
		var bax: Vector2 = (b.axis as Vector2).normalized()
		var d: Vector2 = (b.center as Vector2) - c
		var sep := false
		for t in [axn, Vector2(-axn.y, axn.x), bax, Vector2(-bax.y, bax.x)]:
			var ra := _proj_half(axn, length, depth, t)
			var rb := _proj_half(bax, float(b.len), float(b.depth), t)
			if absf(d.dot(t)) > ra + rb + 8.0:
				sep = true
				break
		if not sep:
			return false
	return true


static func _proj_half(ax: Vector2, length: float, depth: float, t: Vector2) -> float:
	var n := Vector2(-ax.y, ax.x)
	return absf(ax.dot(t)) * length * 0.5 + absf(n.dot(t)) * depth * 0.5


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
static func _adjacency(L: Dictionary) -> Array:
	## [[neighbour, edge name, is runway], ...] per node, built once per layout.
	var adj: Array = L.get("_adj", [])
	if adj.size() == L.taxi_nodes.size() and L.get("_adj_edges", -1) == L.taxi_edges.size():
		return adj
	adj = []
	adj.resize(L.taxi_nodes.size())
	for i in adj.size():
		adj[i] = []
	for e in L.taxi_edges:
		var rw := String(e.name).begins_with("RWY")
		if int(e.a) < adj.size() and int(e.b) < adj.size():
			adj[e.a].append([e.b, e.name, rw])
			adj[e.b].append([e.a, e.name, rw])
	L["_adj"] = adj
	L["_adj_edges"] = L.taxi_edges.size()
	return adj


static func neighbours(L: Dictionary, node: int, allow_runway: bool) -> Array:
	var out := []
	for nb in _adjacency(L)[node]:
		if allow_runway or not nb[2]:
			out.append([nb[0], nb[1]])
	return out


## Dijkstra shortest path; returns [{node, name}] (name = edge used to reach node).
static func find_path(L: Dictionary, from_node: int, to_node: int, allow_runway: bool = false) -> Array:
	var nodes: Array = L.taxi_nodes
	if from_node < 0 or to_node < 0 or from_node >= nodes.size() or to_node >= nodes.size():
		return []
	var adj := _adjacency(L)
	var dist := {from_node: 0.0}
	var prev := {}
	var done := {}
	# binary heap of [dist, node]
	var heap: Array = [[0.0, from_node]]
	while not heap.is_empty():
		var top: Array = heap[0]
		var last: Array = heap.pop_back()
		if not heap.is_empty():
			heap[0] = last
			var i := 0
			while true:
				var l := i * 2 + 1
				var r := l + 1
				var m := i
				if l < heap.size() and float(heap[l][0]) < float(heap[m][0]):
					m = l
				if r < heap.size() and float(heap[r][0]) < float(heap[m][0]):
					m = r
				if m == i:
					break
				var tmp: Array = heap[i]
				heap[i] = heap[m]
				heap[m] = tmp
				i = m
		var cur: int = top[1]
		if done.has(cur):
			continue
		done[cur] = true
		if cur == to_node:
			break
		var pc: Vector2 = nodes[cur].pos
		for nb in adj[cur]:
			if nb[2] and not allow_runway:
				continue
			var nxt: int = nb[0]
			if done.has(nxt):
				continue
			var d: float = float(dist[cur]) + pc.distance_to(nodes[nxt].pos)
			if not dist.has(nxt) or d < float(dist[nxt]):
				dist[nxt] = d
				prev[nxt] = [cur, nb[1]]
				heap.append([d, nxt])
				var j := heap.size() - 1
				while j > 0:
					var pj := (j - 1) / 2
					if float(heap[pj][0]) <= float(heap[j][0]):
						break
					var t2: Array = heap[pj]
					heap[pj] = heap[j]
					heap[j] = t2
					j = pj
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
