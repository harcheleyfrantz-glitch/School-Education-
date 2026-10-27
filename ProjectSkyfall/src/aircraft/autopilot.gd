class_name Autopilot
extends RefCounted
## Autopilot, flight director and autothrottle.
## Lateral: HDG, LNAV, LOC, ROLL, RWY, ROLLOUT.  Vertical: ALT, VS, FLCH, GS, FLARE, TOGA.
## Thrust: SPD, CLB, IDLE, RETARD, TOGA. Outputs target pitch/bank for ControlLaws and a throttle.

signal mode_changed(text: String)
signal disconnected(reason: String)

var spec: Dictionary
var engaged := false
var at_engaged := false
var fd_on := true
var lat_mode := "HDG"
var vert_mode := "ALT"
var thr_mode := "SPD"
var arm_loc := false
var arm_gs := false
var hdg_sel := 0.0
var alt_sel := 1000.0          # metres MSL
var vs_sel := 0.0              # m/s
var spd_sel := 250.0           # knots IAS
var mach_sel := 0.78
var use_mach := false
var plan: Array = []           # [{name, x, z, alt, spd}]
var leg := 1
var approach: Dictionary = {}  # {name, thr_x, thr_z, hdg, elev, slope, len}
var bank_limit := 25.0

var out_pitch := 0.0
var out_bank := 0.0
var out_rudder := 0.0
var out_throttle := 0.0
var out_steer := 0.0
var gs_dev := 0.0              # degrees (+ = aircraft above path)
var loc_dev := 0.0             # degrees (+ = aircraft right of centreline)
var loc_valid := false
var gs_valid := false
var dist_thr := 0.0            # metres to threshold
var xte := 0.0                 # cross-track error (m) on the active LNAV leg
var _vs_i := 0.0
var _thr_i := 0.4
var _flch_pitch := 5.0
var _alpha_f := 2.0
var _last_y := 0.0
var _disc_timer := 0.0


func setup(t: Dictionary) -> void:
	spec = t
	spd_sel = float(t.climb_ias)


func engage(on: bool, reason: String = "") -> void:
	if on == engaged:
		return
	engaged = on
	if not on:
		disconnected.emit(reason)
	mode_changed.emit(fma())


func set_lat(m: String) -> void:
	if lat_mode != m:
		lat_mode = m
		mode_changed.emit(fma())


func set_vert(m: String) -> void:
	if vert_mode != m:
		vert_mode = m
		if m in ["VS", "ALT"]:
			_vs_i = 0.0
		mode_changed.emit(fma())


func set_thr(m: String) -> void:
	if thr_mode != m:
		thr_mode = m
		mode_changed.emit(fma())


func fma() -> String:
	var thr := thr_mode if at_engaged else "MAN"
	var lat := lat_mode + (" | LOC*" if arm_loc and lat_mode != "LOC" else "")
	var vert := vert_mode + (" | G/S*" if arm_gs and vert_mode != "GS" else "")
	return "%s   %s   %s   %s" % [thr, lat, vert, "AP1" if engaged else "FD"]


func target_ias(n: Dictionary) -> float:
	if use_mach:
		return Atmo.tas_to_ias(Atmo.mach_to_tas(mach_sel, n.alt), n.alt) / U.KT
	return spd_sel


# ---------------------------------------------------------------- main update
func update(dt: float, n: Dictionary, fdm: FlightModel, sys: AircraftSystems) -> void:
	_alpha_f = lerpf(_alpha_f, rad_to_deg(fdm.alpha), clampf(dt * 0.6, 0.0, 1.0))
	_update_nav(n)
	_lateral(dt, n, fdm)
	_vertical(dt, n, fdm)
	_thrust(dt, n, fdm, sys)
	# protections: disconnect on stall or loss of power
	if engaged:
		if sys.stall_warning and vert_mode != "FLARE":
			engage(false, "STALL")
		elif not sys.ac_power and not sys.emer_elec and spec.category != "trainer":
			engage(false, "POWER")


func pilot_override(stick_mag: float, dt: float) -> void:
	if not engaged:
		_disc_timer = 0.0
		return
	if stick_mag > 0.55:
		_disc_timer += dt
		if _disc_timer > 0.35:
			engage(false, "OVERRIDE")
	else:
		_disc_timer = 0.0


func _update_nav(n: Dictionary) -> void:
	loc_valid = false
	gs_valid = false
	if approach.is_empty():
		return
	var thr := Vector2(approach.thr_x, approach.thr_z)
	var p := Vector2(n.x, n.z)
	var rd := Vector2(sin(deg_to_rad(approach.hdg)), -cos(deg_to_rad(approach.hdg)))
	var rel := p - thr
	var along := -rel.dot(rd)                        # metres before the threshold
	var lateral := rel.dot(Vector2(-rd.y, rd.x))      # + right of centreline
	dist_thr = along
	var loc_ant := along + float(approach.get("len", 3000.0)) + 300.0
	loc_dev = rad_to_deg(atan2(lateral, maxf(loc_ant, 1.0)))
	loc_valid = along > -float(approach.get("len", 3000.0)) and along < 46000.0 and absf(loc_dev) < 35.0
	# glideslope antenna ~300 m beyond the threshold: the path crosses the threshold at ~50 ft
	var gs_h := float(n.alt) - float(approach.elev)
	var gs_ant := maxf(along + 300.0, 1.0)
	gs_dev = rad_to_deg(atan2(gs_h, gs_ant)) - float(approach.slope)
	gs_valid = along > 200.0 and along < 30000.0 and absf(loc_dev) < 10.0
	_last_y = lateral


# ---------------------------------------------------------------- lateral
func _bank_for_track(desired_track: float, n: Dictionary, limit: float) -> float:
	var d := U.angle_diff_deg(desired_track, n.track if n.gs > 25.0 else n.hdg)
	return clampf(d * 1.6, -limit, limit)


func _lateral(dt: float, n: Dictionary, fdm: FlightModel) -> void:
	var bank_t := 0.0
	out_rudder = 0.0
	if arm_loc and loc_valid and dist_thr > 1500.0 and absf(loc_dev) < 4.0 and lat_mode != "LOC" and lat_mode != "ROLLOUT":
		if absf(U.angle_diff_deg(float(approach.hdg), float(n.track) if n.gs > 25.0 else float(n.hdg))) < 75.0:
			set_lat("LOC")
			arm_loc = false
	match lat_mode:
		"HDG":
			var d := U.angle_diff_deg(hdg_sel, n.hdg)
			bank_t = clampf(d * 1.4, -bank_limit, bank_limit)
		"ROLL":
			bank_t = 0.0 if absf(n.bank) < 6.0 else n.bank
		"LNAV":
			bank_t = _lnav(n)
		"LOC":
			var rd := approach.hdg as float
			var lateral := _last_y
			var lat_rate := 0.0
			var cross_track_vel := Vector2(fdm.vel.x, fdm.vel.z).dot(Vector2(cos(deg_to_rad(rd)), sin(deg_to_rad(rd))))
			lat_rate = cross_track_vel
			var k := clampf(4500.0 / maxf(absf(dist_thr) + 1500.0, 1500.0), 0.12, 1.0)
			var intercept := clampf(-lateral * 0.025 * k - lat_rate * 0.35 * k, -30.0, 30.0)
			bank_t = _bank_for_track(rd + intercept, n, 20.0)
			if n.ra < 30.0:
				bank_t = clampf(bank_t, -5.0, 5.0)
		"RWY", "ROLLOUT":
			bank_t = 0.0
			var rd2 := approach.hdg as float if not approach.is_empty() else hdg_sel
			var hd := U.angle_diff_deg(rd2, n.hdg)
			var cross_v := Vector2(fdm.vel.x, fdm.vel.z).dot(Vector2(cos(deg_to_rad(rd2)), sin(deg_to_rad(rd2))))
			out_rudder = clampf(-_last_y * 0.025 - cross_v * 0.12 + hd * 0.06, -1.0, 1.0) if not approach.is_empty() else clampf(hd * 0.06, -1.0, 1.0)
			out_steer = out_rudder
	# smooth bank target
	out_bank = move_toward(out_bank, bank_t, 3.0 * dt)


func _lnav(n: Dictionary) -> float:
	if plan.size() < 2 or leg >= plan.size():
		hdg_sel = n.hdg
		set_lat("HDG")
		return 0.0
	var a: Dictionary = plan[leg - 1]
	var b: Dictionary = plan[leg]
	var A := Vector2(a.x, a.z)
	var B := Vector2(b.x, b.z)
	var P := Vector2(n.x, n.z)
	var ab := B - A
	var L := maxf(ab.length(), 1.0)
	var u := ab / L
	var rel := P - A
	xte = rel.dot(Vector2(-u.y, u.x))     # + right of course
	var to_go := (B - P).dot(u)
	var course := U.dir_to_heading(Vector3(u.x, 0, u.y))
	# turn anticipation for the next leg
	var turn_r := pow(maxf(n.gs, 50.0), 2.0) / (U.G0 * tan(deg_to_rad(bank_limit)))
	var lead := 0.0
	if leg + 1 < plan.size():
		var C := Vector2(plan[leg + 1].x, plan[leg + 1].z)
		var next_course := U.dir_to_heading(Vector3(C.x - B.x, 0, C.y - B.y))
		var dc := absf(U.angle_diff_deg(next_course, course))
		lead = turn_r * tan(deg_to_rad(minf(dc, 150.0) * 0.5))
	if to_go < maxf(lead, 400.0):
		leg += 1
		mode_changed.emit(fma())
		if leg >= plan.size():
			return 0.0
	var intercept := clampf(-xte * 0.012, -45.0, 45.0)
	return _bank_for_track(course + intercept, n, bank_limit)


# ---------------------------------------------------------------- vertical
func _alpha_trim(n: Dictionary, fdm: FlightModel, gamma_rad: float) -> float:
	## Angle of attack (deg) that supports the aircraft in steady flight on the given path.
	var q := maxf(fdm.qbar, 200.0)
	var cl_req := fdm.mass * U.G0 * cos(gamma_rad) / (q * fdm.S)
	cl_req /= maxf(cos(deg_to_rad(clampf(float(n.bank), -60.0, 60.0))), 0.5)
	var fc := fdm._flap_coeffs()
	var cl0: float = float(spec.cl0) + fc.dcl
	cl0 *= 1.0 - 0.45 * fdm.spoilers
	return rad_to_deg((cl_req - cl0) / float(spec.cla))


func _pitch_for_vs(vs_t: float, n: Dictionary, fdm: FlightModel, dt: float) -> float:
	var tas := maxf(float(n.tas), 30.0)
	var g := asin(clampf(vs_t / tas, -0.5, 0.5))
	var err := vs_t - float(n.vs)
	_vs_i = clampf(_vs_i + err * dt * 0.04, -4.0, 4.0)
	return clampf(rad_to_deg(g) + _alpha_trim(n, fdm, g) + err * 0.22 + _vs_i, -12.0, 20.0)


func _pitch_for_speed(tgt_kt: float, n: Dictionary, fdm: FlightModel, dt: float, gamma_min: float, gamma_max: float) -> float:
	## Energy law: choose the flight path that turns excess thrust into the speed we want.
	var tas := maxf(float(n.tas), 30.0)
	var ratio := tas / maxf(float(n.true_ias_kt) * U.KT, 10.0)
	var v_err := (float(n.true_ias_kt) - tgt_kt) * U.KT * ratio
	var acc := (tas - _prev_tas) / maxf(dt, 0.001)
	_prev_tas = tas
	_acc_f = lerpf(_acc_f, acc, clampf(dt * 1.5, 0.0, 1.0))
	var g_cur := asin(clampf(float(n.vs) / tas, -0.6, 0.6))
	var s := sin(g_cur) + (_acc_f + v_err * 0.12) / U.G0
	var g_t := asin(clampf(s, -0.35, 0.35))
	g_t = clampf(g_t, deg_to_rad(gamma_min), deg_to_rad(gamma_max))
	_gamma_f = lerpf(_gamma_f, g_t, clampf(dt * 0.8, 0.0, 1.0))
	return clampf(rad_to_deg(_gamma_f) + _alpha_trim(n, fdm, _gamma_f), -10.0, 18.0)


var _prev_tas := 0.0
var _acc_f := 0.0
var _gamma_f := 0.0


func _vertical(dt: float, n: Dictionary, fdm: FlightModel) -> void:
	var alt: float = n.alt
	var pitch_t := out_pitch
	if arm_gs and gs_valid and lat_mode == "LOC" and gs_dev < 0.1 and vert_mode != "GS":
		set_vert("GS")
		arm_gs = false
	var cap_vs := 7.6 if spec.category != "trainer" else 3.6     # ~1500 / 700 fpm
	match vert_mode:
		"ALT":
			var vs_t := clampf((alt_sel - alt) * 0.1, -cap_vs, cap_vs)
			pitch_t = _pitch_for_vs(vs_t, n, fdm, dt)
		"VS":
			if absf(alt_sel - alt) < absf(n.vs) * 6.0 + 15.0 and signf(alt_sel - alt) == signf(vs_sel):
				set_vert("ALT")
			var vs_cmd := vs_sel
			# speed protection: never trade the aircraft's last knots for vertical speed
			var vmin := AircraftTypes.stall_speed_kt(spec, fdm.mass, int(round(fdm.flap_frac))) * 1.28
			var short := vmin - float(n.true_ias_kt)
			if short > 0.0 and vs_cmd > 0.0:
				vs_cmd = maxf(vs_cmd - short * 0.6, 0.0)
			pitch_t = _pitch_for_vs(vs_cmd, n, fdm, dt)
		"FLCH":
			var climbing := alt_sel > alt
			var gmin := 0.8 if climbing else -6.0
			var gmax := 14.0 if climbing else -0.8
			pitch_t = _pitch_for_speed(target_ias(n), n, fdm, dt, gmin, gmax)
			if absf(alt_sel - alt) < absf(n.vs) * 6.0 + 15.0:
				set_vert("ALT")
				set_thr("SPD")
		"GS":
			var h_gs := float(approach.elev) + (maxf(dist_thr, -250.0) + 300.0) * tan(deg_to_rad(approach.slope))
			var vs_t3 := -float(n.gs) * tan(deg_to_rad(approach.slope)) + clampf((h_gs - alt) * 0.15, -3.0, 3.0)
			pitch_t = _pitch_for_vs(vs_t3, n, fdm, dt)
			var flare_h := 15.0 if spec.category != "trainer" else 8.0
			if n.ra < flare_h and bool(spec.autoland):
				set_vert("FLARE")
		"FLARE":
			var vs_t4 := -maxf(float(n.ra) * 0.3, 0.3)
			pitch_t = _pitch_for_vs(vs_t4, n, fdm, dt)
			if n.ra < 9.0:
				set_thr("RETARD")
			if fdm.wow[1] or fdm.wow[2]:
				set_vert("ROLLOUT")
				set_lat("ROLLOUT")
		"ROLLOUT":
			pitch_t = move_toward(out_pitch, -0.5, dt * 1.5)
			set_thr("IDLE")
		"TOGA":
			var v2 := float(spec.v2)
			pitch_t = minf(_pitch_for_speed(v2 + 12.0, n, fdm, dt, 1.5, 14.0), 17.0)
			if alt_sel - alt < absf(n.vs) * 6.0 + 15.0 and n.vs > 0.0:
				set_vert("ALT")
				set_thr("SPD")
		"HOLD":
			pass
	out_pitch = move_toward(out_pitch, pitch_t, 2.5 * dt)


# ---------------------------------------------------------------- thrust
func _thrust(dt: float, n: Dictionary, fdm: FlightModel, sys: AircraftSystems) -> void:
	if not at_engaged:
		return
	var target := out_throttle
	match thr_mode:
		"SPD":
			var err: float = target_ias(n) - float(n.true_ias_kt)
			var acc_kt := _acc_f / U.KT
			_thr_i = clampf(_thr_i + err * dt * 0.004, 0.02, 0.95)
			target = clampf(_thr_i + err * 0.018 - acc_kt * 0.12, 0.0, 0.98)
		"CLB":
			target = 0.93
			_thr_i = 0.6
		"TOGA":
			target = 1.0
		"IDLE", "RETARD":
			target = 0.0
			_thr_i = 0.3
	out_throttle = move_toward(out_throttle, target, (0.2 if thr_mode != "TOGA" else 0.6) * dt)


## Fills the approach from a runway end dictionary (Airports.runway_end format).
func distance_to_go(n: Dictionary) -> float:
	## Distance along the remaining LNAV legs (or straight line) to the end of the plan.
	if plan.size() < 2 or leg >= plan.size():
		if approach.is_empty():
			return 0.0
		return U.dist2d(n.x, n.z, approach.thr_x, approach.thr_z)
	var d := U.dist2d(n.x, n.z, plan[leg].x, plan[leg].z)
	for i in range(leg, plan.size() - 1):
		d += U.dist2d(plan[i].x, plan[i].z, plan[i + 1].x, plan[i + 1].z)
	return d


func set_approach(e: Dictionary, slope: float = 3.0) -> void:
	if e.is_empty():
		approach = {}
		return
	approach = {"name": e.name, "thr_x": e.thr_x, "thr_z": e.thr_z, "hdg": e.hdg, "elev": e.elev, "slope": slope, "len": e.len, "airport": e.airport}
