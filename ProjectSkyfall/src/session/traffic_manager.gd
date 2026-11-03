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
var _cross_t := 75.0
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


const DENSITY := {"off": [0.0, 0.0], "low": [300.0, 600.0], "normal": [110.0, 260.0], "busy": [45.0, 110.0]}


func _density() -> String:
	return String(Game.settings.get("air_traffic", "normal"))


func _spawn_encounter() -> void:
	## Another airliner on a course that brings it near the player: crossing, head-on, overtaking,
	## or (sometimes) a genuine collision course. Its crew usually reacts to TCAS and dodges, but
	## not always; the player can always steer into it.
	var ac: Aircraft = session.get("ac")
	if ac == null or ac.crashed_state or ac.fdm.on_ground or float(ac.ra) < 600.0:
		return
	var t := _type_for_span(80.0, ["narrowbody", "regional", "widebody"])
	var al := _airline_for(t, Airports.nearest(ac.world_x(), ac.world_z()))
	var lead := _rng.randf_range(60.0, 90.0)
	var my_v := ac.fdm.vel
	var my_hdg := fposmod(rad_to_deg(atan2(my_v.x, -my_v.z)), 360.0)
	var meet := Vector2(ac.world_x() + my_v.x * lead, ac.world_z() + my_v.z * lead)
	var spd := _rng.randf_range(220.0, 260.0)
	var roll := _rng.randf()
	var kind := "crossing"
	var hdg := fposmod(my_hdg + _rng.randf_range(55.0, 125.0) * (1.0 if _rng.randf() < 0.5 else -1.0), 360.0)
	var miss_m := _rng.randf_range(250.0, 1100.0)
	var dalt := _rng.randf_range(-250.0, 250.0)
	if roll < 0.3:
		kind = "head_on"
		hdg = fposmod(my_hdg + 180.0 + _rng.randf_range(-6.0, 6.0), 360.0)
		miss_m = _rng.randf_range(300.0, 900.0)
		dalt = _rng.randf_range(250.0, 330.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
	elif roll < 0.45:
		kind = "overtake"
		hdg = fposmod(my_hdg + _rng.randf_range(-4.0, 4.0), 360.0)
		spd = my_v.length() / U.KT + _rng.randf_range(45.0, 80.0)
		miss_m = _rng.randf_range(150.0, 500.0)
		dalt = _rng.randf_range(-120.0, 120.0)
		lead = 80.0
	if _rng.randf() < (0.3 if _density() == "busy" else 0.18):
		kind += "_conflict"
		miss_m = _rng.randf_range(0.0, 60.0)
		dalt = _rng.randf_range(-40.0, 40.0)
	var d := Vector2(sin(deg_to_rad(hdg)), -cos(deg_to_rad(hdg)))
	var start: Vector2
	if kind.begins_with("overtake"):
		# comes up from behind, faster, and passes alongside
		var meet2 := Vector2(ac.world_x() + my_v.x * lead, ac.world_z() + my_v.z * lead)
		start = meet2 + Vector2(-d.y, d.x) * miss_m - d * spd * U.KT * lead
	else:
		start = meet + Vector2(-d.y, d.x) * miss_m * (1.0 if _rng.randf() < 0.5 else -1.0) - d * spd * U.KT * lead
	var alt := ac.fdm.pos.y + dalt
	var cs := _callsign(al)
	var item := {"callsign": cs, "x": start.x, "z": start.y, "alt": alt, "vs": 0.0, "hdg": hdg, "spd": spd, "type": t, "airline": al, "model": null,
		"phase": "airborne", "hdg_t": hdg, "alt_t": alt, "bank": 0.0, "react": _rng.randf() < 0.75, "tcas": false, "kind": kind, "called": false, "man_t": 400.0}
	airborne.append(item)
	if airborne.size() > 16:
		_drop_airborne(airborne[0])


func _advise(a: Dictionary, me: Aircraft) -> void:
	## "Traffic, two o'clock, five miles, crossing left to right, one thousand feet above."
	a.called = true
	var rel := Vector2(float(a.x) - me.world_x(), float(a.z) - me.world_z())
	var brg := rad_to_deg(atan2(rel.x, -rel.y))
	var clock := int(round(fposmod(brg - me.fdm.heading_deg(), 360.0) / 30.0)) % 12
	if clock == 0:
		clock = 12
	var nm := rel.length() / 1852.0
	var dft := (float(a.alt) - me.fdm.pos.y) / U.FT
	var vert := "same altitude" if absf(dft) < 300.0 else ("%s feet %s" % [U.fmt_int(int(round(absf(dft) / 100.0) * 100)), "above" if dft > 0.0 else "below"])
	var dh := wrapf(float(a.hdg) - me.fdm.heading_deg(), -180.0, 180.0)
	var motion := "opposite direction" if absf(dh) > 150.0 else ("same direction" if absf(dh) < 30.0 else ("crossing right to left" if dh < 0.0 else "crossing left to right"))
	var spec := AircraftTypes.get_type(String(a.type))
	var my_cs := String(session.get("callsign")) if session.get("callsign") != null else "Skyfall"
	var txt := "%s, traffic, %d o'clock, %d miles, %s, %s, a %s." % [my_cs, clock, maxi(int(round(nm)), 1), motion, vert, String(spec.get("short", "jet"))]
	var atc: Node = session.get("atc")
	if atc and atc.has_method("traffic_advisory"):
		atc.call("traffic_advisory", txt, txt)
	if session.has_signal("toast"):
		session.toast.emit("ATC: " + txt, "caution")


func _fly_airborne(a: Dictionary, me: Aircraft, delta: float) -> void:
	## Simple AI pilots: hold course and level, occasionally turn or change level, and answer a
	## TCAS resolution advisory by climbing or descending away from the player.
	if not a.has("hdg_t"):
		a.hdg_t = float(a.hdg)
		a.alt_t = float(a.alt)
		a.bank = 0.0
		a.react = _rng.randf() < 0.75
		a.tcas = false
		a.man_t = _rng.randf_range(60.0, 240.0)
	var dist := 1e9
	if me != null and not me.crashed_state:
		var rel := Vector3(float(a.x) - me.world_x(), float(a.alt) - me.fdm.pos.y, float(a.z) - me.world_z())
		dist = rel.length()
		var av := item_velocity(a)
		var closing := rel.dot(av - me.fdm.vel) < 0.0
		if not bool(a.get("called", true)) and closing and dist < 14000.0 and dist > 3000.0:
			_advise(a, me)
		if bool(a.react) and not bool(a.tcas) and closing and dist < 2800.0 and absf(rel.y) < 320.0:
			a.tcas = true
			var up := rel.y > 0.0 or (absf(rel.y) < 30.0 and _rng.randf() < 0.5)
			a.alt_t = float(a.alt) + (350.0 if up else -350.0)
			a.vs = 4.0 if up else -4.0
	a.man_t = float(a.man_t) - delta
	if float(a.man_t) <= 0.0 and dist > 9000.0:
		a.man_t = _rng.randf_range(90.0, 300.0)
		if _rng.randf() < 0.6:
			a.hdg_t = fposmod(float(a.hdg) + _rng.randf_range(-45.0, 45.0), 360.0)
		else:
			a.alt_t = clampf(float(a.alt) + _rng.randf_range(-900.0, 900.0), 1500.0, 12000.0)
	var dh := wrapf(float(a.hdg_t) - float(a.hdg), -180.0, 180.0)
	var rate := 2.0
	a.hdg = fposmod(float(a.hdg) + clampf(dh, -rate * delta, rate * delta), 360.0)
	a.bank = move_toward(float(a.bank), clampf(dh * 1.5, -25.0, 25.0), delta * 6.0)
	var vs_t := clampf((float(a.alt_t) - float(a.alt)) * 0.06, -12.0 if bool(a.tcas) else -9.0, 12.0 if bool(a.tcas) else 9.0)
	a.vs = move_toward(float(a.vs), vs_t, delta * (3.0 if bool(a.tcas) else 1.2))
	var d := Vector2(sin(deg_to_rad(float(a.hdg))), -cos(deg_to_rad(float(a.hdg))))
	a.x = float(a.x) + d.x * float(a.spd) * U.KT * delta
	a.z = float(a.z) + d.y * float(a.spd) * U.KT * delta
	a.alt = clampf(float(a.alt) + float(a.vs) * delta, 600.0, 12500.0)


func _contrail() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Contrail"
	p.amount = 160
	p.lifetime = 14.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-4000, -400, -4000), Vector3(8000, 800, 8000))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 3.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 1.0
	pm.gravity = Vector3.ZERO
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(8.0, 0.5, 1.0)
	pm.scale_min = 3.0
	pm.scale_max = 4.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(1, 3.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.75))
	grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(3.0, 3.0)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = GroundOps._soft_dot()
	q.material = m
	p.draw_pass_1 = q
	p.position = Vector3(0, 0, 8.0)
	return p


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
	var dens: Array = DENSITY.get(_density(), DENSITY.normal)
	_cross_t -= delta
	if _cross_t <= 0.0:
		_cross_t = _rng.randf_range(float(dens[0]), float(dens[1])) if float(dens[1]) > 0.0 else 1e9
		if float(dens[1]) > 0.0:
			_spawn_encounter()
	var me: Aircraft = session.get("ac")
	var built_one := false
	for a in airborne.duplicate():
		_fly_airborne(a, me, delta)
		# draw the ones close to the player (one new model per frame at most)
		if me == null:
			continue
		var dist := Vector3(float(a.x) - me.world_x(), float(a.alt) - me.fdm.pos.y, float(a.z) - me.world_z()).length()
		var m = a.get("model")
		if m == null and dist < 9000.0 and not built_one and a.has("type"):
			a.model = _make_model(String(a.type), String(a.airline))
			(a.model as Node3D).add_child(_contrail())
			built_one = true
			m = a.model
		elif m != null and dist > 11000.0:
			(m as Node).queue_free()
			a.model = null
			continue
		if m != null and is_instance_valid(m):
			var am: AircraftModel = m
			am.position = view.world_to_local(float(a.x), float(a.alt), float(a.z))
			am.basis = _basis(float(a.hdg), clampf(float(a.vs) * 0.5, -4.0, 8.0) + 2.0, float(a.bank))
			var cn := am.get_node_or_null("Contrail") as GPUParticles3D
			if cn:
				cn.emitting = float(a.alt) > 7600.0
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
