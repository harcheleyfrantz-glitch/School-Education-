class_name CabinPeople
extends Node3D
## Everyone aboard one aircraft: passengers (persistent population identities) and cabin crew.
## Simulates boarding, seated behaviour, emotions, crew routines, reactions to the flight and
## evacuation. Positions are in the aircraft body frame; drawn with a single Crowd.

signal crew_report(text: String, kind: String)
signal evacuee_out(person: Dictionary, door: Dictionary)
signal boarding_done

const AISLE_GAP := 0.62
const WALK_SPEED := 1.15

var ac: Aircraft
var lay: Dictionary
var crowd: Crowd
var pax: Array = []
var crew: Array = []
var state := "empty"
var flight_phase := "gate"
var seatbelt := false
var mood := 1.0
var _board_t := 0.0
var _board_next := 0
var _board_door: Dictionary = {}
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _demo_t := -1.0
var _service_t := -1.0
var blocked_doors := {}
var exit_counts := {}
var _door_free := {}
var evac_t := 0.0
var brace := false
var lod := 0


func setup(aircraft: Aircraft, manifest: Array, crew_list: Array, crowd_lod: int = 0) -> void:
	ac = aircraft
	lay = CabinLayout.get_layout(ac.type_id)
	lod = crowd_lod
	_rng.seed = U.hash_str(ac.reg + str(WorldSim.clock))
	crowd = Crowd.new()
	crowd.name = "People"
	add_child(crowd)
	crowd.setup(manifest.size() + crew_list.size() + 2, crowd_lod, ac.airline)
	# boarding door: rear door for turboprops, first door otherwise
	var doors: Array = lay.doors
	_board_door = doors[0]
	if ac.spec.category == "turboprop":
		for d in doors:
			if d.kind == "door" and d.side < 0 and d.z > 0.0:
				_board_door = d
	var seats: Array = lay.seats.duplicate()
	var idx := 0
	for p in manifest:
		var person: Dictionary = p.duplicate()
		var seat: Dictionary = _assign_seat(person, seats)
		if seat.is_empty():
			continue
		var ap := Crowd.appearance_for(person)
		person.merge({
			"seat": seat, "app": ap, "slot": idx, "state": "away", "pos": Vector3.ZERO, "yaw": 0.0, "path": [],
			"pose": HumanMesh.POSES["stand"], "phase": _rng.randf(), "rate": 0.3, "bag": _rng.randf() < 0.75,
			"fear": 0.0, "anger": 0.0, "joy": 0.2, "discomfort": 0.0, "lav_t": _rng.randf_range(600.0, 5000.0),
			"injury": "", "outcome": "", "film": false, "stow_t": 0.0, "evac_door": {}, "anxiety": 0.7 if person.get("trait", "") == "anxious" else (0.15 if person.get("trait", "") == "calm" else 0.4),
		}, true)
		pax.append(person)
		idx += 1
	for c in crew_list:
		var fa: Dictionary = c.duplicate()
		var app := Crowd.staff_appearance(Crowd.Outfit.CABIN, int(fa.get("id", idx * 13)), String(fa.get("gender", "")))
		fa.merge({"app": app, "slot": idx, "state": "station", "pos": Vector3.ZERO, "yaw": 0.0, "path": [],
			"pose": HumanMesh.POSES["stand"], "phase": _rng.randf(), "rate": 0.3, "station": crew.size(),
			"injury": "", "outcome": "", "fear": 0.0}, true)
		crew.append(fa)
		idx += 1
	_place_crew_at_stations(true)
	state = "empty"


func _assign_seat(person: Dictionary, seats: Array) -> Dictionary:
	if seats.is_empty():
		return {}
	# business travellers and frequent flyers sit forward; families stay together
	var want_front := String(person.get("purpose", "")) == "business" or bool(person.get("frequent", false))
	var best := -1
	if want_front:
		for i in seats.size():
			if seats[i].cls != "economy":
				best = i
				break
	if best < 0:
		best = 0 if _rng.randf() < 0.5 else _rng.randi() % seats.size()
		if int(person.get("group", -1)) >= 0:
			best = 0
	var s: Dictionary = seats[best]
	seats.remove_at(best)
	return s


func seat_eye(person: Dictionary) -> Vector3:
	var s: Dictionary = person.seat
	return s.pos + Vector3(0, 1.17, -0.06 * float(-s.facing))


# ---------------------------------------------------------------- boarding
func start_boarding(instant: bool = false) -> void:
	state = "boarding"
	_board_next = 0
	_board_t = 0.0
	if instant:
		for p in pax:
			_seat_person(p)
		state = "seated"
		boarding_done.emit()
	_place_crew_at_stations(false)


func _door_inside(d: Dictionary) -> Vector3:
	return Vector3(float(d.x) - float(d.side) * 0.75, float(lay.floor_y), float(d.z))


func _seat_person(p: Dictionary) -> void:
	var s: Dictionary = p.seat
	p.state = "seated"
	p.pos = s.pos
	p.yaw = 0.0 if float(s.facing) < 0.0 else PI
	p.pose = HumanMesh.POSES["sit"]
	p.rate = 0.25
	p.path = []


func _row_aisle_x(seat: Dictionary) -> float:
	return float(seat.get("aisle_x", 0.0))


func _boarding_path(p: Dictionary) -> Array:
	var s: Dictionary = p.seat
	var d := _board_door
	var start := Vector3(float(d.x) - float(d.side) * 0.2, float(lay.floor_y), float(d.z))
	var ax := _row_aisle_x(s)
	var pts := [start, Vector3(0.0 if lay.aisles.size() == 1 else ax, start.y, float(d.z) + (0.6 if s.pos.z > d.z else -0.6))]
	pts.append(Vector3(ax, start.y, float(d.z) + (0.9 if s.pos.z > d.z else -0.9)))
	pts.append(Vector3(ax, start.y, s.pos.z + 0.15))
	return pts


func _update_boarding(delta: float) -> void:
	_board_t -= delta
	if _board_next < pax.size() and _board_t <= 0.0:
		var p: Dictionary = pax[_board_next]
		p.state = "walking"
		p.path = _boarding_path(p)
		p.pos = p.path[0]
		p.pose = HumanMesh.POSES["walk"]
		p.rate = 0.95
		_board_next += 1
		_board_t = _rng.randf_range(1.6, 3.4)
	if _board_next >= pax.size():
		var all := true
		for p2 in pax:
			if p2.state != "seated":
				all = false
				break
		if all and state == "boarding":
			state = "seated"
			boarding_done.emit()


func _walk(p: Dictionary, delta: float, others_in_aisle: Array) -> bool:
	## Moves along p.path; returns true when the path is finished.
	if p.path.is_empty():
		return true
	var target: Vector3 = p.path[0]
	var to = target - p.pos
	to.y = 0.0
	var dist = to.length()
	var speed := WALK_SPEED * (1.5 if p.state == "evac" else 1.0)
	# keep a gap to the person ahead in the same aisle
	var dir = to.normalized() if dist > 0.001 else Vector3.ZERO
	for o in others_in_aisle:
		if o == p:
			continue
		var rel: Vector3 = o.pos - p.pos
		rel.y = 0.0
		if rel.length() < AISLE_GAP and rel.dot(dir) > 0.15:
			p.pose = HumanMesh.POSES["stand"]
			return false
	if dist < speed * delta + 0.02:
		p.pos = target
		p.path.remove_at(0)
		return p.path.is_empty()
	p.pos += dir * speed * delta
	p.yaw = atan2(-dir.x, -dir.z)
	p.pose = HumanMesh.POSES["run" if p.state == "evac" else "walk"]
	return false


# ---------------------------------------------------------------- crew
func _place_crew_at_stations(initial: bool) -> void:
	var doors := []
	for d in lay.doors:
		if d.kind == "door":
			doors.append(d)
	for i in crew.size():
		var fa: Dictionary = crew[i]
		var d: Dictionary = doors[i % maxi(doors.size(), 1)] if not doors.is_empty() else {}
		if d.is_empty():
			continue
		var inside := _door_inside(d)
		var off := Vector3(0, 0, 0.55 if i % 2 == 0 else -0.55)
		fa.station_pos = inside + off * (1.0 if float(d.z) < 0.0 else -1.0)
		fa.door = d
		if initial or fa.state == "station":
			fa.pos = fa.station_pos
			fa.yaw = PI * 0.5 * float(d.side)
			fa.pose = HumanMesh.POSES["stand"]


func start_safety_demo() -> void:
	_demo_t = 0.0
	for i in crew.size():
		var fa: Dictionary = crew[i]
		var row: Dictionary = lay.rows[clampi(int(float(i + 1) / (crew.size() + 1) * lay.rows.size()), 0, maxi(lay.rows.size() - 1, 0))] if not lay.rows.is_empty() else {}
		if row.is_empty():
			continue
		var ax: float = (row.aisles[0] if not row.aisles.is_empty() else 0.0)
		if lay.aisles.size() > 1:
			ax = row.aisles[i % row.aisles.size()]
		fa.state = "demo_walk"
		fa.path = [Vector3(ax, float(lay.floor_y), fa.pos.z), Vector3(ax, float(lay.floor_y), float(row.z0) + 0.2)]


func start_service() -> void:
	_service_t = 0.0
	for i in crew.size():
		var fa: Dictionary = crew[i]
		if i % 2 == 1 or lay.rows.is_empty():
			continue
		var ax: float = lay.aisles[(i / 2) % lay.aisles.size()]
		var r0: Dictionary = lay.rows[0]
		var r1: Dictionary = lay.rows[lay.rows.size() - 1]
		fa.state = "service"
		fa.path = [Vector3(ax, float(lay.floor_y), float(r0.z0)), Vector3(ax, float(lay.floor_y), float(r1.z1))]


func crew_to_stations() -> void:
	for fa in crew:
		if fa.state in ["incapacitated", "evac", "exited"]:
			continue
		fa.state = "to_station"
		fa.path = [Vector3(0.0 if lay.aisles.size() == 1 else float(lay.aisles[0]), float(lay.floor_y), fa.pos.z), fa.station_pos]


func _update_crew(delta: float) -> void:
	var demo_stage := int(_demo_t / 18.0) if _demo_t >= 0.0 else -1
	if _demo_t >= 0.0:
		_demo_t += delta
		if _demo_t > 75.0:
			_demo_t = -1.0
			crew_to_stations()
	for fa in crew:
		match String(fa.state):
			"station":
				fa.pose = HumanMesh.POSES["sit" if flight_phase in ["taxi", "takeoff", "landing"] else "stand"]
				if flight_phase == "boarding" and fa == crew[0]:
					fa.pose = HumanMesh.POSES["wave"] if fmod(_t, 9.0) < 1.2 else HumanMesh.POSES["talk"]
			"demo_walk":
				if _walk(fa, delta, []):
					fa.state = "demo"
					fa.yaw = PI
			"demo":
				fa.pose = HumanMesh.POSES["demo"]
				fa.phase = (clampi(demo_stage, 0, 3) + 0.5) / 4.0
				fa.rate = 0.2
			"service":
				fa.rate = 0.15
				if _walk(fa, delta * 0.12, []):
					fa.state = "to_station"
					fa.path = [fa.station_pos]
				else:
					fa.pose = HumanMesh.POSES["push"]
			"to_station":
				if _walk(fa, delta, []):
					fa.state = "station"
			"evac":
				fa.pose = HumanMesh.POSES["talk"]
				fa.rate = 1.6


# ---------------------------------------------------------------- flight reactions
func on_turbulence(level: float, delta: float) -> void:
	for p in pax:
		if p.state != "seated":
			continue
		var k: float = level * delta * (0.02 + float(p.anxiety) * 0.06)
		p.fear = clampf(float(p.fear) + k - delta * 0.004, 0.0, 1.0)
		p.discomfort = clampf(float(p.discomfort) + level * delta * 0.02, 0.0, 1.0)


func on_shock(amount: float, cause: String) -> void:
	## Sudden scare: hard landing, go-around, bird strike bang, rapid decompression...
	for p in pax:
		p.fear = clampf(float(p.fear) + amount * (0.4 + float(p.anxiety)), 0.0, 1.0)
	mood = clampf(mood - amount * 0.3, 0.0, 1.0)
	if amount > 0.5:
		crew_report.emit("Cabin is shaken after the %s. Crew are reassuring passengers." % cause, "info")


func set_brace(on: bool) -> void:
	brace = on


func deploy_masks() -> void:
	for p in pax:
		if p.state == "seated":
			p.mask = true
			p.fear = clampf(float(p.fear) + 0.5, 0.0, 1.0)


func _update_seated(p: Dictionary, delta: float) -> void:
	var fear: float = p.fear
	p.fear = maxf(fear - delta * 0.003, 0.0)
	if brace:
		p.pose = HumanMesh.POSES["brace"]
		return
	if p.get("mask", false):
		p.pose = HumanMesh.POSES["sit_mask"]
		return
	if fear > 0.75:
		p.pose = HumanMesh.POSES["sit_panic"]
		return
	if p.film:
		p.pose = HumanMesh.POSES["sit_film"]
		return
	# long-lived idle choice so people don't twitch between poses
	if fmod(_t + float(p.phase) * 97.0, 45.0) < delta:
		var r := _rng.randf()
		var night := ac.world != null and ac.world.night > 0.6
		var kind := "sit"
		if r < (0.45 if night else 0.12) and flight_phase == "cruise":
			kind = "sit_sleep"
		elif r < 0.3:
			kind = "sit_read"
		elif r < 0.45 and int(p.get("group", -1)) >= 0:
			kind = "sit_talk"
		p.idle_pose = HumanMesh.POSES[kind]
	p.pose = int(p.get("idle_pose", HumanMesh.POSES["sit"]))
	# a lavatory visit now and then when allowed
	if flight_phase == "cruise" and not seatbelt and not lay.lavs.is_empty():
		p.lav_t = float(p.lav_t) - delta
		if p.lav_t <= 0.0:
			var lav: Dictionary = lay.lavs[_rng.randi() % lay.lavs.size()]
			var ax := _row_aisle_x(p.seat)
			p.state = "to_lav"
			p.path = [Vector3(ax, float(lay.floor_y), p.seat.pos.z), Vector3(ax, float(lay.floor_y), (float(lav.z0) + float(lav.z1)) * 0.5 - 0.6 * signf(float(lav.z0) - p.seat.pos.z))]
			p.lav_t = _rng.randf_range(1800.0, 7000.0)


# ---------------------------------------------------------------- evacuation
func start_evacuation(blocked: Dictionary = {}) -> void:
	state = "evacuating"
	blocked_doors = blocked
	evac_t = 0.0
	exit_counts.clear()
	_door_free.clear()
	for p in pax:
		if p.state in ["deceased", "exited"]:
			continue
		if p.injury == "trapped":
			continue
		var exits := CabinLayout.exits_by_distance(lay, float(p.seat.pos.z), blocked)
		if exits.is_empty():
			p.state = "trapped"
			continue
		# people often head for the door they came in through, not the nearest
		var pick: Dictionary = exits[0]
		if exits.size() > 1 and _rng.randf() < 0.25:
			pick = _board_door if not blocked.has(_board_door.name) else exits[1]
		p.evac_door = pick
		p.state = "evac"
		p.evac_delay = _rng.randf_range(0.5, 6.0) + float(p.age) * 0.03 + (4.0 if p.injury != "" else 0.0)
		var ax := _row_aisle_x(p.seat)
		var inside := _door_inside(pick)
		p.path = [Vector3(ax, float(lay.floor_y), p.seat.pos.z), Vector3(ax, float(lay.floor_y), float(pick.z)), inside]
	for fa in crew:
		if fa.state != "incapacitated":
			fa.state = "evac"


func _update_evac(p: Dictionary, delta: float, aisle_people: Array) -> void:
	if p.get("evac_delay", 0.0) > 0.0:
		p.evac_delay = float(p.evac_delay) - delta
		p.pose = HumanMesh.POSES["sit_panic"]
		return
	if _walk(p, delta, aisle_people):
		var dn := String(p.evac_door.name)
		var free_at: float = _door_free.get(dn, 0.0)
		if evac_t < free_at:
			p.pose = HumanMesh.POSES["stand"]
			return
		_door_free[dn] = evac_t + (1.1 if p.evac_door.kind == "door" else 2.2)
		exit_counts[dn] = int(exit_counts.get(dn, 0)) + 1
		p.state = "exited"
		p.exit_time = evac_t
		evacuee_out.emit(p, p.evac_door)


# ---------------------------------------------------------------- update
func _process(delta: float) -> void:
	if ac == null:
		return
	_t += delta
	if state == "boarding":
		_update_boarding(delta)
	if state == "evacuating":
		evac_t += delta
	var aisle_people := []
	for p in pax:
		if p.state in ["walking", "evac", "to_lav", "from_lav", "stowing"]:
			aisle_people.append(p)
	for p2 in pax:
		match String(p2.state):
			"walking":
				if _walk(p2, delta, aisle_people):
					p2.state = "stowing"
					p2.stow_t = _rng.randf_range(2.5, 8.0) if p2.bag else 0.8
			"stowing":
				p2.pose = HumanMesh.POSES["stow"] if p2.bag else HumanMesh.POSES["stand"]
				p2.stow_t = float(p2.stow_t) - delta
				if p2.stow_t <= 0.0:
					_seat_person(p2)
			"seated":
				_update_seated(p2, delta)
			"to_lav":
				if _walk(p2, delta, aisle_people):
					p2.state = "in_lav"
					p2.lav_left = _rng.randf_range(60.0, 240.0)
			"in_lav":
				p2.lav_left = float(p2.lav_left) - delta
				if p2.lav_left <= 0.0 or seatbelt:
					p2.state = "from_lav"
					p2.path = [Vector3(_row_aisle_x(p2.seat), float(lay.floor_y), p2.seat.pos.z + 0.15)]
			"from_lav":
				if _walk(p2, delta, aisle_people):
					_seat_person(p2)
			"evac":
				_update_evac(p2, delta, aisle_people)
	_update_crew(delta)
	# mood follows fear and comfort
	if not pax.is_empty():
		var f := 0.0
		for p3 in pax:
			f += float(p3.fear) + float(p3.discomfort) * 0.5
		mood = lerpf(mood, clampf(1.0 - f / pax.size(), 0.0, 1.0), clampf(delta * 0.2, 0.0, 1.0))
	_draw_all()


func _draw_all() -> void:
	for p in pax:
		_draw_person(p)
	for fa in crew:
		_draw_person(fa)
	crowd.flush()


func _draw_person(p: Dictionary) -> void:
	var slot: int = p.slot
	if p.state in ["away", "exited", "in_lav"]:
		crowd.hide_person(slot)
		return
	var ap: Dictionary = p.app
	var flags: int = ap.flags
	if p.state in ["walking", "stowing"] and p.get("bag", false):
		flags |= Crowd.FLAG_BAG
	if p.get("film", false):
		flags |= Crowd.FLAG_PHONE
	var xf := Transform3D(Basis(Vector3.UP, float(p.yaw)).scaled(Vector3.ONE * float(ap.scale)), p.pos)
	crowd.set_person(slot, xf, int(p.pose), float(p.phase), float(p.rate), ap.top, int(ap.outfit), float(ap.seed), flags, float(ap.build))


# ---------------------------------------------------------------- queries
func count_state(st: String) -> int:
	var n := 0
	for p in pax:
		if p.state == st:
			n += 1
	return n


func person_at_seat(seat_id: String) -> Dictionary:
	for p in pax:
		if String(p.seat.id) == seat_id:
			return p
	return {}


func average_fear() -> float:
	if pax.is_empty():
		return 0.0
	var f := 0.0
	for p in pax:
		f += float(p.fear)
	return f / pax.size()
