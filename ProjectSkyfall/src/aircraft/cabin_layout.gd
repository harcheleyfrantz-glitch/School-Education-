class_name CabinLayout
extends RefCounted
## Interior arrangement derived from the type data: floor and ceiling heights, cockpit, door zones,
## galleys, lavatories, the seat map and walkable lanes. Body coordinates: +X right, +Y up,
## -Z forward, origin at the centre of gravity (same frame as Aircraft / AircraftModel).

static var _cache := {}

const HEADROOM := {"trainer": 1.15, "turboprop": 1.92, "regional": 2.0, "narrowbody": 2.15, "widebody": 2.45, "bizjet": 1.88, "cargo": 2.1}
const FLOOR_K := {"trainer": -0.55, "turboprop": -0.32, "regional": -0.34, "narrowbody": -0.33, "widebody": -0.30, "bizjet": -0.40, "cargo": 0.30}


static func get_layout(type_id: String) -> Dictionary:
	if not _cache.has(type_id):
		_cache[type_id] = _compute(type_id)
	return _cache[type_id]


static func half_width(spec: Dictionary, z: float, y: float) -> float:
	## Half width of the outer skin at body z and height y (0 outside the section).
	var L: float = spec.length
	var nose_z := -L * float(spec.cg_frac)
	var t := clampf((z - nose_z) / L, 0.0, 1.0)
	var sp := AircraftModel.section(spec, t)
	var rw: float = float(spec.fuse_w) * 0.5
	var rh: float = float(spec.fuse_h) * 0.5
	var sy := sp.y if y >= sp.w else sp.z
	var k := (y - sp.w) / maxf(rh * sy, 0.01)
	if absf(k) >= 1.0:
		return 0.0
	return rw * sp.x * sqrt(1.0 - k * k)


static func _letters(n: int) -> Array:
	var out := []
	var code := 65
	while out.size() < n:
		var ch := String.chr(code)
		code += 1
		if ch == "I" or ch == "O":
			continue
		out.append(ch)
	return out


static func _compute(type_id: String) -> Dictionary:
	var spec := AircraftTypes.get_type(type_id)
	var cat: String = spec.category
	var L: float = spec.length
	var rh: float = float(spec.fuse_h) * 0.5
	var nose_z := -L * float(spec.cg_frac)
	var floor_y: float = rh * float(FLOOR_K.get(cat, -0.33))
	var ceil_y: float = minf(floor_y + float(HEADROOM.get(cat, 2.1)), rh * (1.32 if spec.hump else 0.9))
	if cat == "cargo":
		# upper deck in the hump behind the flight deck
		floor_y = rh * 0.30
		ceil_y = floor_y + 2.05
	var eye := AircraftModel.pilot_eye_station(spec)
	var lay := {
		"type": type_id, "category": cat, "length": L, "nose_z": nose_z, "floor_y": floor_y, "ceil_y": ceil_y,
		"seats": [], "doors": [], "galleys": [], "lavs": [], "jumpseats": [], "aisles": [], "walk": [],
		"dividers": [], "exits": [], "windows": [], "cockpit": {}, "rows": [],
	}
	# ---- flight deck
	var ck_back := nose_z + eye + (1.6 if cat == "widebody" else (1.3 if cat != "trainer" else 0.9))
	var ck := {
		"eye_z": nose_z + eye, "back_z": ck_back, "front_z": nose_z + eye - 1.25,
		"floor_y": floor_y, "eye_y": floor_y + 1.12, "seat_x": 0.52 if cat != "trainer" else 0.3,
		"style": spec.cockpit, "pilots": spec.pilots,
	}
	if cat == "trainer":
		ck.eye_y = floor_y + 0.98
	lay.cockpit = ck
	if cat == "trainer":
		_trainer(lay, spec)
		return lay
	# ---- doors (both sides at every station)
	var door_list: Array = spec.doors
	var di := 0
	for d in door_list:
		di += 1
		var dz := nose_z + float(d) * L
		for side in [-1, 1]:
			var wx := half_width(spec, dz, floor_y + 1.0)
			lay.doors.append({"name": ("L" if side < 0 else "R") + str(di), "z": dz, "side": side, "x": side * wx,
				"width": 0.95 if cat != "bizjet" else 0.85, "height": 1.85, "kind": "door",
				"inside": Vector3(side * maxf(wx - 0.55, 0.2), floor_y, dz), "slide": cat != "bizjet" and cat != "turboprop"})
	var ow: Array = spec.get("overwing", [])
	var oi := 0
	for d2 in ow:
		oi += 1
		var oz := nose_z + float(d2) * L
		for side2 in [-1, 1]:
			var wx2 := half_width(spec, oz, floor_y + 0.9)
			lay.doors.append({"name": "OW%d%s" % [oi, "L" if side2 < 0 else "R"], "z": oz, "side": side2, "x": side2 * wx2,
				"width": 0.5, "height": 0.95, "kind": "overwing", "inside": Vector3(side2 * maxf(wx2 - 0.6, 0.2), floor_y, oz), "slide": false})
	# ---- zones along the cabin
	var first_door_z := nose_z + float(door_list[0]) * L
	var last_door_z := nose_z + float(door_list[door_list.size() - 1]) * L
	var cab_front := ck_back
	var seat_start := first_door_z + 0.62
	var aft_end := last_door_z + 1.6
	if door_list.size() == 1:
		aft_end = nose_z + L * (1.0 - AircraftModel._tail_frac(spec)) + 1.0
	if cat == "turboprop":
		# forward door serves the cargo hold; passengers board at the rear door
		seat_start = first_door_z + 1.0
		aft_end = last_door_z + 1.25
	if cat == "cargo":
		seat_start = ck_back + 0.4
		aft_end = ck_back + 6.0
	lay.cabin_front = cab_front
	lay.cabin_back = aft_end
	# forward galley / lavatory between the flight deck and the first door
	var fz0 := ck_back
	var fz1 := first_door_z - 0.55
	if cat in ["narrowbody", "widebody"] and fz1 - fz0 > 0.5:
		lay.galleys.append({"z0": fz0 + 0.05, "z1": fz1, "side": 1, "depth": 0.85 if cat == "narrowbody" else 1.1})
		lay.lavs.append({"z0": fz0 + 0.05, "z1": fz1, "side": -1, "depth": 0.95, "name": "LAV A"})
	elif cat in ["regional", "bizjet"]:
		# small galley opposite the entry door
		lay.galleys.append({"z0": first_door_z - 0.5, "z1": first_door_z + 0.55, "side": 1, "depth": 0.6})
	# aft galley and lavatories behind the last door
	if door_list.size() > 1:
		aft_end = last_door_z + (2.4 if cat != "turboprop" else 1.5)
		var az0 := last_door_z + 0.6
		if cat == "turboprop":
			lay.lavs.append({"z0": az0, "z1": aft_end - 0.05, "side": 1, "depth": 0.95, "name": "LAV"})
			lay.galleys.append({"z0": az0, "z1": aft_end - 0.05, "side": -1, "depth": 0.6})
		else:
			lay.lavs.append({"z0": az0, "z1": az0 + 0.95, "side": -1, "depth": 0.95, "name": "LAV D"})
			lay.lavs.append({"z0": az0, "z1": az0 + 0.95, "side": 1, "depth": 0.95, "name": "LAV E"})
			lay.galleys.append({"z0": az0 + 1.0, "z1": aft_end - 0.05, "side": 0, "depth": 0.75})
	lay.cabin_back = aft_end
	# ---- seat blocks
	var mid_zones := []   # [z0, z1] blocked by mid-cabin doors
	for k in range(1, door_list.size() - 1):
		var mz := nose_z + float(door_list[k]) * L
		mid_zones.append([mz - 0.6, mz + 2.0])
		lay.galleys.append({"z0": mz + 0.62, "z1": mz + 1.9, "side": 0, "depth": 2.2})
		lay.lavs.append({"z0": mz + 0.62, "z1": mz + 1.6, "side": -1, "depth": 0.95, "name": "LAV %d" % k})
		lay.lavs.append({"z0": mz + 0.62, "z1": mz + 1.6, "side": 1, "depth": 0.95, "name": "LAV %dR" % k})
	var aft_limit := last_door_z - 0.6
	if door_list.size() == 1:
		aft_limit = aft_end - 0.3
		if cat == "bizjet":
			aft_limit = 1e6
	var ow_z := []
	for d3 in ow:
		ow_z.append(nose_z + float(d3) * L)
	var z := seat_start
	var row_no := 1
	var arm_y := floor_y + 0.62
	var seat_rows := []
	for sec in spec.cabin:
		var groups := []
		for g in String(sec.layout).split("-"):
			groups.append(int(g))
		var per_row := 0
		for g in groups:
			per_row += g
		var sw: float = sec.seat_w
		var pitch: float = sec.pitch
		var cls: String = sec.cls
		var letters := _letters(per_row)
		var placed := 0
		if seat_rows.size() > 0:
			z += 0.18   # class divider
			lay.dividers.append({"z": z - 0.09, "cls": cls})
		var guard := 0
		while placed < int(sec.rows) and guard < 200:
			guard += 1
			# hop over mid-cabin door zones
			var blocked := false
			for mzr in mid_zones:
				if z + pitch > mzr[0] and z < mzr[1]:
					z = mzr[1] + 0.05
					blocked = true
			if blocked:
				continue
			var exit_row := false
			for oz in ow_z:
				if absf(z + pitch * 0.5 - oz) < pitch * 0.6:
					exit_row = true
			var row_pitch := pitch + (0.22 if exit_row else 0.0)
			if z + row_pitch > aft_limit:
				break
			if row_no == 13:
				row_no += 1
			var seat_z := z + row_pitch * 0.62    # hip point ~ 2/3 back in the pitch
			var wx := half_width(spec, seat_z, arm_y) - 0.06
			var total := float(per_row) * sw
			var n_aisles := groups.size() - 1
			var aisle_w := 0.52 if cls == "economy" else 0.62
			if cls == "vip" or cls == "crew_rest" or cls == "ga":
				aisle_w = 0.7
			var avail := wx * 2.0
			if total + n_aisles * aisle_w > avail:
				aisle_w = maxf((avail - total) / maxi(n_aisles, 1), 0.36)
				if total + n_aisles * aisle_w > avail:
					sw = (avail - n_aisles * aisle_w) / per_row
			var width := float(per_row) * sw + n_aisles * aisle_w
			var x := -width * 0.5
			var li := 0
			var aisle_xs := []
			for gi in groups.size():
				for si in int(groups[gi]):
					var sx := x + sw * 0.5
					var is_window := (gi == 0 and si == 0) or (gi == groups.size() - 1 and si == int(groups[gi]) - 1)
					var is_aisle := (gi > 0 and si == 0) or (gi < groups.size() - 1 and si == int(groups[gi]) - 1)
					var facing := -1.0
					if cls == "vip" and placed % 2 == 1:
						facing = 1.0    # club seating: every second row faces aft
					lay.seats.append({
						"id": "%d%s" % [row_no, letters[li]], "row": row_no, "letter": letters[li], "cls": cls,
						"pos": Vector3(sx, floor_y, seat_z if facing < 0.0 else z + row_pitch * 0.38), "width": sw,
						"window": is_window, "aisle": is_aisle, "exit_row": exit_row, "group": gi, "facing": facing,
						"side": -1 if sx < 0.0 else 1,
					})
					li += 1
					x += sw
				if gi < groups.size() - 1:
					aisle_xs.append(x + aisle_w * 0.5)
					x += aisle_w
			seat_rows.append({"row": row_no, "z0": z, "z1": z + row_pitch, "cls": cls, "exit": exit_row, "pitch": row_pitch,
				"seat_w": sw, "aisles": aisle_xs, "groups": groups})
			if lay.aisles.is_empty() and not aisle_xs.is_empty():
				lay.aisles = aisle_xs.duplicate()
			z += row_pitch
			row_no += 1
			placed += 1
	lay.rows = seat_rows
	if lay.aisles.is_empty():
		lay.aisles = [0.0]
	if cat == "bizjet":
		aft_end = z + 2.7
		lay.lavs.append({"z0": z + 0.9, "z1": aft_end - 0.05, "side": -1, "depth": 1.1, "name": "LAV"})
		lay.galleys.append({"z0": z + 0.9, "z1": aft_end - 0.05, "side": 1, "depth": 0.7})
		lay.cabin_back = aft_end
	# nearest aisle for each seat and exits ordered by distance
	for st in lay.seats:
		var best := 0.0
		var bd := INF
		for ax in lay.aisles:
			var dd := absf(float(ax) - st.pos.x)
			if dd < bd:
				bd = dd
				best = ax
		st.aisle_x = best
	# ---- crew jumpseats beside each door pair (facing aft)
	for dr in lay.doors:
		if dr.kind == "door" and dr.side < 0:
			lay.jumpseats.append({"pos": Vector3(0.0, floor_y, dr.z + 0.35), "door": dr.name})
	# ---- windows along both sides (skip door positions)
	if cat != "cargo":
		var wp := 0.53 if cat != "bizjet" else 1.1
		var wz := seat_start + 0.2
		while wz < aft_limit:
			var near_door := false
			for dr2 in lay.doors:
				if absf(dr2.z - wz) < (0.76 if dr2.kind == "door" else 0.55):
					near_door = true
			if not near_door:
				lay.windows.append(wz)
			wz += wp
	# ---- walkable lanes (axis aligned rectangles x0, x1, z0, z1)
	var aisle_hw := 0.24
	var prev_aisles := []
	for r in seat_rows:
		var axs: Array = r.aisles if not r.aisles.is_empty() else [0.0]
		for ax2 in axs:
			lay.walk.append(Rect2(float(ax2) - aisle_hw, r.z0 - 0.02, aisle_hw * 2.0, r.z1 - r.z0 + 0.04))
		if not prev_aisles.is_empty() and prev_aisles != axs:
			# class change with a shifted aisle: a short cross lane joins them
			var xa := minf(float(prev_aisles[0]), float(axs[0])) - aisle_hw
			var xb := maxf(float(prev_aisles[prev_aisles.size() - 1]), float(axs[axs.size() - 1])) + aisle_hw
			lay.walk.append(Rect2(xa, r.z0 - 0.3, xb - xa, 0.6))
		prev_aisles = axs
	# from the first row forward to the door area, and from the last row aft
	if not seat_rows.is_empty():
		var fa: Array = seat_rows[0].aisles if not seat_rows[0].aisles.is_empty() else [0.0]
		var la: Array = seat_rows[seat_rows.size() - 1].aisles if not seat_rows[seat_rows.size() - 1].aisles.is_empty() else [0.0]
		var fx0 := float(fa[0]) - aisle_hw
		var fx1 := float(fa[fa.size() - 1]) + aisle_hw
		lay.walk.append(Rect2(minf(fx0, -aisle_hw), cab_front, maxf(fx1, aisle_hw) - minf(fx0, -aisle_hw), seat_rows[0].z0 - cab_front + 0.05))
		var lx0 := float(la[0]) - aisle_hw
		var lx1 := float(la[la.size() - 1]) + aisle_hw
		var lz: float = seat_rows[seat_rows.size() - 1].z1
		lay.walk.append(Rect2(minf(lx0, -aisle_hw), lz - 0.05, maxf(lx1, aisle_hw) - minf(lx0, -aisle_hw), maxf(aft_end - lz - 0.3, 0.3)))
		# across rows between mid-cabin door zones
		for zr2 in mid_zones:
			for ax3 in fa:
				lay.walk.append(Rect2(float(ax3) - aisle_hw, zr2[0] - 0.1, aisle_hw * 2.0, zr2[1] - zr2[0] + 0.2))
	for dr3 in lay.doors:
		if dr3.kind == "door" and dr3.side < 0:
			var hw := half_width(spec, dr3.z, floor_y + 0.3) - 0.25
			lay.walk.append(Rect2(-hw, dr3.z - 0.5, hw * 2.0, 1.0))
	# vestibule behind the flight deck and in front of the aft galley
	var vw := half_width(spec, ck_back + 0.3, floor_y + 0.5) - 0.3
	lay.walk.append(Rect2(-0.45, ck.front_z + 0.6, 0.9, ck_back - ck.front_z - 0.4))
	lay.walk.append(Rect2(-minf(vw, 0.6), ck_back - 0.2, minf(vw, 0.6) * 2.0, maxf(first_door_z - ck_back, 0.6)))
	for zr in mid_zones:
		var hw2 := half_width(spec, (zr[0] + zr[1]) * 0.5, floor_y + 0.3) - 0.3
		lay.walk.append(Rect2(-hw2, zr[0], hw2 * 2.0, zr[1] - zr[0]))
	return lay


static func _trainer(lay: Dictionary, spec: Dictionary) -> void:
	var nose_z: float = lay.nose_z
	var fy: float = lay.floor_y
	var front_z := nose_z + 2.45
	var rear_z := front_z + 0.95
	var i := 0
	for zz in [front_z, rear_z]:
		for sx in [-0.3, 0.3]:
			var row := 1 if zz == front_z else 2
			lay.seats.append({"id": "%d%s" % [row, "A" if sx < 0 else "B"], "row": row, "letter": "A" if sx < 0 else "B", "cls": "ga",
				"pos": Vector3(sx, fy, zz), "width": 0.5, "window": true, "aisle": false, "exit_row": false, "group": 0,
				"facing": -1.0, "side": -1 if sx < 0 else 1, "aisle_x": sx})
			i += 1
	var dz := nose_z + float(spec.doors[0]) * float(spec.length)
	for side in [-1, 1]:
		lay.doors.append({"name": ("L" if side < 0 else "R") + "1", "z": dz, "side": side, "x": side * 0.56, "width": 0.9, "height": 1.0,
			"kind": "door", "inside": Vector3(side * 0.3, fy, dz), "slide": false})
	lay.cabin_front = nose_z + 1.6
	lay.cabin_back = rear_z + 0.7
	lay.aisles = [0.0]


## Seat by id ("12C") or empty dictionary.
static func seat(lay: Dictionary, id: String) -> Dictionary:
	for s in lay.seats:
		if s.id == id:
			return s
	return {}


## Is a body-frame floor point inside a walkable lane?
static func walkable(lay: Dictionary, x: float, z: float) -> bool:
	for r in lay.walk:
		if r.has_point(Vector2(x, z)):
			return true
	return false


## Clamp a desired body-frame position to the walkable area (slides along lane edges).
static func constrain(lay: Dictionary, from: Vector2, to: Vector2) -> Vector2:
	if walkable(lay, to.x, to.y):
		return to
	if walkable(lay, to.x, from.y):
		return Vector2(to.x, from.y)
	if walkable(lay, from.x, to.y):
		return Vector2(from.x, to.y)
	return from


## Exits sorted by distance from a body z (only usable ones).
static func exits_by_distance(lay: Dictionary, z: float, blocked: Dictionary = {}) -> Array:
	var out := []
	for d in lay.doors:
		if blocked.has(d.name):
			continue
		out.append(d)
	out.sort_custom(func(a, b): return absf(a.z - z) < absf(b.z - z))
	return out
