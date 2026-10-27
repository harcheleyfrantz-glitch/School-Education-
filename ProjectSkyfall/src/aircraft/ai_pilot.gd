class_name AIPilot
extends RefCounted
## Flies an aircraft through a complete profile: takeoff, climb, cruise along a route, descent,
## vectors to the ILS, approach, flare, landing and rollout. Used for passenger flights, AI
## crews, autoland training and automated testing. Handles basic failures conservatively.

signal phase_changed(phase: String)
signal callout(text: String)

var ac: Aircraft
var phase := "idle"
var dep: Dictionary = {}          # runway end (Airports.runway_end format)
var arr: Dictionary = {}
var cruise_alt := 3000.0          # metres
var route: Array = []             # [{name, x, z}]
var t_phase := 0.0
var flown_callouts := {}
var pattern_built := false
var allow_autoland := true
var takeoff_flaps := 1
var go_around_count := 0
var _faf_leg := 99


func setup(aircraft: Aircraft, dep_end: Dictionary, arr_end: Dictionary, cruise_alt_m: float, waypoints: Array = []) -> void:
	ac = aircraft
	dep = dep_end
	arr = arr_end
	cruise_alt = cruise_alt_m
	route = waypoints
	var nflaps: int = ac.spec.flaps.size()
	takeoff_flaps = 1 if nflaps <= 4 else 2
	if ac.spec.category == "trainer":
		takeoff_flaps = 1


func _set_phase(p: String) -> void:
	if p != phase:
		phase = p
		t_phase = 0.0
		phase_changed.emit(p)


func start_takeoff() -> void:
	ac.set_flaps(takeoff_flaps)
	ac.sys.ground_spoilers_armed = bool(ac.spec.spoilers)
	ac.sys.autobrake = 4 if ac.spec.category != "trainer" else 0
	ac.sys.parking_brake = false
	ac.sys.lights.landing = true
	ac.sys.lights.strobe = true
	ac.ap.set_approach(dep)
	ac.ap.set_lat("RWY")
	ac.ap.at_engaged = false
	ac.ap.engage(false)
	_set_phase("takeoff_roll")


func update(dt: float) -> void:
	if ac == null or ac.crashed_state:
		return
	t_phase += dt
	var n := ac.nav_state()
	var spec: Dictionary = ac.spec
	var ias: float = n.true_ias_kt
	var agl: float = ac.ra
	match phase:
		"takeoff_roll":
			ac.throttle_lever = move_toward(ac.throttle_lever, 1.0 if spec.category != "trainer" else 1.0, dt * 0.5)
			# centreline tracking with rudder/nose wheel, wings level
			ac.ap.update(dt, n, ac.fdm, ac.sys)
			ac.in_yaw = ac.ap.out_rudder
			ac.in_roll = clampf(-n.bank * 0.05, -0.3, 0.3)
			ac.in_pitch = 0.0
			if ias > float(spec.vr):
				_callout("Rotate")
				_set_phase("rotate")
		"rotate":
			ac.ap.update(dt, n, ac.fdm, ac.sys)
			ac.in_yaw = ac.ap.out_rudder * 0.5
			var target := float(spec.get("tailstrike", 11.0)) - 2.5 if spec.category != "trainer" else 8.0
			# aim for a steady ~2.5 deg/s rotation, easing off before the tail gets close
			var q_deg := rad_to_deg(ac.fdm.omega.x)
			var want_q := 2.5 if n.pitch < target - 1.5 else 0.6
			if n.pitch >= target:
				want_q = 0.0
			ac.in_pitch = clampf(0.25 + (want_q - q_deg) * 0.12, -0.5, 0.8)
			ac.in_roll = clampf(-n.bank * 0.05, -0.3, 0.3)
			if agl > 6.0 and n.vs > 1.0:
				_callout("Positive rate")
				_set_phase("initial_climb")
				ac.laws.reset_to_current(ac.fdm)
				ac.ap.set_approach({})
		"initial_climb":
			ac.in_yaw = 0.0
			if bool(spec.gear_retract) and ac.sys.gear_down_cmd and agl > 15.0:
				ac.toggle_gear()
				_callout("Gear up")
			# hold climb attitude with the flight director until the autopilot is engaged
			var v2 := float(spec.v2)
			var tgt_pitch := clampf(14.0 + (ias - (v2 + 12.0)) * 0.3, 6.0, 17.0) if spec.category != "trainer" else clampf(8.0 + (ias - 75.0) * 0.3, 2.0, 10.0)
			ac.laws.target_pitch = move_toward(ac.laws.target_pitch, tgt_pitch, 1.5 * dt)
			ac.laws.target_bank = move_toward(ac.laws.target_bank, 0.0, 2.0 * dt)
			ac.in_pitch = 0.0
			ac.in_roll = 0.0
			if agl > 120.0 and bool(spec.autopilot):
				ac.ap.hdg_sel = dep.hdg
				ac.ap.alt_sel = cruise_alt
				ac.ap.spd_sel = minf(float(spec.climb_ias), 250.0)
				ac.ap.out_pitch = n.pitch
				ac.ap.out_bank = n.bank
				ac.ap.set_lat("HDG")
				ac.ap.set_vert("TOGA")
				ac.ap.at_engaged = true
				ac.ap.set_thr("TOGA")
				ac.ap.out_throttle = ac.throttle_lever
				ac.ap.engage(true)
				ac.in_pitch = 0.0
				ac.in_roll = 0.0
				_set_phase("climb")
		"climb":
			_flap_retraction(ias)
			if agl > 450.0 and ac.ap.vert_mode == "TOGA":
				ac.ap.set_vert("FLCH")
				ac.ap.set_thr("CLB")
			if not route.is_empty() and ac.ap.lat_mode == "HDG" and agl > 300.0:
				_activate_route(n)
			var spd := float(spec.climb_ias)
			if n.alt < 3050.0:
				spd = minf(spd, 250.0)
			ac.ap.spd_sel = spd
			if spec.mmo > 0.0 and n.mach > float(spec.mmo) - 0.05:
				ac.ap.use_mach = true
				ac.ap.mach_sel = float(spec.mmo) - 0.04
			if absf(n.alt - cruise_alt) < 60.0:
				_set_phase("cruise")
				ac.ap.set_vert("ALT")
				ac.ap.set_thr("SPD")
		"cruise":
			_flap_retraction(ias)
			if ac.ap.use_mach:
				ac.ap.mach_sel = float(spec.mmo) - 0.04
			else:
				ac.ap.spd_sel = float(spec.cruise_ias) if n.alt > 3100.0 else minf(float(spec.cruise_ias), 250.0)
			var dist := _dist_to_arr(n)
			var need = (n.alt - (float(arr.elev) + 900.0)) / tan(deg_to_rad(2.8)) + 18000.0
			if dist < need:
				_set_phase("descent")
				ac.ap.alt_sel = float(arr.elev) + 900.0
				ac.ap.use_mach = false
				ac.ap.spd_sel = float(spec.descent_ias)
				ac.ap.set_vert("FLCH")
				ac.ap.set_thr("IDLE")
		"descent":
			if n.alt < 3300.0:
				ac.ap.spd_sel = minf(float(spec.descent_ias), 250.0)
			if not pattern_built:
				_build_approach_route(n)
			var dist2 := _dist_to_arr(n)
			if dist2 < 28000.0:
				ac.ap.spd_sel = minf(ac.ap.spd_sel, 210.0 if spec.category != "trainer" else 90.0)
			if ac.ap.vert_mode == "ALT" and dist2 < 40000.0:
				_set_phase("approach")
		"approach":
			_approach_config(n, ias)
			if ac.ap.lat_mode == "LNAV" and ac.ap.leg >= _faf_leg and not ac.ap.arm_loc:
				ac.ap.arm_loc = true
				ac.ap.arm_gs = true
			if ac.ap.lat_mode == "LOC" and ac.ap.vert_mode == "GS":
				_set_phase("final")
		"final":
			_approach_config(n, ias)
			if agl < 300.0 and not flown_callouts.has("1000"):
				_callout("One thousand")
				flown_callouts["1000"] = true
			# stabilised-approach gate between 1000 ft and 100 ft above the runway
			if agl < 300.0 and agl > 30.0 and not _stable(n):
				_go_around()
				return
			if not bool(spec.autoland) or not allow_autoland:
				if agl < 60.0:
					ac.ap.engage(false, "MANUAL LAND")
					_set_phase("manual_flare")
			elif ac.ap.vert_mode == "ROLLOUT":
				_set_phase("rollout")
		"manual_flare":
			# hand flare for aircraft without autoland
			var flare_h := 9.0 if spec.category != "trainer" else 5.0
			var vs_t := -3.5 if agl > flare_h else -maxf(agl * 0.35, 0.5)
			var gamma := rad_to_deg(asin(clampf(vs_t / maxf(ac.fdm.tas, 30.0), -0.3, 0.3)))
			ac.laws.target_pitch = clampf(gamma + rad_to_deg(ac.fdm.alpha), -5.0, 12.0)
			ac.in_pitch = clampf((ac.laws.target_pitch - n.pitch) * 0.05, -0.4, 0.4)
			ac.in_roll = clampf(-n.bank * 0.05, -0.3, 0.3)
			if agl < 10.0:
				ac.throttle_lever = move_toward(ac.throttle_lever, 0.0, dt * 0.6)
			if ac.fdm.wow[1] or ac.fdm.wow[2]:
				_set_phase("rollout")
				ac.ap.set_lat("ROLLOUT")
		"rollout":
			ac.throttle_lever = 0.0
			if ac.ap.at_engaged:
				ac.ap.at_engaged = false
			ac.ap.update(dt, n, ac.fdm, ac.sys)
			ac.in_yaw = ac.ap.out_rudder
			ac.in_pitch = -0.2
			ac.in_roll = 0.0
			ac.sys.reverse_cmd = ias > 70.0 and bool(spec.reverser)
			if ac.sys.autobrake == 0 or ac.spec.category == "trainer":
				ac.sys.brake_input = 0.6 if ias < 100.0 else 0.3
			if ias < 30.0:
				ac.sys.reverse_cmd = false
				ac.sys.brake_input = 0.4
				if ac.ap.engaged:
					ac.ap.engage(false, "ROLLOUT COMPLETE")
			if ac.fdm.ground_speed() < 8.0:
				ac.sys.brake_input = 0.0
				_set_phase("landed")
		"go_around":
			ac.throttle_lever = 1.0
			if ac.sys.flap_lever > takeoff_flaps + 1:
				ac.set_flaps(ac.sys.flap_lever - 1)
			if ac.ra > 20.0 and ac.sys.gear_down_cmd and n.vs > 2.0:
				ac.toggle_gear()
			if n.alt > float(arr.elev) + 400.0:
				pattern_built = false
				_set_phase("descent")
				ac.ap.alt_sel = float(arr.elev) + 900.0
				ac.ap.set_vert("FLCH")
				ac.ap.set_thr("SPD")


func _stable(n: Dictionary) -> bool:
	var ias: float = n.true_ias_kt
	var vapp := float(ac.spec.vapp)
	return absf(ac.ap.loc_dev) < 1.5 and absf(ac.ap.gs_dev) < 1.0 and n.vs > -7.5 and ias > vapp - 12.0 and ias < vapp + 25.0


func _go_around() -> void:
	go_around_count += 1
	_callout("Go around, flaps")
	ac.ap.arm_gs = false
	ac.ap.arm_loc = false
	ac.ap.set_vert("TOGA")
	ac.ap.set_thr("TOGA")
	ac.ap.alt_sel = float(arr.elev) + 900.0
	ac.ap.hdg_sel = arr.hdg
	ac.ap.set_lat("HDG")
	if not ac.ap.engaged:
		ac.ap.out_pitch = ac.fdm.pitch_deg()
		ac.ap.out_bank = ac.fdm.bank_deg()
		ac.ap.engage(true)
	_set_phase("go_around")


func _flap_retraction(ias: float) -> void:
	var flaps: Array = ac.spec.flaps
	var idx := ac.sys.flap_lever
	if idx > 0 and ac.ra > 300.0:
		var vfe_next := float(flaps[idx - 1].vfe) if idx - 1 > 0 else 999.0
		var min_spd := float(ac.spec.vref) + 15.0 * (flaps.size() - idx)
		if ias > min_spd and ias < vfe_next + 40.0:
			ac.set_flaps(idx - 1)


func _approach_config(n: Dictionary, ias: float) -> void:
	var spec: Dictionary = ac.spec
	var flaps: Array = spec.flaps
	var nf := flaps.size()
	var dtg := ac.ap.distance_to_go(n)
	if ac.ap.lat_mode == "LOC":
		dtg = maxf(ac.ap.dist_thr, 0.0)
	# configuration follows progress along the approach, not straight-line distance
	var tgt_flap := 0
	var spd := 220.0
	if dtg < 32000.0:
		tgt_flap = 1
		spd = minf(float(flaps[1].vfe) - 15.0, 205.0)
	if dtg < 24000.0:
		tgt_flap = mini(2, nf - 1)
		spd = float(flaps[tgt_flap].vfe) - 15.0
	var gs_alive := ac.ap.vert_mode == "GS" or ac.ap.vert_mode == "FLARE"
	if dtg < 15000.0 or gs_alive:
		tgt_flap = maxi(tgt_flap, nf - 2)
		spd = float(flaps[tgt_flap].vfe) - 12.0
		if ac.sys.gear_down_cmd == false and bool(spec.gear_retract):
			ac.toggle_gear()
			_callout("Gear down")
	if dtg < 9000.0 and gs_alive:
		tgt_flap = nf - 1
		spd = float(spec.vapp)
	spd = maxf(spd, float(spec.vapp))
	if spec.category == "trainer":
		spd = 90.0 if dtg > 5000.0 else float(spec.vapp)
	var lever := ac.sys.flap_lever
	if lever < tgt_flap and ias < float(flaps[lever + 1].vfe) - 3.0:
		ac.set_flaps(lever + 1)
	elif lever > tgt_flap and ias > float(spec.vref) + 15.0 * (nf - lever):
		ac.set_flaps(lever - 1)
	ac.ap.spd_sel = spd
	ac.ap.set_thr("SPD")
	ac.sys.ground_spoilers_armed = bool(spec.spoilers)
	ac.sys.autobrake = 2 if spec.category != "trainer" else 0
	ac.sys.lights.landing = n.alt < float(arr.elev) + 3000.0


func _dist_to_arr(n: Dictionary) -> float:
	return U.dist2d(n.x, n.z, arr.thr_x, arr.thr_z)


func _activate_route(_n: Dictionary) -> void:
	var plan := [{"name": "DEP", "x": dep.thr_x, "z": dep.thr_z}]
	for w in route:
		plan.append(w)
	ac.ap.plan = plan
	ac.ap.leg = 1
	ac.ap.set_lat("LNAV")


func _build_approach_route(n: Dictionary) -> void:
	## Straight-in or a simple downwind/base pattern ending 14 km out on the extended centreline.
	pattern_built = true
	var d := Vector2(sin(deg_to_rad(arr.hdg)), -cos(deg_to_rad(arr.hdg)))
	var thr := Vector2(arr.thr_x, arr.thr_z)
	var faf := thr - d * 16000.0
	var iaf := thr - d * 26000.0
	var p := Vector2(n.x, n.z)
	var plan := [{"name": "PPOS", "x": p.x, "z": p.y}]
	var to_faf := (faf - p)
	var behind := (p - thr).dot(-d) > 12000.0
	if not behind or absf((p - thr).dot(Vector2(-d.y, d.x))) > 18000.0:
		var side := signf((p - thr).dot(Vector2(-d.y, d.x)))
		if side == 0.0:
			side = 1.0
		var dw := thr - d * 4000.0 + Vector2(-d.y, d.x) * side * 9000.0
		var base := iaf + Vector2(-d.y, d.x) * side * 9000.0
		if (p - thr).dot(-d) < 0.0:
			plan.append({"name": "DWND", "x": dw.x, "z": dw.y})
		plan.append({"name": "BASE", "x": base.x, "z": base.y})
	plan.append({"name": "IAF", "x": iaf.x, "z": iaf.y})
	plan.append({"name": "FAF", "x": faf.x, "z": faf.y})
	plan.append({"name": "RW" + String(arr.name), "x": thr.x, "z": thr.y})
	var _u := to_faf
	ac.ap.plan = plan
	ac.ap.leg = 1
	ac.ap.set_lat("LNAV")
	ac.ap.set_approach(arr, 3.5 if arr.airport == "SKHP" else 3.0)
	ac.ap.arm_loc = false
	ac.ap.arm_gs = false
	_faf_leg = plan.size() - 2


func _callout(text: String) -> void:
	callout.emit(text)
