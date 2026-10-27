class_name AircraftSystems
extends RefCounted
## Engines, fuel, electrical, hydraulic, pressurisation, gear, flaps, spoilers, brakes, lights,
## APU, anti-ice and the caution/warning system. Failures are injected with fail().

signal alert(id: String, level: int, text: String)   # level: 0 memo, 1 caution, 2 warning
signal chime(kind: String)

var spec: Dictionary
var etype := "turbofan"
var n_eng := 2

# ---------------------------------------------------------------- engines
var eng: Array = []          # per engine dictionaries
var throttle: Array = []     # lever 0..1
var reverse_cmd := false
var apu_n := 0.0
var apu_on := false
var apu_avail := true

# ---------------------------------------------------------------- fuel (kg): [left, centre, right]
var fuel := [0.0, 0.0, 0.0]
var fuel_cap := [0.0, 0.0, 0.0]
var crossfeed := false
var fuel_leak := 0.0          # kg/s
var fuel_used := 0.0

# ---------------------------------------------------------------- electrical
var battery := true
var battery_charge := 1.0
var ext_power := false
var ac_power := true
var dc_power := true
var emer_elec := false
var rat := false
var gen_fail := []

# ---------------------------------------------------------------- hydraulics
var hyd := [3000.0, 3000.0]
var hyd_fail := [false, false]
var hyd_qty := [1.0, 1.0]

# ---------------------------------------------------------------- flight controls & gear
var flap_lever := 0
var flap_pos := 0.0
var flaps_jammed := false
var gear_down_cmd := true
var gear_pos := [1.0, 1.0, 1.0]
var gear_fault := [false, false, false]
var gear_alt_ext := false
var spoiler_lever := 0.0
var ground_spoilers_armed := false
var spoilers := 0.0
var autobrake := 0               # 0 off, 1 lo, 2 med, 3 max, 4 rto
var autobrake_active := false
var parking_brake := true
var brake_input := 0.0
var brake_cmd := [0.0, 0.0]
var brake_temp := 20.0
var trim := 0.0

# ---------------------------------------------------------------- environment control
var cabin_alt := 0.0
var cabin_rate := 0.0
var press_fail := 0              # 0 none, 1 slow leak, 2 rapid
var packs := [true, true]
var masks_deployed := false
var pilot_mask := false
var hypoxia := 0.0               # 0..1 (1 = unconscious)
var cabin_temp := 23.0
var cabin_smoke := 0.0
var eng_anti_ice := false
var wing_anti_ice := false
var pitot_heat := true
var pitot_iced := false

# ---------------------------------------------------------------- lights & misc
var lights := {"nav": false, "beacon": false, "strobe": false, "landing": false, "taxi": false, "logo": false,
	"wing": false, "cabin": true, "seatbelt": true, "nosmoke": true, "panel": true}
var squawk := "2000"
var xpdr_on := true

# ---------------------------------------------------------------- warnings
var messages: Array = []         # {id, text, level, t}
var master_warning := false
var master_caution := false
var stall_warning := false
var overspeed := false
var config_warning := ""
var _acked := {}
var _t := 0.0


func setup(t: Dictionary, fuel_kg: float, cold_and_dark: bool) -> void:
	spec = t
	etype = String(t.engine_type)
	n_eng = int(t.engine_count)
	eng.clear()
	throttle.clear()
	gen_fail.clear()
	for i in n_eng:
		eng.append({"n1": 0.0, "egt": 15.0, "ff": 0.0, "running": false, "starting": false, "start_t": 0.0,
			"fire": false, "fire_t": 0.0, "failed": "", "thrust": 0.0, "rev": 0.0, "cutoff": true,
			"oil_p": 0.0, "vib": 0.0, "bottles": 2, "handle": false, "max_factor": 1.0, "torque": 0.0, "rpm": 0.0})
		throttle.append(0.0)
		gen_fail.append(false)
	var cap: float = t.max_fuel
	fuel_cap = [cap * 0.3, cap * 0.4, cap * 0.3] if t.category != "trainer" else [cap * 0.5, 0.0, cap * 0.5]
	set_fuel(fuel_kg)
	if not cold_and_dark:
		for e in eng:
			e.running = true
			e.cutoff = false
			e.n1 = _idle_n1(true)
			e.oil_p = 45.0
			e.egt = 420.0
		lights.nav = true
		lights.beacon = true
		parking_brake = false
		ac_power = true
	else:
		ac_power = false
		battery = true
		lights.cabin = true
		lights.seatbelt = false
		hyd = [0.0, 0.0]
	flap_pos = float(flap_lever)


func set_fuel(kg: float) -> void:
	var total_cap: float = fuel_cap[0] + fuel_cap[1] + fuel_cap[2]
	kg = clampf(kg, 0.0, total_cap)
	# wings fill first, centre gets the remainder
	var wing_cap: float = fuel_cap[0] + fuel_cap[2]
	var w := minf(kg, wing_cap)
	fuel[0] = w * 0.5
	fuel[2] = w * 0.5
	fuel[1] = maxf(kg - wing_cap, 0.0)


func fuel_total() -> float:
	return float(fuel[0]) + float(fuel[1]) + float(fuel[2])


func _idle_n1(on_ground: bool) -> float:
	match etype:
		"turbofan":
			return 21.0 if on_ground else 27.0
		"turboprop":
			return 18.0
	return 25.0


func any_engine_running() -> bool:
	for e in eng:
		if e.running:
			return true
	return false


func running_engines() -> int:
	var n := 0
	for e in eng:
		if e.running:
			n += 1
	return n


# ---------------------------------------------------------------- failures
func fail(id: String, idx: int = 0) -> void:
	idx = clampi(idx, 0, n_eng - 1)
	match id:
		"eng_flameout":
			eng[idx].running = false
			eng[idx].failed = "flameout"
		"eng_seize":
			eng[idx].running = false
			eng[idx].failed = "seized"
			eng[idx].vib = 5.0
		"eng_fire":
			eng[idx].fire = true
			eng[idx].fire_t = 0.0
		"eng_damage":
			eng[idx].max_factor = 0.55
			eng[idx].vib = 3.2
			eng[idx].failed = "damaged"
		"gen":
			gen_fail[idx] = true
		"hyd":
			hyd_fail[idx % 2] = true
			hyd_qty[idx % 2] = 0.0
		"press_slow":
			press_fail = 1
		"press_rapid":
			press_fail = 2
		"gear_unsafe":
			gear_fault[idx] = true
		"flaps_jam":
			flaps_jammed = true
		"fuel_leak":
			fuel_leak = 0.9 if spec.category != "trainer" else 0.01
		"elec_total":
			for i in n_eng:
				gen_fail[i] = true
			apu_avail = false
		"pitot":
			pitot_iced = true
		"pack":
			packs[idx % 2] = false
		"smoke":
			cabin_smoke = maxf(cabin_smoke, 0.05)


# ---------------------------------------------------------------- update
func update(dt: float, fdm: FlightModel, alt_m: float, oat_c: float, in_cloud: bool, icing_env: bool) -> void:
	_t += dt
	var on_ground := fdm.on_ground
	var sigma := Atmo.density(maxf(alt_m, 0.0)) / Atmo.RHO0
	_update_electrical(dt)
	_update_engines(dt, fdm, sigma, on_ground)
	_update_fuel(dt)
	_update_hydraulics(dt)
	_update_gear_flaps(dt, fdm, on_ground)
	_update_brakes(dt, fdm, on_ground)
	_update_pressurisation(dt, alt_m, oat_c)
	_update_icing(dt, fdm, in_cloud and icing_env, oat_c)
	_update_warnings(fdm, on_ground)


func _update_electrical(dt: float) -> void:
	var gen_online := false
	for i in n_eng:
		if eng[i].running and eng[i].n1 > 15.0 and not gen_fail[i]:
			gen_online = true
	if apu_n > 95.0 and apu_avail:
		gen_online = true
	if ext_power:
		gen_online = true
	if rat and fdm_ias_cache > 60.0:
		emer_elec = true
	ac_power = gen_online
	emer_elec = not gen_online and battery and (rat or spec.category == "trainer")
	if not gen_online and battery:
		battery_charge = maxf(battery_charge - dt / 1800.0, 0.0)
	elif gen_online:
		battery_charge = minf(battery_charge + dt / 600.0, 1.0)
	dc_power = battery_charge > 0.02 or gen_online
	# APU
	if apu_on and apu_avail and dc_power:
		apu_n = minf(apu_n + dt * 4.5, 100.0)
	else:
		apu_n = maxf(apu_n - dt * 6.0, 0.0)


var fdm_ias_cache := 0.0


func _update_engines(dt: float, fdm: FlightModel, sigma: float, on_ground: bool) -> void:
	fdm_ias_cache = fdm.ias
	var bleed_ok := apu_n > 95.0 or running_engines() > 0 or ext_power
	var idle := _idle_n1(on_ground)
	var spool: float = spec.get("spool", 5.0)
	var static_t: float = spec.static_thrust
	for i in n_eng:
		var e: Dictionary = eng[i]
		var lever: float = throttle[i]
		var fuel_ok = not e.cutoff and _fuel_available(i)
		if e.running and not fuel_ok:
			e.running = false
			if not e.cutoff:
				e.failed = "fuel starvation"
				_raise("eng%d_flameout" % i, 1, "ENG %d FLAMEOUT" % (i + 1))
		# starting
		if e.starting:
			e.start_t += dt
			var need_bleed := etype == "turbofan"
			if need_bleed and not bleed_ok:
				e.starting = false
			elif e.start_t < 12.0:
				e.n1 = move_toward(e.n1, 14.0, dt * 1.6)
			elif fuel_ok and e.failed != "seized":
				e.n1 = move_toward(e.n1, idle, dt * 1.2)
				e.egt = move_toward(e.egt, 640.0, dt * 70.0)
				if e.n1 >= idle - 0.5:
					e.running = true
					e.starting = false
					e.failed = "" if e.failed in ["flameout", "fuel starvation"] else e.failed
					_clear_msg("eng%d_flameout" % i)
		var target := 0.0
		if e.running:
			target = idle + (100.0 - idle) * pow(clampf(lever, 0.0, 1.0), 1.15) * float(e.max_factor)
			if e.rev > 0.5:
				target = idle + (82.0 - idle) * clampf(lever, 0.0, 1.0)
		elif not e.starting:
			target = clampf(fdm.tas / 250.0 * 18.0, 0.0, 18.0) if e.failed != "seized" else 0.0
		var rate = (0.22 + 1.1 * e.n1 / 100.0) / spool * 4.0
		if not e.running:
			rate = 0.35
		# while the starter is cranking it alone drives the spool speed
		if not e.starting:
			e.n1 = e.n1 + (target - e.n1) * clampf(rate * dt, 0.0, 1.0)
		# reversers (ground only, lever at idle to deploy)
		var want_rev := reverse_cmd and on_ground and bool(spec.reverser)
		e.rev = move_toward(e.rev, 1.0 if want_rev else 0.0, dt * 0.7)
		# thrust and fuel flow
		var thrust := 0.0
		var ff := 0.0
		match etype:
			"turbofan":
				var frac := 0.0
				if e.n1 > 19.0:
					frac = 0.045 + 0.955 * pow(clampf((e.n1 - 20.0) / 80.0, 0.0, 1.0), 1.7)
				var byp: float = spec.get("bypass", 5.0)
				var lapse := pow(sigma, 0.8) * clampf(1.0 - (0.22 + 0.03 * byp) * fdm.mach, 0.25, 1.0)
				thrust = static_t * frac * lapse
				if e.rev > 0.05:
					thrust = lerpf(thrust, -0.38 * static_t * frac, e.rev)
				ff = float(spec.tsfc) * absf(thrust) * (1.0 + 0.45 * fdm.mach) + (0.05 if e.running else 0.0) * static_t / 120000.0
			_:
				var power: float = float(spec.power_kw) * 1000.0
				var frac2 := clampf((e.n1 - 15.0) / 85.0, 0.0, 1.0) if e.running else 0.0
				var p_eff := power * frac2 * pow(sigma, 0.75 if etype == "turboprop" else 1.0)
				var eta := 0.82
				var t0: float = static_t * frac2
				var v0 := maxf(p_eff * eta / maxf(t0, 1.0), 1.0)
				thrust = p_eff * eta / sqrt(fdm.tas * fdm.tas + v0 * v0) if p_eff > 0.0 else 0.0
				# windmilling propeller drag when the engine is dead
				if not e.running:
					thrust = -0.012 * fdm.qbar * pow(float(spec.prop_diam), 2.0)
				if e.rev > 0.05:
					thrust = lerpf(thrust, -0.35 * static_t * maxf(frac2, 0.2), e.rev)
				ff = float(spec.bsfc) * p_eff + (0.004 if e.running else 0.0)
				e.torque = frac2 * 100.0
				e.rpm = (0.7 + 0.3 * frac2) * float(spec.max_rpm) if e.running else fdm.tas * 4.0
		if not e.running:
			ff = 0.0
		e.thrust = thrust
		e.ff = ff
		e.egt = move_toward(e.egt, (380.0 + e.n1 * 5.6) if e.running else maxf(15.0, e.egt - 40.0), dt * 60.0)
		e.oil_p = move_toward(e.oil_p, (25.0 + e.n1 * 0.35) if e.running else e.n1 * 0.4, dt * 10.0)
		# fire: grows until the handle is pulled and agent discharged
		if e.fire:
			e.fire_t += dt
			e.egt = maxf(e.egt, 900.0)
			if e.handle and e.bottles < 2 and e.fire_t > 8.0:
				# each discharged bottle has a good chance to extinguish
				var rr := RandomNumberGenerator.new()
				rr.seed = int(e.fire_t * 100.0) + i
				if rr.randf() < (0.75 if e.bottles == 1 else 0.6):
					e.fire = false
					_clear_msg("eng%d_fire" % i)
					_raise("eng%d_fire_out" % i, 0, "ENG %d FIRE EXTINGUISHED" % (i + 1))
				e.fire_t = 0.0
		if e.handle:
			e.cutoff = true
	# RAT: all engines out in flight on transport aircraft
	if not on_ground and running_engines() == 0 and spec.category in ["regional", "narrowbody", "widebody", "bizjet", "cargo"]:
		if not rat and fdm.tas > 40.0:
			rat = true
			_raise("rat", 1, "RAT DEPLOYED")


func _fuel_available(i: int) -> bool:
	var side := 0 if (n_eng == 1 or i < n_eng / 2) else 2
	if n_eng == 1:
		return fuel_total() > 0.5
	if float(fuel[1]) > 1.0:
		return true
	if float(fuel[side]) > 1.0:
		return true
	if crossfeed and float(fuel[2 - side]) > 1.0:
		return true
	return false


func _update_fuel(dt: float) -> void:
	var total_ff := 0.0
	for i in n_eng:
		var burn: float = eng[i].ff * dt
		total_ff += burn
		var side := 0 if (n_eng == 1 or i < n_eng / 2) else 2
		if float(fuel[1]) > 1.0:
			fuel[1] = maxf(float(fuel[1]) - burn, 0.0)
		elif float(fuel[side]) > 0.0:
			fuel[side] = maxf(float(fuel[side]) - burn, 0.0)
		elif crossfeed:
			fuel[2 - side] = maxf(float(fuel[2 - side]) - burn, 0.0)
	if apu_n > 50.0:
		var apu_burn := 0.03 * dt
		fuel[0] = maxf(float(fuel[0]) - apu_burn, 0.0)
	if fuel_leak > 0.0:
		fuel[2] = maxf(float(fuel[2]) - fuel_leak * dt, 0.0)
	fuel_used += total_ff


func fuel_imbalance() -> float:
	return float(fuel[2]) - float(fuel[0])


func _update_hydraulics(dt: float) -> void:
	for s in 2:
		var src := false
		for i in n_eng:
			var side := 0 if (i < maxi(n_eng / 2, 1)) else 1
			if side == s and eng[i].running and eng[i].n1 > 15.0:
				src = true
		if ac_power and not hyd_fail[s]:
			src = true      # electric pumps
		if rat and s == 1:
			src = true
		if hyd_fail[s] or hyd_qty[s] <= 0.0:
			src = false
		hyd[s] = move_toward(hyd[s], 3000.0 if src else 0.0, dt * (1500.0 if src else 120.0))


func hyd_ok() -> bool:
	return hyd[0] > 1500.0 or hyd[1] > 1500.0


func controls_effectiveness() -> float:
	## Hydraulic loss leaves heavy, slow manual or backup control.
	if spec.category == "trainer":
		return 1.0
	if hyd[0] > 1500.0 and hyd[1] > 1500.0:
		return 1.0
	if hyd_ok():
		return 0.8
	return 0.35


func _update_gear_flaps(dt: float, fdm: FlightModel, on_ground: bool) -> void:
	# landing gear
	var normal_ok = hyd_ok() or spec.category == "trainer"
	if not bool(spec.gear_retract):
		gear_pos = [1.0, 1.0, 1.0]
	else:
		for g in 3:
			var target := 1.0 if gear_down_cmd else 0.0
			if on_ground and not gear_down_cmd and fdm.wow[g]:
				target = 1.0     # squat switch prevents retraction on the ground
			var rate := 0.1 if normal_ok else 0.0
			if gear_alt_ext and target > 0.5:
				rate = 0.045
			var pos: float = gear_pos[g]
			if gear_fault[g] and target > 0.5:
				target = 0.72 if not gear_alt_ext else (1.0 if g != 1 else 0.72)
			gear_pos[g] = move_toward(pos, target, rate * dt)
	# flaps
	var flaps: Array = spec.flaps
	flap_lever = clampi(flap_lever, 0, flaps.size() - 1)
	if not flaps_jammed and hyd_ok():
		flap_pos = move_toward(flap_pos, float(flap_lever), dt / 5.5)
	# flap overspeed damage
	var fi := int(round(flap_pos))
	if fi > 0 and fdm.ias / U.KT > float(flaps[fi].vfe) + 25.0 and not on_ground:
		if not flaps_jammed:
			flaps_jammed = true
			_raise("flap_jam", 1, "FLAPS JAMMED (OVERSPEED)")
	# spoilers
	var target_sp := spoiler_lever * (0.6 if not on_ground else 1.0)
	if ground_spoilers_armed and on_ground and fdm.wheel_speed > 15.0:
		var all_idle := true
		for i in n_eng:
			if float(throttle[i]) > 0.15:
				all_idle = false
		if all_idle:
			target_sp = 1.0
	if not bool(spec.spoilers):
		target_sp = 0.0
	spoilers = move_toward(spoilers, target_sp, dt * (1.6 if hyd_ok() else 0.2))


func _update_brakes(dt: float, fdm: FlightModel, on_ground: bool) -> void:
	var manual := brake_input
	if parking_brake:
		manual = 1.0
	var auto := 0.0
	if autobrake > 0 and on_ground and spoilers > 0.5 and fdm.wheel_speed > 3.0:
		autobrake_active = true
	if autobrake_active:
		if manual > 0.3 or not on_ground or fdm.wheel_speed < 2.0:
			autobrake_active = false
		else:
			var target_dec = [0.0, 1.7, 3.0, 6.0, 9.0][autobrake]
			var dec := -fdm.accel_world.dot((-fdm.basis.z).normalized())
			auto = clampf(0.25 + (target_dec - dec) * 0.25, 0.0, 1.0)
	var b := maxf(manual, auto)
	var eff := 1.0 if (hyd_ok() or spec.category == "trainer") else 0.4
	brake_cmd = [b * eff, b * eff]
	brake_temp = move_toward(brake_temp, 20.0, dt * 0.6) + b * absf(fdm.wheel_speed) * dt * 0.04


func _update_pressurisation(dt: float, alt_m: float, oat_c: float) -> void:
	if spec.category == "trainer":
		cabin_alt = alt_m
		return
	var target := clampf(alt_m * 0.2, 0.0, 2440.0)
	if alt_m < 2400.0:
		target = minf(alt_m, target)
	var packs_ok = (packs[0] or packs[1]) and (running_engines() > 0 or apu_n > 95.0)
	if not packs_ok:
		target = alt_m
	var max_rate := 3.0     # m/s
	if press_fail == 1:
		target = alt_m
		max_rate = 6.0
	elif press_fail == 2:
		target = alt_m
		max_rate = 220.0
	var prev := cabin_alt
	cabin_alt = move_toward(cabin_alt, target, max_rate * dt)
	cabin_rate = (cabin_alt - prev) / maxf(dt, 0.0001)
	if cabin_alt > 4267.0 and not masks_deployed:
		masks_deployed = true
		chime.emit("masks")
		_raise("masks", 2, "CABIN ALTITUDE - MASKS DEPLOYED")
	# hypoxia (pilot) beyond ~12,500 ft cabin without oxygen
	if cabin_alt > 3800.0 and not pilot_mask:
		var ft := cabin_alt / U.FT
		var tuc := 1200.0
		if ft > 40000.0:
			tuc = 18.0
		elif ft > 35000.0:
			tuc = 45.0
		elif ft > 30000.0:
			tuc = 90.0
		elif ft > 25000.0:
			tuc = 180.0
		elif ft > 20000.0:
			tuc = 600.0
		hypoxia = minf(hypoxia + dt / tuc, 1.0)
	else:
		hypoxia = maxf(hypoxia - dt / 30.0, 0.0)
	# cabin temperature drifts toward outside when packs are off
	var t_target := 23.0 if packs_ok else lerpf(23.0, oat_c, 0.5)
	cabin_temp = move_toward(cabin_temp, t_target, dt * 0.01)


func _update_icing(dt: float, fdm: FlightModel, icing: bool, oat_c: float) -> void:
	if icing and not wing_anti_ice:
		fdm.ice = minf(fdm.ice + dt / 900.0, 1.0)
	elif wing_anti_ice or oat_c > 3.0:
		fdm.ice = maxf(fdm.ice - dt / 120.0, 0.0)
	if icing and not pitot_heat:
		pitot_iced = true
	elif pitot_heat and pitot_iced and oat_c > -30.0:
		pitot_iced = false


func displayed_ias(true_ias: float) -> float:
	if pitot_iced:
		return true_ias * 0.35
	return true_ias


# ---------------------------------------------------------------- warnings
func _raise(id: String, level: int, text: String) -> void:
	for m in messages:
		if m.id == id:
			return
	messages.append({"id": id, "text": text, "level": level, "t": _t})
	if level == 2:
		master_warning = true
		chime.emit("warning")
	elif level == 1:
		master_caution = true
		chime.emit("caution")
	alert.emit(id, level, text)


func _clear_msg(id: String) -> void:
	for i in range(messages.size() - 1, -1, -1):
		if messages[i].id == id:
			messages.remove_at(i)


func has_msg(id: String) -> bool:
	for m in messages:
		if m.id == id:
			return true
	return false


func ack_master() -> void:
	master_warning = false
	master_caution = false


func _cond(id: String, cond: bool, level: int, text: String) -> void:
	if cond:
		_raise(id, level, text)
	else:
		_clear_msg(id)


func _update_warnings(fdm: FlightModel, on_ground: bool) -> void:
	var t: Dictionary = spec
	var ias_kt := fdm.ias / U.KT
	for i in n_eng:
		var e: Dictionary = eng[i]
		_cond("eng%d_fire" % i, e.fire, 2, "ENG %d FIRE" % (i + 1))
		_cond("eng%d_fail" % i, not e.running and not e.starting and e.failed != "" and not e.cutoff, 1, "ENG %d FAIL" % (i + 1))
		_cond("eng%d_vib" % i, e.vib > 2.5 and e.running, 1, "ENG %d HIGH VIBRATION" % (i + 1))
		_cond("eng%d_oil" % i, e.running and e.oil_p < 13.0, 1, "ENG %d OIL LO PR" % (i + 1))
	stall_warning = not on_ground and fdm.alpha > fdm.alpha_stall - deg_to_rad(2.0) and fdm.tas > 15.0
	var mmo: float = t.mmo
	overspeed = ias_kt > float(t.vmo) + 4.0 or (mmo > 0.0 and fdm.mach > mmo + 0.01)
	_cond("overspeed", overspeed, 2, "OVERSPEED")
	_cond("stall", stall_warning, 2, "STALL")
	if t.category != "trainer":
		_cond("cabin_alt", cabin_alt > 3048.0, 2, "CABIN ALTITUDE")
		_cond("hyd_a", hyd[0] < 1200.0 and any_engine_running(), 1, "HYD SYS A LO PR")
		_cond("hyd_b", hyd[1] < 1200.0 and any_engine_running(), 1, "HYD SYS B LO PR")
		_cond("elec_emer", not ac_power and any_engine_running() == false and not on_ground, 2, "ELEC EMER CONFIG")
		for i in n_eng:
			_cond("gen%d" % i, gen_fail[i] and eng[i].running, 1, "ELEC GEN %d OFF" % (i + 1))
		_cond("fuel_imb", absf(fuel_imbalance()) > float(t.max_fuel) * 0.06, 1, "FUEL IMBALANCE")
		_cond("press_fail", press_fail > 0 and cabin_alt > 2600.0, 1, "CABIN PRESS FAULT")
		_cond("pack1", not packs[0], 1, "AIR PACK 1 FAULT")
	_cond("fuel_low", fuel_total() < float(t.max_fuel) * 0.08, 1, "FUEL LOW LEVEL")
	var gear_unsafe := false
	for g in 3:
		if bool(t.gear_retract) and gear_down_cmd and gear_pos[g] < 0.99 and gear_pos[g] > 0.6 and gear_fault[g]:
			gear_unsafe = true
	_cond("gear_unsafe", gear_unsafe, 2, "L/G GEAR NOT DOWNLOCKED")
	_cond("smoke", cabin_smoke > 0.05, 2, "SMOKE LAVATORY / CABIN")
	_cond("pitot", pitot_iced, 1, "UNRELIABLE AIRSPEED")
	_cond("ice", fdm.ice > 0.15, 1, "ICE DETECTED")
	_cond("hypoxia", hypoxia > 0.15 and not pilot_mask, 2, "CREW OXYGEN - DON MASKS")
	# takeoff configuration warning
	config_warning = ""
	if on_ground and t.category != "trainer":
		var adv := false
		for i in n_eng:
			if float(throttle[i]) > 0.7:
				adv = true
		if adv:
			if flap_lever == 0 and t.flaps.size() > 2:
				config_warning = "FLAPS"
			elif spoiler_lever > 0.1:
				config_warning = "SPOILERS"
			elif parking_brake:
				config_warning = "PARKING BRAKE"
			elif absf(trim) > 0.6:
				config_warning = "TRIM"
	_cond("config", config_warning != "", 2, "CONFIG " + config_warning)
