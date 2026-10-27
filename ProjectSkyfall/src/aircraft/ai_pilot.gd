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
var cleared_alt := -1.0           # latest ATC altitude clearance (m), -1 when no controller
var _faf_leg := 99


func setup(aircraft: Aircraft, dep_end: Dictionary, arr_end: Dictionary, cruise_alt_m: float, waypoints: Array = []) -> void:
	ac = aircraft
	ac.laws.mode = "assisted"    # the AI always flies through the attitude-command law
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
			# top of descent: when the planned descent path through the approach pattern meets us
			var pos := Vector2(n.x, n.z)
			var dtg_est := _plan_length(_approach_plan(pos, n.alt), pos)
			var route_done := not route.is_empty() and ac.ap.lat_mode != "LNAV" and t_phase > 5.0
			var cleared_down: bool = cleared_alt > 0.0 and cleared_alt < float(n.alt) - 150.0
			if n.alt > _path_alt(dtg_est) - 60.0 or route_done or cleared_down:
				_set_phase("descent")
				ac.ap.alt_sel = _app_alt()
				ac.ap.use_mach = false
				ac.ap.spd_sel = float(spec.descent_ias)
				ac.ap.set_vert("VS")
				ac.ap.set_thr("SPD")
		"descent":
			if not pattern_built:
				_build_approach_route(n)
			var dtg := ac.ap.distance_to_go(n)
			var spd := float(spec.descent_ias)
			if n.alt < 3300.0:
				spd = minf(spd, 250.0)
			if dtg < 45000.0:
				spd = minf(spd, 220.0 if spec.category != "trainer" else 95.0)
			ac.ap.spd_sel = spd
			_vnav_descent(n, dtg, dt)
			if dtg < 32000.0 or (ac.ap.vert_mode == "ALT" and dtg < 40000.0):
				_set_phase("approach")
		"approach":
			_approach_config(n, ias)
			if ac.ap.vert_mode == "VS" and not ac.ap.arm_gs:
				# finish any remaining descent to the approach altitude
				_vnav_descent(n, ac.ap.distance_to_go(n), dt)
			else:
				_speedbrake(n, ias, dt)
			if (ac.ap.lat_mode == "LNAV" and ac.ap.leg >= _faf_leg) or ac.ap.lat_mode == "LOC":
				if not ac.ap.arm_loc and ac.ap.lat_mode != "LOC":
					ac.ap.arm_loc = true
				if not ac.ap.arm_gs and ac.ap.vert_mode != "GS":
					ac.ap.arm_gs = true
			# established on the localizer but high: descend to capture the glideslope from above
			if ac.ap.lat_mode == "LOC" and ac.ap.vert_mode != "GS" and ac.ap.gs_dev > 0.45 and ac.ap.dist_thr < 24000.0:
				ac.ap.alt_sel = float(arr.elev) + 60.0
				var steep := float(n.gs) * tan(deg_to_rad(3.0)) + clampf(ac.ap.gs_dev * 2.5, 1.0, 5.0)
				ac.ap.vs_sel = -minf(steep, 12.0)
				ac.ap.set_vert("VS")
			if ac.ap.lat_mode == "LOC" and ac.ap.vert_mode == "GS":
				_set_phase("final")
			elif ac.ap.dist_thr < 2500.0 and ac.ap.lat_mode == "LOC":
				_callout("Missed approach")
				_go_around()
				return
		"final":
			_approach_config(n, ias)
			_speedbrake(n, ias, dt)
			if agl < 300.0 and not flown_callouts.has("1000"):
				_callout("One thousand")
				flown_callouts["1000"] = true
			# stabilised-approach gate: 1000 ft for airliners, 500 ft for light aircraft
			var gate := 300.0 if spec.category != "trainer" else 150.0
			if agl < gate and agl > 30.0 and not _stable(n):
				_go_around()
				return
			if _landing_long(n):
				_callout("Long landing, go around")
				_go_around()
				return
			if not bool(spec.autoland) or not allow_autoland:
				var flare_h := Autopilot.flare_height(spec)
				var above_rwy := float(n.alt) - float(arr.elev) - float(spec.gear_height)
				if agl < flare_h + 2.0 and ac.ap.dist_thr < 600.0 and above_rwy < flare_h + 25.0:
					ac.ap.engage(false, "MANUAL LAND")
					ac.ap.at_engaged = false
					ac.ap.flare_reset(n.pitch)
					_set_phase("manual_flare")
			elif ac.ap.vert_mode == "ROLLOUT":
				_set_phase("rollout")
		"manual_flare":
			# hand-flown flare for aircraft without autoland: same sink-rate law as the autopilot
			ac.laws.target_pitch = ac.ap.flare_law(n, dt)
			ac.in_pitch = 0.0
			ac.in_roll = clampf(-n.bank * 0.05, -0.3, 0.3)
			ac.laws.target_bank = 0.0
			ac.ap.at_engaged = false
			# close the throttles through the flare: idle by touchdown
			var idle_h := 9.0 if spec.category != "trainer" else 6.0
			if agl < idle_h:
				ac.throttle_lever = move_toward(ac.throttle_lever, 0.0, dt * (0.5 if spec.category != "trainer" else 0.3))
			if ac.fdm.wow[1] or ac.fdm.wow[2]:
				ac.throttle_lever = 0.0
				_set_phase("rollout")
				ac.ap.set_lat("ROLLOUT")
			elif _landing_long(n):
				_callout("Long landing, go around")
				_go_around()
				return
		"rollout":
			ac.throttle_lever = 0.0
			if ac.ap.at_engaged:
				ac.ap.at_engaged = false
			ac.ap.update(dt, n, ac.fdm, ac.sys)
			ac.in_yaw = ac.ap.out_rudder
			# light aircraft keep a little back pressure to protect the nose wheel (not enough to
			# fly again) and dump the flaps; jets lower the nose
			if spec.category == "trainer":
				ac.in_pitch = 0.08 if ias > 50.0 else 0.2
				if ac.sys.flap_lever > 0 and t_phase > 1.0:
					ac.set_flaps(0)
			else:
				ac.in_pitch = -0.2
			ac.in_roll = 0.0
			ac.sys.reverse_cmd = ias > 70.0 and bool(spec.reverser)
			if spec.category == "trainer":
				ac.sys.brake_input = 0.25 if ias < 45.0 else 0.0
			elif ac.sys.autobrake == 0:
				ac.sys.brake_input = 0.6 if ias < 100.0 else 0.3
			if ias < 30.0:
				ac.sys.reverse_cmd = false
				ac.sys.brake_input = 0.4 if spec.category != "trainer" else 0.3
				if ac.ap.engaged:
					ac.ap.engage(false, "ROLLOUT COMPLETE")
			if ac.fdm.ground_speed() < 8.0:
				ac.sys.brake_input = 0.0
				_set_phase("landed")
		"go_around":
			ac.throttle_lever = 1.0
			ac.sys.spoiler_lever = 0.0
			if ac.sys.flap_lever > takeoff_flaps + 1:
				ac.set_flaps(ac.sys.flap_lever - 1)
			if ac.ra > 20.0 and ac.sys.gear_down_cmd and n.vs > 2.0:
				ac.toggle_gear()
			if n.alt > float(arr.elev) + 400.0:
				pattern_built = false
				_set_phase("descent")
				ac.ap.alt_sel = _app_alt()
				ac.ap.at_engaged = true
				ac.ap.set_vert("FLCH")
				ac.ap.set_thr("SPD")


func _stable(n: Dictionary) -> bool:
	var ias: float = n.true_ias_kt
	var vapp := float(ac.spec.vapp)
	var low := 16.0 if ac.spec.category == "trainer" else 12.0
	return absf(ac.ap.loc_dev) < 1.5 and absf(ac.ap.gs_dev) < 1.0 and n.vs > -7.5 and ias > vapp - low and ias < vapp + 25.0


func _go_around() -> void:
	go_around_count += 1
	_callout("Go around, flaps")
	ac.ap.arm_gs = false
	ac.ap.arm_loc = false
	ac.ap.set_vert("TOGA")
	ac.ap.set_thr("TOGA")
	ac.ap.alt_sel = _app_alt()
	ac.ap.hdg_sel = arr.hdg
	ac.ap.at_engaged = true
	ac.sys.spoiler_lever = 0.0
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
	var spd := 220.0 if dtg > 32000.0 else 210.0
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
	if dtg < 11500.0 and gs_alive:
		tgt_flap = nf - 1
		spd = float(spec.vapp)
	spd = maxf(spd, float(spec.vapp))
	if spec.category == "trainer":
		spd = 90.0 if dtg > 5000.0 else float(spec.vapp) + 3.0
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


func _app_alt() -> float:
	## Altitude flown level onto the localizer, below the glideslope so it is captured from below.
	return float(arr.elev) + (720.0 if ac.spec.category != "trainer" else 480.0)


func _path_alt(dtg: float) -> float:
	## Planned descent profile: a 2.6 degree idle path that reaches the approach altitude early
	## enough to leave a level segment for slowing down and configuring.
	var level := 22000.0 if ac.spec.category != "trainer" else 9000.0
	return _app_alt() + maxf(dtg - level, 0.0) * tan(deg_to_rad(2.6))


func _vnav_descent(n: Dictionary, dtg: float, dt: float) -> void:
	## Path descent: vertical speed follows the profile, speed brakes when high or fast.
	var gamma := tan(deg_to_rad(2.6))
	var err := float(n.alt) - _path_alt(dtg)              # + above the path
	var vs := -float(n.gs) * gamma - clampf(err * 0.02, -4.0, 6.0)
	var max_rate := 15.0 if ac.spec.category != "trainer" else 4.0
	ac.ap.alt_sel = _app_alt()
	if cleared_alt > ac.ap.alt_sel and cleared_alt < float(n.alt) + 100.0:
		ac.ap.alt_sel = cleared_alt     # never below the level ATC has cleared us to
	if float(n.alt) - ac.ap.alt_sel < 30.0:
		if ac.ap.vert_mode == "VS":
			ac.ap.set_vert("ALT")
		return
	ac.ap.vs_sel = clampf(vs, -max_rate, 0.0)
	if ac.ap.vert_mode != "VS" and ac.ap.vert_mode != "ALT":
		ac.ap.set_vert("VS")
	elif ac.ap.vert_mode == "ALT" and err > 120.0:
		ac.ap.set_vert("VS")
	_speedbrake(n, float(n.true_ias_kt), dt, err)


func _speedbrake(n: Dictionary, ias: float, dt: float, path_err: float = 0.0) -> void:
	## Speed brakes to lose excess speed or height; never close to the ground or with full flap.
	if not bool(ac.spec.spoilers):
		return
	var over := ias - ac.ap.spd_sel
	var want := 0.0
	if ac.ra > 280.0 and ac.sys.flap_lever < ac.spec.flaps.size() - 1:
		if over > 8.0 and ac.throttle_lever < 0.08:
			want = clampf((over - 8.0) / 15.0, 0.3, 1.0)
		if path_err > 250.0:
			want = maxf(want, clampf((path_err - 250.0) / 400.0, 0.3, 1.0))
		if ac.ap.vert_mode == "GS" and ac.ap.gs_dev > 0.5:
			want = maxf(want, 0.5)
	ac.sys.spoiler_lever = move_toward(ac.sys.spoiler_lever, want, dt * 0.6)


func _landing_long(n: Dictionary) -> bool:
	## Still airborne well past the touchdown zone: the landing will not fit on the runway.
	if ac.fdm.on_ground or ac.ra > 40.0:
		return false
	var limit := minf(900.0, float(arr.get("len", 2500.0)) * 0.4)
	return ac.ap.dist_thr < -limit


func _approach_plan(p: Vector2, alt: float) -> Array:
	## Straight-in or a downwind/base pattern onto a final approach fix 16 km out. The initial
	## fix moves further out until the track is long enough to descend and slow down on.
	var d := Vector2(sin(deg_to_rad(arr.hdg)), -cos(deg_to_rad(arr.hdg)))
	var side_v := Vector2(-d.y, d.x)
	var thr := Vector2(arr.thr_x, arr.thr_z)
	var faf := thr - d * 16000.0
	var out_d := (p - thr).dot(-d)                         # how far out on the approach side
	var lat := (p - thr).dot(side_v)
	var side := signf(lat)
	if side == 0.0:
		side = 1.0
	var level := 22000.0 if ac.spec.category != "trainer" else 9000.0
	var need := (alt - _app_alt()) / tan(deg_to_rad(3.2)) + level
	var plan: Array = []
	for k in 12:
		var iaf_d := 26000.0 + k * 6000.0
		var iaf := thr - d * iaf_d
		plan = [{"name": "PPOS", "x": p.x, "z": p.y}]
		var straight := out_d > iaf_d - 4000.0 and absf(lat) < 12000.0
		if not straight:
			var dw := thr - d * 4000.0 + side_v * side * 9000.0
			var base := iaf + side_v * side * 9000.0
			if out_d < 0.0:
				plan.append({"name": "DWND", "x": dw.x, "z": dw.y})
			plan.append({"name": "BASE", "x": base.x, "z": base.y})
		plan.append({"name": "IAF", "x": iaf.x, "z": iaf.y})
		plan.append({"name": "FAF", "x": faf.x, "z": faf.y})
		plan.append({"name": "RW" + String(arr.name), "x": thr.x, "z": thr.y})
		if _plan_length(plan, p) >= need:
			break
	return plan


func _plan_length(plan: Array, p: Vector2) -> float:
	var total := 0.0
	var prev := p
	for i in range(1, plan.size()):
		var q := Vector2(plan[i].x, plan[i].z)
		total += prev.distance_to(q)
		prev = q
	return total


func _build_approach_route(n: Dictionary) -> void:
	pattern_built = true
	var plan := _approach_plan(Vector2(n.x, n.z), float(n.alt))
	ac.ap.plan = plan
	ac.ap.leg = 1
	ac.ap.set_lat("LNAV")
	ac.ap.set_approach(arr, 3.5 if arr.airport == "SKHP" else 3.0)
	ac.ap.arm_loc = false
	ac.ap.arm_gs = false
	_faf_leg = plan.size() - 2


func _callout(text: String) -> void:
	callout.emit(text)
