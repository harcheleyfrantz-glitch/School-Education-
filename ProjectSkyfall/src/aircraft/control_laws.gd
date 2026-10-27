class_name ControlLaws
extends RefCounted
## Turns pilot or autopilot intent into surface deflections.
## "direct": stick = surface (plus trim). "assisted": fly-by-wire style attitude command with
## auto-trim, bank/pitch limits and stall/overspeed protection. The autopilot always feeds the
## attitude controller with target pitch and bank.

var spec: Dictionary
var mode := "assisted"
var auto_rudder := true
var target_pitch := 0.0      # degrees
var target_bank := 0.0
var _pitch_i := 0.0
var _roll_i := 0.0
var _was_ground := true
var pitch_rate_max := 5.0    # deg/s commanded by full stick in assisted mode
var roll_rate_max := 15.0
var protections := true
var law := "normal"          # normal | alternate | direct (degraded by failures)
var _beta_i := 0.0


func setup(t: Dictionary, assisted: bool, fbw_realistic: bool) -> void:
	spec = t
	mode = "assisted" if (assisted or fbw_realistic) else "direct"
	match String(t.category):
		"trainer":
			pitch_rate_max = 9.0
			roll_rate_max = 40.0
		"turboprop":
			pitch_rate_max = 6.0
			roll_rate_max = 18.0
		"bizjet":
			pitch_rate_max = 6.0
			roll_rate_max = 22.0
		"widebody", "cargo":
			pitch_rate_max = 3.5
			roll_rate_max = 11.0
		_:
			pitch_rate_max = 4.5
			roll_rate_max = 15.0


func reset_to_current(fdm: FlightModel) -> void:
	target_pitch = fdm.pitch_deg()
	target_bank = fdm.bank_deg()
	_pitch_i = 0.0
	_roll_i = 0.0


func _sched(fdm: FlightModel) -> float:
	var vref := float(spec.vref) * U.KT * 1.25
	var q_ref := 0.5 * Atmo.RHO0 * vref * vref
	return clampf(q_ref / maxf(fdm.qbar, 300.0), 0.12, 3.0)


## Attitude-hold inner loop. Returns [elevator, aileron].
func attitude_control(fdm: FlightModel, sys: AircraftSystems, dt: float) -> Array:
	var k := _sched(fdm)
	var eff := sys.controls_effectiveness() if sys else 1.0
	var pitch := fdm.pitch_deg()
	var bank := fdm.bank_deg()
	var q := rad_to_deg(fdm.omega.x)
	var p := rad_to_deg(-fdm.omega.z)
	# the steady pitch needs more elevator in a bank (load factor)
	var bank_comp := (1.0 / maxf(cos(deg_to_rad(clampf(bank, -70.0, 70.0))), 0.35) - 1.0) * 2.2
	var e_pitch := clampf(target_pitch - pitch, -12.0, 12.0)
	_pitch_i = clampf(_pitch_i + e_pitch * dt * 0.05 * k, -0.8, 0.8)
	var elev := (e_pitch * 0.075 - q * 0.11) * k + _pitch_i + bank_comp * 0.02 * k
	# load factor protection keeps commanded manoeuvres inside the structural envelope
	var nmax := 2.4 if spec.category != "trainer" else 3.6
	if fdm.nz > nmax - 0.4:
		elev -= (fdm.nz - (nmax - 0.4)) * 0.35
	elif fdm.nz < 0.1:
		elev += (0.1 - fdm.nz) * 0.35
	var e_bank := clampf(U.angle_diff_deg(target_bank, bank), -40.0, 40.0)
	_roll_i = clampf(_roll_i + e_bank * dt * 0.006 * k, -0.2, 0.2)
	var ail := (e_bank * 0.04 - p * 0.06) * k * 1.2 + _roll_i
	return [clampf(elev / maxf(eff, 0.3), -1.0, 1.0), clampf(ail / maxf(eff, 0.3), -1.0, 1.0)]


func yaw_damper(fdm: FlightModel, dt: float) -> float:
	var k := _sched(fdm)
	var r := rad_to_deg(-fdm.omega.y)
	var beta := rad_to_deg(fdm.beta)
	_beta_i = clampf(_beta_i + beta * dt * 0.05, -0.4, 0.4)
	return clampf((beta * 0.06 - r * 0.02) * k + _beta_i, -0.6, 0.6)


## Main entry: pilot inputs (stick/pedal -1..1); ap: Autopilot or null.
func update(fdm: FlightModel, sys: AircraftSystems, ap: Autopilot, stick_pitch: float, stick_roll: float,
		pedal: float, dt: float, ra_m: float) -> void:
	# any wheel on the ground: the stick drives the surfaces directly (needed for rotation)
	var on_ground: bool = fdm.on_ground and (fdm.wow[0] or fdm.wow[1] or fdm.wow[2])
	var ap_active := ap != null and ap.engaged
	var cur_pitch := fdm.pitch_deg()
	var cur_bank := fdm.bank_deg()
	var effective_mode := mode
	if law == "direct":
		effective_mode = "direct"
	if ap_active:
		target_pitch = ap.out_pitch
		target_bank = ap.out_bank
		var out := attitude_control(fdm, sys, dt)
		fdm.elevator = out[0]
		fdm.aileron = out[1]
		fdm.rudder = clampf(yaw_damper(fdm, dt) + ap.out_rudder, -1.0, 1.0)
		sys.trim = clampf(_pitch_i, -1.0, 1.0)
		_was_ground = on_ground
		return
	if effective_mode == "direct" or on_ground:
		# on the ground (or raw law) the stick moves the surfaces directly
		fdm.elevator = clampf(stick_pitch + sys.trim, -1.0, 1.0)
		fdm.aileron = stick_roll
		var yd := 0.0
		if auto_rudder and not on_ground:
			yd = yaw_damper(fdm, dt) * (0.7 if spec.fbw else 0.5)
		fdm.rudder = clampf(pedal + yd, -1.0, 1.0)
		target_pitch = cur_pitch
		target_bank = cur_bank
		_pitch_i = clampf(stick_pitch + sys.trim, -0.8, 0.8) * 0.5
		_roll_i = 0.0
		_was_ground = on_ground
		return
	if _was_ground:
		# just became airborne: hold the attitude we rotated to
		target_pitch = cur_pitch
		target_bank = cur_bank
		_pitch_i = clampf(fdm.elevator, -0.8, 0.8)
	_was_ground = false
	# stick commands pitch and roll rates; neutral stick holds attitude
	target_pitch += stick_pitch * pitch_rate_max * dt
	if absf(stick_roll) > 0.05:
		target_bank += stick_roll * roll_rate_max * dt
	elif absf(target_bank) > 33.0:
		target_bank = move_toward(target_bank, signf(target_bank) * 33.0, 5.0 * dt)
	if absf(stick_roll) < 0.05 and absf(target_bank) < 3.0 and absf(cur_bank) < 3.0:
		target_bank = move_toward(target_bank, 0.0, 1.0 * dt)
	target_bank = clampf(target_bank, -67.0, 67.0)
	target_pitch = clampf(target_pitch, -15.0, 30.0)
	# keep the target close to reality so releasing the stick never causes a lurch
	target_pitch = clampf(target_pitch, cur_pitch - 8.0, cur_pitch + 8.0)
	if protections and law == "normal":
		var margin := rad_to_deg(fdm.alpha_stall - fdm.alpha)
		if margin < 3.5:
			target_pitch = minf(target_pitch, cur_pitch - (3.5 - margin) * 0.8)
		if sys.overspeed:
			target_pitch = maxf(target_pitch, cur_pitch + 0.6)
	var out2 := attitude_control(fdm, sys, dt)
	fdm.elevator = out2[0]
	fdm.aileron = out2[1]
	var yd2 := yaw_damper(fdm, dt) if auto_rudder or spec.fbw else 0.0
	fdm.rudder = clampf(pedal + yd2, -1.0, 1.0)
	sys.trim = clampf(_pitch_i, -1.0, 1.0)
	# flare: in the last few feet let the pilot's pull be felt directly
	if ra_m < 6.0 and stick_pitch > 0.05:
		fdm.elevator = clampf(fdm.elevator + stick_pitch * 0.25, -1.0, 1.0)
