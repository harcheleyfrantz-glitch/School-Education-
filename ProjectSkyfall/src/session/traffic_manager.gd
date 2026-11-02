class_name TrafficManager
extends Node3D
## Living airports around the player's flight: parked aircraft at the gates, AI arrivals flying
## the ILS to a landing and taxiing in, AI departures taxiing out, holding short, lining up and
## taking off. Motion is kinematic along runway and taxi geometry. Answers the runway-occupancy
## questions ATC asks and feeds the TCAS/ND traffic picture.

const MAX_MOVING := 3
const MAX_PARKED := 6

var session: Node
var view: WorldView
var moving: Array = []
var parked: Array = []
var airborne: Array = []         # distant traffic for TCAS only: {callsign, x, z, alt, vs, hdg, spd}
var _rng := RandomNumberGenerator.new()
var _spawn_t := 25.0
var _cross_t := 200.0
var _queue: Array = []           # deferred model builds: {item, kind}
var _next_id := 0
var evacuee_sink: Callable


func setup(sess: Node, world_view: WorldView) -> void:
	session = sess
	view = world_view
	_rng.seed = U.hash_str(String(sess.get("flight_id")) + "traffic")
	view.origin_shifted.connect(func(_shift):
		position = Vector3.ZERO
		for p in parked:
			if p.model != null:
				_place_parked(p))
	var detail := String(Game.settings.get("quality", "high"))
	var dep := String(sess.get("dep_icao"))
	if dep != "":
		_populate_parked(dep, MAX_PARKED if detail in ["high", "ultra"] else 3)
	for i in 5:
		_spawn_airborne()


# ================================================================== helpers
func _ap_local(icao: String, p: Vector2, y: float) -> Vector3:
	var ap: Dictionary = Airports.get_ap(icao)
	return view.world_to_local(float(ap.x) + p.x, y, float(ap.z) + p.y)


func _airline_for(type_id: String, icao: String = "") -> String:
	## Airlines that fly this type, preferring those based within reach of the airport (so New
	## York's gates fill with Liberty Atlantic, not Calderra's island turboprops).
	var codes := []
	var near := []
	var here := Airports.pos2(icao) if icao != "" and Airports.DATA.has(icao) else Vector2.INF
	for c in Airlines.all_codes():
		if Airlines.operates_type(c, type_id):
			codes.append(c)
			if here != Vector2.INF:
				for hb in Airlines.get_al(c).get("hubs", []):
					if Airports.DATA.has(hb) and Airports.pos2(hb).distance_to(here) < 1400000.0:
						near.append(c)
						break
	if not near.is_empty():
		codes = near
	if codes.is_empty():
		return "SKF"
	return codes[_rng.randi() % codes.size()]


func _type_for_span(max_span: float, cats: Array = []) -> String:
	var opts := []
	for t in AircraftTypes.ORDER:
		var s := AircraftTypes.get_type(t)
		if float(s.span) <= max_span and String(s.category) != "trainer" and (cats.is_empty() or String(s.category) in cats):
			opts.append(t)
	if opts.is_empty():
		return "s320"
	return opts[_rng.randi() % opts.size()]


func _callsign(airline: String) -> String:
	var al := Airlines.get_al(airline)
	return "%s %d" % [String(al.get("callsign", airline)).capitalize(), _rng.randi_range(100, 989)]


func _make_model(type_id: String, airline: String) -> AircraftModel:
	var m := AircraftModel.new()
	var reg := "CR-%s%s%s" % [char(65 + _rng.randi() % 26), char(65 + _rng.randi() % 26), char(65 + _rng.randi() % 26)]
	m.build(type_id, airline, reg, 0.45)
	add_child(m)
	m.animate_simple(1.0, 0.0, 0.0, {"nav": false}, view.night, 0.0)
	return m


static func _basis(hdg: float, pitch: float = 0.0, bank: float = 0.0) -> Basis:
	return Basis(Vector3.UP, -deg_to_rad(hdg)) * Basis(Vector3.RIGHT, deg_to_rad(pitch)) * Basis(Vector3(0, 0, -1), deg_to_rad(bank))


# ================================================================== parked aircraft
func _populate_parked(icao: String, count: int) -> void:
	var L := AirportLayout.get_layout(icao)
	var used := [String(session.get("stand"))]
	var stands: Array = L.stands.duplicate()
	U.shuffle(_rng, stands)
	var n := 0
	for sd in stands:
		if n >= count:
			break
		if String(sd.name) in used or _rng.randf() < 0.3:
			continue
		var t := _type_for_span(float(sd.max_span), ["narrowbody", "regional", "widebody", "turboprop", "bizjet"])
		var al := _airline_for(t, icao)
		var item := {"icao": icao, "stand": sd.name, "type": t, "airline": al, "model": null, "callsign": _callsign(al),
			"sd": sd, "phase": "parked", "id": _next_id}
		_next_id += 1
		parked.append(item)
		_queue.append(item)
		n += 1


func _place_parked(item: Dictionary) -> void:
	var m: AircraftModel = item.model
	var sd: Dictionary = item.sd
	var spec := AircraftTypes.get_type(String(item.type))
	var nrm: Vector2 = sd.normal
	var face: Vector2 = sd.get("facade_origin", sd.stop)
	var pos2 := face + nrm * (7.0 + float(spec.length) * float(spec.cg_frac))
	var elev := float(Airports.get_ap(String(item.icao)).elev)
	m.position = _ap_local(String(item.icao), pos2, elev + float(spec.gear_height))
	m.basis = _basis(float(sd.hdg))
	m.animate_simple(1.0, 0.0, 0.0, {"nav": true, "beacon": false}, view.night, 0.0)
	item.x = view.wx(m.position)
	item.z = view.wz(m.position)


# ================================================================== spawning moving traffic
func _active_end(icao: String) -> Dictionary:
	if icao == String(session.get("dep_icao")) and not (session.get("dep_end") as Dictionary).is_empty():
		return session.get("dep_end")
	if icao == String(session.get("arr_icao")) and not (session.get("arr_end") as Dictionary).is_empty():
		return session.get("arr_end")
	var w := WeatherModel.sample(Airports.get_ap(icao).x, Airports.get_ap(icao).z, WorldSim.clock)
	return Airports.best_runway(icao, float(w.get("wind_dir", 0.0)), float(w.get("wind_kt", 0.0)), 1500.0)


func _focus_airport() -> String:
	## The airport where traffic matters right now: the departure airport while the player is
	## on the ground there or climbing out, the arrival airport once within 70 km of it.
	var ac: Aircraft = session.get("ac")
	if ac == null:
		return ""
	var arr := String(session.get("arr_icao"))
	var dep := String(session.get("dep_icao"))
	var px := ac.world_x()
	var pz := ac.world_z()
	if arr != "" and Airports.get_ap(arr) and U.dist2d(px, pz, Airports.get_ap(arr).x, Airports.get_ap(arr).z) < 70000.0:
		return arr
	if dep != "" and U.dist2d(px, pz, Airports.get_ap(dep).x, Airports.get_ap(dep).z) < 25000.0:
		return dep
	return ""


func _spawn_moving() -> void:
	var icao := _focus_airport()
	if icao == "" or moving.size() >= MAX_MOVING:
		return
	var L := AirportLayout.get_layout(icao)
	if L.runways.is_empty() or AirportLayout.get_layout(icao).size == "ga":
		return
	var end := _active_end(icao)
	if end.is_empty():
		return
	var ac: Aircraft = session.get("ac")
	var player_ground := ac != null and ac.fdm.on_ground
	# departures need a parked aircraft to push back from; otherwise spawn an arrival
	var dep_candidates := []
	for p in parked:
		if p.icao == icao and p.model != null:
			dep_candidates.append(p)
	if not dep_candidates.is_empty() and (_rng.randf() < 0.45 or player_ground):
		var item: Dictionary = dep_candidates[_rng.randi() % dep_candidates.size()]
		parked.erase(item)
		_start_departure(item, icao, end)
	else:
		_start_arrival(icao, end)


func _start_arrival(icao: String, end: Dictionary) -> void:
	var t := _type_for_span(66.0, ["narrowbody", "regional", "widebody", "turboprop"])
	var al := _airline_for(t, icao)
	var item := {"icao": icao, "type": t, "airline": al, "model": null, "callsign": _callsign(al), "phase": "final",
		"end": end, "dist": 15000.0 + _rng.randf_range(0.0, 6000.0), "speed": 150.0 * U.KT, "id": _next_id, "t": 0.0,
		"path": [], "hdg": float(end.hdg), "alt": 0.0, "vs": 0.0, "pitch": 0.0, "gear": 1.0, "flap": 3.0}
	_next_id += 1
	moving.append(item)
	_queue.append(item)


func _start_departure(item: Dictionary, icao: String, end: Dictionary) -> void:
	var L := AirportLayout.get_layout(icao)
	var sd: Dictionary = item.sd
	var hold := AirportLayout.hold_node_for(L, String(end.name))
	var path := AirportLayout.find_path(L, int(sd.lane_node), hold) if hold >= 0 else []
	item.phase = "pushback"
	item.gear = 1.0
	item.flap = 0.0
	item.end = end
	item.t = 0.0
	item.speed = 0.0
	item.pts = []
	for step in path:
		item.pts.append(L.taxi_nodes[int(step.node)].pos)
	var spec := AircraftTypes.get_type(String(item.type))
	var nrm: Vector2 = sd.normal
	var face: Vector2 = sd.get("facade_origin", sd.stop)
	item.p2 = face + nrm * (7.0 + float(spec.length) * float(spec.cg_frac))
	item.push_to = item.p2 + nrm * (float(spec.length) * 0.6 + 14.0)
	item.hdg = float(sd.hdg)
	moving.append(item)


func _spawn_airborne() -> void:
	## Background traffic that only appears on TCAS and in radio chatter.
	var ac: Aircraft = session.get("ac")
	var cx := ac.world_x() if ac else 0.0
	var cz := ac.world_z() if ac else 0.0
	var t := _type_for_span(80.0, ["narrowbody", "regional", "widebody"])
	var al := _airline_for(t)
	airborne.append({"callsign": _callsign(al), "x": cx + _rng.randf_range(-60000, 60000), "z": cz + _rng.randf_range(-60000, 60000),
		"alt": _rng.randf_range(2500.0, 11500.0), "vs": _rng.randf_range(-8.0, 8.0) if _rng.randf() < 0.4 else 0.0,
		"hdg": _rng.randf_range(0.0, 360.0), "spd": _rng.randf_range(200.0, 250.0), "type": t, "airline": al, "model": null, "phase": "airborne"})


func _spawn_crossing() -> void:
	## Traffic on a converging course that passes close to the player (a near miss on TCAS,
	## visible out of the window). It is set up to miss; flying into it is the player's doing.
	var ac: Aircraft = session.get("ac")
	if ac == null or ac.crashed_state or ac.fdm.on_ground or float(ac.ra) < 900.0:
		return
	var t := _type_for_span(80.0, ["narrowbody", "regional", "widebody"])
	var al := _airline_for(t)
	var lead := 70.0
	var my_v := ac.fdm.vel
	var meet := Vector2(ac.world_x() + my_v.x * lead, ac.world_z() + my_v.z * lead)
	var spd := _rng.randf_range(210.0, 250.0)
	var hdg := _rng.randf_range(0.0, 360.0)
	var d := Vector2(sin(deg_to_rad(hdg)), -cos(deg_to_rad(hdg)))
	var miss := Vector2(-d.y, d.x) * _rng.randf_range(350.0, 1200.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
	var start := meet + miss - d * spd * U.KT * lead
	airborne.append({"callsign": _callsign(al), "x": start.x, "z": start.y, "alt": ac.fdm.pos.y + _rng.randf_range(-150.0, 150.0), "vs": 0.0,
		"hdg": hdg, "spd": spd, "type": t, "airline": al, "model": null, "phase": "airborne"})
	if airborne.size() > 14:
		_drop_airborne(airborne[0])


func _drop_airborne(a: Dictionary) -> void:
	airborne.erase(a)
	if a.get("model") != null and is_instance_valid(a.model):
		(a.model as Node).queue_free()
	a.model = null


func sky_items() -> Array:
	## Airborne background traffic currently close enough to be drawn (and to collide with).
	var out := []
	for a in airborne:
		if a.get("model") != null:
			out.append(a)
	return out


func item_velocity(item: Dictionary) -> Vector3:
	var hdg := deg_to_rad(float(item.get("hdg", 0.0)))
	var d := Vector3(sin(hdg), 0.0, -cos(hdg))
	match String(item.get("phase", "")):
		"parked", "hold":
			return Vector3.ZERO
		"airborne":
			return d * float(item.spd) * U.KT + Vector3(0, float(item.get("vs", 0.0)), 0)
	return d * float(item.get("speed", 0.0))


func npc_hit(item: Dictionary, impact_vel: Vector3, closing: float, midair: bool) -> void:
	## The other aircraft in a collision. In the air it breaks up and falls burning; on the
	## ground a hard hit sets it on fire.
	var m: AircraftModel = item.get("model")
	if m == null or not is_instance_valid(m):
		return
	var pieces: WreckPieces = session.call("wreck_pieces") if session and session.has_method("wreck_pieces") else null
	if not midair or pieces == null:
		if closing > 15.0 and pieces != null:
			var f := pieces._flames(1.2)
			m.add_child(f)
			f.position = Vector3(0, 1.0, 2.0)
			var sm := pieces._trail(1.0, true)
			m.add_child(sm)
		item.phase = "parked" if String(item.get("phase", "")) == "parked" else "hold"
		moving.erase(item)
		parked.erase(item)
		return
	var v := item_velocity(item)
	moving.erase(item)
	parked.erase(item)
	airborne.erase(item)
	item.model = null
	m.reparent(view.dynamic_root, true)
	var lc := CrashDebris.opts_for(AircraftTypes.get_type(String(item.type)), String(item.airline), 0.3, 1.0)
	var plan := {"tail": _rng.randf() < 0.6, "wing": -1 if _rng.randf() < 0.5 else 1, "nose": _rng.randf() < 0.25}
	var xf := m.global_transform
	pieces.break_up(m, xf, v + impact_vel * 0.15, String(item.type), String(item.airline), "", plan, _rng, true)
	pieces.add_piece(m, v + impact_vel * 0.15, -xf.basis.z * float(plan.wing) * 1.6 + xf.basis.x * _rng.randf_range(-0.5, 0.5),
		{"drag": 0.0022, "rest_h": 2.0, "bounce": 0.1, "smoke": true, "fire": true, "big": true})
	pieces.burst(xf.origin, v, 22, lc, _rng)
	pieces.engine_piece(xf.origin + xf.basis.x * 6.0, v, float(lc.eng_d), lc.accent, _rng, true)
	if session and session.has_signal("toast"):
		session.toast.emit("MID-AIR COLLISION with %s" % String(item.get("callsign", "another aircraft")), "warning")


# ================================================================== per frame
func _process(delta: float) -> void:
	if session == null:
		return
	# build at most one model per frame
	if not _queue.is_empty():
		var item: Dictionary = _queue.pop_front()
		if item in moving or item in parked:
			item.model = _make_model(String(item.type), String(item.airline))
			if item.phase == "parked":
				_place_parked(item)
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = _rng.randf_range(70.0, 150.0)
		_spawn_moving()
	for item in moving.duplicate():
		if item.model == null:
			continue
		match String(item.phase):
			"final", "flare", "rollout", "go_around":
				_update_arrival(item, delta)
			"pushback", "taxi_out", "hold", "lineup", "takeoff", "climb":
				_update_departure(item, delta)
			"taxi_in":
				_update_taxi(item, delta, 8.0)
	_cross_t -= delta
	if _cross_t <= 0.0:
		_cross_t = _rng.randf_range(240.0, 480.0)
		_spawn_crossing()
	var me: Aircraft = session.get("ac")
	var built_one := false
	for a in airborne.duplicate():
		var d := Vector2(sin(deg_to_rad(float(a.hdg))), -cos(deg_to_rad(float(a.hdg))))
		a.x = float(a.x) + d.x * float(a.spd) * U.KT * delta
		a.z = float(a.z) + d.y * float(a.spd) * U.KT * delta
		a.alt = clampf(float(a.alt) + float(a.vs) * delta, 600.0, 12500.0)
		# draw the ones close to the player (one new model per frame at most)
		if me == null:
			continue
		var dist := Vector3(float(a.x) - me.world_x(), float(a.alt) - me.fdm.pos.y, float(a.z) - me.world_z()).length()
		var m = a.get("model")
		if m == null and dist < 6000.0 and not built_one and a.has("type"):
			a.model = _make_model(String(a.type), String(a.airline))
			built_one = true
			m = a.model
		elif m != null and dist > 8000.0:
			(m as Node).queue_free()
			a.model = null
			continue
		if m != null and is_instance_valid(m):
			var am: AircraftModel = m
			am.position = view.world_to_local(float(a.x), float(a.alt), float(a.z))
			am.basis = _basis(float(a.hdg), clampf(float(a.vs) * 0.4, -3.0, 6.0) + 2.0)
			am.animate_simple(0.0, 0.0, 60.0, {"nav": true, "beacon": true, "strobe": true}, view.night, delta)


func _update_arrival(item: Dictionary, dt: float) -> void:
	var m: AircraftModel = item.model
	var end: Dictionary = item.end
	var spec := AircraftTypes.get_type(String(item.type))
	var vapp := float(spec.vapp) * U.KT
	var dir := Vector2(sin(deg_to_rad(float(end.hdg))), -cos(deg_to_rad(float(end.hdg))))
	var thr := Vector2(float(end.thr_x), float(end.thr_z))
	var elev := float(end.elev)
	var gh := float(spec.gear_height)
	item.t = float(item.t) + dt
	match String(item.phase):
		"final":
			item.speed = move_toward(float(item.speed), vapp, dt * 0.6)
			item.dist = float(item.dist) - float(item.speed) * dt
			var h := (float(item.dist) + 300.0) * tan(deg_to_rad(3.0))
			item.alt = elev + gh + maxf(h, 0.0)
			item.pitch = 2.5
			# runway blocked by the player close in: go around
			if float(item.dist) < 3500.0 and float(item.dist) > 1500.0 and _player_on_runway(String(item.icao), end):
				item.phase = "go_around"
				_atc_call(String(item.icao), String(item.callsign), "%s, go around, I say again, go around, runway occupied." % item.callsign,
					"Going around, %s." % item.callsign)
			if float(item.dist) < 15.0 / tan(deg_to_rad(3.0)) - 300.0:
				item.phase = "flare"
		"flare":
			item.dist = float(item.dist) - float(item.speed) * dt
			var hh := float(item.alt) - elev - gh
			hh = maxf(hh - maxf(hh * 0.45, 0.6) * dt, 0.0)
			item.alt = elev + gh + hh
			item.pitch = move_toward(float(item.pitch), 5.0, dt * 1.5)
			if hh <= 0.02:
				item.phase = "rollout"
				item.flap = float(spec.flaps.size() - 1)
		"rollout":
			item.speed = maxf(float(item.speed) - 2.2 * dt, 9.0)
			item.dist = float(item.dist) - float(item.speed) * dt
			item.alt = elev + gh
			item.pitch = move_toward(float(item.pitch), 0.0, dt * 2.0)
			if float(item.speed) <= 9.5:
				_begin_taxi_in(item)
		"go_around":
			item.speed = move_toward(float(item.speed), 180.0 * U.KT, dt * 2.0)
			item.dist = float(item.dist) - float(item.speed) * dt
			item.alt = float(item.alt) + 9.0 * dt
			item.pitch = move_toward(float(item.pitch), 12.0, dt * 2.0)
			item.gear = move_toward(float(item.gear), 0.0, dt * 0.12)
			if float(item.alt) > elev + 900.0:
				_retire(item)
				return
	var p2 := thr - dir * float(item.dist)
	m.position = view.world_to_local(p2.x, float(item.alt), p2.y)
	m.basis = _basis(float(end.hdg), float(item.pitch))
	item.x = p2.x
	item.z = p2.y
	item.hdg = float(end.hdg)
	m.animate_simple(float(item.gear), float(item.flap), 40.0, {"nav": true, "strobe": true, "beacon": true, "landing": true}, view.night, dt,
		float(item.speed) if item.phase == "rollout" else 0.0)


func _begin_taxi_in(item: Dictionary) -> void:
	var icao := String(item.icao)
	var L := AirportLayout.get_layout(icao)
	var ap: Dictionary = Airports.get_ap(icao)
	var here := Vector2(float(item.x) - float(ap.x), float(item.z) - float(ap.z))
	var from := AirportLayout.nearest_node(L, here, ["rwy", "exit", "taxi"])
	var occupied := [String(session.get("arr_stand")), String(session.get("stand"))]
	for p in parked:
		occupied.append(String(p.stand))
	var sd := AirportLayout.free_stand(L, float(AircraftTypes.get_type(String(item.type)).span), occupied, _rng.randi())
	if sd.is_empty() or from < 0:
		_retire(item)
		return
	var path := AirportLayout.find_path(L, from, int(sd.node), true)
	item.pts = []
	for step in path:
		item.pts.append(L.taxi_nodes[int(step.node)].pos)
	item.sd = sd
	item.stand = sd.name
	item.phase = "taxi_in"
	item.speed = 7.0
	item.flap = 0.0


func _update_taxi(item: Dictionary, dt: float, max_speed: float) -> bool:
	## Moves along item.pts (airport-local). Returns true when the route is finished.
	var m: AircraftModel = item.model
	var icao := String(item.icao)
	var ap: Dictionary = Airports.get_ap(icao)
	var spec := AircraftTypes.get_type(String(item.type))
	var pts: Array = item.pts
	var pos := Vector2(float(item.x) - float(ap.x), float(item.z) - float(ap.z))
	if pts.is_empty():
		return true
	var tgt: Vector2 = pts[0]
	var to := tgt - pos
	var d := to.length()
	if d < 4.0:
		pts.pop_front()
		if pts.is_empty():
			if item.phase == "taxi_in":
				_park(item)
			return true
		return false
	var want := fposmod(rad_to_deg(atan2(to.x, -to.y)), 360.0)
	var dh := U.angle_diff_deg(want, float(item.hdg))
	item.hdg = fposmod(float(item.hdg) + clampf(dh, -25.0 * dt, 25.0 * dt), 360.0)
	var spd := max_speed * (0.45 if absf(dh) > 25.0 else 1.0)
	item.speed = move_toward(float(item.speed), spd, dt * 1.2)
	var hd := Vector2(sin(deg_to_rad(float(item.hdg))), -cos(deg_to_rad(float(item.hdg))))
	pos += hd * float(item.speed) * dt
	item.x = float(ap.x) + pos.x
	item.z = float(ap.z) + pos.y
	m.position = _ap_local(icao, pos, float(ap.elev) + float(spec.gear_height))
	m.basis = _basis(float(item.hdg))
	m.animate_simple(1.0, float(item.flap), 18.0, {"nav": true, "beacon": true}, view.night, dt, float(item.speed))
	return false


func _park(item: Dictionary) -> void:
	moving.erase(item)
	item.phase = "parked"
	parked.append(item)
	_place_parked(item)
	if parked.size() > MAX_PARKED + 2:
		var old: Dictionary = parked.pop_front()
		if old.model:
			old.model.queue_free()


func _update_departure(item: Dictionary, dt: float) -> void:
	var m: AircraftModel = item.model
	var icao := String(item.icao)
	var ap: Dictionary = Airports.get_ap(icao)
	var spec := AircraftTypes.get_type(String(item.type))
	var end: Dictionary = item.end
	item.t = float(item.t) + dt
	match String(item.phase):
		"pushback":
			var a: Vector2 = item.p2
			var b: Vector2 = item.push_to
			var f := clampf(float(item.t) / 70.0, 0.0, 1.0)
			var p := a.lerp(b, U.smooth01(f))
			item.x = float(ap.x) + p.x
			item.z = float(ap.z) + p.y
			m.position = _ap_local(icao, p, float(ap.elev) + float(spec.gear_height))
			m.basis = _basis(float(item.hdg))
			m.animate_simple(1.0, 0.0, 6.0 if f > 0.5 else 0.0, {"nav": true, "beacon": true}, view.night, dt, 1.0)
			if f >= 1.0:
				item.phase = "taxi_out"
				item.t = 0.0
				item.flap = 1.0
				# turn to face along the lane before taxiing
				if not (item.pts as Array).is_empty():
					var first: Vector2 = item.pts[0]
					item.hdg = fposmod(rad_to_deg(atan2(first.x - p.x, -(first.y - p.y))), 360.0)
		"taxi_out":
			if _update_taxi(item, dt, 9.0):
				item.phase = "hold"
				item.t = 0.0
		"hold":
			m.animate_simple(1.0, 1.0, 18.0, {"nav": true, "beacon": true}, view.night, dt)
			if float(item.t) > 20.0 and not _player_on_runway(icao, end) and not arrival_within(icao, 70.0):
				item.phase = "lineup"
				item.t = 0.0
				_atc_call(icao, String(item.callsign), "%s, runway %s, cleared for takeoff." % [item.callsign, end.name],
					"Cleared for takeoff runway %s, %s." % [end.name, item.callsign])
				var thr := Vector2(float(end.thr_x), float(end.thr_z)) - Vector2(float(ap.x), float(ap.z))
				var dir := Vector2(sin(deg_to_rad(float(end.hdg))), -cos(deg_to_rad(float(end.hdg))))
				item.pts = [thr + dir * 80.0, thr + dir * 140.0]
				item.speed = 4.0
		"lineup":
			if _update_taxi(item, dt, 6.0):
				item.phase = "takeoff"
				item.t = 0.0
				item.speed = 3.0
				item.alt = float(ap.elev) + float(spec.gear_height)
				item.pitch = 0.0
		"takeoff", "climb":
			var vr := float(spec.vr) * U.KT
			var dir2 := Vector2(sin(deg_to_rad(float(end.hdg))), -cos(deg_to_rad(float(end.hdg))))
			if item.phase == "takeoff":
				item.speed = float(item.speed) + 2.1 * dt
				if float(item.speed) > vr:
					item.pitch = move_toward(float(item.pitch), 9.0, dt * 2.5)
				if float(item.speed) > vr * 1.08:
					item.phase = "climb"
			else:
				item.speed = minf(float(item.speed) + 1.2 * dt, 210.0 * U.KT)
				item.alt = float(item.alt) + float(item.speed) * sin(deg_to_rad(7.0)) * dt
				item.pitch = move_toward(float(item.pitch), 12.0, dt)
				item.gear = move_toward(float(item.gear), 0.0, dt * 0.15)
				if float(item.alt) > float(ap.elev) + 2500.0:
					_retire(item)
					return
			var pos := Vector2(float(item.x), float(item.z)) + dir2 * float(item.speed) * dt
			item.x = pos.x
			item.z = pos.y
			item.hdg = float(end.hdg)
			m.position = view.world_to_local(pos.x, float(item.get("alt", float(ap.elev) + float(spec.gear_height))), pos.y)
			m.basis = _basis(float(end.hdg), float(item.pitch))
			m.animate_simple(float(item.get("gear", 1.0)), 1.0, 60.0, {"nav": true, "beacon": true, "strobe": true, "landing": true}, view.night, dt,
				float(item.speed) if item.phase == "takeoff" else 0.0)


func _retire(item: Dictionary) -> void:
	moving.erase(item)
	if item.model:
		item.model.queue_free()
	item.model = null
	# keep it on TCAS for a while
	airborne.append({"callsign": item.callsign, "x": float(item.get("x", 0.0)), "z": float(item.get("z", 0.0)),
		"alt": float(item.get("alt", 900.0)), "vs": 8.0, "hdg": float(item.get("hdg", 0.0)), "spd": 220.0,
		"type": String(item.get("type", "s320")), "airline": String(item.get("airline", "SKF")), "model": null, "phase": "airborne"})
	if airborne.size() > 14:
		_drop_airborne(airborne[0])


func _atc_call(icao: String, cs: String, atc_text: String, reply: String) -> void:
	var atc: Node = session.get("atc")
	if atc and atc.has_method("traffic_call"):
		atc.call("traffic_call", icao, cs, atc_text, reply)


# ================================================================== queries
func _player_on_runway(icao: String, end: Dictionary) -> bool:
	var ac: Aircraft = session.get("ac")
	if ac == null:
		return false
	var dir := Vector2(sin(deg_to_rad(float(end.hdg))), -cos(deg_to_rad(float(end.hdg))))
	var rel := Vector2(ac.world_x() - float(end.thr_x), ac.world_z() - float(end.thr_z))
	var along := rel.dot(dir)
	var lat := absf(rel.dot(Vector2(-dir.y, dir.x)))
	var on := along > -400.0 and along < float(end.len) + 100.0 and lat < float(end.wid) * 0.5 + 25.0
	return on and ac.ra < 60.0


func runway_busy(icao: String) -> bool:
	for item in moving:
		if item.icao != icao:
			continue
		if item.phase in ["lineup", "takeoff", "flare", "rollout"]:
			return true
		if item.phase == "final" and float(item.dist) < 1200.0:
			return true
	return false


func arrival_within(icao: String, secs: float) -> bool:
	for item in moving:
		if item.icao == icao and item.phase == "final":
			if float(item.dist) / maxf(float(item.speed), 40.0) < secs:
				return true
	return false


func traffic_list(px: float, pz: float, rng_m: float) -> Array:
	## Targets for TCAS and the navigation display.
	var out := []
	for item in moving:
		if item.has("x") and item.phase in ["final", "flare", "go_around", "climb"]:
			if U.dist2d(px, pz, float(item.x), float(item.z)) < rng_m:
				out.append({"x": item.x, "z": item.z, "alt": item.get("alt", 0.0), "vs": 0.0, "callsign": item.callsign})
	for a in airborne:
		if U.dist2d(px, pz, float(a.x), float(a.z)) < rng_m:
			out.append(a)
	return out


func add_evacuee(ac: Aircraft, p: Dictionary, door: Dictionary) -> void:
	if evacuee_sink.is_valid():
		evacuee_sink.call(p, door)
