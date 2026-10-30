class_name CabinWalker
extends Node3D
## First-person walking: through the cabin (body frame, moves with the aircraft, collides with
## seats, galleys and walls through the cabin layout), around the aircraft on the apron for
## the exterior walkaround, through the terminal from the kerb to the gate (terminal frame,
## collides with the hall's furniture, check-in, security, shops) and down the jet bridge to
## the aircraft door (airport frame, follows the bridge's floor). Finds the nearest thing to interact with (own seat, passengers,
## crew, lavatory, flight deck door, exit door, inspection points) and reports it as a prompt.

signal prompt_changed(text: String)
signal interacted(kind: String, data: Dictionary)
signal inspected(point: Dictionary, finding: Dictionary)

const EYE := 1.63
const SEATED_EYE := 1.12

var ac: Aircraft
var view: WorldView
var session: Node
var lay: Dictionary
var where := "cabin"              # cabin | apron | terminal | bridge
var pos := Vector3.ZERO           # body frame in the cabin, world-local on the apron
var yaw := 0.0                    # radians; cabin: relative to the aircraft
var pitch := 0.0
var head_transform := Transform3D()
var move_input := Vector2.ZERO    # touch joystick (x right, y forward)
var running := false
var seated := false
var seat: Dictionary = {}
var inspected_points := {}
var points: Array = []            # exterior inspection points (body frame)
var ti: TerminalInterior = null  # terminal being walked
var av: AirportView = null
var gate_name := ""
var stand_name := ""
var bridge_pts: Array = []        # airport-local floor polyline (terminal door .. aircraft door)
var checked_in := false
var security_done := false
var _bob := 0.0
var _prompt := ""
var _target: Dictionary = {}


func setup(sess: Node, aircraft: Aircraft, world_view: WorldView) -> void:
	session = sess
	ac = aircraft
	view = world_view
	lay = CabinLayout.get_layout(ac.type_id)
	_build_points()
	view.origin_shifted.connect(func(shift):
		if where == "apron":
			pos -= shift
			position = Vector3.ZERO)


## Starts on foot inside the terminal at `at` (terminal frame), walking to `gate`.
func enter_terminal(terminal: TerminalInterior, airport: AirportView, at: Vector3, facing_yaw: float, gate: String, stand: String) -> void:
	ti = terminal
	av = airport
	gate_name = gate
	stand_name = stand
	where = "terminal"
	seated = false
	_reparent(ti)
	pos = Vector3(at.x, TerminalInterior.FLOOR, at.z)
	yaw = facing_yaw


func enter_bridge() -> bool:
	bridge_pts = av.bridge_path(stand_name) if av else []
	if bridge_pts.size() < 4:
		return false
	where = "bridge"
	seated = false
	_reparent(av)
	pos = bridge_pts[0]
	var d: Vector3 = bridge_pts[1] - bridge_pts[0]
	yaw = atan2(-d.x, -d.z)
	return true


func _reparent(host: Node) -> void:
	if get_parent() != host:
		if get_parent():
			get_parent().remove_child(self)
		host.add_child(self)
	position = Vector3.ZERO


# ================================================================== placement
func enter_cabin(at: Vector3, facing_yaw: float = PI) -> void:
	where = "cabin"
	if get_parent() != ac:
		if get_parent():
			get_parent().remove_child(self)
		ac.add_child(self)
	pos = at
	pos.y = float(lay.floor_y)
	yaw = facing_yaw
	seated = false


func sit(s: Dictionary) -> void:
	seat = s
	seated = true
	where = "cabin"
	pos = Vector3(s.pos.x, float(lay.floor_y), s.pos.z)
	yaw = 0.0


func stand_up() -> void:
	if not seated:
		return
	seated = false
	# step into the aisle next to the seat
	var best := Vector3(0, float(lay.floor_y), float(seat.pos.z))
	var bd := INF
	for aisle in lay.get("aisles", []):
		var ax: float = float(aisle) if typeof(aisle) != TYPE_DICTIONARY else float(aisle.get("x", 0.0))
		var d := absf(ax - float(seat.pos.x))
		if d < bd:
			bd = d
			best.x = ax
	pos = best
	yaw = 0.0


func exit_to_apron(world_local: Vector3, facing: Vector3) -> void:
	where = "apron"
	seated = false
	var host: Node = view.dynamic_root
	if get_parent() != host:
		if get_parent():
			get_parent().remove_child(self)
		host.add_child(self)
	pos = _ground(world_local)
	yaw = atan2(-facing.x, -facing.z)


func _ground(p: Vector3) -> Vector3:
	var q := p
	q.y = Geo.ground_height(view.wx(p), view.wz(p))
	return q


# ================================================================== input
func look(dx_deg: float, dy_deg: float) -> void:
	yaw -= deg_to_rad(dx_deg)
	pitch = clampf(pitch + deg_to_rad(dy_deg), deg_to_rad(-80.0), deg_to_rad(75.0))


func interact() -> void:
	if _target.is_empty():
		return
	var kind := String(_target.kind)
	match kind:
		"own_seat":
			sit(_target.seat)
		"inspect":
			var pt: Dictionary = _target.point
			var f := _finding(pt)
			inspected_points[String(pt.id)] = f
			inspected.emit(pt, f)
		"t_checkin":
			checked_in = true
			var seat_id := String(session.get("pax_seat")) if session else ""
			_say("Checked in. Boarding pass: %s, seat %s, gate %s. Bags tagged and gone." % [String(session.get("callsign")) if session else "", seat_id, gate_name])
		"t_security":
			var ex: Vector3 = _target.spot.get("exit", pos)
			pos = Vector3(ex.x, TerminalInterior.FLOOR, ex.z)
			security_done = true
			_say("Security: laptop out, through the arch - cleared. Gate %s is signposted." % gate_name)
		"t_cafe":
			if Game.has_character():
				Game.add_money(-4.5, "Coffee at the airport")
			_say("A flat white to go from %s. That'll be 4.50." % String(_target.spot.get("title", "the café")))
		"t_shop":
			_say("You browse %s for a while." % String(_target.spot.get("title", "the shop")))
		"t_toilet":
			_say("Much better.")
		"t_lounge":
			_say("The lounge is for members and premium passengers.")
		"t_fids":
			_say(_board_line())
		"t_gate_podium":
			if not checked_in:
				checked_in = true
				_say("Gate agent: \"No problem, I can check you in here. Seat %s - we're boarding now.\"" % (String(session.get("pax_seat")) if session else ""))
			else:
				_say("Gate agent: \"Boarding pass scanned - enjoy your flight.\"")
		"t_gate_door":
			if av and av.bridge_state(stand_name) == "docked":
				if enter_bridge():
					_say("Down the jet bridge to the aircraft.")
			elif av and av.bridge_state(stand_name) == "none" and session and session.has_method("walk_out_to_stand"):
				session.call("walk_out_to_stand")
			else:
				_say("The jet bridge isn't connected to the aircraft yet. Boarding will start shortly.")
		"board_bridge":
			if session and session.has_method("board_from_bridge"):
				session.call("board_from_bridge")
	interacted.emit(kind, _target)


func _process(delta: float) -> void:
	if ac == null:
		return
	var mv := move_input
	if mv.length() < 0.05:
		mv = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	running = Input.is_action_pressed("walk_run") or mv.length() > 0.95
	var look_v := Input.get_vector("look_left", "look_right", "look_down", "look_up")
	if look_v.length() > 0.1:
		look(look_v.x * 110.0 * delta, look_v.y * 80.0 * delta)
	if Input.is_action_just_pressed("interact"):
		if seated:
			stand_up()
		else:
			interact()
	if not seated and mv.length() > 0.05:
		var spd := (2.6 if running else 1.35) * (0.6 if where == "cabin" else 1.0)
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		var step := (fwd * mv.y + right * mv.x).limit_length(1.0) * spd * delta
		_move(step)
		_bob += step.length() * 4.2
	_update_head()
	_find_target()


func _move(step: Vector3) -> void:
	if where == "terminal":
		var ok := ti.resolve(Vector2(pos.x, pos.z), Vector2(pos.x + step.x, pos.z + step.z), 0.3)
		var crossed := not ti.sec.is_empty() and _side_of_security(Vector2(pos.x, pos.z)) != _side_of_security(ok)
		pos = Vector3(ok.x, TerminalInterior.FLOOR, ok.y)
		if crossed and not security_done:
			security_done = true
			_say("Security: bag through the scanner, walk through the arch - cleared. Follow the signs to gate %s." % gate_name)
		return
	if where == "bridge":
		_move_bridge(step)
		return
	if where == "cabin":
		var to := Vector2(pos.x + step.x, pos.z + step.z)
		var ok := CabinLayout.constrain(lay, Vector2(pos.x, pos.z), to)
		pos.x = ok.x
		pos.z = ok.y
		pos.y = float(lay.floor_y)
	else:
		var np := pos + step
		# keep out of the airframe: fuselage tube and engine pods
		var local := ac.global_transform.affine_inverse() * np
		var half_w := float(ac.spec.fuse_w) * 0.5 + 0.4
		var L := float(ac.spec.length)
		var nose_z := -L * float(ac.spec.cg_frac)
		if local.z > nose_z + 1.0 and local.z < nose_z + L * 0.92 and absf(local.x) < half_w:
			var push := signf(local.x) if local.x != 0.0 else 1.0
			local.x = push * half_w
			np = ac.global_transform * local
		for ep in FlightModel.engine_positions(ac.spec):
			var e: Vector3 = ep
			var r := float(ac.spec.get("fan_diam", 1.0)) * 0.75 + 0.4
			var flat := Vector2(local.x - e.x, local.z - e.z)
			if flat.length() < r and absf(e.z - local.z) < float(ac.spec.get("fan_diam", 1.0)) * 2.2:
				var n2 := flat.normalized() if flat.length() > 0.01 else Vector2(1, 0)
				local.x = e.x + n2.x * r
				np = ac.global_transform * local
		pos = _ground(np)


func _move_bridge(step: Vector3) -> void:
	## Free movement inside the corridor: stays within the bridge width of the path and
	## follows its floor up or down the tunnel pitch.
	var np := pos + step
	var best := Vector3.ZERO
	var bd := INF
	var t_at := 0.0
	for k in bridge_pts.size() - 1:
		var a: Vector3 = bridge_pts[k]
		var b: Vector3 = bridge_pts[k + 1]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var f := clampf(Vector2(np.x - a.x, np.z - a.z).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var q := a.lerp(b, f)
		var d := Vector2(np.x - q.x, np.z - q.z).length()
		if d < bd:
			bd = d
			best = q
			t_at = float(k) + f
	var lim := AirportView.BRIDGE_W * 0.5 - 0.35
	if bd > lim:
		var off := Vector2(np.x - best.x, np.z - best.z).normalized() * lim
		np = Vector3(best.x + off.x, np.y, best.z + off.y)
	np.y = best.y
	pos = np
	# back out of the corridor into the gate lounge
	if t_at < 0.02 and step.length() > 0.0 and Vector2(step.x, step.z).dot(Vector2(bridge_pts[0].x - bridge_pts[1].x, bridge_pts[0].z - bridge_pts[1].z)) > 0.0:
		var g := ti.gate(gate_name)
		if not g.is_empty():
			var door: Vector3 = g.door
			enter_terminal(ti, av, door - Vector3(float(g.s) * 1.6, 0, 0), yaw, gate_name, stand_name)


func _side_of_security(p: Vector2) -> float:
	var at := float(ti.sec.at)
	return signf((p.x if String(ti.sec.axis) == "x" else p.y) - at)


func _say(text: String) -> void:
	if session and session.has_signal("toast"):
		session.toast.emit(text, "info")


func _update_head() -> void:
	var eye_h := SEATED_EYE if seated else EYE
	var bob := Vector3(0, sin(_bob) * 0.025, 0) if not seated else Vector3.ZERO
	var local := Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ), pos + Vector3(0, eye_h, 0) + bob)
	if where == "cabin":
		if seated and not seat.is_empty():
			local.origin = Vector3(float(seat.pos.x), float(lay.floor_y) + SEATED_EYE, float(seat.pos.z) - 0.05)
		head_transform = ac.global_transform * local
	elif where in ["terminal", "bridge"] and get_parent() is Node3D:
		head_transform = (get_parent() as Node3D).global_transform * local
	else:
		head_transform = local


# ================================================================== interactions
func _find_target() -> void:
	var best := {}
	var bd := 2.4
	if where == "cabin" and not seated:
		var own_id := String(session.get("pax_seat")) if session else ""
		for s in lay.seats:
			var d := Vector2(pos.x - float(s.pos.x), pos.z - float(s.pos.z)).length()
			if d < bd and String(s.id) == own_id:
				bd = d
				best = {"kind": "own_seat", "seat": s, "text": "Sit down (seat %s)" % s.id}
		var people: CabinPeople = session.get("people") if session else null
		if people and best.is_empty():
			for p in people.pax:
				if p.state == "player":
					continue
				var dp := Vector2(pos.x - float(p.pos.x), pos.z - float(p.pos.z)).length()
				if dp < minf(bd, 1.3):
					bd = dp
					best = {"kind": "talk", "person": p, "text": "Talk to %s" % p.get("first", "passenger")}
			for fa in people.crew:
				var df := Vector2(pos.x - float(fa.pos.x), pos.z - float(fa.pos.z)).length()
				if df < minf(bd, 1.6):
					bd = df
					best = {"kind": "crew", "person": fa, "text": "Speak to %s (cabin crew)" % fa.get("first", "crew")}
		for lv in lay.lavs:
			var zc := (float(lv.z0) + float(lv.z1)) * 0.5
			if absf(pos.z - zc) < 1.4 and absf(pos.x) < 1.2:
				best = {"kind": "lav", "text": "Use the lavatory", "lav": lv}
		var ck: Dictionary = lay.cockpit
		if absf(pos.z - float(ck.back_z)) < 1.3 and absf(pos.x) < 0.8:
			best = {"kind": "flight_deck", "text": "Enter the flight deck"}
		for d in lay.doors:
			if d.kind == "door" and absf(pos.z - float(d.z)) < 1.0 and absf(pos.x - float(d.x)) < 1.4 and session and session.call("any_door_open"):
				best = {"kind": "exit", "door": d, "text": "Leave the aircraft (door %s)" % d.name}
	elif where == "terminal" and ti:
		var sp := ti.nearest_spot(pos, 3.2)
		if not sp.is_empty():
			var kind := String(sp.kind)
			var txt := String(sp.text)
			if kind in ["gate_door", "gate_podium"] and String(sp.get("gate", "")) != gate_name:
				txt = "Gate %s (your flight leaves from gate %s)" % [sp.get("gate", ""), gate_name]
				kind = "info"
			best = {"kind": "t_" + kind, "spot": sp, "text": txt}
	elif where == "bridge" and bridge_pts.size() >= 4:
		var end: Vector3 = bridge_pts[bridge_pts.size() - 1]
		if Vector2(pos.x - end.x, pos.z - end.z).length() < 1.6:
			best = {"kind": "board_bridge", "text": "Board the aircraft (door L1)"}
	elif where == "apron":
		for pt in points:
			var wp: Vector3 = ac.global_transform * Vector3(pt.p)
			var d2 := Vector2(pos.x - wp.x, pos.z - wp.z).length()
			if d2 < 3.2:
				var done := inspected_points.has(String(pt.id))
				best = {"kind": "inspect", "point": pt, "text": ("Inspect " if not done else "Inspected: ") + String(pt.label)}
		var door := ac.global_transform * ac.model.door_world_local() if ac.model else ac.global_position
		if Vector2(pos.x - door.x, pos.z - door.z).length() < 6.0:
			best = {"kind": "board", "text": "Board the aircraft"}
	_target = best
	var t := String(best.get("text", ""))
	if t != _prompt:
		_prompt = t
		prompt_changed.emit(t)


# ================================================================== walkaround
func _build_points() -> void:
	var spec: Dictionary = ac.spec
	var gh: float = spec.gear_height
	var L: float = spec.length
	var nose_z := -L * float(spec.cg_frac)
	var b: float = spec.span
	points = [
		{"id": "nose", "label": "nose, radome and probes", "p": Vector3(0, -gh, nose_z - 1.5), "system": "probes"},
		{"id": "nose_gear", "label": "nose gear and tyres", "p": Vector3(1.4, -gh, float(spec.nose_gear_x)), "system": "gear"},
		{"id": "left_main", "label": "left main gear and brakes", "p": Vector3(-float(spec.gear_track) * 0.5 - 1.4, -gh, float(spec.main_gear_x)), "system": "gear"},
		{"id": "right_main", "label": "right main gear and brakes", "p": Vector3(float(spec.gear_track) * 0.5 + 1.4, -gh, float(spec.main_gear_x)), "system": "gear"},
		{"id": "left_wing", "label": "left wing, flaps and tip", "p": Vector3(-b * 0.42, -gh, 2.0), "system": "wing"},
		{"id": "right_wing", "label": "right wing, flaps and tip", "p": Vector3(b * 0.42, -gh, 2.0), "system": "wing"},
		{"id": "tail", "label": "tail, elevators and rudder", "p": Vector3(0, -gh, nose_z + L + 2.0), "system": "tail"},
	]
	var engines := FlightModel.engine_positions(spec)
	for i in engines.size():
		var e: Vector3 = engines[i]
		points.append({"id": "eng_%d" % (i + 1), "label": "engine %d intake and exhaust" % (i + 1),
			"p": Vector3(e.x + (1.8 if e.x >= 0.0 else -1.8), -gh, e.z - 1.5), "system": "engine", "index": i})
	if spec.category != "trainer":
		points.append({"id": "holds", "label": "cargo doors and belly", "p": Vector3(float(spec.fuse_w) * 0.5 + 1.6, -gh, nose_z + L * 0.3), "system": "cargo"})


func _finding(pt: Dictionary) -> Dictionary:
	## What the inspection reveals: open defects on the aircraft record, damage, ice and fuel.
	var rec := WorldSim.aircraft(ac.reg)
	var sys_name := String(pt.system)
	for d in rec.get("defects", []):
		var ds := String(d.get("system", ""))
		if (ds == sys_name) or (ds == "hydraulics" and sys_name == "gear") or (ds == "engine" and sys_name == "engine"):
			return {"ok": false, "text": String(d.text), "severity": int(d.get("severity", 1)), "defect": d}
	var w: Dictionary = ac.weather
	if sys_name == "wing" and float(w.get("temp_c", 15.0)) < 3.0 and String(w.get("precip", "none")) != "none":
		return {"ok": false, "text": "Ice and slush on the upper wing surface: de-icing required before departure.", "severity": 2, "deice": true}
	if String(pt.id) == "tail" and bool(ac.damage.get("tailstrike", false)):
		return {"ok": false, "text": "Scrape marks on the tail skid area.", "severity": 3}
	var cond := float(rec.get("condition", 90.0))
	if cond < 68.0 and U.hash_ints(U.hash_str(String(pt.id)), U.hash_str(ac.reg)) % 4 == 0:
		return {"ok": false, "text": "Worn but within limits. Note it in the tech log.", "severity": 0}
	return {"ok": true, "text": U.pick(U.rng(U.hash_str(String(pt.id) + ac.reg)), ["No damage, no leaks.", "Looks good.", "Secure, no damage.", "Normal."]), "severity": 0}


func _board_line() -> String:
	for f in ti.departures(14):
		var cs := String(session.get("callsign")) if session else ""
		if String(f.get("callsign", "")) == cs or String(f.get("number", "")) == cs.get_slice(" ", 1):
			return "Departures: %s to %s - gate %s - %s." % [f.get("number", ""), Airports.get_ap(String(f.get("to", ""))).get("city", ""), gate_name, TerminalInterior.status_for(f, WorldSim.clock)]
	return "Departures: your flight %s - gate %s - boarding." % [String(session.get("callsign")) if session else "", gate_name]


func walkaround_fraction() -> float:
	if points.is_empty():
		return 1.0
	return float(inspected_points.size()) / points.size()
