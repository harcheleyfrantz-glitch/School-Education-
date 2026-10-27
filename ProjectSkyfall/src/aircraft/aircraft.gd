class_name Aircraft
extends Node3D
## A flyable aircraft: flight model, systems, control laws, autopilot, damage and visuals.

signal touchdown(info: Dictionary)
signal liftoff
signal crashed(info: Dictionary)
signal incident(kind: String, info: Dictionary)
signal gear_changed(down: bool)
signal flaps_changed(index: int)

const STEP_PC := 1.0 / 240.0
const STEP_MOBILE := 1.0 / 120.0

var type_id := "s320"
var spec: Dictionary
var reg := ""
var airline := "SKF"
var callsign := ""
var world: WorldView = null
var fdm := FlightModel.new()
var sys := AircraftSystems.new()
var laws := ControlLaws.new()
var ap := Autopilot.new()
var model: AircraftModel = null
var player_controlled := true
var ai_controlled := false

# loading
var empty_mass := 0.0
var payload := 0.0
var pax_count := 0
var cargo_kg := 0.0

# pilot input state
var in_pitch := 0.0
var in_roll := 0.0
var in_yaw := 0.0
var in_tiller := 0.0
var input_enabled := true
var throttle_lever := 0.0

# status
var crashed_state := false
var crash_info: Dictionary = {}
var damage := {"gear": [false, false, false], "tailstrike": false, "wing_l": 0.0, "wing_r": 0.0, "engines": [], "structure": 0.0, "fire": false}
var max_g := 1.0
var min_g := 1.0
var airborne_time := 0.0
var nz_filtered := 1.0
var ground_time := 0.0
var was_on_ground := true
var last_touchdown: Dictionary = {}
var wind := Vector3.ZERO
var turbulence := 0.0
var in_cloud := false
var ra := 0.0                       # radio altitude (m, gear bottom above ground)
var ground_elev := 0.0
var surface := "runway"
var oat := 15.0
var weather: Dictionary = {}
var sim_rate := 1.0
# session hooks: event effects and kinematic control (pushback, cinematics)
var extra_turb := 0.0
var wind_bias_kt := 0.0
var shear := 0.0
var crosswind_extra_kt := 0.0
var kinematic := false

var _acc := 0.0
var _gust := Vector3.ZERO
var _gust_t := 0.0
var _noise := FastNoiseLite.new()
var _ground_timer := 0.0
var _wx_timer := 0.0
var _mass_timer := 0.0
var _impact_cooldown := 0.0
var _step := STEP_PC


func setup(type: String, registration: String, airline_code: String, world_view: WorldView, build_visuals: bool = true) -> void:
	type_id = type
	spec = AircraftTypes.get_type(type)
	reg = registration
	airline = airline_code
	world = world_view
	if world and not world.origin_shifted.is_connected(on_origin_shift):
		world.origin_shifted.connect(on_origin_shift)
	_step = STEP_MOBILE if Game.is_mobile else STEP_PC
	empty_mass = float(spec.empty_mass)
	_noise.seed = U.hash_str(registration)
	_noise.frequency = 0.35
	_noise.fractal_octaves = 3
	fdm.setup(spec, empty_mass + 5000.0)
	sys.setup(spec, float(spec.max_fuel) * 0.5, false)
	laws.setup(spec, Game.settings.assist == "assisted", bool(spec.fbw))
	laws.auto_rudder = bool(Game.settings.auto_rudder)
	ap.setup(spec)
	damage.engines = []
	for i in int(spec.engine_count):
		damage.engines.append(false)
	if build_visuals:
		model = AircraftModel.new()
		add_child(model)
		model.build(type, airline_code, registration)
	_update_mass()


func set_load(pax: int, cargo: float, fuel_kg: float) -> void:
	pax_count = pax
	cargo_kg = cargo
	payload = pax * 95.0 + cargo
	sys.set_fuel(fuel_kg)
	_update_mass()


func total_mass() -> float:
	return empty_mass + payload + sys.fuel_total()


func _update_mass() -> void:
	fdm.set_mass(total_mass())
	# CG shift from fuel imbalance and payload distribution is modelled as a small aft offset
	fdm.cg_aft = clampf((payload / maxf(float(spec.max_payload), 1.0) - 0.5) * 0.4, -0.3, 0.3)


func place_at(local_pos: Vector3, heading: float, on_ground: bool, speed_mps: float = 0.0) -> void:
	fdm.set_attitude(heading, 0.0, 0.0)
	if on_ground:
		fdm.pos = local_pos + Vector3(0, float(spec.gear_height) - 0.05, 0)
		fdm.vel = Vector3.ZERO
		fdm.omega = Vector3.ZERO
		sys.gear_pos = [1.0, 1.0, 1.0]
		sys.gear_down_cmd = true
		was_on_ground = true
	else:
		fdm.pos = local_pos
		fdm.vel = U.heading_to_dir(heading) * speed_mps
		sys.gear_down_cmd = false
		sys.gear_pos = [0.0, 0.0, 0.0] if bool(spec.gear_retract) else [1.0, 1.0, 1.0]
		was_on_ground = false
		laws.reset_to_current(fdm)
		ap.out_pitch = fdm.pitch_deg()
	_refresh_ground(true)
	_sync_transform()


func world_x() -> float:
	return fdm.pos.x + (world.origin_x if world else 0.0)


func world_z() -> float:
	return fdm.pos.z + (world.origin_z if world else 0.0)


func on_origin_shift(shift: Vector3) -> void:
	fdm.pos -= shift
	_sync_transform()


# ---------------------------------------------------------------- input
func _read_input(dt: float) -> void:
	if not input_enabled or not player_controlled:
		return
	var kp := Input.get_axis("pitch_down", "pitch_up")
	var kr := Input.get_axis("roll_left", "roll_right")
	var ky := Input.get_axis("yaw_left", "yaw_right")
	if bool(Game.settings.invert_pitch):
		kp = -kp
	# keyboard/digital inputs ramp in for a smoother feel; analog sticks pass through
	in_pitch = _ramp(in_pitch, kp, dt)
	in_roll = _ramp(in_roll, kr, dt)
	in_yaw = _ramp(in_yaw, ky, dt)
	if PilotInput.touch_active:
		in_pitch = clampf(in_pitch + PilotInput.stick.y, -1.0, 1.0)
		in_roll = clampf(in_roll + PilotInput.stick.x, -1.0, 1.0)
		in_yaw = clampf(in_yaw + PilotInput.pedal, -1.0, 1.0)
	if PilotInput.tilt and Game.is_mobile:
		var acc := Input.get_accelerometer()
		if acc.length() > 1.0:
			var d := acc - PilotInput.tilt_ref
			in_roll = clampf(in_roll + d.x / 4.0, -1.0, 1.0)
			in_pitch = clampf(in_pitch - d.z / 4.0, -1.0, 1.0)
	in_tiller = Input.get_axis("tiller_left", "tiller_right")
	# throttle
	var tdir := Input.get_axis("throttle_down", "throttle_up")
	if absf(tdir) > 0.05:
		throttle_lever = clampf(throttle_lever + tdir * dt * 0.45, 0.0, 1.0)
		if ap.at_engaged:
			ap.at_engaged = false
	if PilotInput.throttle >= 0.0:
		throttle_lever = PilotInput.throttle
	var brakes := maxf(Input.get_action_strength("brakes"), PilotInput.brake)
	sys.brake_input = brakes
	sys.reverse_cmd = Input.is_action_pressed("reverse")
	ap.pilot_override(maxf(absf(in_pitch), absf(in_roll)), dt)


func _ramp(cur: float, target: float, dt: float) -> float:
	if absf(target) > 0.0 and absf(target) < 0.99:
		return target
	var rate := 2.6 if absf(target) > absf(cur) else 5.0
	return move_toward(cur, target, rate * dt)


func _unhandled_input(event: InputEvent) -> void:
	if not player_controlled or not input_enabled:
		return
	if event.is_action_pressed("gear"):
		toggle_gear()
	elif event.is_action_pressed("flaps_down"):
		set_flaps(sys.flap_lever + 1)
	elif event.is_action_pressed("flaps_up"):
		set_flaps(sys.flap_lever - 1)
	elif event.is_action_pressed("parking_brake"):
		sys.parking_brake = not sys.parking_brake
	elif event.is_action_pressed("spoilers"):
		cycle_spoilers()
	elif event.is_action_pressed("autopilot"):
		toggle_autopilot()
	elif event.is_action_pressed("autothrottle"):
		toggle_autothrottle()
	elif event.is_action_pressed("throttle_idle"):
		throttle_lever = 0.0
	elif event.is_action_pressed("throttle_full"):
		throttle_lever = 1.0
	elif event.is_action_pressed("lights_landing"):
		sys.lights.landing = not sys.lights.landing
		sys.lights.taxi = sys.lights.landing
	elif event.is_action_pressed("trim_up"):
		sys.trim = clampf(sys.trim + 0.04, -1.0, 1.0)
	elif event.is_action_pressed("trim_down"):
		sys.trim = clampf(sys.trim - 0.04, -1.0, 1.0)
	elif event.is_action_pressed("oxygen_mask"):
		sys.pilot_mask = not sys.pilot_mask


func toggle_gear() -> void:
	if not bool(spec.gear_retract):
		return
	if fdm.on_ground and sys.gear_down_cmd:
		return
	sys.gear_down_cmd = not sys.gear_down_cmd
	gear_changed.emit(sys.gear_down_cmd)


func set_flaps(idx: int) -> void:
	var n: int = spec.flaps.size()
	var v := clampi(idx, 0, n - 1)
	if v != sys.flap_lever:
		sys.flap_lever = v
		flaps_changed.emit(v)


func cycle_spoilers() -> void:
	if not bool(spec.spoilers):
		return
	if fdm.on_ground or ra < 30.0:
		sys.ground_spoilers_armed = not sys.ground_spoilers_armed
		sys.spoiler_lever = 0.0
	else:
		sys.spoiler_lever = 0.0 if sys.spoiler_lever > 0.4 else 1.0


func toggle_autopilot() -> void:
	if not bool(spec.autopilot):
		return
	if ap.engaged:
		ap.engage(false, "PILOT")
	elif not fdm.on_ground or ap.lat_mode == "ROLLOUT":
		ap.out_pitch = fdm.pitch_deg()
		ap.out_bank = fdm.bank_deg()
		if ap.vert_mode == "ALT" and absf(ap.alt_sel - fdm.pos.y) > 60.0:
			ap.alt_sel = snappedf(fdm.pos.y, 30.48)
		if ap.lat_mode == "HDG":
			ap.hdg_sel = snappedf(fdm.heading_deg(), 1.0)
		ap.engage(true)


func toggle_autothrottle() -> void:
	ap.at_engaged = not ap.at_engaged
	if ap.at_engaged:
		ap.out_throttle = throttle_lever
		ap.spd_sel = snappedf(fdm.ias / U.KT, 1.0)


# ---------------------------------------------------------------- environment
func _refresh_ground(force: bool) -> void:
	var wx := world_x()
	var wz := world_z()
	var alt := fdm.pos.y
	_ground_timer -= get_physics_process_delta_time() if is_inside_tree() else 0.0
	if not force and _ground_timer > 0.0 and fdm.agl > 400.0:
		return
	_ground_timer = 0.4
	var h0 := Geo.ground_height(wx, wz)
	var fwd := U.heading_to_dir(fdm.heading_deg())
	var right := Vector3(-fwd.z, 0, fwd.x)
	var s := 18.0
	var h1 := Geo.ground_height(wx + fwd.x * s, wz + fwd.z * s)
	var h2 := Geo.ground_height(wx + right.x * s, wz + right.z * s)
	var water := Geo.is_water(wx, wz)
	var rw := Geo.runway_at(wx, wz)
	if not rw.is_empty() or Geo.airports_flat.any(func(ap2): return U.dist2d(wx, wz, ap2[0], ap2[1]) < ap2[3] * 0.9):
		h1 = h0
		h2 = h0
	var p0 := Vector3(fdm.pos.x, h0, fdm.pos.z)
	var p1 := p0 + fwd * s + Vector3(0, h1 - h0, 0)
	var p2 := p0 + right * s + Vector3(0, h2 - h0, 0)
	var n := (p1 - p0).cross(p2 - p0).normalized()
	if n.y < 0.0:
		n = -n
	if n.y < 0.3:
		n = Vector3.UP
	fdm.ground_plane = Plane(n, p0)
	fdm.ground_is_water = water
	ground_elev = h0
	surface = "water" if water else ("runway" if not rw.is_empty() and rw.surface == "asphalt" else Geo.surface_at(wx, wz) if fdm.agl < 300.0 else "terrain")
	var wet: bool = weather.get("precip", "none") in ["rain", "thunderstorm"]
	var snow: bool = weather.get("precip", "none") == "snow"
	fdm.surface_mu = 0.3 if snow else (0.55 if wet else 1.0)
	fdm.ground_rough = 0.0 if surface in ["runway", "urban"] else 1.0
	if surface == "grass_strip":
		fdm.surface_mu *= 0.7
	var _a := alt


func _update_weather(dt: float) -> void:
	_wx_timer -= dt
	if _wx_timer <= 0.0:
		_wx_timer = 1.5
		if world and not world.weather_override.is_empty():
			weather = world.weather_override
		else:
			weather = WeatherModel.sample(world_x(), world_z(), WorldSim.clock if world == null else world.time)
		oat = Atmo.temperature(fdm.pos.y) - 273.15 + (float(weather.get("temp_c", 15.0)) - 15.0)
		fdm.isa_dev = float(weather.get("temp_c", 15.0)) - 15.0
	var base_wind := WeatherModel.wind_at_alt(weather, fdm.pos.y, ground_elev) if not weather.is_empty() else Vector3.ZERO
	wind = base_wind
	# turbulence: Dryden-like filtered noise scaled by weather, cloud and storm proximity
	var t_int: float = weather.get("turb", 0.1)
	in_cloud = world != null and world.inside_cloud > 0.3
	if in_cloud:
		t_int += 0.25
	if world:
		for cell in world.storm_cells:
			var d := U.dist2d(world_x(), world_z(), cell.x, cell.z)
			if d < cell.r * 2.2:
				t_int += clampf(1.0 - d / (cell.r * 2.2), 0.0, 1.0) * 1.4
				if d < cell.r:
					# downdraft / microburst near the core
					wind += Vector3(0, -6.0 * (1.0 - d / cell.r), 0)
	var low_level := clampf(1.0 - ra / 600.0, 0.0, 1.0) * float(weather.get("gust_kt", 0.0) - weather.get("wind_kt", 0.0)) / 25.0
	t_int += maxf(low_level, 0.0) + extra_turb
	# event effects: stronger winds aloft, windshear near the ground, gusty crosswind
	var fwd := -basis.z
	var flat_fwd := Vector3(fwd.x, 0.0, fwd.z).normalized()
	if wind_bias_kt != 0.0 and fdm.pos.y > 3000.0:
		wind += -flat_fwd * wind_bias_kt * U.KT
	if shear > 0.0 and ra < 600.0:
		wind += Vector3(0, -7.0 * shear, 0) + flat_fwd * 8.0 * shear
		t_int += 0.6 * shear
	if crosswind_extra_kt > 0.0 and ra < 500.0:
		wind += flat_fwd.cross(Vector3.UP) * crosswind_extra_kt * U.KT * (0.75 + 0.25 * sin(_gust_t * 0.7))
	turbulence = clampf(t_int, 0.0, 2.0)
	_gust_t += dt * (1.0 + fdm.tas / 60.0)
	var amp := turbulence * 3.2
	_gust = Vector3(_noise.get_noise_2d(_gust_t, 0.0), _noise.get_noise_2d(0.0, _gust_t) * 1.4, _noise.get_noise_2d(_gust_t, 77.0)) * amp
	fdm.wind = wind
	fdm.gust = _gust


# ---------------------------------------------------------------- simulation
func _physics_process(delta: float) -> void:
	if crashed_state:
		_wreck_update(delta)
		return
	if kinematic:
		# position driven externally (pushback tug, cinematics); systems keep running
		sys.update(delta, fdm, fdm.pos.y, oat, false, false)
		_sync_transform()
		if model:
			model.animate(self, delta)
		return
	var dt := delta * sim_rate
	_read_input(delta)
	_update_weather(dt)
	_refresh_ground(false)
	# throttle: autothrottle drives the lever, otherwise the pilot does
	if ap.at_engaged and sys.ac_power:
		throttle_lever = ap.out_throttle
	for i in sys.n_eng:
		sys.throttle[i] = throttle_lever
	var step := _step if sim_rate <= 2.0 else minf(_step * sim_rate / 2.0, 1.0 / 30.0)
	_acc += dt
	var steps := 0
	while _acc >= step and steps < 64:
		_acc -= step
		steps += 1
		_sim_step(step)
		if crashed_state:
			break
	_sync_transform()
	if model:
		model.animate(self, delta)


func _sim_step(dt: float) -> void:
	ra = fdm.agl - float(spec.gear_height)
	var n := nav_state()
	if ap.engaged or ap.at_engaged or ap.fd_on:
		ap.update(dt, n, fdm, sys)
	laws.update(fdm, sys, ap, in_pitch, in_roll, in_yaw, dt, ra)
	fdm.steer = clampf(in_yaw + in_tiller + (ap.out_steer if ap.engaged else 0.0), -1.0, 1.0)
	sys.update(dt, fdm, fdm.pos.y, oat, in_cloud, bool(weather.get("icing", false)))
	# hand systems to the flight model
	fdm.flap_frac = sys.flap_pos
	fdm.gear = sys.gear_pos
	fdm.spoilers = sys.spoilers
	fdm.brake_l = sys.brake_cmd[0]
	fdm.brake_r = sys.brake_cmd[1]
	for i in sys.n_eng:
		fdm.thrust[i] = sys.eng[i].thrust
	fdm.damage_roll = (damage.wing_r - damage.wing_l) * 0.04 + sys.fuel_imbalance() / maxf(float(spec.max_fuel), 1.0) * 0.02
	fdm.impacts.clear()
	fdm.step(dt, fdm.pos.y)
	_mass_timer += dt
	if _mass_timer > 1.0:
		_mass_timer = 0.0
		_update_mass()
	_check_structure(dt)
	max_g = maxf(max_g, nz_filtered)
	min_g = minf(min_g, nz_filtered)
	_process_impacts()
	_track_ground_state(dt)


func nav_state() -> Dictionary:
	return {
		"x": world_x(), "z": world_z(), "alt": fdm.pos.y, "ra": ra,
		"ias_kt": sys.displayed_ias(fdm.ias) / U.KT, "true_ias_kt": fdm.ias / U.KT, "tas": fdm.tas,
		"gs": fdm.ground_speed(), "vs": fdm.vel.y, "track": fdm.track_deg(), "hdg": fdm.heading_deg(),
		"pitch": fdm.pitch_deg(), "bank": fdm.bank_deg(), "alpha": rad_to_deg(fdm.alpha), "on_ground": fdm.on_ground,
		"mach": fdm.mach, "flap": sys.flap_lever, "gear_down": sys.gear_down_cmd,
	}


func _sync_transform() -> void:
	transform = Transform3D(fdm.basis, fdm.pos)


func _track_ground_state(dt: float) -> void:
	var mains = fdm.wow[1] or fdm.wow[2]
	if mains and not was_on_ground:
		if airborne_time > 4.0:
			var e := _nearest_runway_info()
			last_touchdown = {
				"vs_fpm": -fdm.vel.y / U.FPM, "ias_kt": fdm.ias / U.KT, "pitch": fdm.pitch_deg(), "bank": fdm.bank_deg(),
				"g": max_g, "surface": surface, "x": world_x(), "z": world_z(), "runway": e.get("name", ""),
				"dist_from_thr": e.get("dist", -1.0), "centerline": e.get("lateral", 0.0), "airport": e.get("airport", ""),
				"crosswind": e.get("crosswind", 0.0), "gear_down": sys.gear_down_cmd,
			}
			touchdown.emit(last_touchdown)
		was_on_ground = true
		airborne_time = 0.0
	elif not fdm.on_ground and was_on_ground:
		ground_time += dt
		if ra > 3.0:
			was_on_ground = false
			airborne_time = 0.0
			max_g = 1.0
			liftoff.emit()
	if fdm.on_ground:
		ground_time += dt
		airborne_time = 0.0 if was_on_ground else airborne_time
	else:
		airborne_time += dt


func _nearest_runway_info() -> Dictionary:
	var wx := world_x()
	var wz := world_z()
	var best := {}
	var bd := INF
	var icao := Airports.nearest(wx, wz)
	if icao == "":
		return {}
	for e in Airports.runway_ends(icao):
		var d := Vector2(sin(deg_to_rad(e.hdg)), -cos(deg_to_rad(e.hdg)))
		var rel := Vector2(wx - e.thr_x, wz - e.thr_z)
		var along := rel.dot(d)
		var lateral := rel.dot(Vector2(-d.y, d.x))
		if along < -200.0 or along > float(e.len) + 200.0 or absf(lateral) > 120.0:
			continue
		var hd := absf(U.angle_diff_deg(e.hdg, fdm.heading_deg()))
		if hd > 60.0:
			continue
		if hd < bd:
			bd = hd
			var w_from: float = weather.get("wind_dir", 0.0)
			var cw := sin(deg_to_rad(w_from - float(e.hdg))) * float(weather.get("wind_kt", 0.0))
			best = {"name": e.name, "dist": along, "lateral": lateral, "airport": icao, "crosswind": cw}
	return best


# ---------------------------------------------------------------- damage
func _check_structure(dt: float) -> void:
	# airframe loads use a filtered accelerometer while airborne; wheel impacts are judged
	# separately in _process_impacts (gear spikes are not wing loads)
	nz_filtered = lerpf(nz_filtered, fdm.nz, clampf(dt * 8.0, 0.0, 1.0))
	if fdm.on_ground or airborne_time < 0.5:
		nz_filtered = 1.0
	var nzf := nz_filtered
	var limit_pos := 2.5 if spec.category != "trainer" else 3.8
	var limit_neg := -1.0 if spec.category != "trainer" else -1.52
	if nzf > limit_pos * 1.15 or nzf < limit_neg * 1.2:
		damage.structure = minf(damage.structure + dt * 0.5, 1.0)
		if not has_meta("overstress"):
			set_meta("overstress", true)
			incident.emit("overstress", {"g": nzf})
	if nzf > limit_pos * 1.55 or nzf < limit_neg * 1.6:
		_structural_failure("structural overload (%.1f g)" % nzf)
	var vd := float(spec.vmo) + 45.0
	var md: float = float(spec.mmo) + 0.07 if float(spec.mmo) > 0.0 else 9.0
	if fdm.ias / U.KT > vd or fdm.mach > md:
		damage.structure = minf(damage.structure + dt * 0.25, 1.0)
		if damage.structure > 0.7:
			_structural_failure("flutter and in-flight breakup beyond design dive speed")
	fdm.damage_drag = damage.structure * 0.03 + (0.02 if damage.gear.has(true) else 0.0)


func _structural_failure(cause: String) -> void:
	if crashed_state:
		return
	damage.structure = 1.0
	fdm.damage_lift = 0.7
	fdm.damage_roll = 0.25
	incident.emit("breakup", {"cause": cause})
	set_meta("breakup", cause)


func _process_impacts() -> void:
	if fdm.impacts.is_empty():
		return
	var worst := {}
	var worst_score := 0.0
	for imp in fdm.impacts:
		var score: float = imp.vs * 1.0 + (imp.speed * 0.05 if imp.kind == "body" else 0.0)
		if score > worst_score:
			worst_score = score
			worst = imp
	if worst.is_empty():
		return
	var part: String = worst.part
	var vs: float = worst.vs
	var speed: float = worst.speed
	var water: bool = worst.get("water", false)
	if water:
		var level := absf(fdm.bank_deg()) < 12.0 and fdm.pitch_deg() > -4.0 and fdm.pitch_deg() < 14.0
		if vs > 4.5 or speed > 85.0 or not level:
			_crash({"cause_hint": "water impact", "ditching": false})
		elif speed < 8.0 or fdm.vel.length() < 8.0:
			_crash({"cause_hint": "ditching", "ditching": true})
		return
	if worst.kind == "gear":
		var g := 0 if part == "nose" else (1 if part == "main_l" else 2)
		if vs > 6.2 and not damage.gear[g]:
			damage.gear[g] = true
			fdm.gear_ok[g] = false
			incident.emit("gear_collapse", {"gear": part, "vs_fpm": vs / U.FPM})
		elif vs > 3.6:
			if not has_meta("hard_landing"):
				set_meta("hard_landing", true)
				incident.emit("hard_landing", {"vs_fpm": vs / U.FPM})
		return
	# structure touching the ground
	_impact_cooldown -= get_physics_process_delta_time()
	var high_energy := vs > 7.5 or (speed > 45.0 and vs > 4.0) or speed > 130.0
	if part.begins_with("nose_cone") and speed > 20.0:
		high_energy = true
	if surface in ["forest", "urban", "mountain"] and speed > 30.0:
		high_energy = true
	if high_energy:
		_crash({"cause_hint": "terrain impact", "part": part})
		return
	if part == "tail" and not damage.tailstrike:
		damage.tailstrike = true
		incident.emit("tailstrike", {"speed": speed})
	elif part.begins_with("wing"):
		var side := "wing_l" if part == "wing_l" else "wing_r"
		damage[side] = minf(float(damage[side]) + 0.4, 1.0)
		if _impact_cooldown <= 0.0:
			_impact_cooldown = 2.0
			incident.emit("wingstrike", {"side": side, "speed": speed})
		if damage[side] > 0.9 and speed > 40.0:
			_crash({"cause_hint": "wing separation", "part": part})
	elif part.begins_with("engine"):
		var ei := int(part.substr(7))
		if ei < damage.engines.size() and not damage.engines[ei]:
			damage.engines[ei] = true
			sys.fail("eng_damage", ei)
			incident.emit("engine_strike", {"engine": ei})
	elif part.begins_with("belly"):
		if _impact_cooldown <= 0.0:
			_impact_cooldown = 3.0
			incident.emit("belly_contact", {"speed": speed})
		if speed > 3.0 and sys.fuel_total() > 500.0 and randf() < 0.002:
			damage.fire = true


func _crash(extra: Dictionary) -> void:
	if crashed_state:
		return
	crashed_state = true
	var v := fdm.vel
	crash_info = {
		"speed_kt": v.length() / U.KT, "vs_fpm": -v.y / U.FPM, "pitch": fdm.pitch_deg(), "bank": fdm.bank_deg(),
		"heading": fdm.heading_deg(), "x": world_x(), "z": world_z(), "alt": fdm.pos.y, "surface": surface,
		"gear_down": sys.gear_down_cmd and sys.gear_pos[1] > 0.95, "fuel_kg": sys.fuel_total(),
		"engines_running": sys.running_engines(), "flaps": sys.flap_lever, "breakup": get_meta("breakup", ""),
		"place": Geo.place_name(world_x(), world_z()), "time": WorldSim.clock,
	}
	crash_info.merge(extra, true)
	# energy based severity 0..1
	var vh := Vector2(v.x, v.z).length()
	var vv := maxf(-v.y, 0.0)
	var sev := clampf((vv - 2.5) / 32.0, 0.0, 1.0) * 0.65 + clampf((vh - 25.0) / 140.0, 0.0, 1.0) * 0.45
	sev += clampf((absf(fdm.bank_deg()) - 20.0) / 100.0, 0.0, 0.3)
	sev += clampf((-fdm.pitch_deg() - 10.0) / 60.0, 0.0, 0.4)
	if surface in ["mountain", "forest", "urban"]:
		sev += 0.15
	if extra.get("ditching", false):
		sev = clampf(0.12 + vv / 30.0, 0.1, 0.4)
	if String(crash_info.breakup) != "":
		sev = maxf(sev, 0.85)
	crash_info.severity = clampf(sev, 0.02, 1.0)
	crash_info.fire = (crash_info.fuel_kg > 300.0 and sev > 0.25 and surface != "water") or damage.fire
	crashed.emit(crash_info)


func _wreck_update(delta: float) -> void:
	# after impact the wreckage slides to a stop
	var v := fdm.vel
	v.y = 0.0
	var spd := v.length()
	if spd > 0.1:
		var dec := 9.0 if surface != "water" else 4.0
		v = v.normalized() * maxf(spd - dec * delta, 0.0)
		fdm.vel = Vector3(v.x, 0.0, v.z)
		fdm.pos += fdm.vel * delta
		fdm.pos.y = lerpf(fdm.pos.y, ground_elev + float(spec.fuse_h) * 0.35, clampf(delta * 3.0, 0.0, 1.0))
	_sync_transform()
	if model:
		model.animate(self, delta)


# ---------------------------------------------------------------- helpers for UI
func flap_label() -> String:
	return String(spec.flaps[sys.flap_lever].label)


func gear_state_text() -> String:
	if not bool(spec.gear_retract):
		return "FIXED"
	var p: float = sys.gear_pos[1]
	if p > 0.99:
		return "DOWN"
	if p < 0.01:
		return "UP"
	return "TRANSIT"
