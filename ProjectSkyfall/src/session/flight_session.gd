class_name FlightSession
extends Node3D
## Runs one flight from the gate to the gate: world, aircraft, flight deck and cabin, people,
## ground operations and the pushback tug, taxi guidance, ATC, AI traffic, events, checklists,
## the flight recorder, phases, approach monitoring, diversions, emergencies, walking (cabin and
## walkaround), the crash hand-off and the debrief.
## Modes: "pilot" (career or free flight), "passenger" (the AI crew flies, the player rides along).

signal finished(result: Dictionary)
signal phase_changed(phase: String)
signal toast(text: String, kind: String)

var params: Dictionary = {}
var mode := "pilot"
var view: WorldView
var ac: Aircraft
var cockpit: CockpitInterior
var cabin: CabinInterior
var people: CabinPeople
var rig: CameraRig
var atc: AtcController
var events: EventDirector
var checklists: Checklists
var recorder := FlightRecorder.new()
var hud: Node = null
var walker: CabinWalker = null
var _walk_hint := false
var ground_ops: GroundOps = null
var ai: AIPilot = null
var ai_taxi: AITaxi = null
var traffic: TrafficManager = null
var phase := "preflight"
var dep_icao := ""
var arr_icao := ""
var alt_icao := ""
var dep_end: Dictionary = {}
var arr_end: Dictionary = {}
var stand := ""
var arr_stand := ""
var taxi_path: Array = []
var taxi_ribbon: MeshInstance3D = null
var pushback_done := false
var pushback_active := false
var _push := {}
var turb_boost := 0.0
var wind_bias := 0.0
var windshear := 0.0
var icing_boost := 0.0
var crosswind_boost := 0.0
var slot_delay_min := 0
var emergency := ""
var diverted := false
var go_arounds := 0
var unstable_points := 0
var deviations: Array = []
var incidents: Array = []
var accepted_defects: Array = []
var touchdown: Dictionary = {}
var start_clock := 0.0
var sched_arr := 0.0
var fuel_planned := 0.0
var fuel_start := 0.0
var crash_info: Dictionary = {}
var aftermath: Dictionary = {}
var ended := false
var bridge_docked := false
var _phase_t := 0.0
var _stab_timer := 0.0
var _min_final_agl := 9999.0
var _rng := RandomNumberGenerator.new()
var _view_before_walk := "cockpit"
var _arrival_started := false
var _tug_requested := false
var flight_id := ""
var callsign := ""
var pax_seat := ""


func start(p: Dictionary) -> void:
	params = p
	mode = String(p.get("mode", "pilot"))
	flight_id = String(p.get("flight_id", "FREE-%d" % int(WorldSim.clock)))
	callsign = String(p.get("callsign", "Skyfall 123"))
	dep_icao = String(p.dep)
	arr_icao = String(p.get("arr", p.dep))
	_rng.seed = U.hash_str(flight_id)
	if p.has("clock"):
		WorldSim.clock = float(p.clock)
	start_clock = WorldSim.clock
	sched_arr = float(p.get("sched_arr", WorldSim.clock + 5400.0))
	WorldSim.sim_running = true
	if p.has("weather"):
		WeatherModel.override_preset = String(p.weather)
	_build_world()
	_spawn_aircraft()
	_setup_interiors()
	_setup_people()
	_setup_ops()
	_setup_camera_and_hud()
	recorder.mark("start", "Flight %s %s-%s" % [callsign, dep_icao, arr_icao])
	if mode == "passenger":
		_setup_passenger_mode()


# ================================================================== world and aircraft
func _build_world() -> void:
	var ap: Dictionary = Airports.get_ap(dep_icao)
	view = WorldView.new()
	view.name = "World"
	add_child(view)
	view.setup(float(ap.x), float(ap.z), WorldSim.clock, true)
	view.airports.ensure_loaded(dep_icao)
	dep_end = _runway_for(dep_icao, String(params.get("dep_rwy", "")), 0.0)
	arr_end = _runway_for(arr_icao, String(params.get("arr_rwy", "")), 3600.0)
	var aap: Dictionary = Airports.get_ap(arr_icao)
	alt_icao = Airports.nearest(float(aap.x), float(aap.z), arr_icao, 1500.0)


func _runway_for(icao: String, forced: String, t_ahead: float) -> Dictionary:
	if forced != "":
		var e := Airports.runway_end(icao, forced)
		if not e.is_empty():
			return e
	var ap: Dictionary = Airports.get_ap(icao)
	var w := WeatherModel.sample(float(ap.x), float(ap.z), WorldSim.clock + t_ahead)
	return Airports.best_runway(icao, float(w.get("wind_dir", 0.0)), float(w.get("wind_kt", 0.0)), 600.0)


func _spawn_aircraft() -> void:
	var type_id := String(params.get("type", "s320"))
	var airline := String(params.get("airline", "SKF"))
	var reg := String(params.get("reg", "CR-SFA"))
	ac = Aircraft.new()
	ac.name = "PlayerAircraft"
	view.dynamic_root.add_child(ac)
	ac.setup(type_id, reg, airline, view, true)
	ac.callsign = callsign
	ac.player_controlled = mode == "pilot"
	ac.laws.mode = String(Game.settings.get("assist", "assisted"))
	var spec := ac.spec
	var pax := int(params.get("pax", AircraftTypes.seat_count(type_id) * 8 / 10))
	var cargo := float(params.get("cargo", 1500.0 if spec.category != "cargo" else float(spec.max_payload) * 0.6))
	var dist := Airports.distance_m(dep_icao, arr_icao)
	var trip_h := dist / (float(spec.cruise_tas) * U.KT) / 3600.0
	var endurance_h := float(spec.range_nm) * U.NM / (float(spec.cruise_tas) * U.KT) / 3600.0
	var burn := float(spec.max_fuel) / maxf(endurance_h, 1.0)
	fuel_planned = clampf((trip_h + 0.75) * burn, float(spec.max_fuel) * 0.15, float(spec.max_fuel))
	var fuel := float(params.get("fuel", fuel_planned))
	ac.set_load(pax, cargo, fuel)
	fuel_start = fuel
	var start_kind := String(params.get("start", "gate"))
	var ap: Dictionary = Airports.get_ap(dep_icao)
	var L := AirportLayout.get_layout(dep_icao)
	if start_kind == "gate" and not L.stands.is_empty():
		var sd := AirportLayout.stand_by_name(L, String(params.get("stand", "")))
		if sd.is_empty():
			sd = AirportLayout.free_stand(L, float(spec.span), [], U.hash_str(flight_id))
		stand = sd.name
		var xf := _stand_pose(sd)
		ac.place_at(view.world_to_local(float(ap.x) + xf.x, float(ap.elev), float(ap.z) + xf.y), xf.z, true)
		ac.sys.setup(spec, fuel, true)
		ac.sys.parking_brake = true
		ac.sys.apu_on = spec.category != "trainer"
		ac.sys.ext_power = spec.category != "trainer"
		ac.throttle_lever = 0.0
		phase = "preflight"
		_dock_bridge()
	elif start_kind == "runway":
		var d := Vector3(sin(deg_to_rad(dep_end.hdg)), 0, -cos(deg_to_rad(dep_end.hdg)))
		var p := view.world_to_local(float(dep_end.thr_x), float(dep_end.elev), float(dep_end.thr_z)) + d * 60.0
		ac.place_at(p, float(dep_end.hdg), true)
		ac.sys.parking_brake = true
		for k in ["landing", "strobe", "beacon", "nav", "taxi"]:
			ac.sys.lights[k] = true
		ac.set_flaps(1 if spec.flaps.size() <= 4 else 2)
		phase = "lineup"
		pushback_done = true
	else:
		var alt := float(params.get("alt_ft", 6000.0)) * U.FT
		var dd := Vector2(sin(deg_to_rad(arr_end.hdg)), -cos(deg_to_rad(arr_end.hdg)))
		var pos2 := Vector2(arr_end.thr_x, arr_end.thr_z) - dd * float(params.get("dist_km", 40.0)) * 1000.0
		ac.place_at(view.world_to_local(pos2.x, alt, pos2.y), float(arr_end.hdg), false, minf(float(spec.cruise_ias), 250.0) * U.KT)
		view.rebase(ac.position)
		ac.ap.alt_sel = alt
		ac.ap.hdg_sel = float(arr_end.hdg)
		ac.ap.spd_sel = minf(float(spec.cruise_ias), 250.0)
		ac.ap.set_lat("HDG")
		ac.ap.set_vert("ALT")
		ac.ap.set_thr("SPD")
		ac.ap.at_engaged = true
		ac.ap.engage(true)
		for k2 in ["strobe", "beacon", "nav"]:
			ac.sys.lights[k2] = true
		phase = "cruise"
		pushback_done = true
	ac.touchdown.connect(_on_touchdown)
	ac.incident.connect(_on_incident)
	ac.crashed.connect(_on_crash)
	ac.liftoff.connect(func(): recorder.mark("liftoff", "Liftoff"))
	ac.ap.disconnected.connect(func(reason):
		if mode == "pilot" and String(reason) != "MANUAL LAND":
			toast.emit("Autopilot disconnected: %s" % reason, "caution"))
	ac.sys.alert.connect(func(_id, level, text):
		recorder.mark("alert", text)
		if level >= 2 and mode == "pilot":
			toast.emit(text, "warning"))


func _stand_pose(sd: Dictionary) -> Vector3:
	## Airport-local (x, z) and heading for a nose-in parked aircraft (nose ~7 m from the facade).
	var n: Vector2 = sd.normal
	var face: Vector2 = sd.get("facade_origin", sd.stop)
	var nose_gap := 7.0 + (2.0 if ac.spec.category == "widebody" else 0.0)
	var cg_from_nose := float(ac.spec.length) * float(ac.spec.cg_frac)
	var pos := face + n * (nose_gap + cg_from_nose)
	return Vector3(pos.x, pos.y, float(sd.hdg))


func _dock_bridge(icao: String = "") -> void:
	var airport := dep_icao if icao == "" else icao
	var av := view.airports.get_view(airport)
	var stand_name := stand if airport == dep_icao and icao == "" else arr_stand
	if av == null or ac.model == null or ac.spec.category in ["trainer", "turboprop", "bizjet"]:
		bridge_docked = false
		return
	var door := ac.model.door_world_local()
	var ap: Dictionary = Airports.get_ap(airport)
	var gp := ac.global_transform * door
	var local := Vector3(view.wx(gp) - float(ap.x), gp.y - float(ap.elev), view.wz(gp) - float(ap.z))
	bridge_docked = av.dock_bridge(stand_name, local)


func _undock_bridge() -> void:
	var av := view.airports.get_view(dep_icao)
	if av:
		av.undock_bridge(stand)
	bridge_docked = false


# ================================================================== interiors and people
func _setup_interiors() -> void:
	var q := String(Game.settings.get("quality", "high"))
	cockpit = CockpitInterior.new()
	ac.add_child(cockpit)
	cockpit.build(ac.type_id, ac.airline, q)
	cockpit.attach(ac)
	if AircraftTypes.is_passenger(ac.type_id) and ac.spec.category != "trainer":
		cabin = CabinInterior.new()
		ac.add_child(cabin)
		cabin.build(ac.type_id, ac.airline)
		if String(params.get("start", "gate")) == "gate":
			cabin.open_door(_boarding_door_name(), true)
			if ac.model:
				ac.model.set_door("L1", 1.0)


func _boarding_door_name() -> String:
	return "L2" if ac.spec.category == "turboprop" else "L1"


func _setup_people() -> void:
	if cabin == null:
		return
	var manifest := WorldSim.build_manifest(flight_id, dep_icao, arr_icao, ac.pax_count)
	var crew := []
	var r := U.rng(U.hash_str(flight_id + "crew"))
	for i in int(ac.spec.fa):
		var fa := Names.flight_attendant(r)
		fa.id = 900000 + U.hash_str(flight_id) % 50000 + i
		crew.append(fa)
	people = CabinPeople.new()
	people.name = "CabinPeople"
	ac.add_child(people)
	var lod := 0 if String(Game.settings.get("quality", "high")) in ["high", "ultra"] else 1
	people.setup(ac, manifest, crew, lod)
	people.crew_report.connect(func(t, k): toast.emit("Cabin: " + t, k))
	people.evacuee_out.connect(_on_evacuee_out)
	if String(params.get("start", "gate")) == "gate":
		people.flight_phase = "boarding"
		people.start_boarding(bool(params.get("instant_boarding", false)))
	else:
		people.start_boarding(true)
		people.flight_phase = "cruise"
	if mode == "passenger":
		var seat_id := String(params.get("seat", ""))
		var pick: Dictionary = {}
		if seat_id != "":
			for pp in people.pax:
				if String(pp.seat.id) == seat_id:
					pick = pp
					break
		if pick.is_empty() and not people.pax.is_empty():
			# by default a left window seat a third of the way back, ahead of the wing: the
			# terminal at the gate, the wing and engine in flight, the runway on the way down
			var zs: Array = people.pax.map(func(q): return float(q.seat.pos.z))
			var z_target := lerpf(float(zs.min()), float(zs.max()), 0.3)
			var best := INF
			for pp2 in people.pax:
				var st: Dictionary = pp2.seat
				var score := absf(float(st.pos.z) - z_target) + (0.0 if bool(st.get("window", false)) else 6.0) + (0.0 if float(st.pos.x) < 0.0 else 3.0)
				if score < best:
					best = score
					pick = pp2
		if not pick.is_empty():
			pax_seat = String(pick.seat.id)
			pick.state = "player"


func _setup_ops() -> void:
	checklists = Checklists.new(ac.spec.category)
	atc = AtcController.new()
	atc.name = "ATC"
	add_child(atc)
	var L2 := AirportLayout.get_layout(arr_icao)
	var arr_sd := AirportLayout.free_stand(L2, float(ac.spec.span), [], U.hash_str(flight_id + "arr"))
	arr_stand = String(arr_sd.get("name", ""))
	atc.setup(self, ac, {"callsign": callsign, "dep": dep_icao, "arr": arr_icao, "dep_end": dep_end, "arr_end": arr_end,
		"stand": stand, "arr_stand": arr_stand, "cruise_m": float(params.get("cruise_ft", _default_cruise_ft())) * U.FT,
		"route": params.get("route", _default_route()), "start": params.get("start", "gate"), "auto": mode == "passenger" or bool(Game.settings.get("auto_atc", false))})
	if mode == "passenger":
		atc.auto_atc = true
		atc.spoken = false
	atc.transmission.connect(func(st, _who, text): recorder.voice(st, text))
	atc.deviation.connect(_on_deviation)
	atc.cleared.connect(_on_atc_cleared)
	events = EventDirector.new()
	events.name = "Events"
	add_child(events)
	var ctx := {"flight_id": flight_id, "aircraft_record": WorldSim.aircraft(ac.reg), "weather": ac.weather,
		"block_hours": Airports.distance_m(dep_icao, arr_icao) / (float(ac.spec.cruise_tas) * U.KT) / 3600.0 + 0.4}
	if params.has("force_event"):
		ctx.force_event = params.force_event
	events.setup(self, ac, ctx)
	events.message.connect(func(t, k):
		toast.emit(t, k)
		recorder.mark("event", t))
	events.event_started.connect(func(ev):
		if float(ev.severity) >= 0.5:
			checklists.show_abnormal(_abnormal_for(String(ev.id))))
	ground_ops = GroundOps.new()
	ground_ops.name = "GroundOps"
	view.dynamic_root.add_child(ground_ops)
	ground_ops.setup(self, ac, view)
	if String(params.get("start", "gate")) == "gate":
		ground_ops.begin_turnaround(dep_icao, bridge_docked)
	traffic = TrafficManager.new()
	traffic.name = "Traffic"
	view.dynamic_root.add_child(traffic)
	traffic.setup(self, view)
	walker = CabinWalker.new()
	walker.name = "Walker"
	walker.setup(self, ac, view)
	ac.add_child(walker)
	if mode == "pilot":
		ac.ap.plan = _plan_for_fms()
		ac.ap.leg = 1


func _abnormal_for(id: String) -> String:
	match id:
		"engine_fire":
			return "eng_fire"
		"engine_failure", "bird_strike":
			return "eng_fail"
		"pressurization":
			return "cabin_alt"
		"smoke":
			return "smoke"
		"gear_unsafe":
			return "gear_unsafe"
	return ""


func _default_cruise_ft() -> float:
	var spec := ac.spec
	if spec.category == "trainer":
		return 4500.0
	var dist_nm := Airports.distance_nm(dep_icao, arr_icao)
	var ft := clampf(dist_nm * 180.0, 9000.0, float(spec.cruise_alt))
	return roundf(ft / 1000.0) * 1000.0


func _default_route() -> Array:
	var a := Vector2(dep_end.thr_x, dep_end.thr_z)
	var b := Vector2(arr_end.thr_x, arr_end.thr_z)
	var out := []
	var names := ["ORENA", "KALEX", "TUMBA", "VERIS", "MODAN", "PELIX"]
	var n := clampi(int(a.distance_to(b) / 60000.0), 1, 4)
	var d := Vector2(sin(deg_to_rad(dep_end.hdg)), -cos(deg_to_rad(dep_end.hdg)))
	var first := a + d * 15000.0
	out.append({"name": names[U.hash_str(dep_icao) % names.size()], "x": first.x, "z": first.y})
	for i in range(1, n + 1):
		var p := first.lerp(b, float(i) / (n + 1))
		out.append({"name": names[(U.hash_str(dep_icao + arr_icao) + i) % names.size()] + str(i), "x": p.x, "z": p.y})
	return out


func _plan_for_fms() -> Array:
	var plan := [{"name": dep_icao, "x": dep_end.thr_x, "z": dep_end.thr_z}]
	for w in params.get("route", _default_route()):
		plan.append(w)
	var dd := Vector2(sin(deg_to_rad(arr_end.hdg)), -cos(deg_to_rad(arr_end.hdg)))
	var faf := Vector2(arr_end.thr_x, arr_end.thr_z) - dd * 16000.0
	plan.append({"name": "FAF" + String(arr_end.name), "x": faf.x, "z": faf.y})
	plan.append({"name": "RW" + String(arr_end.name), "x": arr_end.thr_x, "z": arr_end.thr_z})
	ac.ap.set_approach(arr_end, 3.5 if arr_icao == "SKHP" else 3.0)
	return plan


func _setup_camera_and_hud() -> void:
	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	rig.setup(ac, view, cockpit.E if cockpit else Vector3(0, 1, -5))
	rig.walker = walker
	rig.avatar_look = SkinnedHuman.player_look(mode == "passenger")
	if mode == "passenger" and people:
		var pp := people.person_at_seat(pax_seat)
		if not pp.is_empty():
			rig.seat_local = people.seat_eye(pp)
			rig.set_mode("cabin")
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	layer.layer = 5
	add_child(layer)
	var hud_script: GDScript = load("res://src/ui/hud.gd")
	hud = hud_script.new()
	layer.add_child(hud)
	hud.call("setup", self)
	_update_interior_visibility()
	Audio.music(false)
	Audio.attach(ac, rig)
	if atc:
		atc.transmission.connect(func(_st, _who, _t): Audio.squelch())


func _setup_passenger_mode() -> void:
	ai = AIPilot.new()
	ai.setup(ac, dep_end, arr_end, float(params.get("cruise_ft", _default_cruise_ft())) * U.FT, params.get("route", _default_route()))
	ai.callout.connect(func(t): recorder.voice("FO", t))
	ai_taxi = AITaxi.new()
	ai_taxi.setup(self, ac)
	ac.player_controlled = false
	if String(params.get("start", "gate")) != "gate":
		# airborne or runway starts hand over to the crew straight away
		if phase == "cruise":
			ai.phase = "descent"
			ai.pattern_built = false
		else:
			ai.start_takeoff()


# ================================================================== per frame
func _process(delta: float) -> void:
	if ac == null or ended:
		return
	WorldSim.advance(delta)
	view.set_time(WorldSim.clock)
	if ac.position.length() > 2048.0:
		view.rebase(ac.position)
	_apply_event_effects(delta)
	_update_pushback(delta)
	_update_phase(delta)
	_update_cabin(delta)
	_update_interior_visibility()
	recorder.record(ac, phase, delta)
	if mode == "passenger" and not ac.crashed_state:
		_update_ai(delta)
	if traffic and cockpit and cockpit.canvas:
		cockpit.canvas.traffic = traffic.traffic_list(ac.world_x(), ac.world_z(), 60000.0)


func _apply_event_effects(delta: float) -> void:
	ac.extra_turb = turb_boost
	ac.wind_bias_kt = wind_bias
	ac.shear = windshear
	ac.crosswind_extra_kt = crosswind_boost
	if icing_boost > 0.0 and ac.in_cloud and not ac.sys.wing_anti_ice:
		ac.fdm.ice = minf(ac.fdm.ice + delta * 0.004 * icing_boost, 0.6)


func _update_phase(delta: float) -> void:
	_phase_t += delta
	if ac.crashed_state:
		return
	var n := ac.nav_state()
	var agl: float = ac.ra
	var prev := phase
	var gs: float = ac.fdm.ground_speed()
	var dist_arr := U.dist2d(n.x, n.z, arr_end.thr_x, arr_end.thr_z)
	match phase:
		"preflight":
			if gs > 0.6 or pushback_active:
				_set_phase("pushback" if pushback_active else "taxi_out")
		"pushback":
			if pushback_done and not pushback_active:
				_set_phase("taxi_out")
		"taxi_out", "lineup":
			if ac.fdm.on_ground and float(n.ias_kt) > 40.0 and _on_runway(n, dep_end):
				_set_phase("takeoff_roll")
		"takeoff_roll":
			if not ac.fdm.on_ground and agl > 3.0:
				_set_phase("initial_climb")
			elif float(n.ias_kt) < 25.0 and _phase_t > 10.0:
				_set_phase("taxi_out")
				recorder.mark("rejected", "Rejected takeoff")
		"initial_climb":
			if agl > 450.0:
				_set_phase("climb")
		"climb":
			var cruise := float(atc.cruise_m)
			if float(n.alt) > cruise - 150.0 or (absf(float(n.vs)) < 1.0 and _phase_t > 60.0 and float(n.alt) > cruise * 0.6):
				_set_phase("cruise")
		"cruise":
			if float(n.vs) < -3.0 and float(n.alt) < float(atc.cruise_m) - 600.0:
				_set_phase("descent")
		"descent":
			if dist_arr < 35000.0 and float(n.alt) < float(arr_end.elev) + 3000.0:
				_set_phase("approach")
		"approach":
			if agl < 330.0 and dist_arr < 12000.0:
				_set_phase("final")
				_min_final_agl = agl
		"final":
			_min_final_agl = minf(_min_final_agl, agl)
			_monitor_stability(n, agl, delta)
			if ac.fdm.on_ground:
				_set_phase("landing_roll")
			elif agl > _min_final_agl + 120.0 and float(n.vs) > 2.0:
				go_arounds += 1
				recorder.mark("go_around", "Go-around")
				_set_phase("approach")
		"landing_roll":
			if gs < 15.0:
				_set_phase("taxi_in")
		"taxi_in":
			if not _arrival_started:
				_arrival_started = true
				var L := AirportLayout.get_layout(arr_icao)
				ground_ops.begin_arrival(AirportLayout.stand_by_name(L, arr_stand), arr_icao)
			if ac.sys.parking_brake and gs < 0.3 and _near_arrival_stand():
				_set_phase("arrived")
		"arrived":
			if ac.sys.running_engines() == 0 and _phase_t > 3.0:
				_set_phase("deboarding")
				_start_deboarding()
	if phase != prev:
		events.phase_changed(_event_family(phase))


func _event_family(ph: String) -> String:
	match ph:
		"preflight", "pushback":
			return "gate"
		"takeoff_roll", "initial_climb":
			return "takeoff"
		"final":
			return "approach"
	return ph


func _set_phase(p: String) -> void:
	if p == phase:
		return
	_record_checklist_completion()
	phase = p
	_phase_t = 0.0
	recorder.mark("phase", p)
	phase_changed.emit(p)
	var idx := {"preflight": 0, "pushback": 0, "taxi_out": 2, "lineup": 2, "takeoff_roll": 2, "initial_climb": 3, "climb": 3,
		"descent": 4, "approach": 4, "final": 5, "landing_roll": 6, "taxi_in": 6, "arrived": 7, "deboarding": 7}
	if checklists and idx.has(p):
		var i: int = idx[p]
		if ac.spec.category == "trainer":
			i = {0: 0, 2: 2, 3: 3, 4: 4, 5: 4, 6: 5, 7: 5}.get(i, i)
		checklists.select(i)
	if p == "taxi_out" and ac.sys.running_engines() > 0 and checklists:
		checklists.select(1)
	_set_cabin_phase(p)


func _record_checklist_completion() -> void:
	if checklists == null:
		return
	var cl := checklists.current()
	if checklists.abnormal_id == "":
		checklists.completions[String(cl[0])] = checklists.fraction(String(cl[0]))


func _set_cabin_phase(p: String) -> void:
	if people == null:
		return
	match p:
		"pushback", "taxi_out":
			people.flight_phase = "taxi"
			if people._demo_t < 0.0 and not people.has_meta("demo_done"):
				people.set_meta("demo_done", true)
				people.start_safety_demo()
		"takeoff_roll", "initial_climb":
			people.flight_phase = "takeoff"
			if cabin:
				cabin.set_light_mode("takeoff")
		"climb":
			people.flight_phase = "climb"
		"cruise":
			people.flight_phase = "cruise"
			if cabin:
				cabin.set_light_mode("night" if view.night > 0.6 else "cruise")
			if not people.has_meta("service_done"):
				people.set_meta("service_done", true)
				people.start_service()
		"descent", "approach":
			people.flight_phase = "landing"
			people.crew_to_stations()
		"final":
			if cabin:
				cabin.set_light_mode("takeoff")
		"landing_roll", "taxi_in":
			people.flight_phase = "taxi"
			if cabin:
				cabin.set_light_mode("boarding")


func _monitor_stability(n: Dictionary, agl: float, delta: float) -> void:
	if agl > 300.0 or agl < 150.0:
		return
	_stab_timer += delta
	if _stab_timer < 1.0:
		return
	_stab_timer = 0.0
	var vref := float(ac.spec.vref)
	var ok := float(n.ias_kt) > vref - 5.0 and float(n.ias_kt) < vref + 25.0 and float(n.vs) > -5.6
	ok = ok and ac.sys.gear_down_cmd and ac.sys.flap_lever >= ac.spec.flaps.size() - 2
	if ac.ap.loc_valid:
		ok = ok and absf(ac.ap.loc_dev) < 1.2 and absf(ac.ap.gs_dev) < 1.0
	if not ok:
		unstable_points += 1


func _on_runway(n: Dictionary, e: Dictionary) -> bool:
	var d := Vector2(sin(deg_to_rad(e.hdg)), -cos(deg_to_rad(e.hdg)))
	var rel := Vector2(float(n.x) - float(e.thr_x), float(n.z) - float(e.thr_z))
	var along := rel.dot(d)
	return along > -50.0 and along < float(e.len) + 50.0 and absf(rel.dot(Vector2(-d.y, d.x))) < float(e.wid) * 0.5 + 5.0


func near_holding_point() -> bool:
	var L := AirportLayout.get_layout(dep_icao)
	var hold := AirportLayout.hold_node_for(L, String(dep_end.name))
	if hold < 0:
		return true
	var ap: Dictionary = Airports.get_ap(dep_icao)
	var hp: Vector2 = L.taxi_nodes[hold].pos
	return U.dist2d(ac.world_x(), ac.world_z(), float(ap.x) + hp.x, float(ap.z) + hp.y) < 140.0


func _near_arrival_stand() -> bool:
	var L := AirportLayout.get_layout(arr_icao)
	var ap: Dictionary = Airports.get_ap(arr_icao)
	var sd := AirportLayout.stand_by_name(L, arr_stand)
	if sd.is_empty():
		return false
	var pose := _stand_pose(sd)
	return U.dist2d(ac.world_x(), ac.world_z(), float(ap.x) + pose.x, float(ap.z) + pose.y) < 25.0


func _update_cabin(delta: float) -> void:
	if people == null:
		return
	people.seatbelt = bool(ac.sys.lights.get("seatbelt", false))
	if ac.turbulence > 0.25 and not ac.fdm.on_ground:
		people.on_turbulence(ac.turbulence, delta)
	if cabin:
		cabin.set_signs(people.seatbelt)
		cabin.smoke = maxf(cabin.smoke, ac.sys.cabin_smoke)


func _update_interior_visibility() -> void:
	if rig == null:
		return
	var m := rig.mode
	var in_cabin := m == "cabin" or (m == "walk" and walker != null and walker.where == "cabin")
	if cockpit:
		cockpit.visible = m in ["cockpit", "wing"] or (m == "walk" and walker != null and walker.where == "cabin")
	if cabin:
		cabin.visible = in_cabin
	if people:
		people.visible = in_cabin
	if ac.model:
		ac.model.show_exterior_fuselage(not (m == "cockpit" or in_cabin))
	view.set_interior(m == "cockpit" or in_cabin)


# ================================================================== views and walking
func set_view(m: String) -> void:
	if m == "cockpit" and mode == "passenger":
		m = "cabin"
	if m == "cabin" and cabin == null:
		m = "cockpit"
	if rig.mode == "walk":
		end_walk(m)
		return
	if m == "cabin" and people:
		var pp := people.person_at_seat(pax_seat) if pax_seat != "" else {}
		if pp.is_empty() and not people.pax.is_empty():
			pp = people.pax[clampi(people.pax.size() / 3, 0, people.pax.size() - 1)]
		if not pp.is_empty():
			rig.seat_local = people.seat_eye(pp)
	rig.set_mode(m)


func toggle_walk() -> void:
	if rig.mode == "walk":
		end_walk(_view_before_walk)
		return
	if not _walk_hint:
		_walk_hint = true
		toast.emit("Walking: V switches between first and third person.", "info")
	if cabin == null and not ac.fdm.on_ground:
		toast.emit("There is nowhere to walk on this aircraft.", "info")
		return
	_view_before_walk = rig.mode
	if cabin == null:
		walk_to_apron()
		return
	var lay := CabinLayout.get_layout(ac.type_id)
	var start := Vector3(0, float(lay.floor_y), float(lay.cockpit.back_z) + 0.8)
	if mode == "passenger" and people:
		var me := people.person_at_seat(pax_seat)
		if not me.is_empty():
			walker.enter_cabin(Vector3(me.seat.pos.x, float(lay.floor_y), me.seat.pos.z), PI)
			walker.sit(me.seat)
			walker.stand_up()
			rig.set_mode("walk")
			return
	walker.enter_cabin(start, PI)
	rig.set_mode("walk")


func end_walk(to_mode: String) -> void:
	if walker.where == "apron" and not ac.fdm.on_ground:
		return
	if walker.get_parent() != ac:
		walker.enter_cabin(Vector3.ZERO)
	if mode == "passenger":
		to_mode = "cabin"
	rig.set_mode(to_mode if to_mode != "walk" else "cockpit")
	if to_mode == "cabin" and people:
		var pp := people.person_at_seat(pax_seat)
		if not pp.is_empty():
			rig.seat_local = people.seat_eye(pp)


func walk_to_apron() -> void:
	## Steps out of the aircraft for the exterior walkaround (only on the ground at the stand).
	if not ac.fdm.on_ground or ac.fdm.ground_speed() > 0.5:
		toast.emit("You can only leave the aircraft when it is parked.", "caution")
		return
	var spec := ac.spec
	var L := float(spec.length)
	var nose := ac.global_transform * Vector3(-float(spec.fuse_w) * 0.5 - 3.0, -float(spec.gear_height), -L * float(spec.cg_frac) + 3.0)
	var fwd := -ac.global_transform.basis.z
	walker.exit_to_apron(nose, -fwd)
	if rig.mode != "walk":
		_view_before_walk = rig.mode
	rig.set_mode("walk")
	toast.emit("Exterior walkaround: inspect the marked areas around the aircraft (Space / interact).", "info")


func passenger_window() -> void:
	if people == null:
		return
	var pp := people.person_at_seat(pax_seat)
	if pp.is_empty():
		return
	rig.seat_local = people.seat_eye(pp)
	rig.set_mode("cabin")
	var side := signf(float(pp.seat.pos.x))
	rig.look_yaw = -75.0 * side if side != 0.0 else 75.0
	rig.look_pitch = -10.0


func dialogue_context() -> Dictionary:
	var n := ac.nav_state()
	var left := U.dist2d(n.x, n.z, float(arr_end.thr_x), float(arr_end.thr_z))
	var aap: Dictionary = Airports.get_ap(arr_icao)
	var w := WeatherModel.sample(float(aap.x), float(aap.z), WorldSim.clock)
	return {"phase": people.flight_phase if people else phase, "dep_city": Airports.get_ap(dep_icao).city,
		"arr_city": aap.city, "minutes_left": int(left / maxf(float(n.gs), 60.0) / 60.0),
		"arr_weather": WeatherModel.describe(w).to_lower(), "seatbelt": bool(ac.sys.lights.get("seatbelt", false)),
		"turbulence": ac.turbulence, "player_name": String(Game.player.get("first", "friend")) if Game.has_character() else "friend"}


func call_maintenance(finding: Dictionary) -> void:
	slot_delay_min += 25
	sched_arr += 25.0 * 60.0
	WorldSim.advance(25.0 * 60.0)
	var rec := WorldSim.aircraft(ac.reg)
	if finding.has("defect") and not rec.is_empty():
		rec.defects.erase(finding.defect)
	recorder.mark("maintenance", "Maintenance called: %s" % finding.get("text", ""))
	toast.emit("Engineers fixed the problem. 25 minutes delay.", "good")


func accept_defect(finding: Dictionary) -> void:
	accepted_defects.append(finding)
	recorder.mark("defect_accepted", "Accepted with: %s" % finding.get("text", ""))


# ================================================================== pushback and ground ops
func start_pushback() -> void:
	if pushback_active or pushback_done or _tug_requested:
		return
	var L := AirportLayout.get_layout(dep_icao)
	var sd := AirportLayout.stand_by_name(L, stand)
	if sd.is_empty() or ac.spec.category == "trainer":
		pushback_done = true
		return
	_tug_requested = true
	_undock_bridge()
	if cabin:
		cabin.open_door(_boarding_door_name(), false)
	if ac.model:
		ac.model.set_door("L1", 0.0)
	ground_ops.release_for_pushback()
	toast.emit("The doors are closed and armed. A tug is connecting for pushback." if mode == "passenger" else "Ground: tug connecting. Release the parking brake when cleared.", "info")
	ground_ops.call_tug(func(): _begin_push(sd))


func _begin_push(sd: Dictionary) -> void:
	var n: Vector2 = sd.normal
	var start := Vector2(ac.world_x(), ac.world_z())
	var back := float(ac.spec.length) * 0.8 + 22.0
	var mid := start + n * back
	var face_left := _rng.randf() < 0.5
	var axis: Vector2 = sd.axis * (1.0 if face_left else -1.0)
	var end := mid + axis * 18.0 + n * 8.0
	_push = {"t": 0.0, "dur": 55.0 + float(ac.spec.length) * 0.4, "p0": start, "p1": mid, "p2": end,
		"h0": float(ac.fdm.heading_deg()), "h2": fposmod(rad_to_deg(atan2(axis.x, -axis.y)), 360.0)}
	pushback_active = true
	ac.kinematic = true
	ac.sys.parking_brake = false
	recorder.mark("pushback", "Pushback started")
	toast.emit("We're moving backwards - pushback. The engines will spool up in a moment." if mode == "passenger" else "Pushback in progress - start the engines.", "info")


func _update_pushback(delta: float) -> void:
	if not pushback_active:
		return
	_push.t = float(_push.t) + delta
	var f := clampf(float(_push.t) / float(_push.dur), 0.0, 1.0)
	var e := U.smooth01(f)
	var p0: Vector2 = _push.p0
	var p1: Vector2 = _push.p1
	var p2: Vector2 = _push.p2
	# quadratic curve: straight back, then a swing to face along the taxi lane
	var q := p0.lerp(p1, e).lerp(p1.lerp(p2, e), e)
	var h := lerp_angle(deg_to_rad(float(_push.h0)), deg_to_rad(float(_push.h2)), smoothstep(0.35, 1.0, f))
	var y := Geo.ground_height(q.x, q.y)
	var lp := view.world_to_local(q.x, y, q.y)
	ac.fdm.set_attitude(rad_to_deg(h), 0.0, 0.0)
	ac.fdm.pos = lp + Vector3(0, float(ac.spec.gear_height) - 0.05, 0)
	ac.fdm.vel = Vector3.ZERO
	if f >= 1.0:
		pushback_active = false
		pushback_done = true
		ac.kinematic = false
		ac.sys.parking_brake = true
		ground_ops.disconnect_tug()
		recorder.mark("pushback", "Pushback complete")
		toast.emit("The tug pulls away and the ground crew waves us off." if mode == "passenger" else "Pushback complete. Tug disconnected - wait for the hand signal, then request taxi.", "info")
		_build_taxi_ribbon()


func _build_taxi_ribbon() -> void:
	## "Follow the greens": a glowing line along the cleared taxi route.
	if taxi_ribbon:
		taxi_ribbon.queue_free()
		taxi_ribbon = null
	if taxi_path.is_empty() or mode != "pilot":
		return
	var icao := dep_icao if phase in ["preflight", "pushback", "taxi_out"] else arr_icao
	var L := AirportLayout.get_layout(icao)
	var ap: Dictionary = Airports.get_ap(icao)
	var mb := MeshBuilder.new()
	var pts := []
	for step in taxi_path:
		var node: Dictionary = L.taxi_nodes[int(step.node)]
		var p: Vector2 = node.pos
		pts.append(Vector3(p.x, 0.07, p.y))
	var col := Color(0.25, 1.0, 0.4)
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var d := (b - a)
		if d.length() < 0.5:
			continue
		var side := Vector3(-d.z, 0, d.x).normalized() * 0.3
		mb.add_quad(a - side, b - side, b + side, a + side, col)
		mb.add_quad(a + side, b + side, b - side, a - side, col)
	taxi_ribbon = MeshInstance3D.new()
	taxi_ribbon.mesh = mb.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(1.6, 1.6, 1.6)
	taxi_ribbon.material_override = m
	taxi_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.static_root.add_child(taxi_ribbon)
	view.register_static(taxi_ribbon, float(ap.x), float(ap.elev), float(ap.z))


func _on_atc_cleared(kind: String) -> void:
	match kind:
		"pushback":
			if mode == "pilot":
				start_pushback()
		"taxi":
			_build_taxi_ribbon()
		"takeoff":
			recorder.mark("clearance", "Cleared for takeoff")
		"landing":
			recorder.mark("clearance", "Cleared to land")


func _start_deboarding() -> void:
	_dock_bridge(arr_icao)
	if cabin:
		cabin.open_door(_boarding_door_name(), true)
	if ac.model:
		ac.model.set_door("L1", 1.0)
	ground_ops.on_blocks(bridge_docked)
	toast.emit("On blocks at %s. Passengers are disembarking." % Airports.get_ap(arr_icao).short, "good")
	get_tree().create_timer(8.0).timeout.connect(func(): finish_flight("diverted" if diverted else "landed"))


# ================================================================== traffic queries (for ATC)
func runway_occupied(icao: String) -> bool:
	return traffic != null and traffic.runway_busy(icao)


func runway_traffic_soon(icao: String, secs: float) -> bool:
	return traffic != null and traffic.arrival_within(icao, secs)


# ================================================================== event hooks
func on_emergency_declared(kind: String, nearest: String) -> void:
	emergency = kind
	ac.sys.squawk = "7700"
	recorder.mark("emergency", "%s declared" % kind.to_upper())
	Engine.time_scale = 1.0
	if people:
		people.on_shock(0.3, "announcement")
	if nearest != "" and nearest != arr_icao and kind == "mayday":
		divert_to(nearest, "emergency")


func divert_nearest(reason: String) -> void:
	var near := Airports.nearest(ac.world_x(), ac.world_z(), "", 1400.0)
	if near != "":
		divert_to(near, reason)


func divert_alternate() -> void:
	if alt_icao != "":
		divert_to(alt_icao, "destination closed")


func divert_to(icao: String, reason: String) -> void:
	if icao == arr_icao or icao == "":
		return
	diverted = true
	arr_icao = icao
	arr_end = _runway_for(icao, "", 0.0)
	atc.arr = icao
	atc.arr_end = arr_end
	var L2 := AirportLayout.get_layout(icao)
	arr_stand = String(AirportLayout.free_stand(L2, float(ac.spec.span), [], 3).get("name", ""))
	atc.arr_stand = arr_stand
	ac.ap.plan = [{"name": "PPOS", "x": ac.world_x(), "z": ac.world_z()}, {"name": "RW" + String(arr_end.name), "x": arr_end.thr_x, "z": arr_end.thr_z}]
	ac.ap.leg = 1
	ac.ap.set_approach(arr_end, 3.5 if icao == "SKHP" else 3.0)
	if ai:
		ai.arr = arr_end
		ai.pattern_built = false
		if ai.phase == "cruise":
			ai._set_phase("descent")
	view.airports.ensure_loaded(icao)
	recorder.mark("divert", "Diverting to %s (%s)" % [icao, reason])
	toast.emit("Diverting to %s - %s." % [Airports.get_ap(icao).short, reason], "caution")


func place_storm_ahead() -> void:
	var fwd := -ac.global_transform.basis.z
	var ahead := Vector2(ac.world_x(), ac.world_z()) + Vector2(fwd.x, fwd.z).normalized() * 30000.0
	view.storm_cells.append({"x": ahead.x, "z": ahead.y, "r": 5200.0, "top": 12500.0})


func change_arrival_runway() -> void:
	for e in Airports.runway_ends(arr_icao):
		if e.name != arr_end.name and e.surface == "asphalt" and float(e.len) > 1500.0:
			arr_end = e
			atc.arr_end = e
			ac.ap.set_approach(e, 3.0)
			if ai:
				ai.arr = e
				ai.pattern_built = false
			return


func deploy_masks() -> void:
	if cabin:
		cabin.deploy_masks()
	if people:
		people.deploy_masks()


func on_seatbelt_sign(on: bool) -> void:
	if people:
		people.seatbelt = on


func call_cabin() -> void:
	var fear := people.average_fear() if people else 0.0
	var injured := 0
	if people:
		for p in people.pax:
			if String(p.get("injury", "")) in ["minor", "serious", "trapped"]:
				injured += 1
	toast.emit("Purser: " + Dialogue.purser_report(people.mood if people else 1.0, fear, injured, people.pax.size() if people else 0), "info")


func open_pa() -> void:
	if hud and hud.has_method("open_pa"):
		hud.call("open_pa")


func pa_announcement(kind: String) -> void:
	recorder.voice("PA", kind)
	Audio.play("chime", -8.0 if kind in ["welcome", "crew_seats", "turbulence"] else -2.0)
	var lines := {"welcome": "Good %s ladies and gentlemen, welcome aboard." % ("evening" if view.night > 0.5 else "morning"),
		"turbulence": "We're expecting some turbulence. Please return to your seats and fasten your seat belts.",
		"crew_seats": "Cabin crew, please prepare the cabin for landing.", "brace": "BRACE, BRACE, BRACE!",
		"evacuate": "EVACUATE, EVACUATE, EVACUATE!"}
	toast.emit("PA: " + String(lines.get(kind, kind)), "warning" if kind in ["brace", "evacuate"] else "info")
	if people == null:
		return
	match kind:
		"welcome":
			for p in people.pax:
				p.fear = maxf(float(p.fear) - 0.1, 0.0)
		"turbulence":
			ac.sys.lights.seatbelt = true
			people.seatbelt = true
			for p in people.pax:
				p.fear = maxf(float(p.fear) - 0.15, 0.0)
		"brace":
			people.set_brace(true)
		"crew_seats":
			people.crew_to_stations()
		"evacuate":
			command_evacuation()


func command_evacuation() -> void:
	if people == null or people.state == "evacuating":
		return
	if ac.fdm.ground_speed() > 3.0 and not ac.crashed_state:
		toast.emit("Stop the aircraft before evacuating!", "warning")
		return
	var blocked := {}
	if cabin:
		var fire_x := 0.0
		if bool(ac.damage.get("fire", false)) or bool(crash_info.get("fire", false)):
			fire_x = 1.0 if _rng.randf() < 0.5 else -1.0
		for d in cabin.lay.doors:
			var side := float(d.get("side", -1))
			if fire_x != 0.0 and signf(side) == fire_x and _rng.randf() < 0.7:
				blocked[d.name] = true
				continue
			cabin.open_door(String(d.name), true)
			if d.kind == "door" and bool(d.get("slide", false)):
				var gy := float(ac.ground_elev) - ac.global_position.y
				cabin.deploy_slide(String(d.name), gy, ac.surface == "water")
	people.set_brace(false)
	people.start_evacuation(blocked)
	recorder.mark("evacuation", "Evacuation commanded")


func _on_evacuee_out(p: Dictionary, door: Dictionary) -> void:
	if ground_ops:
		ground_ops.add_evacuee(p, door)


func any_door_open() -> bool:
	if cabin == null:
		return false
	for k in cabin.door_nodes.keys():
		if float(cabin.door_nodes[k].target) > 0.5:
			return true
	return false


func open_atc() -> void:
	if hud and hud.has_method("toggle_panel"):
		hud.call("toggle_panel", "atc")


func open_checklist() -> void:
	if hud and hud.has_method("toggle_panel"):
		hud.call("toggle_panel", "checklist")


func open_xpdr() -> void:
	if hud and hud.has_method("toggle_panel"):
		hud.call("toggle_panel", "atc")


func open_fms() -> void:
	if hud and hud.has_method("toggle_panel"):
		hud.call("toggle_panel", "fms")


# ================================================================== aircraft signals
func _on_touchdown(info: Dictionary) -> void:
	if touchdown.is_empty() or phase in ["final", "approach"]:
		touchdown = info
	recorder.mark("touchdown", "Touchdown %d fpm" % int(info.vs_fpm))
	var vs := absf(float(info.vs_fpm))
	if rig:
		rig.add_shake(clampf(vs / 500.0, 0.2, 2.5))
	if people:
		if vs > 500.0:
			people.on_shock(clampf((vs - 400.0) / 600.0, 0.2, 1.0), "hard landing")
		elif vs < 200.0 and _rng.randf() < 0.25:
			for p in people.pax:
				if _rng.randf() < 0.3:
					p.idle_pose = HumanMesh.POSES["sit_clap"]


func _on_incident(kind: String, _info: Dictionary) -> void:
	incidents.append(kind)
	recorder.mark("incident", kind)
	toast.emit({"hard_landing": "Hard landing", "tailstrike": "Tail strike!", "gear_collapse": "Landing gear collapsed!",
		"overstress": "Airframe overstressed", "wingstrike": "Wing strike!", "engine_strike": "Engine pod strike!",
		"belly_contact": "Fuselage contact with the ground", "breakup": "Structural failure"}.get(kind, kind), "warning")
	if kind in ["gear_collapse", "breakup"] and ac.fdm.on_ground and ground_ops:
		ground_ops.emergency_response(ac.global_position, false, 60.0)


func _on_deviation(kind: String, severity: float, text: String) -> void:
	deviations.append({"kind": kind, "severity": severity, "text": text, "clock": WorldSim.clock})
	recorder.mark("deviation", text)
	toast.emit("ATC: " + text, "caution")


func _on_crash(info: Dictionary) -> void:
	crash_info = info
	recorder.mark("crash", "Impact: %s" % String(info.get("cause_hint", "")))
	Engine.time_scale = 1.0
	if rig:
		rig.add_shake(3.0)
	if hud and hud.has_method("on_crash"):
		hud.call("on_crash", info)
	var aftermath_script: GDScript = load("res://src/session/crash_aftermath.gd")
	var aft: Node = aftermath_script.new()
	aft.name = "Aftermath"
	add_child(aft)
	aft.call("begin", self, info)


# ================================================================== passenger mode crew
func _update_ai(delta: float) -> void:
	if ai == null:
		return
	ai.cleared_alt = atc.clearance.alt_m if atc and phase in ["cruise", "descent", "approach"] else -1.0
	if phase == "preflight":
		var boarded := people == null or people.state == "seated"
		if boarded and _phase_t > 6.0 and not _tug_requested:
			ac.sys.lights.beacon = true
			ac.sys.lights.seatbelt = true
			ac.sys.lights.nav = true
			if people:
				people.seatbelt = true
			if atc.options.any(func(o): return o.id == "req_push"):
				atc.choose("req_push")
			start_pushback()
		return
	if pushback_active or (_tug_requested and not pushback_done):
		return
	if pushback_done and ac.sys.running_engines() < ac.sys.n_eng and ai.phase == "idle":
		for i in ac.sys.n_eng:
			var e: Dictionary = ac.sys.eng[i]
			if not bool(e.running) and not bool(e.starting):
				e.cutoff = false
				e.starting = true
				e.start_t = 0.0
		return
	if ai.phase == "idle":
		if ground_ops.tug_state == "leaving" and _phase_t < 25.0:
			return
		if ai_taxi.update_out(delta):
			ac.sys.lights.landing = true
			ac.sys.lights.strobe = true
			ai.start_takeoff()
	elif ai.phase == "landed":
		ai_taxi.update_in(delta)
		if ai_taxi.stage == "parked" and ac.sys.running_engines() > 0:
			ac.sys.lights.beacon = false
			ac.sys.lights.seatbelt = false
	else:
		ai.update(delta)


# ================================================================== end of flight
func _exit_tree() -> void:
	Audio.detach()


func _passenger_debrief(res: Dictionary, late: float) -> void:
	## Rates the trip from the seat: how it felt, how it ended, and what the people around said.
	var vs := absf(float(touchdown.get("vs_fpm", 0.0)))
	var g_hi := float(recorder.max_nz)
	var g_lo := float(recorder.min_nz)
	var bumps := events.history.filter(func(e): return String(e.id) in ["turbulence", "storm_route", "windshear", "icing"]).size()
	var smooth := clampf(100.0 - maxf(g_hi - 1.25, 0.0) * 120.0 - maxf(0.75 - g_lo, 0.0) * 120.0 - bumps * 8.0, 5.0, 100.0)
	var landing := clampf(100.0 - maxf(vs - 120.0, 0.0) * 0.12, 5.0, 100.0) if vs > 0.0 else 50.0
	var punctual := clampf(100.0 - maxf(late, 0.0) * 1.5, 0.0, 100.0)
	var cabin_mood := clampf((people.mood if people else 1.0) * 100.0, 0.0, 100.0)
	res.ratings = {"smoothness": smooth, "landing": landing, "punctuality": punctual, "cabin": cabin_mood}
	res.score = smooth * 0.3 + landing * 0.3 + punctual * 0.2 + cabin_mood * 0.2
	res.grade = "A" if res.score >= 88.0 else ("B" if res.score >= 75.0 else ("C" if res.score >= 60.0 else "D"))
	var notes := []
	if vs > 0.0:
		if vs < 180.0:
			notes.append("A feather-light touchdown - a few people actually applauded.")
		elif vs < 420.0:
			notes.append("A normal, positive landing.")
		elif vs < 650.0:
			notes.append("A firm landing that rattled the overhead bins.")
		else:
			notes.append("A hard landing. Several passengers gasped and a few bags fell from the bins.")
	if bumps > 0:
		notes.append("The flight was bumpy at times; the seat-belt sign came on %s." % ("once" if bumps == 1 else "%d times" % bumps))
	elif smooth > 90.0:
		notes.append("Smooth air all the way - drinks stayed in their cups.")
	if go_arounds > 0:
		notes.append("The crew went around %s before landing and explained it over the PA." % ("once" if go_arounds == 1 else "%d times" % go_arounds))
	if String(res.get("outcome", "")) == "diverted" or arr_icao != String(params.get("arr", arr_icao)):
		notes.append("The flight diverted to %s instead of %s." % [Airports.get_ap(arr_icao).name, Airports.get_ap(String(params.get("arr", arr_icao))).name])
	if late <= 5.0:
		notes.append("On time%s." % (" - even a few minutes early" if late < -3.0 else ""))
	else:
		notes.append("%d minutes late." % int(late))
	res.notes = notes
	var reviews := []
	if people and not people.pax.is_empty():
		var ctx := {"landing_fpm": vs, "late_min": late, "bumps": bumps, "go_arounds": go_arounds, "smooth": smooth,
			"arr_city": Airports.get_ap(arr_icao).city}
		var pool: Array = people.pax.filter(func(p): return String(p.get("state", "")) != "deceased")
		var picked := {}
		var said := {}
		for i in mini(12, pool.size()):
			if reviews.size() >= 4:
				break
			var p: Dictionary = pool[_rng.randi() % pool.size()]
			var line := Dialogue.review(p, ctx)
			if picked.has(p.get("id", 0)) or said.has(line):
				continue
			picked[p.get("id", 0)] = true
			said[line] = true
			reviews.append({"name": "%s %s" % [p.get("first", ""), String(p.get("last", "")).left(1) + "."], "age": int(p.get("age", 30)),
				"home": String(p.get("home", "")), "text": line})
	res.reviews = reviews


func _captain_name() -> String:
	## The player when they fly; otherwise the airline's captain for this flight (stable per flight).
	if mode == "pilot" and Game.has_character():
		return String(Game.player.get("name", "the captain"))
	var p := Names.person(U.rng(U.hash_str(flight_id + "captain")), 34, 60)
	return "%s %s" % [p.first, p.last]


func finish_flight(outcome: String) -> void:
	if ended:
		return
	ended = true
	_record_checklist_completion()
	var cls := []
	for k in checklists.completions.keys():
		cls.append(checklists.completions[k])
	var block_h := (WorldSim.clock - start_clock) / 3600.0
	var late := (WorldSim.clock - sched_arr) / 60.0
	var used := fuel_start - ac.sys.fuel_total()
	var fuel_ratio := used / maxf(fuel_planned * 0.7, 1.0)
	var rate := 60.0
	if Game.has_character():
		rate = CareerRules.pay_rate(String(Game.player.get("rank", "First Officer")), ac.airline)
	if mode == "passenger" or outcome in ["crashed", "ditched", "abandoned"]:
		rate = 0.0
	var res := FlightScoring.evaluate({
		"touchdown": touchdown, "recorder": recorder, "outcome": outcome, "unstable_points": unstable_points,
		"go_arounds": go_arounds, "checklists": cls, "deviations": deviations, "mood": people.mood if people else 1.0,
		"late_min": late, "fuel_ratio": fuel_ratio, "incidents": incidents, "events": events.history,
		"emergency_declared": emergency != "", "block_hours": block_h, "pay_rate": rate,
	})
	var walk_frac := walker.walkaround_fraction() if walker else 0.0
	res.merge({"flight_id": flight_id, "callsign": callsign, "type": ac.type_id, "reg": ac.reg, "airline": ac.airline,
		"dep": dep_icao, "arr": arr_icao, "planned_arr": String(params.get("arr", arr_icao)), "touchdown": touchdown,
		"events": events.history.map(func(e): return {"id": e.id, "label": e.label, "severity": e.severity, "choice": e.get("choice", "")}),
		"deviations": deviations, "incidents": incidents, "mode": mode, "clock": WorldSim.clock,
		"pax": people.pax.size() if people else 0, "mood": people.mood if people else 1.0,
		"recorder": recorder.export(), "crash": crash_info, "aftermath": aftermath, "max_g": recorder.max_nz,
		"weather": ac.weather, "fuel_planned": fuel_planned, "fuel_start": fuel_start, "accepted_defects": accepted_defects,
		"walkaround": walk_frac, "emergency_declared": emergency != "", "phase": phase, "late_min": late,
		"free_flight": bool(params.get("free_flight", false)), "aircraft_record": WorldSim.aircraft(ac.reg),
		"captain": _captain_name()}, true)
	if outcome in ["crashed", "ditched"] or not incidents.is_empty():
		var inv_in := res.duplicate()
		inv_in.fatalities = int(aftermath.get("counts", {}).get("fatal", 0))
		inv_in.checklists = cls
		inv_in.unstable_points = unstable_points
		if Game.has_character():
			inv_in.pilot_type_hours = float(Game.player.get("hours_by_type", {}).get(ac.type_id, 0.0))
		res.investigation = Investigation.analyse(inv_in)
	if mode == "passenger" and not outcome in ["crashed", "ditched"]:
		_passenger_debrief(res, late)
	WorldSim.sim_running = false
	WeatherModel.override_preset = ""
	Engine.time_scale = 1.0
	finished.emit(res)
