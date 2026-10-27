extends Node
## Headless flight test: AI pilot flies takeoff -> climb -> route -> ILS -> landing for each type.
## Usage: godot --headless --path . res://tests/flight_test.tscn -- [type] [dep_icao dep_rwy arr_icao arr_rwy] [verbose]

var results := []

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var types := AircraftTypes.ORDER.duplicate()
	if args.size() > 0 and args[0] != "all":
		types = [args[0]]
	var dep_icao := "SKPC"
	var dep_rwy := "27R"
	var arr_icao := "SKPC"
	var arr_rwy := "27R"
	if args.size() >= 5:
		dep_icao = args[1]
		dep_rwy = args[2]
		arr_icao = args[3]
		arr_rwy = args[4]
	var verbose := args.has("verbose")
	for t in types:
		var d := dep_icao
		var dr := dep_rwy
		var a := arr_icao
		var ar := arr_rwy
		if t == "t172" and args.size() < 5:
			d = "SKWF"
			dr = "21"
			a = "SKWF"
			ar = "21"
		results.append(await _fly(t, d, dr, a, ar, verbose))
	print("\n===== SUMMARY =====")
	for r in results:
		print(r)
	get_tree().quit()

func _fly(type_id: String, dep_icao: String, dep_rwy: String, arr_icao: String, arr_rwy: String, verbose: bool) -> String:
	var ac := Aircraft.new()
	add_child(ac)
	ac.setup(type_id, "TEST-" + type_id, "SKF", null, false)
	ac.player_controlled = false
	var spec := ac.spec
	var pax := AircraftTypes.seat_count(type_id) * 8 / 10
	ac.set_load(pax, 2000.0 if spec.category == "cargo" else 0.0, float(spec.max_fuel) * 0.45)
	if spec.category == "cargo":
		ac.set_load(0, float(spec.max_payload) * 0.6, float(spec.max_fuel) * 0.45)
	var dep := Airports.runway_end(dep_icao, dep_rwy)
	var arr := Airports.runway_end(arr_icao, arr_rwy)
	var d := Vector3(sin(deg_to_rad(dep.hdg)), 0, -cos(deg_to_rad(dep.hdg)))
	var start := Vector3(dep.thr_x, dep.elev, dep.thr_z) + d * 60.0
	ac.place_at(start, dep.hdg, true)
	ac.sys.parking_brake = false
	var cruise := 1500.0 if spec.category == "trainer" else (3600.0 if dep_icao == arr_icao else float(spec.cruise_alt) * U.FT * 0.6)
	var route := []
	if dep_icao == arr_icao:
		# out 30 km on runway heading then return for the ILS
		var p1 := Vector2(dep.thr_x, dep.thr_z) + Vector2(d.x, d.z) * 30000.0
		var side := Vector2(-d.z, d.x)
		var p2 := p1 + side * 15000.0
		route = [{"name": "OUT", "x": p1.x, "z": p1.y}, {"name": "SIDE", "x": p2.x, "z": p2.y}]
	var pilot := AIPilot.new()
	pilot.setup(ac, dep, arr, cruise, route)
	pilot.start_takeoff()
	var log := []
	pilot.phase_changed.connect(func(p): log.append("%.0fs %s" % [pilot.t_phase, p]))
	var t := 0.0
	var dt := 1.0 / 60.0
	var next_print := 0.0
	var max_t := 3600.0 * 1.5
	var crashed := false
	var td := {}
	ac.crashed.connect(func(info): crashed = true)
	ac.touchdown.connect(func(info): td = info)
	var incidents := []
	ac.incident.connect(func(k, info): incidents.append(k))
	var t0 := Time.get_ticks_msec()
	while t < max_t:
		pilot.update(dt)
		ac._physics_process(dt)
		t += dt
		if verbose and t >= next_print:
			next_print += (2.0 if t < 120.0 else (1.0 if ac.ra < 150.0 and pilot.phase != "climb" and pilot.phase != "initial_climb" else 20.0))
			var n := ac.nav_state()
			print("%5.0fs %-14s alt=%5.0fft ra=%5.1f ias=%3.0f vs=%5.0f pit=%5.1f bnk=%5.1f hdg=%3.0f flap=%s gear=%s thr=%.2f AP=%s/%s/%s dist=%.1fkm loc=%.2f gs=%.2f fuel=%.0f" % [
				t, pilot.phase, n.alt / U.FT, ac.ra / U.FT, n.true_ias_kt, n.vs / U.FPM, n.pitch, n.bank, n.hdg, ac.flap_label(), ac.gear_state_text(),
				ac.throttle_lever, ac.ap.lat_mode, ac.ap.vert_mode, ac.ap.thr_mode, U.dist2d(n.x, n.z, arr.thr_x, arr.thr_z) / 1000.0,
				ac.ap.loc_dev, ac.ap.gs_dev, ac.sys.fuel_total()])
		if crashed or pilot.phase == "landed":
			break
		if int(t * 60.0) % 600 == 0:
			await get_tree().process_frame
	var wall := (Time.get_ticks_msec() - t0) / 1000.0
	var res := "%s: %s after %.0fs sim (%.1fs wall). " % [type_id, "CRASHED" if crashed else pilot.phase, t, wall]
	if crashed:
		res += "crash=%s " % str(ac.crash_info)
	if not td.is_empty():
		res += "TD vs=%.0ffpm ias=%.0f dist=%.0fm cl=%.1fm rwy=%s " % [td.vs_fpm, td.ias_kt, td.dist_from_thr, td.centerline, td.runway]
	res += "maxg=%.2f incidents=%s phases=%s" % [ac.max_g, str(incidents), str(log)]
	ac.queue_free()
	return res
