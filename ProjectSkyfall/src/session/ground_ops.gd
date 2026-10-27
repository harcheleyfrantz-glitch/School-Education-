class_name GroundOps
extends Node3D
## Everything that happens around the aircraft on the ground: the turnaround (refueller under the
## wing, catering at the galley door, belt loaders and baggage trains at the holds, GPU, stairs),
## the pushback (tug drives in, cradles the nose wheel, pushes, disconnects; headset operator and
## wing walkers), the arrival (marshaller, chocks, vehicles drive in), evacuees running from the
## slides and the emergency response (crash tenders spraying, ambulances, firefighters, medics).
## Lives under WorldView.dynamic_root so it follows the floating origin.

signal tug_connected
signal tug_clear

const STAFF_CAP := 28

var session: Node
var ac: Aircraft
var view: WorldView
var vehicles: Array = []         # {node, kind, path, speed, max_speed, reverse, done, role, wait}
var staff: Array = []            # {slot, pos, yaw, pose, phase, rate, app, path, speed, role}
var evacuees: Array = []         # {slot, pos, yaw, path, speed, pose, app, state}
var crowd: Crowd
var evac_crowd: Crowd = null
var tug: Dictionary = {}
var tug_state := "none"          # none | waiting | approaching | connected | leaving
var mode := "idle"
var icao := ""
var _t := 0.0
var _evac_next := 0
var _assembly := Vector3.ZERO
var arff: Array = []
var emergency_target := Vector3.ZERO
var emergency_active := false
var spray_power := 0.0           # total water/foam reaching the target (0..n trucks)
var _rng := RandomNumberGenerator.new()


func setup(sess: Node, aircraft: Aircraft, world_view: WorldView) -> void:
	session = sess
	ac = aircraft
	view = world_view
	_rng.seed = U.hash_str(aircraft.reg + "ground")
	view.origin_shifted.connect(_on_origin_shift)
	crowd = Crowd.new()
	crowd.name = "GroundStaff"
	add_child(crowd)
	crowd.setup(STAFF_CAP, 1, "", true)


func _on_origin_shift(shift: Vector3) -> void:
	## Everything here is stored in world-local coordinates: move it all with the origin and
	## undo the parent's blanket shift of this node.
	position = Vector3.ZERO
	for v in vehicles:
		if is_instance_valid(v.node):
			v.node.position -= shift
		for wp in v.path:
			wp.p -= shift
	for s in staff:
		s.pos -= shift
		var np := []
		for q in s.path:
			np.append(q - shift)
		s.path = np
	for e in evacuees:
		e.pos -= shift
		var np2 := []
		for q2 in e.path:
			np2.append(q2 - shift)
		e.path = np2
	emergency_target -= shift
	_assembly -= shift


# ================================================================== frames
func _body(p: Vector3) -> Vector3:
	## Aircraft body-frame point -> world-local.
	return ac.global_transform * p


func _ground(p: Vector3) -> Vector3:
	var q := p
	q.y = Geo.ground_height(view.wx(p), view.wz(p)) + 0.02
	return q


func _ac_right() -> Vector3:
	var r: Vector3 = ac.global_transform.basis.x
	r.y = 0.0
	return r.normalized()


func _ac_fwd() -> Vector3:
	var f: Vector3 = -ac.global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func _yaw_for(dir: Vector3) -> float:
	## Node yaw that points the vehicle front (-Z) along dir.
	return atan2(-dir.x, -dir.z)


# ================================================================== vehicles
func _spawn(kind: String, pos: Vector3, facing: Vector3, livery: Dictionary = {}, role: String = "") -> Dictionary:
	var node := VehicleBuilder.build(kind, livery)
	add_child(node)
	node.position = _ground(pos)
	node.rotation.y = _yaw_for(facing)
	var v := {"node": node, "kind": kind, "path": [], "speed": 0.0, "max_speed": 7.0 if kind != "arff" else 16.0,
		"reverse": false, "done": Callable(), "role": role, "wait": 0.0, "lift": 0.0, "lift_target": 0.0,
		"boom": 0.0, "boom_target": 0.0, "free_at_end": false}
	VehicleBuilder.set_lamps(node, kind in ["arff", "ambulance", "follow_me"], view.night > 0.4)
	vehicles.append(v)
	return v


func _drive(v: Dictionary, pts: Array, reverse_first: float = 0.0, on_done: Callable = Callable(), free_at_end: bool = false) -> void:
	## Queue a route. reverse_first backs straight out by that many metres before driving.
	var node: Node3D = v.node
	var path := []
	if reverse_first > 0.0:
		var back := node.global_transform.basis.z
		back.y = 0.0
		path.append({"p": node.position + back.normalized() * reverse_first, "rev": true})
	for p in pts:
		path.append({"p": p, "rev": false})
	v.path = path
	v.done = on_done
	v.free_at_end = free_at_end


func _update_vehicle(v: Dictionary, dt: float) -> void:
	var node: Node3D = v.node
	if not is_instance_valid(node):
		return
	# animated equipment
	if absf(float(v.lift) - float(v.lift_target)) > 0.001:
		v.lift = move_toward(float(v.lift), float(v.lift_target), dt * 0.35)
		VehicleBuilder.set_lift(node, float(v.lift))
		var lp := VehicleBuilder.part(node, "lift")
		if lp:
			lp.position.z = 1.4 - 2.6 * clampf(float(v.lift) / 2.0, 0.0, 1.0)
	if absf(float(v.boom) - float(v.boom_target)) > 0.0005:
		v.boom = move_toward(float(v.boom), float(v.boom_target), dt * 0.12)
		var bp := VehicleBuilder.part(node, "boom")
		if bp:
			bp.rotation.x = float(v.boom)
	if float(v.wait) > 0.0:
		v.wait = float(v.wait) - dt
		return
	var path: Array = v.path
	if path.is_empty():
		v.speed = move_toward(float(v.speed), 0.0, dt * 3.0)
		return
	var wp: Dictionary = path[0]
	var target: Vector3 = wp.p
	var pos := node.position
	var to := target - pos
	to.y = 0.0
	var d := to.length()
	var rev: bool = wp.rev
	if d < (0.5 if path.size() == 1 else 2.0):
		path.pop_front()
		if path.is_empty():
			v.speed = 0.0
			var cb: Callable = v.done
			if v.free_at_end:
				node.queue_free()
				vehicles.erase(v)
			if cb.is_valid():
				cb.call()
		return
	var want := atan2(to.x, to.z) if rev else atan2(-to.x, -to.z)
	var dy := wrapf(want - node.rotation.y, -PI, PI)
	var spd := absf(float(v.speed))
	var turn := 0.75 * clampf(spd / 3.0, 0.15, 1.0)
	node.rotation.y += clampf(dy, -turn * dt, turn * dt)
	var limit: float = float(v.max_speed) * (0.35 if absf(dy) > 0.6 else 1.0) * (0.4 if rev else 1.0)
	if path.size() == 1:
		limit = minf(limit, d * 0.7 + 0.4)
	v.speed = move_toward(spd, limit, dt * (2.2 if float(v.max_speed) < 10.0 else 3.5))
	var fwd := Vector3(-sin(node.rotation.y), 0.0, -cos(node.rotation.y))
	var step := fwd * float(v.speed) * dt * (-1.0 if rev else 1.0)
	node.position = _ground(pos + step)
	VehicleBuilder.roll(node, step.length() * (-1.0 if rev else 1.0), rad_to_deg(clampf(dy, -0.6, 0.6)) * (-1.0 if rev else 1.0))


# ================================================================== turnaround
func begin_turnaround(airport: String, bridge: bool) -> void:
	## Places the service vehicles around a parked aircraft, already working.
	icao = airport
	mode = "turnaround"
	var spec: Dictionary = ac.spec
	var cat: String = spec.category
	var lay := CabinLayout.get_layout(ac.type_id)
	var al_col: Color = Airlines.livery_colors(ac.airline).get("tail", Color(0.1, 0.2, 0.5))
	var liv_al := {"main": Color(0.95, 0.95, 0.96), "accent": al_col, "text": Airlines.get_al(ac.airline).get("name", "").to_upper()}
	var liv_ops := {"main": VehicleBuilder.YELLOW, "text": ac.airline}
	var gh: float = spec.gear_height
	var half_w := float(spec.fuse_w) * 0.5
	var R := _ac_right()
	var F := _ac_fwd()
	var L := float(spec.length)
	var nose_z := -L * float(spec.cg_frac)
	if cat == "trainer":
		_add_staff("ground", _body(Vector3(-3.0, -gh, nose_z + 1.5)), _yaw_for(-R), "stand")
		return
	# tug waiting off the nose
	var nose := _body(Vector3(0, -gh, nose_z))
	tug = _spawn("tug", nose + F * 14.0 - R * 9.0, R, liv_ops, "tug")
	tug_state = "waiting"
	# GPU at the nose unless a bridge supplies power
	if not bridge or cat == "bizjet":
		_spawn("gpu", nose + F * 4.0 - R * 4.5, -F, liv_ops, "gpu")
	# stairs at L1 when there is no jet bridge (bizjets and turboprops have airstairs)
	if not bridge and cat in ["narrowbody", "widebody", "regional", "cargo"]:
		for d in lay.doors:
			if d.name == "L1":
				var door := _body(Vector3(-half_w, 0, d.z))
				var st := _spawn("stairs", door - R * 7.6, R, liv_ops, "stairs")
				VehicleBuilder.part(st.node, "stairs").rotation.x = -atan2(maxf(gh + float(lay.floor_y) - 4.0, -3.0), 5.6) * 0.3
	# refueller under the right wing, parallel to the fuselage
	_spawn("fuel_truck", _body(Vector3(half_w + float(spec.span) * 0.17 + 1.5, -gh, 3.0)), F, {"main": VehicleBuilder.WHITE, "text": "JET A-1"}, "fuel")
	_add_staff("ground", _body(Vector3(half_w + float(spec.span) * 0.17 - 1.0, -gh, 1.0)), _yaw_for(F), "stand")
	# catering at the first right-hand door (galley side)
	if cat in ["narrowbody", "widebody", "regional"]:
		var rdoor := {}
		for d2 in lay.doors:
			if String(d2.name).begins_with("R") and d2.kind == "door":
				rdoor = d2
				if cat != "widebody":
					break
		if not rdoor.is_empty():
			var sill := gh + float(lay.floor_y)
			var cat_v := _spawn("catering", _body(Vector3(half_w + 6.4, -gh, rdoor.z)), -R, liv_al, "catering")
			cat_v.lift_target = clampf(sill - 1.3 - 0.15, 0.0, 4.6)
			cat_v.lift = cat_v.lift_target
			VehicleBuilder.set_lift(cat_v.node, cat_v.lift)
			var lp := VehicleBuilder.part(cat_v.node, "lift")
			if lp:
				lp.position.z = 1.4 - 2.6 * clampf(float(cat_v.lift) / 2.0, 0.0, 1.0)
	# belt loaders and baggage trains at the holds
	var holds := [nose_z + L * 0.27, nose_z + L * 0.66] if cat != "turboprop" else [nose_z + L * 0.82]
	if cat == "bizjet":
		holds = [nose_z + L * 0.8]
	var hold_sill := gh - float(spec.fuse_h) * 0.5 + 0.55
	var hi := 0
	for hz in holds:
		var tip := _body(Vector3(half_w, -gh, hz))
		var bl := _spawn("belt_loader", tip + R * 4.2, -R, liv_ops, "belt")
		var ang := asin(clampf((hold_sill - 0.95) / 7.0, 0.0, 0.5))
		bl.boom_target = ang
		bl.boom = ang
		VehicleBuilder.part(bl.node, "boom").rotation.x = ang
		var dolly := "cart" if cat in ["narrowbody", "regional", "turboprop", "bizjet"] else "uld_dolly"
		var train_o := tip + R * 9.0 + F * (3.0 if hi == 0 else -3.0)
		_spawn("tractor", train_o + F * 2.0, F, liv_ops, "bag_tractor")
		for k in (2 if cat != "bizjet" else 1):
			_spawn(dolly, train_o - F * (2.0 + k * 3.6), F, liv_al, "bag_cart")
		_add_staff("ground", tip + R * 1.2 + F * 0.6, _yaw_for(-R), "push")
		_add_staff("ground", train_o + R * 1.4 - F * 2.0, _yaw_for(-R), "stow")
		hi += 1
	# ground engineer with headset at the nose
	_add_staff("ground", _body(Vector3(-1.2, -gh, float(spec.nose_gear_x) - 2.0)), _yaw_for(-F), "stand", "headset")


func release_for_pushback() -> void:
	## Everything except the tug drives back to the service road.
	mode = "departing"
	var R := _ac_right()
	var F := _ac_fwd()
	var delay := 0.0
	for v in vehicles.duplicate():
		if v.role == "tug":
			continue
		var node: Node3D = v.node
		var side := signf((node.position - ac.position).dot(R))
		if side == 0.0:
			side = 1.0
		var away := node.position + R * side * 32.0 + F * 6.0
		var road := away + R * side * 50.0 - F * 30.0
		v.wait = delay
		delay += 2.5
		if v.kind == "catering":
			v.lift_target = 0.0
			v.wait = float(v.wait) + 7.0
		if v.kind == "belt_loader":
			v.boom_target = 0.0
			v.wait = float(v.wait) + 3.0
		_drive(v, [away, road], 6.0, Callable(), true)
	for s in staff.duplicate():
		if s.role != "headset":
			var sp: Vector3 = s.pos
			var side2 := signf((sp - ac.position).dot(R))
			s.path = [sp + R * (side2 if side2 != 0.0 else 1.0) * 25.0]
			s.speed = 1.4
			s.leave = true


func call_tug(on_connected: Callable = Callable()) -> void:
	## The tug drives to the nose gear and cradles it.
	if tug.is_empty():
		on_connected.call()
		return
	tug_state = "approaching"
	var spec: Dictionary = ac.spec
	var gh: float = spec.gear_height
	var nw := _body(Vector3(0, -gh, float(spec.nose_gear_x)))
	var F := _ac_fwd()
	var cradle: Vector3 = tug.node.get_meta("cradle", Vector3(0, 0.3, 2.65))
	var park := nw + F * cradle.z
	var line_up := park + F * 14.0
	_drive(tug, [line_up, park], 0.0, func():
		tug_state = "connected"
		tug.node.rotation.y = _yaw_for(F)
		VehicleBuilder.set_lamps(tug.node, true, view.night > 0.4)
		tug_connected.emit()
		if on_connected.is_valid():
			on_connected.call())
	tug.max_speed = 4.0
	# wing walkers take position
	for sx in [-1.0, 1.0]:
		var tip := _body(Vector3(sx * float(spec.span) * 0.5, -gh, 1.0))
		_add_staff("ground", tip + F * 2.0, _yaw_for(-F), "wave", "wingwalker")


func update_pushback() -> void:
	## Keeps the connected tug glued to the nose wheel while the aircraft is pushed.
	if tug_state != "connected" or tug.is_empty():
		return
	var node: Node3D = tug.node
	var spec: Dictionary = ac.spec
	var nw := _body(Vector3(0, -float(spec.gear_height), float(spec.nose_gear_x)))
	var F := _ac_fwd()
	var cradle: Vector3 = node.get_meta("cradle", Vector3(0, 0.3, 2.65))
	var before := node.position
	node.position = _ground(nw + F * cradle.z)
	node.rotation.y = _yaw_for(F)
	VehicleBuilder.roll(node, -(node.position - before).length(), 0.0)
	# headset operator walks alongside; wing walkers follow their tips
	for s in staff:
		match String(s.get("role", "")):
			"headset":
				s.pos = _ground(nw - _ac_right() * 2.2 + F * 1.0)
				s.yaw = _yaw_for(-F)
				s.pose = HumanMesh.POSES["walk"] if (node.position - before).length() > 0.005 else HumanMesh.POSES["stand"]
			"wingwalker":
				var sx := signf(float(s.get("side", 1.0)))
				s.pos = _ground(_body(Vector3(sx * float(spec.span) * 0.5, -float(spec.gear_height), 2.5)))
				s.pose = HumanMesh.POSES["walk"] if (node.position - before).length() > 0.005 else HumanMesh.POSES["wave"]


func disconnect_tug() -> void:
	if tug.is_empty():
		tug_clear.emit()
		return
	tug_state = "leaving"
	var node: Node3D = tug.node
	var R := _ac_right()
	var F := _ac_fwd()
	var p := node.position
	tug.max_speed = 6.0
	_drive(tug, [p + F * 6.0 - R * 10.0, p - R * 40.0 + F * 25.0, p - R * 120.0 + F * 30.0], 0.0, func():
		tug_state = "none"
		tug_clear.emit(), true)
	for s in staff:
		if s.get("role", "") == "headset":
			s.path = [s.pos - R * 12.0 + F * 6.0]
			s.speed = 1.3
			s.after = "wave"
		elif s.get("role", "") == "wingwalker":
			s.path = [s.pos + F * 10.0 + R * signf(float(s.get("side", 1.0))) * 6.0]
			s.speed = 1.3
			s.after = "wave"


# ================================================================== arrival
func begin_arrival(stand: Dictionary, airport: String) -> void:
	## Marshaller waiting at the stop line with wands.
	icao = airport
	mode = "arriving"
	var ap: Dictionary = Airports.get_ap(airport)
	var stop: Vector2 = stand.get("stop", Vector2.ZERO)
	var n: Vector2 = stand.get("normal", Vector2(0, 1))
	var p := view.world_to_local(float(ap.x) + stop.x - n.x * 2.0, float(ap.elev), float(ap.z) + stop.y - n.y * 2.0)
	_add_staff("ground", _ground(p), _yaw_for(Vector3(n.x, 0, n.y)), "wave", "marshaller")


func on_blocks(bridge: bool) -> void:
	## Engines off at the stand: chocks in, service vehicles arrive.
	for s in staff.duplicate():
		if s.get("role", "") == "marshaller":
			s.pose = HumanMesh.POSES["stand"]
	var before := vehicles.size()
	begin_turnaround(icao, bridge)
	# the new vehicles drive in from the service road rather than appearing in place
	var R := _ac_right()
	var F := _ac_fwd()
	for i in range(before, vehicles.size()):
		var v: Dictionary = vehicles[i]
		if v.role == "tug":
			continue
		var node: Node3D = v.node
		var final := node.position
		var side := signf((final - ac.position).dot(R))
		if side == 0.0:
			side = 1.0
		node.position = _ground(final + R * side * 70.0 - F * 20.0)
		node.rotation.y = _yaw_for(-R * side)
		v.wait = 4.0 + (i - before) * 3.0
		if v.kind == "catering":
			var target_lift := float(v.lift)
			v.lift = 0.0
			VehicleBuilder.set_lift(node, 0.0)
			v.lift_target = 0.0
			_drive(v, [final + R * side * 12.0, final], 0.0, func(): v.lift_target = target_lift)
		elif v.kind == "belt_loader":
			var tb := float(v.boom)
			v.boom = 0.0
			v.boom_target = 0.0
			VehicleBuilder.part(node, "boom").rotation.x = 0.0
			_drive(v, [final + R * side * 12.0, final], 0.0, func(): v.boom_target = tb)
		else:
			_drive(v, [final + R * side * 12.0, final])


# ================================================================== staff
func _add_staff(kind: String, pos: Vector3, yaw: float, pose: String, role: String = "") -> Dictionary:
	var slot := -1
	var used := {}
	for s in staff:
		used[int(s.slot)] = true
	for i in STAFF_CAP:
		if not used.has(i):
			slot = i
			break
	if slot < 0:
		return {}
	var outfit := Crowd.Outfit.GROUND
	match kind:
		"fire":
			outfit = Crowd.Outfit.FIRE
		"medic":
			outfit = Crowd.Outfit.MEDIC
		"police":
			outfit = Crowd.Outfit.POLICE
	var app := Crowd.staff_appearance(outfit, U.hash_ints(slot, U.hash_str(ac.reg + kind)), "")
	if role == "headset" or role == "marshaller":
		app.flags = int(app.flags) | Crowd.FLAG_HAT
	var s := {"slot": slot, "pos": _ground(pos), "yaw": yaw, "pose": HumanMesh.POSES.get(pose, 0), "phase": _rng.randf(),
		"rate": 1.0, "app": app, "path": [], "speed": 1.3, "role": role, "leave": false, "after": "",
		"side": signf((pos - ac.position).dot(_ac_right())) if ac else 1.0}
	staff.append(s)
	return s


func _update_staff(dt: float) -> void:
	for s in staff.duplicate():
		var path: Array = s.path
		if not path.is_empty():
			var tgt: Vector3 = path[0]
			var to = tgt - s.pos
			to.y = 0.0
			var d = to.length()
			if d < 0.3:
				path.pop_front()
				if path.is_empty():
					if s.leave:
						crowd.hide_person(int(s.slot))
						staff.erase(s)
						continue
					if String(s.after) != "":
						s.pose = HumanMesh.POSES.get(String(s.after), 0)
						s.yaw = _yaw_for(ac.position - s.pos)
			else:
				s.yaw = atan2(to.x, to.z) + PI
				s.pos = _ground(s.pos + to / d * minf(float(s.speed) * dt, d))
				s.pose = HumanMesh.POSES["run" if float(s.speed) > 2.5 else "walk"]
				s.rate = float(s.speed) / 1.3
		var app: Dictionary = s.app
		var xf := Transform3D(Basis(Vector3.UP, float(s.yaw)).scaled(Vector3.ONE * float(app.scale)), s.pos)
		crowd.set_person(int(s.slot), xf, int(s.pose), float(s.phase), float(s.rate), app.top, int(app.outfit), float(app.seed), int(app.flags), float(app.build))
	crowd.flush()


# ================================================================== evacuation
func add_evacuee(p: Dictionary, door: Dictionary) -> void:
	## A passenger leaves the aircraft at a door/slide and runs to the assembly point upwind.
	if evac_crowd == null:
		evac_crowd = Crowd.new()
		evac_crowd.name = "Evacuees"
		add_child(evac_crowd)
		evac_crowd.setup(AircraftTypes.seat_count(ac.type_id) + 16, 1, ac.airline, false)
		var w: Dictionary = ac.weather
		var wind_from := deg_to_rad(float(w.get("wind_dir", 0.0)))
		var up := Vector3(sin(wind_from), 0, -cos(wind_from))
		var side := signf(up.dot(_ac_right()))
		if side == 0.0:
			side = 1.0
		_assembly = _ground(ac.position + _ac_right() * side * (float(ac.spec.span) * 0.5 + 45.0) + up * 25.0)
	var side_d := float(door.get("side", -1))
	var gh: float = ac.spec.gear_height
	var dz := float(door.get("z", 0.0))
	var dx := float(door.get("x", side_d * float(ac.spec.fuse_w) * 0.5))
	var slide_len := 0.0 if door.get("kind", "door") == "overwing" else 4.5
	var start := _body(Vector3(dx + side_d * slide_len, -gh, dz))
	if door.get("kind", "door") == "overwing":
		start = _body(Vector3(side_d * float(ac.spec.span) * 0.3, -gh, dz + 4.0))
	var jitter := Vector3(_rng.randf_range(-6.0, 6.0), 0, _rng.randf_range(-6.0, 6.0))
	var e := {"slot": _evac_next, "pos": _ground(start), "yaw": 0.0, "path": [_ground(start + _ac_right() * side_d * 12.0), _ground(_assembly + jitter)],
		"speed": _rng.randf_range(2.2, 4.2) * (0.6 if int(p.get("age", 40)) > 70 else 1.0), "pose": HumanMesh.POSES["run"],
		"app": p.get("app", Crowd.appearance_for(p)), "state": "running", "person": p, "phase": _rng.randf()}
	if int(p.get("injury", 0)) >= 2:
		e.speed = 0.9
	_evac_next += 1
	evacuees.append(e)


func _update_evacuees(dt: float) -> void:
	if evac_crowd == null:
		return
	for e in evacuees:
		var path: Array = e.path
		if not path.is_empty():
			var tgt: Vector3 = path[0]
			var to = tgt - e.pos
			to.y = 0.0
			var d = to.length()
			if d < 0.5:
				path.pop_front()
				if path.is_empty():
					e.state = "assembled"
					var r := _rng.randf()
					e.pose = HumanMesh.POSES["film" if r < 0.15 else ("grief" if r < 0.3 else ("talk" if r < 0.55 else "stand"))]
					e.yaw = _yaw_for(ac.position - e.pos)
			else:
				e.yaw = atan2(to.x, to.z) + PI
				e.pos = _ground(e.pos + to / d * minf(float(e.speed) * dt, d))
		var app: Dictionary = e.app
		var flags := int(app.flags)
		if e.state == "assembled" and e.pose == HumanMesh.POSES["film"]:
			flags |= Crowd.FLAG_PHONE
		if bool(e.person.get("soot", false)):
			flags |= Crowd.FLAG_SOOT
		var xf := Transform3D(Basis(Vector3.UP, float(e.yaw)).scaled(Vector3.ONE * float(app.scale)), e.pos)
		evac_crowd.set_person(int(e.slot), xf, int(e.pose), float(e.phase), float(e.speed) / 1.6, app.top, int(app.outfit), float(app.seed), flags, float(app.build))
	evac_crowd.flush()


func assembled_count() -> int:
	var n := 0
	for e in evacuees:
		if e.state == "assembled":
			n += 1
	return n


# ================================================================== emergency response
func emergency_response(target: Vector3, fire: bool, delay_s: float = 45.0) -> void:
	## Crash tenders drive to the scene (from the fire station when on the airport, otherwise
	## from a road nearby), surround it upwind and spray; ambulances and crews follow.
	if emergency_active:
		return
	emergency_active = true
	emergency_target = target
	var near := Airports.nearest(view.wx(target), view.wz(target), "", 0.0)
	var start := target + Vector3(900.0, 0, 600.0)
	var on_airport := false
	if near != "":
		var ap: Dictionary = Airports.get_ap(near)
		var L := AirportLayout.get_layout(near)
		var st: Vector2 = L.arff
		var stw := view.world_to_local(float(ap.x) + st.x, float(ap.elev), float(ap.z) + st.y)
		if stw.distance_to(target) < 6000.0:
			start = stw
			on_airport = true
	var w: Dictionary = ac.weather
	var wind_from := deg_to_rad(float(w.get("wind_dir", 0.0)))
	var upwind := Vector3(sin(wind_from), 0, -cos(wind_from))
	var n_trucks := 3 if on_airport else 2
	for i in n_trucks:
		var ang := (float(i) - (n_trucks - 1) * 0.5) * 0.75
		var stop := target + upwind.rotated(Vector3.UP, ang) * 34.0
		var from := start + Vector3(i * 8.0, 0, i * 5.0)
		var dir := (stop - from)
		dir.y = 0.0
		var v := _spawn("arff", from, dir.normalized(), {"main": VehicleBuilder.LIME}, "arff")
		v.wait = delay_s * (0.4 if on_airport else 1.0) + i * 2.0
		v.max_speed = 19.0
		var mid := from.lerp(stop, 0.75) + Vector3(_rng.randf_range(-15, 15), 0, _rng.randf_range(-15, 15))
		_drive(v, [mid, stop], 0.0, func(): _deploy_crew(v, fire))
		arff.append(v)
	for j in 2:
		var stop2 := target + upwind.rotated(Vector3.UP, 1.6 + j * 0.4) * 70.0
		var a := _spawn("ambulance", start + Vector3(-10.0 - j * 6.0, 0, 8.0), (stop2 - start).normalized(), {}, "ambulance")
		a.wait = delay_s * (0.6 if on_airport else 1.3) + 10.0 + j * 4.0
		a.max_speed = 16.0
		_drive(a, [stop2], 0.0, func(): _deploy_medics(a))


func _deploy_crew(v: Dictionary, fire: bool) -> void:
	var node: Node3D = v.node
	v.spraying = fire
	if fire:
		_attach_spray(node)
	for k in 2:
		var p := node.position + node.global_transform.basis.x * (2.0 if k == 0 else -2.0) + node.global_transform.basis.z * 3.0
		var s := _add_staff("fire", p, node.rotation.y, "walk", "firefighter")
		if not s.is_empty():
			var to := emergency_target - p
			to.y = 0.0
			s.path = [p + to.normalized() * minf(to.length() - 18.0, 14.0)]
			s.after = "push"


func _deploy_medics(v: Dictionary) -> void:
	var node: Node3D = v.node
	for k in 2:
		var p := node.position + node.global_transform.basis.z * 3.5 + node.global_transform.basis.x * (k - 0.5) * 1.5
		var s := _add_staff("medic", p, node.rotation.y, "walk", "medic")
		if not s.is_empty():
			s.path = [_assembly if _assembly != Vector3.ZERO else emergency_target + Vector3(30, 0, 30)]
			s.after = "kneel"


func _attach_spray(node: Node3D) -> void:
	var barrel := VehicleBuilder.part(node, "turret_barrel")
	if barrel == null:
		return
	var p := GPUParticles3D.new()
	p.name = "Spray"
	p.amount = 240 if String(Game.settings.get("quality", "high")) in ["high", "ultra"] else 90
	p.lifetime = 2.4
	p.position = Vector3(0, 0, -1.9)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.05, -1)
	pm.spread = 3.5
	pm.initial_velocity_min = 34.0
	pm.initial_velocity_max = 42.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = 2.0
	pm.damping_max = 5.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.25))
	curve.add_point(Vector2(1, 2.4))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(0.92, 0.95, 1.0, 0.32)
	m.albedo_texture = _soft_dot()
	q.material = m
	p.draw_pass_1 = q
	p.local_coords = false
	barrel.add_child(p)


static var _dot_tex: Texture2D


static func _soft_dot() -> Texture2D:
	if _dot_tex == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
				var a := clampf(1.0 - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a * a))
		_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex


func _aim_turrets(dt: float) -> void:
	spray_power = 0.0
	for v in arff:
		var node: Node3D = v.node
		if not is_instance_valid(node) or not bool(v.get("spraying", false)):
			continue
		var turret := VehicleBuilder.part(node, "turret")
		var barrel := VehicleBuilder.part(node, "turret_barrel")
		if turret == null or barrel == null:
			continue
		var local := node.global_transform.affine_inverse() * emergency_target
		var want_yaw := atan2(-local.x, -(local.z - turret.position.z))
		turret.rotation.y = rotate_toward(turret.rotation.y, want_yaw + sin(_t * 0.4) * 0.12, dt * 0.6)
		var horiz := Vector2(local.x, local.z).length()
		barrel.rotation.x = lerp_angle(barrel.rotation.x, clampf(atan2(6.0, horiz) * 0.9, 0.05, 0.5), dt)
		spray_power += 1.0


# ================================================================== per frame
func _process(delta: float) -> void:
	_t += delta
	for v in vehicles.duplicate():
		_update_vehicle(v, delta)
	if tug_state == "connected":
		update_pushback()
	_update_staff(delta)
	_update_evacuees(delta)
	if emergency_active:
		_aim_turrets(delta)
	if int(_t * 2.0) % 10 == 0:
		var night := view.night > 0.4
		for v2 in vehicles:
			if is_instance_valid(v2.node):
				VehicleBuilder.set_lamps(v2.node, v2.kind in ["arff", "ambulance", "follow_me", "tug"] or absf(float(v2.speed)) > 0.2, night)
